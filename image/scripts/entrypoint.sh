#!/bin/bash
# entrypoint.sh - Container entrypoint that sets up Claude configuration
#
# This script runs on every container start to:
# 1. Set up Claude Code settings (permissions, etc.)
# 2. Execute the provided command or default to bash
#
# The home directory is a tmpfs mount, so configuration must be
# recreated on each container start.

set -euo pipefail

# Claude settings directory
CLAUDE_CONFIG_DIR="${HOME}/.claude"

# Set up Claude Code configuration
setup_claude_config() {
    # Create Claude config directory
    mkdir -p "${CLAUDE_CONFIG_DIR}"
    
    # Copy pre-configured settings if they exist
    if [[ -f /etc/claude/settings.json ]]; then
        cp /etc/claude/settings.json "${CLAUDE_CONFIG_DIR}/settings.json"
    fi
    
    # Mark that we've accepted terms (prevents interactive prompt)
    touch "${CLAUDE_CONFIG_DIR}/.terms-accepted"
}

# Run setup
setup_claude_config

# Execute the provided command or default to bash
exec "$@"

