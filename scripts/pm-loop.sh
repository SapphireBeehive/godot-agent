#!/bin/bash
# pm-loop.sh - Periodic PM agent invocation for GitHub issue management
#
# Runs a fresh Claude instance at configurable intervals to check
# task status, release unblocked tasks, and report progress.
#
# Usage:
#   ./scripts/pm-loop.sh                          # Run loop (default: 15 min interval)
#   ./scripts/pm-loop.sh --once                   # Run once and exit
#   ./scripts/pm-loop.sh --standalone             # Run directly on host (no container)
#   POLL_INTERVAL=300 ./scripts/pm-loop.sh        # 5-minute intervals
#
# Environment:
#   GITHUB_OWNER      - Repository owner (required)
#   GITHUB_REPO       - Repository name (required)
#   POLL_INTERVAL     - Seconds between checks (default: 900 = 15 minutes)
#   PM_LOG_DIR        - Log directory (default: ./logs/pm)
#
# Modes:
#   Container mode (default): Uses docker exec to run Claude in agent container
#   Standalone mode (--standalone): Runs Claude directly on host
#   Auto-detect: If inside container, runs Claude directly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
POLL_INTERVAL="${POLL_INTERVAL:-900}"  # 15 minutes default
PM_LOG_DIR="${PM_LOG_DIR:-${PROJECT_ROOT}/logs/pm}"
GITHUB_OWNER="${GITHUB_OWNER:?Error: GITHUB_OWNER is required}"
GITHUB_REPO="${GITHUB_REPO:?Error: GITHUB_REPO is required}"

# Parse arguments
RUN_ONCE=false
STANDALONE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)
            RUN_ONCE=true
            shift
            ;;
        --standalone)
            STANDALONE=true
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: $0 [--once] [--standalone]"
            exit 1
            ;;
    esac
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Stats
CYCLES_TOTAL=0
CYCLES_SKIPPED=0
CYCLES_INVOKED=0

# Ensure log directory exists
mkdir -p "$PM_LOG_DIR"

# The PM prompt instructs Claude what to do
PM_PROMPT="You are the Project Manager agent for ${GITHUB_OWNER}/${GITHUB_REPO}.

Perform your PM React Loop:

