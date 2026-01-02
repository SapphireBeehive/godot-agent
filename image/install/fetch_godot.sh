#!/bin/bash
# fetch_godot.sh - Downloads and verifies Godot 4.6 headless binary for Linux arm64
#
# TODO: Update these values when Godot 4.6 is officially released
# As of writing, Godot 4.6 may not have official releases yet.
# Check https://godotengine.org/download/server/ for official builds.
#
# For headless/server builds, Godot provides Linux Server builds.
# The arm64 builds may be available at:
# https://downloads.tuxfamily.org/godotengine/4.x.x/
# or via GitHub releases.

set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.3}"
GODOT_RELEASE_TYPE="${GODOT_RELEASE_TYPE:-stable}"

# TODO: These URLs are placeholders - verify against official Godot downloads
# Godot 4.x server/headless builds for Linux arm64
# Official naming convention: Godot_v{VERSION}-{TYPE}_linux.arm64.zip (for templates)
# or: Godot_v{VERSION}-{TYPE}_linux_server.arm64.zip (for server builds)

# Placeholder URL structure based on Godot's release patterns
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE_TYPE}"

# For server builds (headless), the naming is typically:
# Godot_v4.3-stable_linux.arm64.zip (export templates)
# For the editor/server binary, you may need to build from source for arm64
# or use the linux.x86_64 build under emulation

# TODO: CRITICAL - Godot does not officially provide arm64 Linux server binaries
# Options:
# 1. Use x86_64 binary with QEMU emulation (slow but works)
# 2. Build from source for arm64 (complex but native speed)
# 3. Wait for official arm64 builds
#
# For now, we'll set up for the x86_64 binary path as a fallback

GODOT_BINARY_NAME="Godot_v${GODOT_VERSION}-${GODOT_RELEASE_TYPE}_linux.x86_64"
DOWNLOAD_URL="${BASE_URL}/${GODOT_BINARY_NAME}.zip"

# Expected SHA256 checksum - TODO: Update this with the actual checksum
# You can get this from the official Godot downloads page or compute it yourself
# Example: sha256sum Godot_v4.3-stable_linux.x86_64.zip
EXPECTED_SHA256="${GODOT_SHA256:-TODO_UPDATE_CHECKSUM_FROM_OFFICIAL_SOURCE}"

INSTALL_DIR="${INSTALL_DIR:-/opt/godot}"
TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

echo "=== Godot Headless/Server Binary Fetcher ==="
echo "Version: ${GODOT_VERSION}-${GODOT_RELEASE_TYPE}"
echo "Install directory: ${INSTALL_DIR}"
echo ""

# Check if checksum is still a placeholder
if [[ "$EXPECTED_SHA256" == "TODO_UPDATE_CHECKSUM_FROM_OFFICIAL_SOURCE" ]]; then
    echo "ERROR: GODOT_SHA256 environment variable is not set!"
    echo ""
    echo "To get the correct checksum:"
    echo "1. Visit https://godotengine.org/download/server/"
    echo "2. Download the Linux server/headless build"
    echo "3. Run: sha256sum <downloaded_file>"
    echo "4. Set GODOT_SHA256=<checksum> in your build args"
    echo ""
    echo "Alternatively, for Godot 4.x releases, check:"
    echo "https://github.com/godotengine/godot/releases"
    echo ""
    exit 1
fi

echo "Downloading Godot from: ${DOWNLOAD_URL}"
cd "$TEMP_DIR"

# Download the binary
if command -v curl &> /dev/null; then
    curl -fSL -o godot.zip "$DOWNLOAD_URL"
elif command -v wget &> /dev/null; then
    wget -O godot.zip "$DOWNLOAD_URL"
else
    echo "ERROR: Neither curl nor wget available"
    exit 1
fi

echo "Verifying SHA256 checksum..."
ACTUAL_SHA256=$(sha256sum godot.zip | awk '{print $1}')

if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
    echo "ERROR: Checksum verification failed!"
    echo "Expected: ${EXPECTED_SHA256}"
    echo "Got:      ${ACTUAL_SHA256}"
    echo ""
    echo "This could indicate:"
    echo "- Corrupted download"
    echo "- Tampered file"
    echo "- Wrong checksum value in build args"
    exit 1
fi

echo "Checksum verified successfully!"

echo "Extracting to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
unzip -q godot.zip -d "$INSTALL_DIR"

# Rename to a consistent name
mv "${INSTALL_DIR}/${GODOT_BINARY_NAME}" "${INSTALL_DIR}/godot"
chmod +x "${INSTALL_DIR}/godot"

echo "Creating symlink in /usr/local/bin..."
ln -sf "${INSTALL_DIR}/godot" /usr/local/bin/godot

echo ""
echo "=== Installation complete ==="
echo "Godot binary: ${INSTALL_DIR}/godot"
echo "Symlink: /usr/local/bin/godot"
echo ""
echo "Verify with: godot --headless --version"

