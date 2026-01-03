#!/bin/bash
# fetch_godot.sh - Downloads and verifies Godot headless binary for Linux
#
# Supports both x86_64 and arm64 architectures (auto-detected).
#
# Download sources:
#   - godotengine/godot-builds (GitHub) - All releases (stable, beta, rc, dev)
#   - godotengine/godot (GitHub) - Stable releases only
#   - downloads.tuxfamily.org - Alternative mirror
#
# See: https://godotengine.org/download/archive/

set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.6}"
GODOT_RELEASE_TYPE="${GODOT_RELEASE_TYPE:-beta2}"

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        GODOT_ARCH="x86_64"
        ;;
    aarch64|arm64)
        GODOT_ARCH="arm64"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Godot binary naming convention: Godot_v{VERSION}-{TYPE}_linux.{ARCH}
GODOT_BINARY_NAME="Godot_v${GODOT_VERSION}-${GODOT_RELEASE_TYPE}_linux.${GODOT_ARCH}"

# Build download URLs
# GitHub repos:
#   godotengine/godot       - stable releases only
#   godotengine/godot-builds - ALL releases (stable, beta, rc, dev)
# TuxFamily mirror - alternative source

if [[ "$GODOT_RELEASE_TYPE" == "stable" ]]; then
    # Stable releases are on both repos
    GITHUB_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE_TYPE}/${GODOT_BINARY_NAME}.zip"
    TUXFAMILY_URL="https://downloads.tuxfamily.org/godotengine/${GODOT_VERSION}/${GODOT_BINARY_NAME}.zip"
else
    # Pre-releases (beta, rc, dev) are ONLY on godot-builds repo
    GITHUB_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-${GODOT_RELEASE_TYPE}/${GODOT_BINARY_NAME}.zip"
    TUXFAMILY_URL="https://downloads.tuxfamily.org/godotengine/${GODOT_VERSION}/${GODOT_RELEASE_TYPE}/${GODOT_BINARY_NAME}.zip"
fi

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
echo "Architecture: ${GODOT_ARCH} (detected: ${ARCH})"
echo "Install directory: ${INSTALL_DIR}"
echo ""

# Check if checksum verification should be skipped
SKIP_CHECKSUM=false
if [[ "$EXPECTED_SHA256" == "TODO_UPDATE_CHECKSUM_FROM_OFFICIAL_SOURCE" ]] || [[ -z "$EXPECTED_SHA256" ]]; then
    echo "WARNING: GODOT_SHA256 environment variable is not set!"
    echo ""
    echo "To enable checksum verification (recommended for production):"
    echo "1. Visit https://godotengine.org/download/server/"
    echo "2. Download the Linux server/headless build"
    echo "3. Run: sha256sum <downloaded_file>"
    echo "4. Set GODOT_SHA256=<checksum> in your build args"
    echo ""
    echo "Alternatively, for Godot 4.x releases, check:"
    echo "https://github.com/godotengine/godot/releases"
    echo ""
    echo "Proceeding WITHOUT checksum verification..."
    echo ""
    SKIP_CHECKSUM=true
fi

cd "$TEMP_DIR"

# Download the binary - try TuxFamily first, then GitHub
download_success=false

for url in "$GITHUB_URL" "$TUXFAMILY_URL"; do
    echo "Downloading Godot from: ${url}"
    if command -v curl &> /dev/null; then
        if curl -fSL -o godot.zip "$url" 2>/dev/null; then
            download_success=true
            break
        fi
    elif command -v wget &> /dev/null; then
        if wget -O godot.zip "$url" 2>/dev/null; then
            download_success=true
            break
        fi
    else
        echo "ERROR: Neither curl nor wget available"
        exit 1
    fi
    echo "Failed to download from ${url}, trying next mirror..."
done

if [[ "$download_success" != "true" ]]; then
    echo "ERROR: Failed to download Godot from all mirrors"
    echo "Tried:"
    echo "  - ${GITHUB_URL}"
    echo "  - ${TUXFAMILY_URL}"
    exit 1
fi

if [[ "$SKIP_CHECKSUM" == "true" ]]; then
    echo "Skipping SHA256 checksum verification (not recommended for production)"
    ACTUAL_SHA256=$(sha256sum godot.zip | awk '{print $1}')
    echo "Downloaded file SHA256: ${ACTUAL_SHA256}"
    echo "Save this checksum for production builds!"
else
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
fi

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

