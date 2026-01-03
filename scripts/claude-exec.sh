#!/bin/bash
# claude-exec.sh - Execute Claude commands in a running agent container
#
# Usage:
#   ./scripts/claude-exec.sh                    # Interactive Claude session
#   ./scripts/claude-exec.sh "your prompt"      # Single prompt, returns when done
#   ./scripts/claude-exec.sh --shell            # Open bash shell in container
#
# Prerequisites:
#   - Agent container must be running (use: make up-agent PROJECT=/path)
#   - Authentication configured in .env file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${PROJECT_ROOT}/compose"
LOGS_DIR="${PROJECT_ROOT}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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
Usage: $0 [options] [prompt]

Execute Claude commands in the running agent container.

Options:
  --shell, -s     Open a bash shell instead of Claude
  --print, -p     Enable print mode for non-interactive/batch use
                  (outputs result without interactive prompts)
  --help, -h      Show this help message

Arguments:
  prompt          Optional prompt to send to Claude (runs non-interactively)
                  If omitted, opens interactive Claude session

Examples:
  $0                                     # Interactive Claude session
  $0 "What files are in this project?"   # Single prompt
  $0 "Add a jump mechanic to player.gd"  # Single prompt
  $0 --shell                             # Open bash shell
  $0 --print "List all .gd files"        # Non-interactive batch mode

Non-Interactive Mode:
  When running from scripts, CI/CD, or other automation contexts:
  1. The script auto-detects TTY availability and adjusts accordingly
  2. Use --print flag for fully non-interactive output
  3. Claude Code settings in the container auto-approve file operations

Prerequisites:
  Start the agent first with: make up-agent PROJECT=/path/to/project
EOF
    exit 0
}

# Parse arguments
OPEN_SHELL=false
PRINT_MODE=false
PROMPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --shell|-s)
            OPEN_SHELL=true
            shift
            ;;
        --print|-p)
            PRINT_MODE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            # Collect remaining args as prompt
            PROMPT="$*"
            break
            ;;
    esac
done

# Check if agent container is running
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agent$'; then
    # Check if there's a one-shot agent running instead
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'claude-godot-sandbox-agent-run'; then
        log_error "A one-shot agent container is running, but 'make claude' requires the persistent agent named 'agent'."
        echo ""
        echo "Stop the one-shot container with:"
        echo "  docker stop \$(docker ps -q -f name=claude-godot-sandbox-agent-run)"
        echo ""
        echo "Then start the persistent agent with:"
        echo "  make up-agent PROJECT=/path/to/your/project"
    else
        log_error "Agent container is not running."
        echo ""
        echo "Start it with:"
        echo "  make up-agent PROJECT=/path/to/your/project"
        echo ""
        echo "Or for one-off sessions (no persistent container):"
        echo "  make run-direct PROJECT=/path/to/your/project"
    fi
    exit 1
fi

# Get container info
CONTAINER_PROJECT=$(docker exec agent pwd 2>/dev/null || echo "/project")
log_info "Agent container is running (workdir: ${CONTAINER_PROJECT})"

# Create logs directory
mkdir -p "$LOGS_DIR"

# Detect TTY availability for docker exec flags
# When running from non-interactive contexts (CI, scripts, automation),
# -it flags will fail with "the input device is not a TTY"
if [[ -t 0 ]] && [[ "$PRINT_MODE" != "true" ]]; then
    # TTY available and not in print mode - use interactive mode
    TTY_FLAGS="-it"
else
    # No TTY or print mode - non-interactive mode
    TTY_FLAGS=""
    if [[ -z "$PROMPT" ]] && [[ "$OPEN_SHELL" != "true" ]]; then
        log_warn "No TTY available. Running in non-interactive mode."
        log_warn "Provide a prompt with: make claude P=\"your prompt\""
    fi
fi

# Build Claude CLI arguments
CLAUDE_ARGS=""
if [[ "$PRINT_MODE" == "true" ]]; then
    # Print mode: outputs result without interactive prompts
    CLAUDE_ARGS="--print"
fi

if [[ "$OPEN_SHELL" == "true" ]]; then
    # Open bash shell (no logging for shell sessions)
    log_info "Opening bash shell in agent container..."
    # shellcheck disable=SC2086
    exec docker exec $TTY_FLAGS agent bash
elif [[ -n "$PROMPT" ]]; then
    # Run single prompt with logging
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="${LOGS_DIR}/claude_prompt_${TIMESTAMP}.log"
    
    if [[ "$PRINT_MODE" != "true" ]]; then
        echo -e "${CYAN}Prompt:${NC} $PROMPT"
        echo -e "${GREEN}Logging to:${NC} $LOG_FILE"
        echo ""
    fi
    
    # Write session header to log
    {
        echo "=== Claude Prompt Session ==="
        echo "Timestamp: $(date)"
        echo "Prompt: $PROMPT"
        echo "Mode: $([ "$PRINT_MODE" == "true" ] && echo "print" || echo "interactive")"
        echo "=========================="
        echo ""
    } >> "$LOG_FILE"
    
    # Execute and capture output
    # shellcheck disable=SC2086
    docker exec $TTY_FLAGS agent claude $CLAUDE_ARGS "$PROMPT" 2>&1 | tee -a "$LOG_FILE"
    EXIT_STATUS=${PIPESTATUS[0]}
    
    # Write session footer to log
    {
        echo ""
        echo "=== Session Ended ==="
        echo "Timestamp: $(date)"
        echo "Exit status: $EXIT_STATUS"
        echo "==================="
    } >> "$LOG_FILE"
    
    if [[ "$PRINT_MODE" != "true" ]]; then
        echo ""
        log_info "Logs saved to: $LOG_FILE"
    fi
    
    exit $EXIT_STATUS
else
    # Interactive Claude session
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    LOG_FILE="${LOGS_DIR}/claude_interactive_${TIMESTAMP}.log"
    
    log_info "Starting interactive Claude session..."
    log_info "Logging to: $LOG_FILE"
    echo -e "${YELLOW}Tip:${NC} Type 'exit' or Ctrl+D to leave Claude"
    echo ""
    
    # Write session header to log
    {
        echo "=== Claude Interactive Session ==="
        echo "Timestamp: $(date)"
        echo "Mode: interactive"
        echo "================================"
        echo ""
    } >> "$LOG_FILE"
    
    # For interactive sessions, we can't easily capture all output without interfering
    # So we'll log that the session started and use docker logs for full output
    log_info "Note: Full session output available via: docker logs agent"
    log_info "This log file will record session start/end times only."
    echo ""
    
    # Execute interactive session (output goes to terminal, not log file)
    # shellcheck disable=SC2086
    docker exec $TTY_FLAGS agent claude $CLAUDE_ARGS
    
    # Write session footer to log
    {
        echo ""
        echo "=== Session Ended ==="
        echo "Timestamp: $(date)"
        echo "==================="
    } >> "$LOG_FILE"
    
    log_info "Session ended. Log file: $LOG_FILE"
    log_info "For full output, see: docker logs agent"
fi

