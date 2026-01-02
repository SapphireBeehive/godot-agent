# Claude-Godot Sandbox Makefile
# Usage: make <target>
#
# Run 'make help' to see all available targets

.PHONY: help build up down doctor logs clean run-direct run-staging run-offline \
        run-godot promote diff-review scan logs-report shell test validate \
        build-no-cache restart status

# Default target
.DEFAULT_GOAL := help

# Configuration (can be overridden: make build GODOT_VERSION=4.4)
GODOT_VERSION ?= 4.3
GODOT_RELEASE_TYPE ?= stable
GODOT_SHA256 ?=
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
	@echo "$(GREEN)Quick Start:$(RESET)"
	@echo "  make doctor        # Check your environment"
	@echo "  make build         # Build the agent image"
	@echo "  make up            # Start infrastructure services"
	@echo "  make run-direct PROJECT=/path/to/project"
	@echo ""
	@echo "$(GREEN)Available Targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(CYAN)%-18s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(GREEN)Examples:$(RESET)"
	@echo "  make run-direct PROJECT=~/my-godot-game"
	@echo "  make run-staging STAGING=~/staging LIVE=~/my-godot-game"
	@echo "  make run-godot PROJECT=~/my-godot-game ARGS='--version'"
	@echo "  make promote STAGING=~/staging LIVE=~/my-godot-game"
	@echo ""

#==============================================================================
# SETUP & BUILD
#==============================================================================

doctor: ## Check environment health
	@./$(SCRIPT_DIR)/doctor.sh

build: ## Build the agent container image
	@GODOT_VERSION=$(GODOT_VERSION) \
	 GODOT_RELEASE_TYPE=$(GODOT_RELEASE_TYPE) \
	 GODOT_SHA256=$(GODOT_SHA256) \
	 ./$(SCRIPT_DIR)/build.sh

build-no-cache: ## Build image without cache
	@GODOT_VERSION=$(GODOT_VERSION) \
	 GODOT_RELEASE_TYPE=$(GODOT_RELEASE_TYPE) \
	 GODOT_SHA256=$(GODOT_SHA256) \
	 ./$(SCRIPT_DIR)/build.sh --no-cache

validate: ## Validate compose configuration
	@echo "Validating compose files..."
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml config --quiet && \
		echo "✓ compose.base.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.direct.yml config --quiet && \
		echo "✓ compose.direct.yml is valid"
	@cd $(COMPOSE_DIR) && docker compose -f compose.base.yml -f compose.staging.yml config --quiet && \
		echo "✓ compose.staging.yml is valid"
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
	@docker rmi claude-godot-agent:$(GODOT_VERSION) 2>/dev/null || true
	@echo "Done."

#==============================================================================
# DEVELOPMENT
#==============================================================================

test: doctor validate ## Run all checks
	@echo ""
	@echo "All tests passed!"

lint-scripts: ## Lint shell scripts with shellcheck
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck $(SCRIPT_DIR)/*.sh $(IMAGE_DIR)/install/*.sh; \
		echo "All scripts passed!"; \
	else \
		echo "shellcheck not installed. Install with: brew install shellcheck"; \
		exit 1; \
	fi

#==============================================================================
# INTERNAL HELPERS
#==============================================================================

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

# Print configuration
config: ## Show current configuration
	@echo "Configuration:"
	@echo "  GODOT_VERSION:      $(GODOT_VERSION)"
	@echo "  GODOT_RELEASE_TYPE: $(GODOT_RELEASE_TYPE)"
	@echo "  GODOT_SHA256:       $(if $(GODOT_SHA256),$(GODOT_SHA256),(not set))"
	@echo "  PROJECT_PATH:       $(if $(PROJECT_PATH),$(PROJECT_PATH),(not set))"
	@echo "  STAGING_PATH:       $(if $(STAGING_PATH),$(STAGING_PATH),(not set))"
	@echo "  LIVE_PATH:          $(if $(LIVE_PATH),$(LIVE_PATH),(not set))"

