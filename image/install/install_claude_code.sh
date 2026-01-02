#!/bin/bash
# install_claude_code.sh - Installs Claude Code CLI in the container
#
# Claude Code (also known as "claude" CLI) is Anthropic's official CLI tool.
# Installation methods may vary - this script follows the official documentation.
#
# TODO: Verify the exact installation method from official Anthropic docs
# As of this implementation, Claude Code may be installed via:
# 1. npm (Node.js package)
# 2. Direct binary download
# 3. Other package managers

set -euo pipefail

echo "=== Claude Code CLI Installer ==="
echo ""

# Method 1: npm-based installation (most likely method)
# Claude Code CLI is typically distributed as an npm package
if command -v npm &> /dev/null; then
    echo "Installing Claude Code via npm..."
    
    # TODO: Update package name when confirmed
    # The package name might be:
    # - @anthropic-ai/claude-code
    # - claude-code
    # - @anthropic/claude
    
    CLAUDE_PACKAGE="${CLAUDE_NPM_PACKAGE:-@anthropic-ai/claude-code}"
    
    echo "Package: ${CLAUDE_PACKAGE}"
    echo ""
    
    # Install globally
    npm install -g "${CLAUDE_PACKAGE}" || {
        echo "WARNING: npm install failed for ${CLAUDE_PACKAGE}"
        echo "The package name may have changed."
        echo ""
        echo "Please check official documentation:"
        echo "https://docs.anthropic.com/claude/docs/claude-code"
        echo ""
        echo "After finding the correct package, either:"
        echo "1. Set CLAUDE_NPM_PACKAGE env var during build"
        echo "2. Update this script with the correct package name"
        exit 1
    }
    
    echo "Claude Code installed successfully via npm"
    
elif [[ -n "${CLAUDE_BINARY_URL:-}" ]]; then
    # Method 2: Direct binary download
    echo "Installing Claude Code from binary URL..."
    echo "URL: ${CLAUDE_BINARY_URL}"
    
    INSTALL_DIR="/usr/local/bin"
    
    if command -v curl &> /dev/null; then
        curl -fSL -o "${INSTALL_DIR}/claude" "${CLAUDE_BINARY_URL}"
    elif command -v wget &> /dev/null; then
        wget -O "${INSTALL_DIR}/claude" "${CLAUDE_BINARY_URL}"
    else
        echo "ERROR: Neither curl nor wget available"
        exit 1
    fi
    
    chmod +x "${INSTALL_DIR}/claude"
    echo "Claude Code binary installed to ${INSTALL_DIR}/claude"
    
else
    echo "ERROR: Cannot install Claude Code"
    echo ""
    echo "No installation method available. Please either:"
    echo ""
    echo "1. Ensure Node.js/npm is available in the container for npm-based install"
    echo "   Then set CLAUDE_NPM_PACKAGE to the correct package name"
    echo ""
    echo "2. Set CLAUDE_BINARY_URL to a direct download URL for the binary"
    echo ""
    echo "3. Manually install Claude Code after container build"
    echo "   Mount it from host or install via another method"
    echo ""
    echo "See official Anthropic documentation for current installation options:"
    echo "https://docs.anthropic.com/claude/docs/claude-code"
    echo ""
    exit 1
fi

# Verify installation
echo ""
echo "Verifying installation..."
if command -v claude &> /dev/null; then
    echo "Claude Code CLI found at: $(which claude)"
    echo ""
    echo "Version info:"
    claude --version 2>/dev/null || echo "(version command may require API key)"
    echo ""
    echo "=== Installation complete ==="
else
    echo "WARNING: 'claude' command not found in PATH after installation"
    echo "The binary may have a different name or installation location."
    echo "Please verify manually."
    exit 1
fi

