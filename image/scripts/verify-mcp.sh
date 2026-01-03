#!/bin/bash
# verify-mcp.sh - Verify MCP GitHub integration is working
#
# This script verifies that:
# 1. ~/.claude.json has MCP configuration (mcpServers)
# 2. GitHub token is present and valid
# 3. Token has correct permissions for the target repo
#
# Note: MCP servers are configured in ~/.claude.json (root config),
#       NOT in ~/.claude/settings.json (which is for permissions).
#
# Usage:
#   /opt/scripts/verify-mcp.sh [--verbose]
#
# Environment:
#   GITHUB_VERIFY_REPO  - Optional: repo to verify access to (owner/repo)
#   GITHUB_DEBUG        - Set to "1" for verbose output
#
# Exit codes:
#   0 - All checks passed
#   1 - Configuration error (missing settings, invalid JSON)
#   2 - Token error (missing, expired, or invalid)
#   3 - Permission error (can't access required resources)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

VERBOSE="${GITHUB_DEBUG:-0}"
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE="1"
fi

# Track overall status
STATUS=0
WARNINGS=0

log_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1" >&2
    WARNINGS=$((WARNINGS + 1))
}

log_fail() {
    echo -e "${RED}✗${NC} $1" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "1" ]]; then
        echo -e "  ${1}" >&2
    fi
}

# Check 1: ~/.claude.json exists and has MCP config
check_settings() {
    # MCP servers are configured in ~/.claude.json (root config file),
    # NOT in ~/.claude/settings.json (which is for permissions)
    local claude_config="${HOME}/.claude.json"
    
    if [[ ! -f "$claude_config" ]]; then
        log_fail "Claude config not found: $claude_config"
        log_debug "MCP servers must be configured in ~/.claude.json"
        return 1
    fi
    
    # Verify it's valid JSON
    if ! jq empty "$claude_config" 2>/dev/null; then
        log_fail "Claude config is not valid JSON"
        return 1
    fi
    
    # Check for mcpServers.github
    local has_github
    has_github=$(jq -r '.mcpServers.github // empty' "$claude_config")
    
    if [[ -z "$has_github" ]]; then
        log_fail "No MCP GitHub server configured in ~/.claude.json"
        log_debug "Expected: .mcpServers.github object"
        return 1
    fi
    
    # Check for token in MCP config
    local token
    token=$(jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN // empty' "$claude_config")
    
    if [[ -z "$token" ]]; then
        log_fail "No GitHub token in MCP configuration"
        return 1
    fi
    
    # Mask token for display
    local token_preview="${token:0:10}...${token: -4}"
    log_ok "MCP config found with token: ${token_preview}"
    
    # Export for later checks
    export MCP_TOKEN="$token"
    return 0
}

# Check 2: Token is valid (not expired)
check_token_valid() {
    local token="${MCP_TOKEN:-}"
    
    if [[ -z "$token" ]]; then
        log_fail "No token available for validation"
        return 2
    fi
    
    # Test token with a simple API call
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/user" 2>/dev/null)
    
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')
    
    case "$http_code" in
        200)
            local login
            login=$(echo "$body" | jq -r '.login // "unknown"')
            log_ok "Token valid - authenticated as: ${login}"
            return 0
            ;;
        401)
            log_fail "Token is invalid or expired"
            log_debug "HTTP 401: Bad credentials"
            return 2
            ;;
        403)
            # Installation tokens return 403 for /user but may still work for repo operations
            # Try to get rate limit info instead
            local rate_response
            rate_response=$(curl -s \
                -H "Authorization: Bearer ${token}" \
                -H "Accept: application/vnd.github+json" \
                "https://api.github.com/rate_limit" 2>/dev/null)
            
            local remaining
            remaining=$(echo "$rate_response" | jq -r '.rate.remaining // 0')
            
            if [[ "$remaining" -gt 0 ]]; then
                log_ok "Token valid (installation token) - rate limit remaining: ${remaining}"
                return 0
            else
                log_fail "Token rejected (HTTP 403)"
                return 2
            fi
            ;;
        *)
            log_warn "Unexpected response (HTTP ${http_code})"
            log_debug "Response: ${body}"
            return 2
            ;;
    esac
}

# Check 3: Can access target repository (if specified)
check_repo_access() {
    local repo="${GITHUB_VERIFY_REPO:-}"
    local token="${MCP_TOKEN:-}"
    
    if [[ -z "$repo" ]]; then
        log_debug "GITHUB_VERIFY_REPO not set, skipping repo access check"
        return 0
    fi
    
    if [[ -z "$token" ]]; then
        log_warn "No token for repo access check"
        return 0
    fi
    
    local response
    local http_code
    
    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${repo}" 2>/dev/null)
    
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | sed '$d')
    
    case "$http_code" in
        200)
            local permissions
            permissions=$(echo "$body" | jq -r '.permissions | to_entries | map(select(.value == true) | .key) | join(", ")' 2>/dev/null || echo "unknown")
            log_ok "Repository access: ${repo} (${permissions})"
            return 0
            ;;
        404)
            log_fail "Repository not found or no access: ${repo}"
            return 3
            ;;
        403)
            log_fail "Permission denied for repository: ${repo}"
            return 3
            ;;
        *)
            log_warn "Unexpected response for repo check (HTTP ${http_code})"
            return 3
            ;;
    esac
}

# Check 4: MCP server can be started (optional, heavier check)
check_mcp_server_startup() {
    if [[ "$VERBOSE" != "1" ]]; then
        return 0
    fi
    
    if ! command -v npx >/dev/null 2>&1; then
        log_warn "npx not available, cannot test MCP server startup"
        return 0
    fi
    
    log_debug "Testing MCP server startup (this may take a moment)..."
    
    # Try to start the MCP server and immediately send a tool list request
    # The server should respond with available tools
    if ! command -v timeout >/dev/null 2>&1; then
        # macOS doesn't have timeout by default
        log_debug "timeout command not available, skipping MCP server test"
        return 0
    fi
    
    # Start MCP server with token, capture output
    local token="${MCP_TOKEN:-}"
    local output
    output=$(GITHUB_PERSONAL_ACCESS_TOKEN="$token" timeout 10 npx -y @github/github-mcp-server 2>&1 || true)
    
    if echo "$output" | grep -qi "error\|failed\|cannot"; then
        log_warn "MCP server startup may have issues"
        log_debug "Output: ${output:0:200}..."
    else
        log_ok "MCP server startup check passed"
    fi
    
    return 0
}

# Main
main() {
    echo "=== MCP GitHub Integration Verification ==="
    echo ""
    
    # Run checks
    if ! check_settings; then
        STATUS=1
    fi
    
    if [[ $STATUS -eq 0 ]]; then
        if ! check_token_valid; then
            STATUS=2
        fi
    fi
    
    if [[ $STATUS -eq 0 ]]; then
        if ! check_repo_access; then
            STATUS=3
        fi
    fi
    
    check_mcp_server_startup
    
    echo ""
    
    # Summary
    if [[ $STATUS -eq 0 ]]; then
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}MCP verification completed with ${WARNINGS} warning(s)${NC}"
        else
            echo -e "${GREEN}MCP verification passed${NC}"
        fi
    else
        echo -e "${RED}MCP verification failed (exit code: ${STATUS})${NC}"
    fi
    
    return $STATUS
}

main "$@"

