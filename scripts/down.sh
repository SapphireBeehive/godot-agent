#!/bin/bash
# down.sh - Stop all sandbox services
#
# Usage:
#   ./scripts/down.sh
#   ./scripts/down.sh --volumes  # Also remove volumes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${PROJECT_ROOT}/compose"

# Colors
GREEN='\033[0;32m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

EXTRA_FLAGS=""
if [[ "${1:-}" == "--volumes" ]]; then
    EXTRA_FLAGS="-v"
    log_info "Removing volumes as well..."
fi

log_info "Stopping Claude-Godot Sandbox services..."

cd "$COMPOSE_DIR"

# Stop all compose configurations
docker compose -f compose.base.yml -f compose.direct.yml down $EXTRA_FLAGS 2>/dev/null || true
docker compose -f compose.base.yml -f compose.staging.yml down $EXTRA_FLAGS 2>/dev/null || true
docker compose -f compose.offline.yml down $EXTRA_FLAGS 2>/dev/null || true
docker compose -f compose.base.yml down $EXTRA_FLAGS 2>/dev/null || true

log_info "All services stopped."

