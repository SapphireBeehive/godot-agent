#!/bin/bash
# logs-report.sh - Parse and summarize sandbox logs
#
# Usage:
#   ./scripts/logs-report.sh
#   ./scripts/logs-report.sh --since 1h
#   ./scripts/logs-report.sh --output report.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${PROJECT_ROOT}/compose"

# Colors (disabled if output is not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    NC=''
fi

SINCE=""
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --since)
            SINCE="--since $2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--since <duration>] [--output <file>]"
            exit 1
            ;;
    esac
done

generate_report() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            SANDBOX NETWORK ACTIVITY REPORT                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Generated: $(date)"
    echo ""
    
    cd "$COMPOSE_DIR"
    
    # Check if services are running
    if ! docker compose -f compose.base.yml ps --quiet 2>/dev/null | grep -q .; then
        echo "Note: Base services are not currently running."
        echo "Showing logs from any previous sessions..."
        echo ""
    fi
    
    # Get logs
    # shellcheck disable=SC2086
    LOGS=$(docker compose -f compose.base.yml logs $SINCE 2>/dev/null || echo "")
    
    if [[ -z "$LOGS" ]]; then
        echo "No logs available."
        return
    fi
    
    echo "────────────────────────────────────────────────────────────────"
    echo "DNS QUERIES (from dnsfilter)"
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    
    # Extract DNS queries from CoreDNS logs
    DNS_LOGS=$(echo "$LOGS" | grep "dnsfilter" || true)
    
    if [[ -n "$DNS_LOGS" ]]; then
        # Count allowed queries (resolved to our proxy IPs)
        echo -e "${GREEN}Allowed DNS queries:${NC}"
        echo "$DNS_LOGS" | grep -oE '[a-zA-Z0-9.-]+\.(com|org|io|net)' | sort | uniq -c | sort -rn | head -20 || echo "  (none captured)"
        echo ""
        
        # Look for NXDOMAIN responses (blocked queries)
        echo -e "${RED}Blocked DNS queries (NXDOMAIN):${NC}"
        echo "$DNS_LOGS" | grep -i "nxdomain\|refused" | grep -oE '[a-zA-Z0-9.-]+\.(com|org|io|net|co)' | sort | uniq -c | sort -rn | head -20 || echo "  (none)"
        echo ""
    else
        echo "  No DNS logs captured."
        echo ""
    fi
    
    echo "────────────────────────────────────────────────────────────────"
    echo "PROXY CONNECTIONS"
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    
    # Extract proxy logs
    for proxy in proxy_github proxy_raw_githubusercontent proxy_codeload_github proxy_godot_docs proxy_anthropic_api; do
        PROXY_LOGS=$(echo "$LOGS" | grep "$proxy" || true)
        
        if [[ -n "$PROXY_LOGS" ]]; then
            # Count connections
            CONN_COUNT=$(echo "$PROXY_LOGS" | grep -c "200\|bytes" || echo "0")
            echo -e "${CYAN}${proxy}:${NC} $CONN_COUNT connections logged"
            
            # Show sample entries
            echo "$PROXY_LOGS" | tail -3 | sed 's/^/  /'
            echo ""
        fi
    done
    
    echo "────────────────────────────────────────────────────────────────"
    echo "SUMMARY"
    echo "────────────────────────────────────────────────────────────────"
    echo ""
    
    # Calculate time range
    FIRST_TS=$(echo "$LOGS" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "unknown")
    LAST_TS=$(echo "$LOGS" | tail -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "unknown")
    
    echo "Time range: $FIRST_TS to $LAST_TS"
    echo "Total log lines: $(echo "$LOGS" | wc -l | tr -d ' ')"
    echo ""
    
    # Allowlist domains summary
    echo "Allowlisted domains:"
    echo "  - github.com (code hosting)"
    echo "  - raw.githubusercontent.com (raw file access)"
    echo "  - codeload.github.com (archive downloads)"
    echo "  - docs.godotengine.org (documentation)"
    echo "  - api.anthropic.com (Claude API)"
    echo ""
    
    echo "════════════════════════════════════════════════════════════════"
    echo "END OF REPORT"
    echo "════════════════════════════════════════════════════════════════"
}

if [[ -n "$OUTPUT_FILE" ]]; then
    generate_report > "$OUTPUT_FILE"
    echo "Report written to: $OUTPUT_FILE"
else
    generate_report
fi

