#!/bin/bash
# run-godot.sh - Run Godot headless commands inside the sandbox
#
# Usage:
#   ./scripts/run-godot.sh /path/to/project --version
#   ./scripts/run-godot.sh /path/to/project -s res://tests/run.gd
#   ./scripts/run-godot.sh /path/to/project --quit-after 1000
#
# All arguments after the project path are passed directly to Godot.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${PROJECT_ROOT}/compose"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 <project_path> [godot_args...]

Run Godot headless commands inside the sandbox container.

Examples:
  $0 /path/to/project --version
  $0 /path/to/project --headless -s res://tests/run.gd
  $0 /path/to/project --headless --quit-after 1000
  $0 /path/to/project --headless --export-release "Linux" build/game.x86_64

Common Godot headless options:
  --version          Print version
  -s <script>        Run a script
  --quit-after <ms>  Quit after N milliseconds
  --export-release   Export project
  --validate-project Validate project files
  --doctor           Run project doctor

Note: --headless flag is automatically added if not present.
EOF
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

PROJECT_PATH="$1"
shift

# Validate project path
if [[ ! -d "$PROJECT_PATH" ]]; then
    log_error "Project path does not exist: $PROJECT_PATH"
    exit 1
fi

# Make path absolute
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# Collect Godot arguments
GODOT_ARGS=("$@")

# Add --headless if not already present
HAS_HEADLESS=false
for arg in "${GODOT_ARGS[@]}"; do
    if [[ "$arg" == "--headless" ]]; then
        HAS_HEADLESS=true
        break
    fi
done

if [[ "$HAS_HEADLESS" == "false" ]]; then
    GODOT_ARGS=("--headless" "${GODOT_ARGS[@]}")
fi

log_info "Running Godot headless in sandbox"
log_info "Project: $PROJECT_PATH"
log_info "Command: godot ${GODOT_ARGS[*]}"
echo ""

# Use offline compose for Godot operations (no network needed)
cd "$COMPOSE_DIR"
export PROJECT_PATH

docker compose -f compose.offline.yml run --rm agent \
    godot "${GODOT_ARGS[@]}"