1. CHECK: Gather the current state of all open issues AND all open pull requests from agent branches (claude/* or godot-agent/*)
2. DECIDE:
   a. Identify agent PRs that can be merged (all checks passing or no checks required)
   b. Identify issues that can be released (dependencies satisfied - meaning dependency issues are CLOSED)
3. ACT:
   a. FIRST: Merge eligible agent PRs (squash-merge, delete branch). This auto-closes linked issues.
   b. THEN: Release unblocked issues by adding agent-ready label
4. REPORT: Output a structured status report

IMPORTANT:
- A dependency is satisfied when its issue is CLOSED (state=closed), NOT when it has a label.
- Merge PRs BEFORE releasing tasks - merging closes linked issues which may unblock dependent tasks.
- Only merge PRs from agent branches (claude/* or godot-agent/*).
- Before merging, check for Copilot review comments. If present, create a follow-up issue for the feedback, then merge.
- Use gh CLI for all GitHub operations (standalone mode).

Use the skills defined in your context (CLAUDE.pm.md) to accomplish this.

Environment:
- GITHUB_OWNER=${GITHUB_OWNER}
- GITHUB_REPO=${GITHUB_REPO}

Begin your PM cycle now."

# Detect execution environment
detect_mode() {
    # Explicit standalone flag takes precedence
    if [[ "$STANDALONE" == "true" ]]; then
        echo "standalone"
        return
    fi

    # Check if running inside a container
    if [[ -f /.dockerenv ]] || grep -q 'docker\|lxc' /proc/1/cgroup 2>/dev/null; then
        echo "container"
        return
    fi

    # Running on host - check for agent container
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agent$'; then
        echo "docker-exec"
        return
    fi

    # Host without container - check if claude is available locally
    if command -v claude &>/dev/null; then
        echo "standalone"
        return
    fi

    # No valid execution mode
    echo "none"
}

show_banner() {
    local mode
    mode=$(detect_mode)

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         PM Agent Loop                                 ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  Repository:  ${GITHUB_OWNER}/${GITHUB_REPO}"
    echo -e "${CYAN}║${NC}  Interval:    ${POLL_INTERVAL}s"
    echo -e "${CYAN}║${NC}  Logs:        ${PM_LOG_DIR}"
    echo -e "${CYAN}║${NC}  Mode:        $([ "$RUN_ONCE" == "true" ] && echo "One-time check" || echo "Continuous loop")"
    echo -e "${CYAN}║${NC}  Execution:   ${mode}"
    echo -e "${CYAN}║${NC}  Pre-check:   $([ "$mode" == "standalone" ] && echo "enabled (bash gate)" || echo "disabled (no gh CLI)")"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ---------------------------------------------------------------------------
# Pre-check: lightweight bash gate that decides whether Claude is needed.
# Two gh API calls (~0 tokens) vs a full Claude invocation (~15K tokens).
# Returns 0 = action needed (invoke Claude), 1 = idle (skip).
# ---------------------------------------------------------------------------
pre_check() {
    local repo="${GITHUB_OWNER}/${GITHUB_REPO}"
    local state_file="${PM_LOG_DIR}/.pm_state"

    # Pre-check requires gh CLI — only works in standalone mode.
    # In container/docker-exec modes, fall through and always invoke Claude.
    local mode
    mode=$(detect_mode)
    if [[ "$mode" != "standalone" ]]; then
        return 0
    fi

    # --- Check 1: Any open PRs from agent branches? ---
    local agent_pr_count
    agent_pr_count=$(gh pr list --repo "$repo" --state open \
        --json headRefName \
        --jq '[.[] | select(.headRefName | test("^(claude|godot-agent)/"))] | length' 2>/dev/null || echo "0")

    if [[ "$agent_pr_count" -gt 0 ]]; then
        log_info "Pre-check: ${agent_pr_count} open agent PR(s) — invoking Claude"
        return 0
    fi

    # --- Check 2: Has the set of closed issues changed since last cycle? ---
    # If an issue closed since we last looked, a dependency chain may have
    # unblocked.  Comparing a hash of closed-issue numbers is cheap.
    local current_closed
    current_closed=$(gh issue list --repo "$repo" --state closed \
        --json number -L 200 \
        --jq '[.[].number] | sort | join(",")' 2>/dev/null || echo "")

    local current_hash
    current_hash=$(echo "$current_closed" | shasum | cut -d' ' -f1)

    local prev_hash=""
    if [[ -f "$state_file" ]]; then
        prev_hash=$(cat "$state_file" 2>/dev/null || echo "")
    fi

    # Persist current state for next cycle
    echo "$current_hash" > "$state_file" 2>/dev/null || true

    if [[ "$current_hash" != "$prev_hash" ]]; then
        log_info "Pre-check: Closed-issue set changed — invoking Claude"
        return 0
    fi

    # --- Nothing actionable ---
    log_info "Pre-check: No agent PRs, no state changes — skipping Claude (saved ~15K tokens)"
    return 1
}

run_pm_check() {
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local log_file="${PM_LOG_DIR}/pm_${timestamp}.log"
    local mode
    mode=$(detect_mode)

    log_info "Running PM check (mode: ${mode})..."

    # Write header to log (handle permission errors gracefully)
    {
        echo "=== PM Agent Check ==="
        echo "Timestamp: $(date)"
        echo "Repository: ${GITHUB_OWNER}/${GITHUB_REPO}"
        echo "Mode: ${mode}"
        echo "========================"
        echo ""
    } > "$log_file" 2>/dev/null || log_file="/dev/null"

    # Read CLAUDE.pm.md for system prompt
    local pm_context=""
    local pm_context_paths=(
        "/etc/claude/CLAUDE.pm.md"           # Mounted in container
        "${PROJECT_ROOT}/CLAUDE.pm.md"       # Host path
        "./CLAUDE.pm.md"                     # Current directory
    )
    for path in "${pm_context_paths[@]}"; do
        if [[ -f "$path" ]]; then
            pm_context=$(cat "$path")
            log_info "Loaded PM context from: $path"
            break
        fi
    done
    if [[ -z "$pm_context" ]]; then
        log_warn "CLAUDE.pm.md not found, running without PM context"
    fi

    # Run Claude based on detected mode
    local exit_status=0

    case "$mode" in
        container)
            # Running inside container - call Claude directly
            log_info "Running Claude directly (container mode)"
            if [[ -n "$pm_context" ]]; then
                claude \
                    --print \
                    --dangerously-skip-permissions \
                    --append-system-prompt "$pm_context" \
                    "$PM_PROMPT" 2>&1 | tee -a "$log_file" || exit_status=$?
            else
                claude \
                    --print \
                    --dangerously-skip-permissions \
                    "$PM_PROMPT" 2>&1 | tee -a "$log_file" || exit_status=$?
            fi
            ;;

        docker-exec)
            # Running on host - exec into agent container
            log_info "Running Claude via docker exec (host mode)"
            if [[ -n "$pm_context" ]]; then
                docker exec agent claude \
                    --print \
                    --dangerously-skip-permissions \
                    --append-system-prompt "$pm_context" \
                    "$PM_PROMPT" 2>&1 | tee -a "$log_file" || exit_status=$?
            else
                docker exec agent claude \
                    --print \
                    --dangerously-skip-permissions \
                    "$PM_PROMPT" 2>&1 | tee -a "$log_file" || exit_status=$?
            fi
            ;;

        standalone)
            # Running on host without container - use local Claude
            log_info "Running Claude directly (standalone mode)"
            if [[ -n "$pm_context" ]]; then
                claude \
                    --print \
                    --dangerously-skip-permissions \
                    --append-system-prompt "$pm_context" \
                    "$PM_PROMPT" 2>&1 | tee -a "$log_file" || exit_status=$?
            else
                claude \
                    --print \
                    --dangerously-skip-permissions \
                    "$PM_PROMPT" 2>&1 | tee -a "$log_file" || exit_status=$?
            fi
            ;;

        none)
            log_error "No valid execution mode available."
            log_error "Options:"
            log_error "  1. Start agent container: make up-agent PROJECT=/path"
            log_error "  2. Install Claude CLI and use --standalone"
            log_error "  3. Run this script inside the container"
            echo "ERROR: No valid execution mode" >> "$log_file" 2>/dev/null
            return 1
            ;;
    esac

    # Write footer to log
    {
        echo ""
        echo "=== PM Check Completed ==="
        echo "Timestamp: $(date)"
        echo "Exit status: $exit_status"
        echo "=========================="
    } >> "$log_file" 2>/dev/null

    if [[ $exit_status -eq 0 ]]; then
        log_info "PM check completed. Log: $log_file"
    else
        log_warn "PM check finished with exit status $exit_status. Log: $log_file"
    fi

    return $exit_status
}

# Graceful shutdown
shutdown() {
    echo ""
    log_info "Shutting down PM loop..."
    if [[ $CYCLES_TOTAL -gt 0 ]]; then
        local pct_skipped=0
        if [[ $CYCLES_TOTAL -gt 0 ]]; then
            pct_skipped=$(( CYCLES_SKIPPED * 100 / CYCLES_TOTAL ))
        fi
        log_info "Final stats: ${CYCLES_INVOKED} invoked / ${CYCLES_SKIPPED} skipped / ${CYCLES_TOTAL} total (${pct_skipped}% saved)"
    fi
    exit 0
}
trap shutdown SIGINT SIGTERM

# Main
main() {
    show_banner

    # Validate we have a valid execution mode
    local mode
    mode=$(detect_mode)
    if [[ "$mode" == "none" ]]; then
        log_error "Cannot run PM: no valid execution mode detected."
        log_error ""
        log_error "Options to fix:"
        log_error "  1. Start the agent container:"
        log_error "     make up-agent PROJECT=/path/to/project"
        log_error ""
        log_error "  2. Run in standalone mode with local Claude:"
        log_error "     ./scripts/pm-loop.sh --standalone"
        log_error ""
        log_error "  3. Run this script inside the agent container"
        exit 1
    fi

    if [[ "$RUN_ONCE" == "true" ]]; then
        log_info "Running one-time PM check..."
        run_pm_check
        log_info "Done."
        exit 0
    fi

    log_info "Starting PM loop (Ctrl+C to stop)"
    log_info "First check in 10 seconds..."

    # Small initial delay
    sleep 10

    while true; do
        CYCLES_TOTAL=$((CYCLES_TOTAL + 1))
        if pre_check; then
            CYCLES_INVOKED=$((CYCLES_INVOKED + 1))
            run_pm_check || true  # Don't exit loop on error
        else
            CYCLES_SKIPPED=$((CYCLES_SKIPPED + 1))
        fi

        log_info "Stats: ${CYCLES_INVOKED} invoked / ${CYCLES_SKIPPED} skipped / ${CYCLES_TOTAL} total"
        log_info "Next check in ${POLL_INTERVAL}s..."
        sleep "$POLL_INTERVAL"
    done
}

main
