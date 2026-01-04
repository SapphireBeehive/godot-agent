# Claude-Godot Sandbox Makefile
# Usage: make <target>
#
# Run 'make help' to see all available targets

.PHONY: help build up down doctor logs clean run-direct run-staging run-offline \
        run-godot promote diff-review scan logs-report shell test validate \
        build-no-cache restart status ci ci-validate ci-build ci-list ci-dry-run \
        auth auth-status auth-setup-token install-hooks install-tests \
        test-security test-dns test-network test-hardening test-filesystem test-offline \
        test-github-app-module test-github-app-integration \
        up-agent down-agent up-isolated down-isolated \
        claude claude-print claude-shell agent-status verify-permissions \
        queue-start queue-stop queue-status queue-logs queue-add queue-init queue-results \
        pool-start pool-stop pool-status pool-logs pool-scale \
        github-app-test github-app-validate

# Default target
.DEFAULT_GOAL := help

# Configuration (can be overridden: make build GODOT_VERSION=4.4)
GODOT_VERSION ?= 4.6
GODOT_RELEASE_TYPE ?= beta2
PROJECT_PATH ?=
STAGING_PATH ?=
LIVE_PATH ?=

# Directories
SCRIPT_DIR := scripts
COMPOSE_DIR := compose
IMAGE_DIR := image
LOGS_DIR := logs

