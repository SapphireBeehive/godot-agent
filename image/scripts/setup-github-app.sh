#!/bin/bash
# setup-github-app.sh - Sets up GitHub App MCP integration for Claude Code
#
# This script generates an installation token from GitHub App credentials
# and configures the MCP server for Claude Code to use.
#
# Required environment variables:
#   GITHUB_APP_ID              - The GitHub App's ID
#   GITHUB_APP_INSTALLATION_ID - The installation ID for the target org/user
#
# One of these for the private key:
#   GITHUB_APP_PRIVATE_KEY     - The private key content (base64 encoded)
#   GITHUB_APP_PRIVATE_KEY_PATH - Path to the private key file (inside container)
#
# Optional:
#   GITHUB_APP_REPOSITORIES    - Comma-separated list of repo names to scope token
#
# Usage:
#   source /opt/scripts/setup-github-app.sh
#   # or
#   . /opt/scripts/setup-github-app.sh
#
# After sourcing, GITHUB_TOKEN will be set with the installation token

# shellcheck disable=SC2317  # return/exit pattern for sourced scripts
set -euo pipefail

# Check if GitHub App is configured
if [[ -z "${GITHUB_APP_ID:-}" ]]; then
    if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: GITHUB_APP_ID not set, skipping GitHub App setup" >&2
    fi
    return 0 2>/dev/null || exit 0
fi

if [[ -z "${GITHUB_APP_INSTALLATION_ID:-}" ]]; then
    echo "WARNING: GITHUB_APP_INSTALLATION_ID not set, skipping GitHub App setup" >&2
    return 0 2>/dev/null || exit 0
fi

# Get private key
PRIVATE_KEY=""

if [[ -n "${GITHUB_APP_PRIVATE_KEY:-}" ]]; then
    # Decode base64 private key
    PRIVATE_KEY=$(echo "${GITHUB_APP_PRIVATE_KEY}" | base64 -d)
    if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
        echo "DEBUG: Using GITHUB_APP_PRIVATE_KEY (base64 decoded)" >&2
    fi
