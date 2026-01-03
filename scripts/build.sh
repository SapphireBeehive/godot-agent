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
GODOT_VERSION="${GODOT_VERSION:-4.6}"
GODOT_RELEASE_TYPE="${GODOT_RELEASE_TYPE:-beta1}"

log_info "Building Claude-Godot Agent image"
echo ""
echo "Configuration:"
echo "  GODOT_VERSION:      $GODOT_VERSION"
echo "  GODOT_RELEASE_TYPE: $GODOT_RELEASE_TYPE"
echo "  GODOT_SHA256:       ${GODOT_SHA256:-(not set - verification skipped)}"
echo ""

# Info about missing checksum (optional, not required)
if [[ -z "${GODOT_SHA256:-}" ]]; then
    log_warn "GODOT_SHA256 not set - checksum verification will be skipped"
    echo ""
    echo "For production builds, set the SHA256 for Godot ${GODOT_VERSION}-${GODOT_RELEASE_TYPE}:"
    echo "  1. Download: https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE_TYPE}/"
    echo "  2. Get hash: sha256sum Godot_v${GODOT_VERSION}-${GODOT_RELEASE_TYPE}_linux.x86_64.zip"
    echo "  3. Build:    GODOT_SHA256=<hash> make build"
    echo ""
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