# Colors for help output
CYAN := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RESET := \033[0m

#==============================================================================
# HELP
#==============================================================================

help: ## Show this help message
	@echo ""
	@echo "$(CYAN)Claude-Godot Sandbox$(RESET)"
	@echo "====================="
	@echo ""
	@echo "$(GREEN)Quick Start (Persistent Mode - Recommended):$(RESET)"
	@echo "  make doctor                    # Check your environment"
	@echo "  make build                     # Build the agent image"
	@echo ""
	@echo "$(CYAN)Persistent Mode (mount local project):$(RESET)"
	@echo "  make up-agent PROJECT=~/game   # Start agent with local project"
	@echo "  make claude                    # Interactive Claude session"
	@echo "  make claude P=\"your prompt\"    # Single prompt"
	@echo "  make down-agent                # Stop when done"
	@echo ""
	@echo "$(CYAN)Isolated Mode (agent clones its own repo):$(RESET)"
	@echo "  make up-isolated REPO=org/repo # Start agent (clones repo)"
	@echo "  make claude P=\"fix issue #1\"   # Agent works in isolation"
	@echo "  make down-isolated             # Stop (destroys workspace)"
	@echo ""
	@echo "$(CYAN)Pool Mode (multiple agents processing issues):$(RESET)"
	@echo "  make pool-start REPO=org/repo WORKERS=3  # Start 3 isolated workers"
	@echo "  make pool-status               # Check worker status"
	@echo "  make pool-stop                 # Stop all workers"
	@echo ""
	@echo "$(GREEN)Quick Start (One-shot Mode):$(RESET)"
	@echo "  make run-direct PROJECT=/path/to/project"
	@echo ""
	@echo "$(GREEN)Available Targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Examples:$(RESET)"
	@echo "  make up-agent PROJECT=~/my-godot-game"
	@echo "  make claude P=\"Add player movement\""
	@echo "  make pool-start REPO=myorg/mygame WORKERS=5"
	@echo "  make run-direct PROJECT=~/my-godot-game"
	@echo "  make run-staging STAGING=~/staging LIVE=~/my-godot-game"
	@echo "  make run-godot PROJECT=~/my-godot-game ARGS='--version'"
	@echo ""

#==============================================================================
# SETUP & BUILD
#==============================================================================

doctor: ## Check environment health
	@./$(SCRIPT_DIR)/doctor.sh

auth: auth-status ## Check Claude authentication status (alias)

auth-status: ## Check Claude authentication status
	@./$(SCRIPT_DIR)/setup-claude-auth.sh status

auth-setup-token: ## Generate Claude Max OAuth token
	@./$(SCRIPT_DIR)/setup-claude-auth.sh setup-token

github-pat: ## Create GitHub PAT for a repository (usage: make github-pat REPO=owner/repo)
	@if [ -z "$(REPO)" ]; then \
		echo "Usage: make github-pat REPO=owner/repo"; \
		exit 1; \
	fi
	@./$(SCRIPT_DIR)/create-github-pat.sh $(REPO)

github-app-test: _check-tests ## Test GitHub App credentials and token generation
	@echo "Testing GitHub App credentials..."
	@if [ -f ".env" ]; then set -a; . ./.env; set +a; fi; \
	$(VENV_PYTHON) -m github_app.test_github_app $(if $(REPOS),--repositories $(REPOS))

github-app-validate: _check-tests ## Validate GitHub App setup (quick check)
	@echo "Validating GitHub App configuration..."
	@if [ -z "$${GITHUB_APP_ID:-}" ]; then \
		if [ -f ".env" ]; then \
			. ./.env 2>/dev/null || true; \
		fi; \
	fi; \
	if [ -z "$${GITHUB_APP_ID:-}" ]; then \
		echo "❌ GITHUB_APP_ID not set"; \
		echo "   Set in .env or environment"; \
		exit 1; \
	fi; \
	if [ -z "$${GITHUB_APP_INSTALLATION_ID:-}" ]; then \
		echo "❌ GITHUB_APP_INSTALLATION_ID not set"; \
		exit 1; \
	fi; \
	if [ -z "$${GITHUB_APP_PRIVATE_KEY:-}" ] && [ -z "$${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]; then \
		echo "❌ No private key configured"; \
		echo "   Set GITHUB_APP_PRIVATE_KEY (base64) or GITHUB_APP_PRIVATE_KEY_PATH"; \
		exit 1; \
	fi; \
	echo "✅ GitHub App configuration looks valid"; \
	echo "   App ID: $${GITHUB_APP_ID}"; \
	echo "   Installation ID: $${GITHUB_APP_INSTALLATION_ID}"; \
	if [ -n "$${GITHUB_APP_PRIVATE_KEY_PATH:-}" ]; then \
		echo "   Private Key: $${GITHUB_APP_PRIVATE_KEY_PATH}"; \
	else \
		echo "   Private Key: [base64 encoded]"; \
	fi

build: ## Build the agent container image
	@GODOT_VERSION=$(GODOT_VERSION) \
	 GODOT_RELEASE_TYPE=$(GODOT_RELEASE_TYPE) \
	 ./$(SCRIPT_DIR)/build.sh

build-no-cache: ## Build image without cache
	@GODOT_VERSION=$(GODOT_VERSION) \
	 GODOT_RELEASE_TYPE=$(GODOT_RELEASE_TYPE) \
	 ./$(SCRIPT_DIR)/build.sh --no-cache

validate: ## Validate compose configuration
	@echo "Validating compose files..."
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml config --quiet && \
		echo "✓ compose.base.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.direct.yml config --quiet && \
		echo "✓ compose.direct.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.staging.yml config --quiet && \
		echo "✓ compose.staging.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.persistent.yml config --quiet && \
		echo "✓ compose.persistent.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.isolated.yml config --quiet && \
		echo "✓ compose.isolated.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.queue.yml config --quiet && \
		echo "✓ compose.queue.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.pool.yml config --quiet && \
		echo "✓ compose.pool.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.offline.yml config --quiet && \
		echo "✓ compose.offline.yml is valid"
	@echo "All compose files valid!"

#==============================================================================
# SERVICE LIFECYCLE
#==============================================================================

up: ## Start infrastructure services (DNS + proxies)
	@./$(SCRIPT_DIR)/up.sh

down: ## Stop all services
	@./$(SCRIPT_DIR)/down.sh

down-volumes: ## Stop all services and remove volumes
	@./$(SCRIPT_DIR)/down.sh --volumes

restart: down up ## Restart all services

status: ## Show service status
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml ps

#==============================================================================
# CLAUDE SESSIONS
#==============================================================================

run-direct: _check-project ## Run Claude in direct mode (PROJECT=/path required)
	@./$(SCRIPT_DIR)/run-claude.sh direct "$(PROJECT_PATH)"

run-staging: _check-staging ## Run Claude in staging mode (STAGING=/path required)
	@./$(SCRIPT_DIR)/run-claude.sh staging "$(STAGING_PATH)"

run-offline: _check-project ## Run Claude in offline mode (PROJECT=/path required)
	@./$(SCRIPT_DIR)/run-claude.sh offline "$(PROJECT_PATH)"

shell: ## Open a shell in the agent container (offline mode)
ifdef PROJECT_PATH
	@cd $(COMPOSE_DIR) && PROJECT_PATH=$(PROJECT_PATH) \
		docker compose -f compose.offline.yml run --rm agent bash
else
	@echo "Usage: make shell PROJECT=/path/to/project"
	@exit 1
endif

#==============================================================================
# PERSISTENT MODE (keeps agent running for quick iterations)
#==============================================================================

up-agent: _check-project _check-auth ## Start persistent agent container (PROJECT=/path)
	@echo "Starting infrastructure services..."
	@./$(SCRIPT_DIR)/up.sh
	@echo ""
	@echo "Starting persistent agent container..."
	@cd $(COMPOSE_DIR) && PROJECT_PATH=$(PROJECT_PATH) \
		docker compose --env-file ../.env -f compose.base.yml -f compose.persistent.yml up -d agent
	@echo ""
	@echo "Agent is running! Use these commands:"
	@echo "  make claude              - Start interactive Claude session"
	@echo "  make claude P=\"prompt\"   - Run single prompt"
	@echo "  make agent-status        - Check agent status"
	@echo "  make down-agent          - Stop agent"

down-agent: ## Stop persistent agent container
	@echo "Stopping agent container..."
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.persistent.yml down
	@echo "Agent stopped."

agent-status: ## Show persistent agent status
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agent$$'; then \
		echo "Agent container: RUNNING"; \
		echo "  Project: $$(docker exec agent pwd 2>/dev/null || echo 'unknown')"; \
		echo "  Uptime: $$(docker ps --format '{{.Status}}' --filter name=agent)"; \
	else \
		echo "Agent container: NOT RUNNING"; \
		echo "  Start with: make up-agent PROJECT=/path/to/project"; \
		echo "  Or isolated: make up-isolated REPO=owner/repo"; \
	fi

#==============================================================================
# ISOLATED MODE (agent clones repo into its own workspace)
#==============================================================================

_check-repo:
ifndef REPO
	@echo "Error: REPO is required for isolated mode"
	@echo "Usage: make up-isolated REPO=owner/repo"
	@echo "   or: make up-isolated REPO=owner/repo BRANCH=feature-branch"
	@exit 1
endif

up-isolated: _check-repo _check-auth ## Start isolated agent (REPO=owner/repo, BRANCH=main)
	@echo "Starting infrastructure services..."
	@./$(SCRIPT_DIR)/up.sh
	@echo ""
	@echo "Starting isolated agent container..."
	@echo "  Repository: $(REPO)"
	@echo "  Branch: $(or $(BRANCH),main)"
	@cd $(COMPOSE_DIR) && GITHUB_REPO=$(REPO) GITHUB_BRANCH=$(or $(BRANCH),main) \
		docker compose --env-file ../.env -f compose.base.yml -f compose.isolated.yml up -d agent
	@echo ""
	@sleep 2  # Give time for clone to complete
	@echo "Agent is running in isolated mode!"
	@echo "  The agent will clone $(REPO) into its own workspace."
	@echo ""
	@echo "Commands:"
	@echo "  make claude              - Start interactive Claude session"
	@echo "  make claude P=\"prompt\"   - Run single prompt"
	@echo "  make agent-status        - Check agent status"
	@echo "  make down-isolated       - Stop agent (workspace destroyed)"

down-isolated: ## Stop isolated agent (destroys workspace)
	@echo "Stopping isolated agent container..."
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.isolated.yml down -v
	@echo "Agent stopped and workspace destroyed."

claude: ## Run Claude in agent (interactive or P="prompt")
ifdef P
	@./$(SCRIPT_DIR)/claude-exec.sh "$(P)"
else
	@./$(SCRIPT_DIR)/claude-exec.sh
endif

claude-print: ## Run Claude in print mode for automation (P="prompt" required)
ifndef P
	@echo "Error: P (prompt) is required for print mode"
	@echo "Usage: make claude-print P=\"your prompt\""
	@exit 1
endif
	@./$(SCRIPT_DIR)/claude-exec.sh --print "$(P)"

claude-shell: ## Open bash shell in running agent
	@./$(SCRIPT_DIR)/claude-exec.sh --shell

verify-permissions: ## Verify Claude Code permissions configuration
	@./$(SCRIPT_DIR)/verify-permissions.sh
	@./$(SCRIPT_DIR)/claude-exec.sh --shell

#==============================================================================
# QUEUE MODE (async task processing)
#==============================================================================

queue-start: _check-project _check-auth ## Start queue processor daemon (PROJECT=/path)
	@echo "Starting infrastructure services..."
	@./$(SCRIPT_DIR)/up.sh
	@echo ""
	@echo "Initializing queue directories..."
	@mkdir -p "$(PROJECT_PATH)/.claude/queue"
	@mkdir -p "$(PROJECT_PATH)/.claude/completed"
	@mkdir -p "$(PROJECT_PATH)/.claude/failed"
	@mkdir -p "$(PROJECT_PATH)/.claude/results"
	@echo ""
	@echo "Starting queue processor daemon..."
	@cd $(COMPOSE_DIR) && PROJECT_PATH=$(PROJECT_PATH) \
		docker compose --env-file ../.env -f compose.base.yml -f compose.queue.yml up -d agent
	@echo ""
	@echo "Queue processor running!"
	@echo ""
	@echo "Add tasks:"
	@echo "  make queue-add TASK=\"your prompt\" NAME=001-task PROJECT=$(PROJECT_PATH)"
	@echo "  echo \"prompt\" > $(PROJECT_PATH)/.claude/queue/001-task.md"
	@echo ""
	@echo "Monitor:"
	@echo "  make queue-status PROJECT=$(PROJECT_PATH)"
	@echo "  make queue-logs"

queue-stop: ## Stop queue processor daemon
	@echo "Stopping queue processor..."
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.queue.yml down
	@echo "Queue processor stopped."

queue-status: _check-project ## Show queue status (PROJECT=/path)
	@echo "╔══════════════════════════════════════════════════════════════════════╗"
	@echo "║                         Queue Status                                 ║"
	@echo "╚══════════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📬 Pending tasks:"
	@ls -1 "$(PROJECT_PATH)/.claude/queue/"*.md "$(PROJECT_PATH)/.claude/queue/"*.txt 2>/dev/null | \
		while read f; do echo "   - $$(basename $$f)"; done || echo "   (none)"
	@echo ""
	@echo "⚙️  Processing:"
	@ls -1 "$(PROJECT_PATH)/.claude/processing/"*.md "$(PROJECT_PATH)/.claude/processing/"*.txt 2>/dev/null | \
		while read f; do echo "   - $$(basename $$f)"; done || echo "   (none)"
	@echo ""
	@echo "✅ Completed (last 5):"
	@ls -1t "$(PROJECT_PATH)/.claude/completed/"*.md "$(PROJECT_PATH)/.claude/completed/"*.txt 2>/dev/null | \
		head -5 | while read f; do echo "   - $$(basename $$f)"; done || echo "   (none)"
	@echo ""
	@echo "❌ Failed:"
	@ls -1 "$(PROJECT_PATH)/.claude/failed/"*.md "$(PROJECT_PATH)/.claude/failed/"*.txt 2>/dev/null | \
		while read f; do echo "   - $$(basename $$f)"; done || echo "   (none)"
	@echo ""
	@if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^agent$$'; then \
		echo "🟢 Queue processor: RUNNING"; \
	else \
		echo "🔴 Queue processor: NOT RUNNING"; \
	fi

queue-logs: ## Follow queue processor logs
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.queue.yml logs -f agent

queue-add: _check-project ## Add task to queue (TASK="prompt" NAME=001-name PROJECT=/path)
ifndef TASK
	@echo "Error: TASK is required"
	@echo "Usage: make queue-add TASK=\"your prompt here\" NAME=001-taskname PROJECT=/path"
	@exit 1
endif
	$(eval TASK_NAME := $(or $(NAME),$(shell date +%Y%m%d%H%M%S)))
	@mkdir -p "$(PROJECT_PATH)/.claude/queue"
	@echo "$(TASK)" > "$(PROJECT_PATH)/.claude/queue/$(TASK_NAME).md"
	@echo "✅ Added task: $(PROJECT_PATH)/.claude/queue/$(TASK_NAME).md"
	@echo ""
	@cat "$(PROJECT_PATH)/.claude/queue/$(TASK_NAME).md"

queue-init: _check-project ## Initialize queue directories (PROJECT=/path)
	@echo "Initializing queue directories in $(PROJECT_PATH)/.claude/..."
	@mkdir -p "$(PROJECT_PATH)/.claude/queue"
	@mkdir -p "$(PROJECT_PATH)/.claude/processing"
	@mkdir -p "$(PROJECT_PATH)/.claude/completed"
	@mkdir -p "$(PROJECT_PATH)/.claude/failed"
	@mkdir -p "$(PROJECT_PATH)/.claude/results"
	@echo "✅ Queue directories created:"
	@echo "   $(PROJECT_PATH)/.claude/queue/      - Drop task files here"
	@echo "   $(PROJECT_PATH)/.claude/results/    - View execution logs"
	@echo "   $(PROJECT_PATH)/.claude/completed/  - Completed tasks"
	@echo "   $(PROJECT_PATH)/.claude/failed/     - Failed tasks"

queue-results: _check-project ## Show latest result (PROJECT=/path)
	@LATEST=$$(ls -1t "$(PROJECT_PATH)/.claude/results/"*.log 2>/dev/null | head -1); \
	if [ -n "$$LATEST" ]; then \
		echo "Latest result: $$LATEST"; \
		echo ""; \
		cat "$$LATEST"; \
	else \
		echo "No results yet."; \
	fi

#==============================================================================
# POOL MODE (multiple isolated agents processing GitHub issues)
#==============================================================================

WORKERS ?= 3
ISSUE_LABEL ?= agent-ready

pool-start: _check-repo _check-auth ## Start worker pool (REPO=owner/repo WORKERS=3)
	@echo "Starting infrastructure services..."
	@./$(SCRIPT_DIR)/up.sh
	@echo ""
	@echo "Starting worker pool..."
	@echo "  Repository: $(REPO)"
	@echo "  Workers: $(WORKERS)"
	@echo "  Issue Label: $(ISSUE_LABEL)"
	@echo ""
	@cd $(COMPOSE_DIR) && GITHUB_REPO=$(REPO) ISSUE_LABEL=$(ISSUE_LABEL) \
		docker compose --env-file ../.env -f compose.base.yml -f compose.pool.yml up -d --scale worker=$(WORKERS)
	@echo ""
	@echo "Worker pool running!"
	@echo ""
	@echo "Workers will:"
	@echo "  1. Clone $(REPO) into isolated workspaces"
	@echo "  2. Poll for issues labeled '$(ISSUE_LABEL)'"
	@echo "  3. Claim issues, create branches, run Claude"
	@echo "  4. Open PRs for completed work"
	@echo ""
	@echo "Commands:"
	@echo "  make pool-status               - Show worker status"
	@echo "  make pool-logs                 - Follow worker logs"
	@echo "  make pool-scale WORKERS=5      - Scale to 5 workers"
	@echo "  make pool-stop                 - Stop all workers"

pool-stop: ## Stop worker pool
	@echo "Stopping worker pool..."
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.pool.yml down -v
	@echo "Worker pool stopped and workspaces destroyed."

pool-status: ## Show worker pool status
	@echo "╔══════════════════════════════════════════════════════════════════════╗"
	@echo "║                       Worker Pool Status                             ║"
	@echo "╚══════════════════════════════════════════════════════════════════════╝"
	@echo ""
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.pool.yml ps worker 2>/dev/null || echo "Pool not running"
	@echo ""
	@RUNNING=$$(docker ps --filter "name=compose-worker" --format '{{.Names}}' 2>/dev/null | wc -l | tr -d ' '); \
	echo "Active workers: $$RUNNING"

pool-logs: ## Follow worker pool logs
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.pool.yml logs -f worker

pool-scale: _check-auth ## Scale worker pool (WORKERS=N)
	@echo "Scaling worker pool to $(WORKERS) workers..."
	@cd $(COMPOSE_DIR) && docker compose --env-file ../.env -f compose.base.yml -f compose.pool.yml up -d --scale worker=$(WORKERS)
	@echo "Pool scaled to $(WORKERS) workers."

#==============================================================================
# GODOT OPERATIONS
#==============================================================================

run-godot: _check-project ## Run Godot headless command (PROJECT=/path ARGS='...')
	@./$(SCRIPT_DIR)/run-godot.sh "$(PROJECT_PATH)" $(ARGS)

godot-version: _check-project ## Show Godot version
	@./$(SCRIPT_DIR)/run-godot.sh "$(PROJECT_PATH)" --version

godot-validate: _check-project ## Validate Godot project
	@./$(SCRIPT_DIR)/run-godot.sh "$(PROJECT_PATH)" --validate-project

godot-doctor: _check-project ## Run Godot project doctor
	@./$(SCRIPT_DIR)/run-godot.sh "$(PROJECT_PATH)" --doctor

#==============================================================================
# STAGING WORKFLOW
#==============================================================================

promote: _check-staging _check-live ## Promote staging to live (STAGING=/path LIVE=/path)
	@./$(SCRIPT_DIR)/promote.sh "$(STAGING_PATH)" "$(LIVE_PATH)"

promote-dry-run: _check-staging _check-live ## Preview promotion without copying
	@./$(SCRIPT_DIR)/promote.sh "$(STAGING_PATH)" "$(LIVE_PATH)" --dry-run

diff-review: _check-staging _check-live ## Show diff between staging and live
	@./$(SCRIPT_DIR)/diff-review.sh "$(STAGING_PATH)" "$(LIVE_PATH)"

diff-full: _check-staging _check-live ## Show full diff output
	@./$(SCRIPT_DIR)/diff-review.sh "$(STAGING_PATH)" "$(LIVE_PATH)" --full

#==============================================================================
# SECURITY
#==============================================================================

scan: _check-project ## Scan project for dangerous patterns
	@./$(SCRIPT_DIR)/scan-dangerous.sh "$(PROJECT_PATH)"

scan-staging: _check-staging ## Scan staging directory
	@./$(SCRIPT_DIR)/scan-dangerous.sh "$(STAGING_PATH)"

#==============================================================================
# OBSERVABILITY
#==============================================================================

logs: ## Follow all service logs
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml logs -f

logs-dns: ## Follow DNS filter logs only
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml logs -f dnsfilter

logs-proxy: ## Follow all proxy logs
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml logs -f \
		proxy_github proxy_raw_githubusercontent proxy_codeload_github \
		proxy_godot_docs proxy_anthropic_api

logs-report: ## Generate network activity report
	@./$(SCRIPT_DIR)/logs-report.sh

logs-report-1h: ## Generate report for last hour
	@./$(SCRIPT_DIR)/logs-report.sh --since 1h

#==============================================================================
# CLEANUP
#==============================================================================

clean: ## Remove logs and temporary files
	@echo "Cleaning logs directory..."
	@rm -rf $(LOGS_DIR)/*
	@echo "Done."

clean-all: down-volumes clean ## Stop services, remove volumes and logs
	@echo "Removing dangling images..."
	@docker image prune -f 2>/dev/null || true
	@echo "Done."

clean-images: ## Remove agent images
	@echo "Removing claude-godot-agent images..."
	@docker rmi claude-godot-agent:latest 2>/dev/null || true
	@docker rmi claude-godot-agent:godot-$(GODOT_VERSION)-$(GODOT_RELEASE_TYPE) 2>/dev/null || true
	@echo "Done."

#==============================================================================
# DEVELOPMENT
#==============================================================================

test: doctor validate ## Run all checks (not security tests)
	@echo ""
	@echo "All validation checks passed!"
	@echo "Run 'make test-security' for security tests (requires Docker)"

#==============================================================================
# SECURITY TESTS
#==============================================================================

# Virtual environment for tests
VENV := .venv
VENV_PYTHON := $(VENV)/bin/python
VENV_PYTEST := $(VENV)/bin/pytest

install-tests: $(VENV) ## Install test dependencies (requires uv)

$(VENV): tests/requirements.txt
	@if ! command -v uv >/dev/null 2>&1; then \
		echo "Error: uv is not installed"; \
		echo "Install with: brew install uv"; \
		exit 1; \
	fi
	@echo "Creating virtual environment..."
	@uv venv $(VENV)
	@echo "Installing test dependencies..."
	@uv pip install -p $(VENV_PYTHON) -r tests/requirements.txt
	@touch $(VENV)
	@echo "✓ Test dependencies installed in $(VENV)"

test-security: _check-tests build ## Run all security tests
	@echo "Running security tests..."
	@cd tests && ../$(VENV_PYTEST) -v --tb=short

test-security-parallel: _check-tests build ## Run security tests in parallel
	@echo "Running security tests in parallel..."
	@cd tests && ../$(VENV_PYTEST) -v --tb=short -n auto

test-dns: _check-tests ## Run DNS filtering tests only
	@echo "Running DNS filtering tests..."
	@cd tests && ../$(VENV_PYTEST) test_dns_filtering.py -v

test-network: _check-tests ## Run network restriction tests only
	@echo "Running network restriction tests..."
	@cd tests && ../$(VENV_PYTEST) test_network_restrictions.py -v

test-hardening: _check-tests ## Run container hardening tests only
	@echo "Running container hardening tests..."
	@cd tests && ../$(VENV_PYTEST) test_container_hardening.py -v

test-filesystem: _check-tests ## Run filesystem restriction tests only
	@echo "Running filesystem restriction tests..."
	@cd tests && ../$(VENV_PYTEST) test_filesystem_restrictions.py -v

test-offline: _check-tests ## Run offline mode tests only
	@echo "Running offline mode tests..."
	@cd tests && ../$(VENV_PYTEST) test_offline_mode.py -v

test-github-app-module: _check-tests ## Run GitHub App module unit tests
	@echo "Running GitHub App module tests..."
	@cd tests && ../$(VENV_PYTEST) test_github_app_module.py -v

test-github-app-integration: _check-tests build ## Run GitHub App integration tests
	@echo "Running GitHub App integration tests..."
	@cd tests && ../$(VENV_PYTEST) test_github_app_integration.py -v

_check-tests:
	@if ! docker info >/dev/null 2>&1; then \
		echo "Error: Docker is not running"; \
		exit 1; \
	fi
	@if [ ! -f "$(VENV_PYTEST)" ]; then \
		echo "Error: Test environment not set up"; \
		echo "Run: make install-tests"; \
		exit 1; \
	fi

#==============================================================================
# DEVELOPMENT (continued)
#==============================================================================

lint-scripts: ## Lint shell scripts with shellcheck
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck $(SCRIPT_DIR)/*.sh $(IMAGE_DIR)/install/*.sh; \
		echo "All scripts passed!"; \
	else \
		echo "shellcheck not installed. Install with: brew install shellcheck"; \
		exit 1; \
	fi

install-hooks: ## Install git pre-commit hooks for secret scanning and shellcheck
	@echo "Installing git hooks..."
	@git config core.hooksPath .githooks
	@echo "✓ Git hooks installed from .githooks/"
	@echo "  Pre-commit hook will:"
	@echo "    - Scan for secrets before each commit"
	@echo "    - Run shellcheck on shell scripts"
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo ""; \
		echo "⚠️  shellcheck not installed. Install with: brew install shellcheck"; \
	fi

#==============================================================================
# CI/CD LOCAL TESTING (requires: brew install act)
#==============================================================================

# Architecture flag for Apple Silicon
ACT_ARCH := $(shell uname -m | grep -q arm64 && echo "--container-architecture linux/amd64" || echo "")

ci: _check-act ## Run full CI workflow locally
	@echo "Running CI workflow locally..."
	act push -W .github/workflows/ci.yml $(ACT_ARCH)

ci-validate: _check-act ## Run CI validate job only
	@echo "Running validate job..."
	act -j validate $(ACT_ARCH)

ci-build: _check-act ## Run CI build-test job only
	@echo "Running build-test job..."
	act -j build-test $(ACT_ARCH)

ci-list: _check-act ## List available CI jobs
	@act -l

ci-dry-run: _check-act ## Dry run CI (show what would happen)
	@act push -W .github/workflows/ci.yml -n $(ACT_ARCH)

_check-act:
	@if ! command -v act >/dev/null 2>&1; then \
		echo "Error: 'act' is not installed"; \
		echo "Install with: brew install act"; \
		exit 1; \
	fi

#==============================================================================
# INTERNAL HELPERS
#==============================================================================

_check-auth:
	@if [ ! -f ".env" ]; then \
		echo "Warning: .env file not found"; \
	fi
	@if [ -z "$${ANTHROPIC_API_KEY:-}" ] && [ -z "$${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then \
		if [ -f ".env" ]; then \
			. ./.env 2>/dev/null || true; \
		fi; \
		if [ -z "$${ANTHROPIC_API_KEY:-}" ] && [ -z "$${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then \
			echo "Warning: No Claude authentication configured in .env"; \
			echo "  Set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN"; \
		fi; \
	fi

_check-project:
ifndef PROJECT_PATH
ifndef PROJECT
	@echo "Error: PROJECT or PROJECT_PATH is required"
	@echo "Usage: make $@ PROJECT=/path/to/project"
	@exit 1
else
	$(eval PROJECT_PATH := $(PROJECT))
endif
endif

_check-staging:
ifndef STAGING_PATH
ifndef STAGING
	@echo "Error: STAGING or STAGING_PATH is required"
	@echo "Usage: make $@ STAGING=/path/to/staging"
	@exit 1
else
	$(eval STAGING_PATH := $(STAGING))
endif
endif

_check-live:
ifndef LIVE_PATH
ifndef LIVE
	@echo "Error: LIVE or LIVE_PATH is required"
	@echo "Usage: make $@ LIVE=/path/to/live"
	@exit 1
else
	$(eval LIVE_PATH := $(LIVE))
endif
endif

#==============================================================================
# SHORTCUTS
#==============================================================================

# Aliases for common operations
d: doctor
b: build
u: up
s: status
l: logs
r: logs-report
c: claude
cp: claude-print
a: agent-status
q: queue-status
qs: queue-start
qx: queue-stop
p: pool-status
ps: pool-start
px: pool-stop
pl: pool-logs

# Print configuration
config: ## Show current configuration
	@echo "Configuration:"
	@echo "  GODOT_VERSION:      $(GODOT_VERSION)"
	@echo "  GODOT_RELEASE_TYPE: $(GODOT_RELEASE_TYPE)"
	@echo "  PROJECT_PATH:       $(if $(PROJECT_PATH),$(PROJECT_PATH),(not set))"
	@echo "  STAGING_PATH:       $(if $(STAGING_PATH),$(STAGING_PATH),(not set))"
	@echo "  LIVE_PATH:          $(if $(LIVE_PATH),$(LIVE_PATH),(not set))"

