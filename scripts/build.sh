#!/bin/bash
# build.sh - Build the agent container image
#
# Usage:
#   ./scripts/build.sh
#   ./scripts/build.sh --no-cache
#   GODOT_SHA256=abc123 ./scripts/build.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_DIR="${PROJECT_ROOT}/image"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Parse arguments
NO_CACHE=""
if [[ "${1:-}" == "--no-cache" ]]; then
    NO_CACHE="--no-cache"
fi

# Default values
GODOT_VERSION="${GODOT_VERSION:-4.3}"
GODOT_RELEASE_TYPE="${GODOT_RELEASE_TYPE:-stable}"

log_info "Building Claude-Godot Agent image"
echo ""
echo "Configuration:"
echo "  GODOT_VERSION:      $GODOT_VERSION"
echo "  GODOT_RELEASE_TYPE: $GODOT_RELEASE_TYPE"
echo "  GODOT_SHA256:       ${GODOT_SHA256:-NOT SET}"
echo ""

# Warn about missing checksum
if [[ -z "${GODOT_SHA256:-}" ]]; then
    log_warn "GODOT_SHA256 is not set!"
    log_warn "The Godot download will fail during build."
    log_warn ""
    log_warn "To get the checksum:"
    log_warn "  1. Download Godot from https://godotengine.org/download/server/"
    log_warn "  2. Run: sha256sum <downloaded_file>"
    log_warn "  3. Export: export GODOT_SHA256=<checksum>"
    log_warn ""
    read -rp "Continue anyway? (build will likely fail) [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

log_info "Building image..."

cd "$IMAGE_DIR"

docker build \
    $NO_CACHE \
    --build-arg "GODOT_VERSION=${GODOT_VERSION}" \
    --build-arg "GODOT_RELEASE_TYPE=${GODOT_RELEASE_TYPE}" \
    --build-arg "GODOT_SHA256=${GODOT_SHA256:-}" \
    -t claude-godot-agent:latest \
    -t "claude-godot-agent:${GODOT_VERSION}" \
    .

log_info "Build complete!"
echo ""
echo "Image: claude-godot-agent:latest"
echo ""
echo "To verify:"
echo "  docker run --rm claude-godot-agent:latest godot --headless --version"
echo ""
echo "To run Claude:"
echo "  ./scripts/run-claude.sh direct /path/to/project"

