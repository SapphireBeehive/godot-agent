#!/bin/bash
# diff-review.sh - Generate a concise diff report between staging and live
#
# Usage:
#   ./scripts/diff-review.sh /path/to/staging /path/to/live

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 <staging_path> <live_path> [options]

Generate a diff report between staging and live directories.

Options:
  --full     Show full diff output (not just summary)
  --output   Write report to file instead of stdout

Examples:
  $0 ./staging ./my-project
  $0 ./staging ./my-project --full
  $0 ./staging ./my-project --output report.txt
EOF
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

STAGING_PATH="$1"
LIVE_PATH="$2"
shift 2

FULL_DIFF=false
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            FULL_DIFF=true
            shift
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate paths
if [[ ! -d "$STAGING_PATH" ]]; then
    echo "Error: Staging path does not exist: $STAGING_PATH" >&2
    exit 1
fi

# Live path might not exist yet (first time setup)
if [[ ! -d "$LIVE_PATH" ]]; then
    echo "Note: Live path does not exist yet: $LIVE_PATH"
    echo "All files from staging would be new additions."
    echo ""
    echo "Files in staging:"
    find "$STAGING_PATH" -type f | sed "s|$STAGING_PATH/||" | sort
    exit 0
fi

# Make paths absolute
STAGING_PATH="$(cd "$STAGING_PATH" && pwd)"
LIVE_PATH="$(cd "$LIVE_PATH" && pwd)"

# Generate report
generate_report() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    DIFF REVIEW REPORT                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Generated: $(date)"
    echo "Staging:   $STAGING_PATH"
    echo "Live:      $LIVE_PATH"
    echo ""
    
    # File counts
    STAGING_COUNT=$(find "$STAGING_PATH" -type f | wc -l | tr -d ' ')
    LIVE_COUNT=$(find "$LIVE_PATH" -type f | wc -l | tr -d ' ')
    echo "File counts:"
    echo "  Staging: $STAGING_COUNT files"
    echo "  Live:    $LIVE_COUNT files"
    echo ""
    
    # === New files (in staging but not in live) ===
    echo "────────────────────────────────────────────────────────────────"
    echo "NEW FILES (in staging only)"
    echo "────────────────────────────────────────────────────────────────"
    
    NEW_FILES=$(comm -23 \
        <(find "$STAGING_PATH" -type f | sed "s|$STAGING_PATH/||" | sort) \
        <(find "$LIVE_PATH" -type f | sed "s|$LIVE_PATH/||" | sort))
    
    if [[ -n "$NEW_FILES" ]]; then
        echo "$NEW_FILES" | while read -r file; do
            SIZE=$(stat -f%z "$STAGING_PATH/$file" 2>/dev/null || stat -c%s "$STAGING_PATH/$file" 2>/dev/null || echo "?")
            echo "  + $file ($SIZE bytes)"
        done
    else
        echo "  (none)"
    fi
    echo ""
    
    # === Deleted files (in live but not in staging) ===
    echo "────────────────────────────────────────────────────────────────"
    echo "DELETED FILES (would be removed if --delete used)"
    echo "────────────────────────────────────────────────────────────────"
    
    DELETED_FILES=$(comm -13 \
        <(find "$STAGING_PATH" -type f | sed "s|$STAGING_PATH/||" | sort) \
        <(find "$LIVE_PATH" -type f | sed "s|$LIVE_PATH/||" | sort))
    
    if [[ -n "$DELETED_FILES" ]]; then
        echo "$DELETED_FILES" | while read -r file; do
            echo "  - $file"
        done
    else
        echo "  (none)"
    fi
    echo ""
    
    # === Modified files ===
    echo "────────────────────────────────────────────────────────────────"
    echo "MODIFIED FILES"
    echo "────────────────────────────────────────────────────────────────"
    
    COMMON_FILES=$(comm -12 \
        <(find "$STAGING_PATH" -type f | sed "s|$STAGING_PATH/||" | sort) \
        <(find "$LIVE_PATH" -type f | sed "s|$LIVE_PATH/||" | sort))
    
    MODIFIED_COUNT=0
    if [[ -n "$COMMON_FILES" ]]; then
        while read -r file; do
            if ! diff -q "$STAGING_PATH/$file" "$LIVE_PATH/$file" > /dev/null 2>&1; then
                MODIFIED_COUNT=$((MODIFIED_COUNT + 1))
                LINES_ADDED=$(diff "$LIVE_PATH/$file" "$STAGING_PATH/$file" 2>/dev/null | grep -c '^>' || true)
                LINES_REMOVED=$(diff "$LIVE_PATH/$file" "$STAGING_PATH/$file" 2>/dev/null | grep -c '^<' || true)
                echo "  ~ $file (+$LINES_ADDED/-$LINES_REMOVED lines)"
            fi
        done <<< "$COMMON_FILES"
    fi
    
    if [[ $MODIFIED_COUNT -eq 0 ]]; then
        echo "  (none)"
    fi
    echo ""
    
    # === Git diff stat if applicable ===
    if [[ -d "${LIVE_PATH}/.git" ]]; then
        echo "────────────────────────────────────────────────────────────────"
        echo "GIT DIFF STAT (vs current HEAD)"
        echo "────────────────────────────────────────────────────────────────"
        
        # Create temp commit with staging content
        cd "$LIVE_PATH"
        echo "  (Live project is a git repo - use 'git diff' after promotion)"
        echo ""
    fi
    
    # === Full diff output ===
    if [[ "$FULL_DIFF" == "true" ]]; then
        echo "────────────────────────────────────────────────────────────────"
        echo "FULL DIFF OUTPUT"
        echo "────────────────────────────────────────────────────────────────"
        diff -rN "$LIVE_PATH" "$STAGING_PATH" 2>/dev/null || true
        echo ""
    fi
    
    # === Dangerous pattern scan ===
    echo "────────────────────────────────────────────────────────────────"
    echo "SECURITY SCAN"
    echo "────────────────────────────────────────────────────────────────"
    "${SCRIPT_DIR}/scan-dangerous.sh" "$STAGING_PATH" 2>/dev/null || echo "  (scan script not found)"
    echo ""
    
    echo "════════════════════════════════════════════════════════════════"
    echo "END OF REPORT"
    echo "════════════════════════════════════════════════════════════════"
}

if [[ -n "$OUTPUT_FILE" ]]; then
    generate_report > "$OUTPUT_FILE"
    echo "Report written to: $OUTPUT_FILE"
else
    generate_report
fi

