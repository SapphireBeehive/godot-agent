#!/bin/bash
# up.sh - Start infrastructure services (DNS filter + proxies)
#
# Usage:
#   ./scripts/up.sh
#   ./scripts/up.sh --build  # Rebuild images first

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${PROJECT_ROOT}/compose"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

BUILD_FLAG=""
if [[ "${1:-}" == "--build" ]]; then
    BUILD_FLAG="--build"
fi

log_info "Starting Claude-Godot Sandbox infrastructure..."

cd "$COMPOSE_DIR"

# Start base services
docker compose -f compose.base.yml up -d $BUILD_FLAG

log_info "Waiting for services to be healthy..."
sleep 3

# Check service status
echo ""
log_info "Service status:"
docker compose -f compose.base.yml ps

echo ""
log_info "Infrastructure is running!"
echo ""
echo "Services:"
echo "  - dnsfilter (CoreDNS):     Filtering DNS queries"
echo "  - proxy_github:            GitHub access"
echo "  - proxy_raw_githubusercontent: GitHub raw content"
echo "  - proxy_codeload_github:   GitHub archive downloads"
echo "  - proxy_godot_docs:        Godot documentation"
echo "  - proxy_anthropic_api:     Claude API access"
echo ""
echo "To view logs:     docker compose -f compose/compose.base.yml logs -f"
echo "To stop:          ./scripts/down.sh"
echo "To run Claude:    ./scripts/run-claude.sh direct /path/to/project"

