#!/bin/bash
# scan-dangerous.sh - Scan Godot project for potentially dangerous API usage
#
# Usage:
#   ./scripts/scan-dangerous.sh /path/to/project
#
# This script greps for Godot APIs that could be used for:
# - Arbitrary code execution (OS.execute, JavaScript.eval)
# - File system access outside project
# - Network operations
# - Loading external code

set -euo pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project_path>" >&2
    exit 1
fi

PROJECT_PATH="$1"

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: Project path does not exist: $PROJECT_PATH" >&2
    exit 1
fi

echo "Scanning for potentially dangerous Godot API usage..."
echo "Project: $PROJECT_PATH"
echo ""

FOUND_ISSUES=0

# Function to search and report
search_pattern() {
    local pattern="$1"
    local description="$2"
    local severity="$3"  # HIGH, MEDIUM, LOW
    
    # Search in GDScript files
    local results
    results=$(grep -rn --include="*.gd" --include="*.gdscript" "$pattern" "$PROJECT_PATH" 2>/dev/null || true)
    
    if [[ -n "$results" ]]; then
        FOUND_ISSUES=$((FOUND_ISSUES + 1))
        
        case "$severity" in
            HIGH)
                echo -e "${RED}[HIGH]${NC} $description"
                ;;
            MEDIUM)
                echo -e "${YELLOW}[MEDIUM]${NC} $description"
                ;;
            LOW)
                echo -e "${CYAN}[LOW]${NC} $description"
                ;;
        esac
        
        echo "  Pattern: $pattern"
        echo "$results" | head -10 | sed 's/^/  /'
        if [[ $(echo "$results" | wc -l) -gt 10 ]]; then
            echo "  ... and more matches"
        fi
        echo ""
    fi
}

# === HIGH SEVERITY: Code Execution ===
search_pattern "OS\.execute" \
    "OS.execute - Can run arbitrary system commands" \
    "HIGH"

search_pattern "OS\.create_process" \
    "OS.create_process - Can spawn external processes" \
    "HIGH"

search_pattern "Expression\.execute" \
    "Expression.execute - Dynamic code execution" \
    "HIGH"

search_pattern "JavaScript\.eval" \
    "JavaScript.eval - Can execute arbitrary JavaScript (web export)" \
    "HIGH"

search_pattern "GDScript\.new\(\)" \
    "GDScript.new() - Dynamic script creation" \
    "HIGH"

search_pattern "ResourceLoader\.load.*user://" \
    "Loading resources from user:// - Could load malicious scripts" \
    "HIGH"

# === MEDIUM SEVERITY: File System Access ===
search_pattern "FileAccess\.open" \
    "FileAccess.open - File system access" \
    "MEDIUM"

search_pattern "DirAccess\." \
    "DirAccess - Directory manipulation" \
    "MEDIUM"

search_pattern '"/home' \
    "Absolute path outside project (Linux home)" \
    "MEDIUM"

search_pattern '"/Users' \
    "Absolute path outside project (macOS home)" \
    "MEDIUM"

search_pattern '"C:\\' \
    "Absolute path outside project (Windows)" \
    "MEDIUM"

# === MEDIUM SEVERITY: Network Operations ===
search_pattern "HTTPRequest" \
    "HTTPRequest - Network communication" \
    "MEDIUM"

search_pattern "HTTPClient" \
    "HTTPClient - Low-level network access" \
    "MEDIUM"

search_pattern "TCPServer" \
    "TCPServer - Opens network ports" \
    "MEDIUM"

search_pattern "UDPServer" \
    "UDPServer - Opens network ports" \
    "MEDIUM"

search_pattern "WebSocketPeer" \
    "WebSocketPeer - WebSocket communication" \
    "MEDIUM"

search_pattern "ENetMultiplayerPeer" \
    "ENetMultiplayerPeer - Network multiplayer" \
    "MEDIUM"

# === LOW SEVERITY: Worth noting ===
search_pattern "load.*\.gd" \
    "Dynamic script loading" \
    "LOW"

search_pattern "preload.*\.gd" \
    "Preloaded scripts (check paths)" \
    "LOW"

search_pattern "get_tree\(\)\.change_scene" \
    "Scene changing (review scene paths)" \
    "LOW"

# === Check for .import files that might reference external resources ===
IMPORT_FILES=$(find "$PROJECT_PATH" -name "*.import" 2>/dev/null | wc -l || echo "0")
if [[ "$IMPORT_FILES" -gt 0 ]]; then
    echo -e "${CYAN}[INFO]${NC} Found $IMPORT_FILES .import files"
    echo "  These define how resources are imported. Review if unfamiliar."
    echo ""
fi

# === Summary ===
echo "────────────────────────────────────────────────────────────────"
if [[ $FOUND_ISSUES -eq 0 ]]; then
    echo -e "${CYAN}No potentially dangerous patterns found.${NC}"
else
    echo -e "Found ${YELLOW}$FOUND_ISSUES${NC} categories of potentially dangerous patterns."
    echo ""
    echo "Review these patterns carefully before running the project."
    echo "Not all matches are malicious - many are legitimate uses."
    echo ""
    echo "Recommendations:"
    echo "  1. Review the context of each match"
    echo "  2. Verify the code does what you expect"
    echo "  3. Test in sandbox before running on host"
fi

