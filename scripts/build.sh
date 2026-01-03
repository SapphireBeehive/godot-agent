#!/bin/bash
# build.sh - Build the agent container image
#
# Usage:
#   ./scripts/build.sh
#   ./scripts/build.sh --no-cache
#
# Checksum verification is automatic using Godot's official SHA512-SUMS.txt

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
GODOT_RELEASE_TYPE="${GODOT_RELEASE_TYPE:-beta2}"

log_info "Building Claude-Godot Agent image"
echo ""
echo "Configuration:"
echo "  GODOT_VERSION:      $GODOT_VERSION"
echo "  GODOT_RELEASE_TYPE: $GODOT_RELEASE_TYPE"
echo ""
echo "Checksum: Auto-verified using Godot's official SHA512-SUMS.txt"
echo ""

log_info "Building image..."

cd "$IMAGE_DIR"

# Build the full version tag (e.g., 4.6-beta2 or 4.5-stable)
GODOT_FULL_VERSION="${GODOT_VERSION}-${GODOT_RELEASE_TYPE}"

docker build \
    $NO_CACHE \
    --build-arg "GODOT_VERSION=${GODOT_VERSION}" \
    --build-arg "GODOT_RELEASE_TYPE=${GODOT_RELEASE_TYPE}" \
    -t claude-godot-agent:latest \
    -t "claude-godot-agent:godot-${GODOT_FULL_VERSION}" \
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

