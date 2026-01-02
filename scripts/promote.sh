#!/bin/bash
# promote.sh - Promote changes from staging directory to live project
#
# Usage:
#   ./scripts/promote.sh /path/to/staging /path/to/live
#
# This script:
# 1. Shows a diff between staging and live
# 2. Requires explicit confirmation
# 3. Copies changes from staging to live

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 <staging_path> <live_path> [options]

Promote changes from staging directory to live project.

Options:
  --dry-run    Show what would be copied without actually copying
  --no-confirm Skip confirmation prompt (use with caution!)
  --delete     Delete files in live that don't exist in staging

Examples:
  $0 ./staging ./my-project
  $0 ./staging ./my-project --dry-run
  $0 ./staging ./my-project --delete
EOF
    exit 1
}

if [[ $# -lt 2 ]]; then
    usage
fi

STAGING_PATH="$1"
LIVE_PATH="$2"
shift 2

DRY_RUN=false
NO_CONFIRM=false
DELETE_FLAG=""

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-confirm)
            NO_CONFIRM=true
            shift
            ;;
        --delete)
            DELETE_FLAG="--delete"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate paths
if [[ ! -d "$STAGING_PATH" ]]; then
    log_error "Staging path does not exist: $STAGING_PATH"
    exit 1
fi

if [[ ! -d "$LIVE_PATH" ]]; then
    log_warn "Live path does not exist, will create: $LIVE_PATH"
    if [[ "$DRY_RUN" == "false" && "$NO_CONFIRM" == "false" ]]; then
        read -rp "Create live directory? [y/N] " response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Aborted."
            exit 0
        fi
        mkdir -p "$LIVE_PATH"
    fi
fi

# Make paths absolute
STAGING_PATH="$(cd "$STAGING_PATH" && pwd)"
LIVE_PATH="$(cd "$LIVE_PATH" 2>/dev/null && pwd)" || LIVE_PATH="$LIVE_PATH"

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║               STAGING PROMOTION REVIEW                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Staging: $STAGING_PATH"
echo "Live:    $LIVE_PATH"
echo ""

# Show diff summary
log_info "Changes to be promoted:"
echo ""

if command -v rsync &> /dev/null; then
    # Use rsync for detailed diff
    RSYNC_OPTS="-avh --itemize-changes"
    if [[ -n "$DELETE_FLAG" ]]; then
        RSYNC_OPTS="$RSYNC_OPTS $DELETE_FLAG"
    fi
    
    echo "--- rsync dry-run output ---"
    # shellcheck disable=SC2086
    rsync $RSYNC_OPTS --dry-run "$STAGING_PATH/" "$LIVE_PATH/" 2>/dev/null || true
    echo "--- end rsync output ---"
else
    # Fallback to diff
    if [[ -d "$LIVE_PATH" ]]; then
        diff -rq "$STAGING_PATH" "$LIVE_PATH" 2>/dev/null | head -50 || true
    else
        log_info "All files from staging will be copied (new directory)"
        find "$STAGING_PATH" -type f | head -50
    fi
fi

echo ""

# Check for potentially dangerous files
log_info "Scanning for potentially dangerous patterns..."
"${SCRIPT_DIR}/scan-dangerous.sh" "$STAGING_PATH" 2>/dev/null || true

echo ""

# Show git status if applicable
if [[ -d "${LIVE_PATH}/.git" ]]; then
    log_info "Live project is a git repository"
    log_info "After promotion, review with: cd $LIVE_PATH && git diff"
fi

# Confirmation
if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Dry run complete. No changes made."
    exit 0
fi

if [[ "$NO_CONFIRM" == "false" ]]; then
    echo ""
    echo -e "${YELLOW}⚠️  WARNING: This will overwrite files in the live project!${NC}"
    echo ""
    read -rp "Proceed with promotion? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

# Perform the copy
log_info "Promoting changes..."

if command -v rsync &> /dev/null; then
    RSYNC_OPTS="-avh"
    if [[ -n "$DELETE_FLAG" ]]; then
        RSYNC_OPTS="$RSYNC_OPTS $DELETE_FLAG"
    fi
    # shellcheck disable=SC2086
    rsync $RSYNC_OPTS "$STAGING_PATH/" "$LIVE_PATH/"
else
    cp -rv "$STAGING_PATH/"* "$LIVE_PATH/"
fi

log_info "Promotion complete!"

# Post-promotion suggestions
echo ""
log_info "Recommended next steps:"
if [[ -d "${LIVE_PATH}/.git" ]]; then
    echo "  1. cd $LIVE_PATH"
    echo "  2. git diff"
    echo "  3. git add -p  (review each change)"
    echo "  4. git commit -m 'Changes from Claude session'"
else
    echo "  1. Review the copied files manually"
    echo "  2. Consider initializing git: cd $LIVE_PATH && git init"
fi

