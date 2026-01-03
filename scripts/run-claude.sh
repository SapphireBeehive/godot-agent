#!/bin/bash
# run-claude.sh - Launches the Claude Code CLI inside the sandbox
#
# Usage:
#   ./scripts/run-claude.sh direct /path/to/project
#   ./scripts/run-claude.sh staging /path/to/staging [/path/to/live]
#   ./scripts/run-claude.sh offline /path/to/project
#
# Prerequisites:
#   - Docker and docker compose installed
#   - Authentication configured (see ./scripts/setup-claude-auth.sh)
#     Option 1: CLAUDE_CODE_OAUTH_TOKEN in .env (run: claude setup-token)
#     Option 2: ANTHROPIC_API_KEY in .env file (pay-per-use)
#   - Agent image built (run ./scripts/build.sh first)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${PROJECT_ROOT}/compose"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
Usage: $0 <mode> <project_path> [staging_live_path]

Modes:
  direct   - Mount project directly (fast, but agent can modify files)
  staging  - Mount staging directory only (safer, requires promotion)
  offline  - No network access at all (maximum isolation)

Examples:
  $0 direct /path/to/my/godot/project
  $0 staging /path/to/staging
  $0 offline /path/to/project

Environment variables:
  ANTHROPIC_API_KEY       - API key for Claude (pay-per-use)
  CLAUDE_CODE_OAUTH_TOKEN - OAuth token from Claude Max subscription
  AGENT_MEMORY_LIMIT      - Container memory limit (default: 2G)
  AGENT_CPU_LIMIT         - Container CPU limit (default: 2.0)

Authentication (choose one):
  - ANTHROPIC_API_KEY: API key from console.anthropic.com (pay-per-use)
  - CLAUDE_CODE_OAUTH_TOKEN: Run 'claude setup-token' (included with Max subscription)
EOF
    exit 1
}

# Validate arguments
if [[ $# -lt 2 ]]; then
    usage
fi

MODE="$1"
PROJECT_PATH="$2"

# Validate mode
case "$MODE" in
    direct|staging|offline)
        ;;
    *)
        log_error "Invalid mode: $MODE"
        usage
        ;;
esac

# Validate project path
if [[ ! -d "$PROJECT_PATH" ]]; then
    log_error "Project path does not exist: $PROJECT_PATH"
    exit 1
fi

# Make paths absolute
PROJECT_PATH="$(cd "$PROJECT_PATH" && pwd)"

# Load environment
if [[ -f "${PROJECT_ROOT}/.env" ]]; then
    # shellcheck disable=SC1091
    source "${PROJECT_ROOT}/.env"
else
    log_warn ".env file not found."
fi

# Validate authentication for non-offline modes
if [[ "$MODE" != "offline" ]]; then
    # Check for API key (takes priority)
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        log_info "Authentication: API key (ANTHROPIC_API_KEY)"
    # Check for OAuth token (Claude Max subscription)
    elif [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        log_info "Authentication: Claude Max (CLAUDE_CODE_OAUTH_TOKEN)"
    else
        log_error "No Claude authentication found!"
        echo ""
        echo "You need one of these in your .env file:"
        echo ""
        echo "  Option 1 - Claude Max subscription (recommended):"
        echo "    Run: claude setup-token"
        echo "    Add: CLAUDE_CODE_OAUTH_TOKEN=sk-ant-..."
        echo ""
        echo "  Option 2 - API key (pay-per-use):"
        echo "    Add: ANTHROPIC_API_KEY=sk-ant-..."
        echo ""
        exit 1
    fi
fi

# Create logs directory
mkdir -p "$LOGS_DIR"

# Generate timestamp for log file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOGS_DIR}/claude_${MODE}_${TIMESTAMP}.log"

log_info "Claude-Godot Sandbox"
log_info "Mode: $MODE"
log_info "Project path: $PROJECT_PATH"
log_info "Log file: $LOG_FILE"
echo ""

# Start infrastructure services if needed
if [[ "$MODE" != "offline" ]]; then
    log_info "Starting infrastructure services (DNS + proxies)..."
    
    cd "$COMPOSE_DIR"
    docker compose -f compose.base.yml up -d
    
    log_info "Waiting for services to be ready..."
    sleep 3
fi

# Build compose command based on mode
cd "$COMPOSE_DIR"

case "$MODE" in
    direct)
        export PROJECT_PATH
        COMPOSE_CMD="docker compose -f compose.base.yml -f compose.direct.yml"
        ;;
    staging)
        export STAGING_PATH="$PROJECT_PATH"
        COMPOSE_CMD="docker compose -f compose.base.yml -f compose.staging.yml"
        ;;
    offline)
        export PROJECT_PATH
        COMPOSE_CMD="docker compose -f compose.offline.yml"
        ;;
esac

log_info "Starting agent container..."

# Run the agent container interactively with Claude Code
# The command runs inside the container and logs are captured
{
    echo "=== Claude Session Started ==="
    echo "Timestamp: $(date)"
    echo "Mode: $MODE"
    echo "Project: $PROJECT_PATH"
    echo "=========================="
    echo ""
} >> "$LOG_FILE"

# Check if claude command exists in the image
# If not, provide helpful error message
$COMPOSE_CMD run --rm agent bash -c '
    if command -v claude &> /dev/null; then
        echo "Starting Claude Code CLI..."
        claude --help 2>&1 || echo "Claude CLI available but may need configuration"
        echo ""
        echo "To start a Claude session, run: claude"
        echo "To run with a prompt: claude \"your prompt here\""
        echo ""
        exec bash
    else
        echo "WARNING: Claude Code CLI not found in container"
        echo ""
        echo "The Claude Code CLI may not be installed yet."
        echo "Please check image/install/install_claude_code.sh for installation details."
        echo ""
        echo "For now, you can use this shell for Godot and git operations."
        echo "Godot is available at: $(which godot 2>/dev/null || echo "not found")"
        echo ""
        exec bash
    fi
' 2>&1 | tee -a "$LOG_FILE"

# Capture exit status
EXIT_STATUS=${PIPESTATUS[0]}

{
    echo ""
    echo "=== Claude Session Ended ==="
    echo "Timestamp: $(date)"
    echo "Exit status: $EXIT_STATUS"
    echo "=========================="
} >> "$LOG_FILE"

log_info "Session ended. Logs saved to: $LOG_FILE"

# If in staging mode, remind about promotion
if [[ "$MODE" == "staging" ]]; then
    echo ""
    log_info "To review and promote changes from staging:"
    log_info "  ./scripts/diff-review.sh $PROJECT_PATH /path/to/live/project"
    log_info "  ./scripts/promote.sh $PROJECT_PATH /path/to/live/project"
fi

exit $EXIT_STATUS