elif [[ -n "${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]]; then
    if [[ -f "${GITHUB_APP_PRIVATE_KEY_PATH}" ]]; then
        PRIVATE_KEY=$(cat "${GITHUB_APP_PRIVATE_KEY_PATH}")
        if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
            echo "DEBUG: Using private key from ${GITHUB_APP_PRIVATE_KEY_PATH}" >&2
        fi
    else
        echo "ERROR: Private key file not found: ${GITHUB_APP_PRIVATE_KEY_PATH}" >&2
        return 1 2>/dev/null || exit 1
    fi
else
    echo "WARNING: No GitHub App private key configured, skipping" >&2
    echo "  Set GITHUB_APP_PRIVATE_KEY (base64) or GITHUB_APP_PRIVATE_KEY_PATH" >&2
    return 0 2>/dev/null || exit 0
fi

# Write private key to temp file (needed for JWT signing)
TEMP_KEY_FILE=$(mktemp)
echo "${PRIVATE_KEY}" > "${TEMP_KEY_FILE}"
chmod 600 "${TEMP_KEY_FILE}"

# Cleanup function
cleanup() {
    rm -f "${TEMP_KEY_FILE}" 2>/dev/null || true
}
trap cleanup EXIT

# Generate JWT using Python (requires PyJWT)
generate_jwt() {
    python3 << EOF
import time
import jwt

# Read private key
with open("${TEMP_KEY_FILE}") as f:
    private_key = f.read()

# Generate JWT
now = int(time.time())
payload = {
    "iat": now,
    "exp": now + 600,  # 10 minutes
    "iss": "${GITHUB_APP_ID}"
}

token = jwt.encode(payload, private_key, algorithm="RS256")
print(token)
EOF
}

# Generate installation token using the JWT
generate_installation_token() {
    local jwt_token="$1"
    local api_url="https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens"
    
    # Build request body for repository scoping
    local body="{}"
    if [[ -n "${GITHUB_APP_REPOSITORIES:-}" ]]; then
        # Convert comma-separated list to JSON array
        local repos_json
        repos_json=$(echo "${GITHUB_APP_REPOSITORIES}" | tr ',' '\n' | jq -R . | jq -s .)
        body="{\"repositories\": ${repos_json}}"
    fi
    
    # Make API request
    local response
    response=$(curl -s -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${jwt_token}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "${body}" \
        "${api_url}")
    
    # Extract token
    echo "${response}" | jq -r '.token // empty'
}

echo "Setting up GitHub App MCP integration..." >&2

# Check for required tools
if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 not found, cannot generate JWT" >&2
    return 1 2>/dev/null || exit 1
fi

if ! python3 -c "import jwt" 2>/dev/null; then
    echo "ERROR: PyJWT not installed, cannot generate JWT" >&2
    echo "  Install with: uv pip install --system PyJWT cryptography" >&2
    return 1 2>/dev/null || exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq not found, cannot parse API response" >&2
    return 1 2>/dev/null || exit 1
fi

# Generate JWT
if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
    echo "DEBUG: Generating JWT for app authentication..." >&2
fi

JWT_TOKEN=$(generate_jwt)
if [[ -z "${JWT_TOKEN}" ]]; then
    echo "ERROR: Failed to generate JWT" >&2
    return 1 2>/dev/null || exit 1
fi

if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
    echo "DEBUG: JWT generated successfully" >&2
fi

# Generate installation token
if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
    echo "DEBUG: Generating installation token..." >&2
fi

INSTALLATION_TOKEN=$(generate_installation_token "${JWT_TOKEN}")
if [[ -z "${INSTALLATION_TOKEN}" ]]; then
    echo "ERROR: Failed to generate installation token" >&2
    echo "  Check that GITHUB_APP_INSTALLATION_ID is correct" >&2
    return 1 2>/dev/null || exit 1
fi

# Export token for use by git and gh
export GITHUB_TOKEN="${INSTALLATION_TOKEN}"
export GH_TOKEN="${INSTALLATION_TOKEN}"

if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
    echo "DEBUG: Installation token generated (expires in ~1 hour)" >&2
    echo "DEBUG: Token prefix: ${INSTALLATION_TOKEN:0:20}..." >&2
fi

# Configure git to use the token
git config --global credential.helper "!f() { echo username=x-access-token; echo password=${GITHUB_TOKEN}; }; f"
git config --global url."https://github.com/".insteadOf "git@github.com:"

# Set up MCP configuration for Claude Code
# MCP servers must be configured in ~/.claude.json, not settings.json
CLAUDE_CONFIG="${HOME}/.claude.json"

# Create .claude.json if it doesn't exist
if [[ ! -f "${CLAUDE_CONFIG}" ]]; then
    echo "{}" > "${CLAUDE_CONFIG}"
    chmod 600 "${CLAUDE_CONFIG}"
fi

# Use jq to merge MCP config into .claude.json
TEMP_CONFIG=$(mktemp)
jq --arg token "${INSTALLATION_TOKEN}" \
    '.mcpServers.github = {
        "type": "stdio",
        "command": "npx",
        "args": ["-y", "@github/github-mcp-server"],
        "env": {
            "GITHUB_PERSONAL_ACCESS_TOKEN": $token
        }
    }' "${CLAUDE_CONFIG}" > "${TEMP_CONFIG}"

# Replace config file with updated version
mv "${TEMP_CONFIG}" "${CLAUDE_CONFIG}"
chmod 600 "${CLAUDE_CONFIG}"

# Remove old MCP config files if they exist
rm -f "${HOME}/.claude/claude_mcp_config.json"

# Also ensure settings.json doesn't have mcpServers (wrong location)
SETTINGS_FILE="${HOME}/.claude/settings.json"
if [[ -f "${SETTINGS_FILE}" ]] && jq -e '.mcpServers' "${SETTINGS_FILE}" >/dev/null 2>&1; then
    TEMP_SETTINGS=$(mktemp)
    jq 'del(.mcpServers)' "${SETTINGS_FILE}" > "${TEMP_SETTINGS}"
    mv "${TEMP_SETTINGS}" "${SETTINGS_FILE}"
    chmod 600 "${SETTINGS_FILE}"
fi

if [[ "${GITHUB_DEBUG:-}" == "1" ]]; then
    echo "DEBUG: MCP configuration added to .claude.json" >&2
fi

echo "✅ GitHub App MCP integration configured" >&2
echo "   Token expires in ~1 hour" >&2
echo "   MCP config: ${CLAUDE_CONFIG}" >&2

# Branch protection (same as setup-git-pat.sh)
git config --global receive.denyNonFastForwards true
git config --global receive.denyDeletes true
git config --global init.defaultBranch main

# Create pre-push hook for branch protection
HOOKS_DIR="${HOME}/.git-templates/hooks"
mkdir -p "${HOOKS_DIR}"

cat > "${HOOKS_DIR}/pre-push" << 'HOOK'
#!/bin/bash
# Pre-push hook: Prevent direct pushes to main/master branches

protected_branches=("main" "master")
current_branch=$(git symbolic-ref HEAD 2>/dev/null | sed 's|refs/heads/||')

for branch in "${protected_branches[@]}"; do
    if [[ "$current_branch" == "$branch" ]]; then
        echo "🛑 ERROR: Direct push to '$branch' branch is blocked!"
        echo ""
        echo "To make changes safely:"
        echo "  1. Create a feature branch:  git checkout -b feature/my-changes"
        echo "  2. Make your changes and commit"
        echo "  3. Push the feature branch:  git push -u origin feature/my-changes"
        echo "  4. Create a PR:              gh pr create"
        exit 1
    fi
done

exit 0
HOOK

chmod +x "${HOOKS_DIR}/pre-push"
git config --global init.templateDir "${HOME}/.git-templates"

# Git aliases for safe workflow
git config --global alias.safe-branch '!git checkout -b'
# shellcheck disable=SC2016
git config --global alias.start '!f() { git checkout -b "claude/$1"; }; f'

echo "⚠️  Safety: Direct pushes to main/master are blocked (use feature branches)" >&2
