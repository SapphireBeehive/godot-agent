#!/bin/bash
# setup-claude-auth.sh - Configure Claude authentication for the sandbox
#
# Usage:
#   ./scripts/setup-claude-auth.sh [status|setup-token]
#
# This script helps you authenticate Claude Code with your Claude Max subscription
# using a long-lived OAuth token.
#
# Prerequisites:
#   - Claude Code CLI installed on host (npm install -g @anthropic-ai/claude-code)
#   - Claude Max subscription

set -euo pipefail

# Save original directory and restore on exit
ORIGINAL_DIR="$(pwd)"
cleanup() {
    cd "$ORIGINAL_DIR" 2>/dev/null || true
}
trap cleanup EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

log_hint() {
    echo -e "${BLUE}[HINT]${NC} $1"
}

check_claude_installed() {
    if ! command -v claude &> /dev/null; then
        log_error "Claude Code CLI not found on your host machine."
        echo ""
        echo "Install it with:"
        echo "  npm install -g @anthropic-ai/claude-code"
        echo ""
        echo "Then run this script again."
        exit 1
    fi
}

show_status() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            CLAUDE AUTHENTICATION STATUS                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Load .env if present
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        # shellcheck disable=SC1091
        source "${PROJECT_ROOT}/.env"
    fi
    
    HAS_AUTH=false
    
    # Check for API key
    echo "API Key Authentication:"
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        if [[ "${ANTHROPIC_API_KEY}" =~ ^sk-ant- ]]; then
            echo -e "  ${GREEN}✓${NC} ANTHROPIC_API_KEY is set (sk-ant-...)"
        else
            echo -e "  ${YELLOW}!${NC} ANTHROPIC_API_KEY is set (unusual format)"
        fi
        HAS_AUTH=true
    else
        echo -e "  ${BLUE}○${NC} ANTHROPIC_API_KEY is not set"
    fi
    echo ""
    
    # Check for OAuth token
    echo "Claude Max OAuth Token:"
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        if [[ "${CLAUDE_CODE_OAUTH_TOKEN}" =~ ^sk-ant- ]]; then
            echo -e "  ${GREEN}✓${NC} CLAUDE_CODE_OAUTH_TOKEN is set (sk-ant-...)"
        else
            echo -e "  ${YELLOW}!${NC} CLAUDE_CODE_OAUTH_TOKEN is set (unusual format)"
        fi
        HAS_AUTH=true
    else
        echo -e "  ${BLUE}○${NC} CLAUDE_CODE_OAUTH_TOKEN is not set"
    fi
    echo ""
    
    # Check .env file
    echo ".env File:"
    if [[ -f "${PROJECT_ROOT}/.env" ]]; then
        echo -e "  ${GREEN}✓${NC} .env file exists"
    else
        echo -e "  ${YELLOW}!${NC} .env file not found"
        log_hint "Run: cp .env.example .env"
    fi
    echo ""
    
    # Summary
    echo "════════════════════════════════════════════════════════════════"
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        echo -e "${GREEN}Ready:${NC} Using API key authentication (pay-per-use)"
    elif [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        echo -e "${GREEN}Ready:${NC} Using Claude Max subscription"
    else
        echo -e "${YELLOW}Action needed:${NC} Set up authentication"
        echo ""
        echo "To authenticate with Claude Max (recommended):"
        echo ""
        echo "  ${GREEN}Step 1:${NC} Generate OAuth token"
        echo "    claude setup-token"
        echo ""
        echo "  ${GREEN}Step 2:${NC} Add token to .env file"
        echo "    echo 'CLAUDE_CODE_OAUTH_TOKEN=sk-ant-...' >> .env"
        echo ""
        echo "Or for API key (pay-per-use):"
        echo "    echo 'ANTHROPIC_API_KEY=sk-ant-...' >> .env"
    fi
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

do_setup_token() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║         GENERATE CLAUDE MAX OAUTH TOKEN                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_claude_installed
    
    log_info "Running 'claude setup-token'..."
    echo ""
    echo "This will generate a long-lived OAuth token (valid for 1 year)."
    echo "A browser window may open for authentication."
    echo ""
    
    # Run claude setup-token (pushd/popd to preserve working directory)
    pushd "$ORIGINAL_DIR" > /dev/null
    if claude setup-token; then
        popd > /dev/null
        echo ""
        log_info "Token generated successfully!"
        echo ""
        echo "Add the token to your .env file:"
        echo "  echo 'CLAUDE_CODE_OAUTH_TOKEN=<your-token>' >> ${PROJECT_ROOT}/.env"
        echo ""
        log_hint "Then verify with: ./scripts/setup-claude-auth.sh status"
    else
        popd > /dev/null
        log_error "Token generation failed. Please try again."
        exit 1
    fi
}

usage() {
    cat << EOF
Usage: $0 [command]

Commands:
  status       - Show current authentication status (default)
  setup-token  - Generate a long-lived OAuth token for Claude Max

Examples:
  $0                # Show status
  $0 status         # Show status
  $0 setup-token    # Generate OAuth token

Authentication Methods:
  1. Claude Max subscription (recommended):
     - Run 'claude setup-token' to generate an OAuth token
     - Add CLAUDE_CODE_OAUTH_TOKEN to your .env file
     - Token is valid for 1 year

  2. API Key (pay-per-use):
     - Get key from console.anthropic.com
     - Add ANTHROPIC_API_KEY to your .env file
EOF
}

# Main
case "${1:-status}" in
    status)
        show_status
        ;;
    setup-token)
        do_setup_token
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
