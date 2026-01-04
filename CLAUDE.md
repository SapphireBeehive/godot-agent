# Claude Code Context for godot-agent

This repository provides a secure, sandboxed Docker environment for running Claude Code with Godot game development projects.

## Project Purpose

The sandbox isolates Claude Code in a container with:
- **Network allowlisting**: Only GitHub, Godot docs, and Anthropic API are accessible
- **Filesystem isolation**: Only the mounted project directory is writable
- **Security hardening**: Read-only rootfs, dropped capabilities, resource limits

This protects against Claude accidentally (or maliciously) accessing sensitive data or making unwanted network connections.

**Permissions**: Claude Code runs with all permissions pre-granted (file edits, command execution, etc.) since security is enforced by the container sandbox, not by Claude's internal permission system. See `image/config/claude-settings.json` for the full list.

## ⚠️ Two Contexts: Host vs Sandboxed Agent

This file (`CLAUDE.md`) documents **host-side operations** - commands run on the developer's machine to manage the sandbox infrastructure.

**If you are Claude running INSIDE the sandbox container**, your context file is:
```text
/project/.claude/sandbox-context.md
```
Or see `image/config/sandbox-context.md` in this repo for the full reference.

### Key Differences

| Context | GitHub Access | Git Operations | File Access |
|---------|---------------|----------------|-------------|
| **Host** (this file) | `gh` CLI, git with SSH | Full git access | Full filesystem |
| **Sandboxed Agent** | **MCP tools only** | git for local ops, MCP for remote | Only `/project` |

### For Sandboxed Agents: Use MCP Tools, NOT `gh`

When running inside the container, **do NOT use `gh` CLI** for GitHub operations. Instead use MCP tools:

| Task | ❌ Don't Use | ✅ Use Instead |
|------|-------------|----------------|
| List issues | `gh issue list` | `list_issues` MCP tool |
| Create issue | `gh issue create` | `create_issue` MCP tool |
| Create PR | `gh pr create` | `create_pull_request` MCP tool |
| Comment on issue | `gh issue comment` | `create_issue_comment` MCP tool |
| Read remote file | `gh api` | `get_file_contents` MCP tool |

**Why?** The `gh` CLI requires authentication setup that may not be available in the sandbox. MCP tools are pre-configured with GitHub App authentication.

**Git CLI is fine for local operations:**
```bash
git status          # ✅ OK
git add .           # ✅ OK  
git commit -m "..."  # ✅ OK
git checkout -b ...  # ✅ OK
git push            # ⚠️ Use MCP push_files if git push fails
```

## Contents

- [Two Contexts: Host vs Sandboxed Agent](#️-two-contexts-host-vs-sandboxed-agent)
- [Pre-built Image](#pre-built-image)
- [Skills](#skills)
  - [First-Time Setup](#skill-first-time-setup)
  - [GitHub Authentication](#skill-github-authentication)
  - [Persistent Mode (Recommended)](#skill-running-claude-in-the-sandbox-persistent-mode---recommended)
  - [Non-Interactive / Automation](#skill-non-interactive--automation-mode)
  - [One-shot Mode](#skill-running-claude-in-the-sandbox-one-shot-mode)
  - [Daily Workflows](#skill-daily-workflow-persistent-mode)
  - [Queue Mode](#skill-queue-mode-async-task-processing)
  - [Emergency Recovery](#skill-emergency-recovery)
  - [Updating to Latest Image](#skill-updating-to-latest-image)
  - [Debugging Infrastructure](#skill-debugging-infrastructure-issues)
  - [Before Committing](#skill-before-committing-changes)
  - [Security Scanning](#skill-scanning-for-security-issues)
  - [Staging Mode](#skill-working-with-staging-mode)
  - [Running Godot](#skill-running-godot-commands)
  - [Security Tests](#skill-running-security-tests)
  - [Testing CI Locally](#skill-testing-ci-locally)
  - [Building with Different Godot Versions](#skill-building-with-different-godot-versions)
  - [Adding a New Allowed Domain](#skill-adding-a-new-allowed-domain)
  - [Sandboxed Agent Workflows](#skill-sandboxed-agent-workflows)
- [Repository Structure](#repository-structure)
- [Logging](#logging)
- [Makefile Quick Reference](#makefile-quick-reference)
- [Authentication](#authentication)
- [Conventions](#conventions)
- [Common Issues](#common-issues)
- [Lessons Learned](#lessons-learned-for-future-claude-instances)
  - [#1: Nginx Stream Proxy](#critical-issue-1-nginx-stream-proxy-configuration)
  - [#2: CoreDNS Configuration](#critical-issue-2-coredns-configuration)
  - [#3: Agent Container is Minimal](#critical-issue-3-agent-container-is-minimal)
  - [#4: CI Test Project Permissions](#critical-issue-4-ci-test-project-permissions)
  - [#5: Prefer Pre-built Image](#critical-issue-5-prefer-pre-built-image-over-local-builds)
  - [#6: Claude Config Files (MCP vs Settings)](#critical-issue-6-claude-configuration-files-mcp-vs-settings)
  - [#7: Godot Download URLs](#critical-issue-7-godot-download-urls)

---

## Pre-built Image

The agent image is automatically built and pushed to GitHub Container Registry:
```text
ghcr.io/sapphirebeehivestudios/claude-godot-agent
```

### Available Tags

| Tag | Example | Description |
|-----|---------|-------------|
| `latest` | `:latest` | Most recent build from main branch |
| `godot-X.Y-TYPE` | `:godot-4.6-beta2` | Tagged by Godot version + release type |
| `claude-X.Y.Z` | `:claude-2.0.76` | Tagged by Claude Code version |
| `YYYYMMDD` | `:20250102` | Tagged by build date |
| `sha-XXXXXX` | `:sha-a1b2c3d` | Tagged by git commit SHA |

### Architectures

Multi-arch manifest with both platforms (pulls correct one automatically):
- `linux/amd64` - Intel/AMD (x86_64)
- `linux/arm64` - Apple Silicon, ARM servers

Build workflow: `.github/workflows/build-and-push.yml`

---

## Skills

### Skill: First-Time Setup

When setting up this project for the first time:

```bash
# 0. Verify Docker is running
docker ps || { echo "Error: Docker is not running. Start Docker Desktop first."; exit 1; }

# 1. Check environment prerequisites
make doctor

# 2. Set up authentication (Claude Max recommended)
claude setup-token
# Copy the token, then:
echo 'CLAUDE_CODE_OAUTH_TOKEN=sk-ant-...' >> .env

# 3. Verify auth is configured
make auth

# 4. Install git hooks for secret scanning
make install-hooks

# 5. Get the agent image (pull pre-built - faster than building locally)
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:4.6

# 5a. (Optional) Build locally only if modifying the Dockerfile
# make build

# 6. Start infrastructure services
make up
```

### Skill: GitHub Authentication

#### Host-Side (Outside Container)

On your host machine, use `gh` CLI with your personal authentication:

```bash
# Authenticate gh CLI (one-time)
gh auth login

# Then use normally
gh issue list
gh pr create --title "Fix" --body "Details"
gh release create v1.0.0
```

#### Sandboxed Agent (Inside Container) - MCP Only

**⚠️ The sandboxed agent uses MCP tools exclusively for GitHub operations.**

No `gh` CLI. No PAT. MCP tools are pre-authenticated via GitHub App.

```
# List issues
Use list_issues with owner and repo parameters

# Create an issue  
Use create_issue with owner, repo, title, body

# Create a PR
Use create_pull_request with owner, repo, title, body, head, base

# Comment on issue (to claim it)
Use create_issue_comment with owner, repo, issue_number, body

# Read remote files
Use get_file_contents with owner, repo, path

# Push changes
Use push_files with owner, repo, branch, files, message
```

**Why MCP only?**
- Pre-authenticated via GitHub App (no token management)
- Installation tokens auto-refresh (~1 hour expiry)
- No credential leakage risk
- Consistent behavior across all sandbox modes

**Git CLI is fine for local operations:**
```bash
git status          # ✅ OK
git add .           # ✅ OK  
git commit -m "..."  # ✅ OK
git checkout -b ...  # ✅ OK
git log             # ✅ OK
# For remote operations (push, PR) → use MCP tools
```

**Branch Protection (enabled automatically):**
- ⛔ Direct pushes to `main`/`master` are **blocked** by pre-push hook
- ✅ Clone script automatically creates a `claude/work-*` branch
- ✅ Force pushes and branch deletions are disabled
- Use MCP `create_pull_request` to merge changes

**GitHub App Setup (Required for Sandbox):**
```bash
# Set in .env file:
GITHUB_APP_ID=your_app_id
GITHUB_APP_INSTALLATION_ID=your_installation_id
GITHUB_APP_PRIVATE_KEY_PATH=/secrets/your-app.private-key.pem
```

See `docs/GITHUB_APP_SETUP.md` for full GitHub App configuration.

### Skill: Running Claude in the Sandbox (Persistent Mode - Recommended)

Persistent mode keeps the agent running for quick iterations:

```bash
# Start persistent agent (infrastructure + agent container)
make up-agent PROJECT=/path/to/godot/project

# Run Claude commands instantly (no startup delay)
make claude                          # Interactive session
make claude P="your prompt here"     # Single prompt
make claude-print P="your prompt"    # Non-interactive batch mode (for scripts/CI)

# Check agent status
make agent-status

# Open bash shell in agent
make claude-shell

# Stop agent when done
make down-agent
```

### Skill: Non-Interactive / Automation Mode

For running Claude from scripts, CI/CD pipelines, or other automation contexts:

```bash
# Print mode - outputs result without interactive prompts
make claude-print P="List all .gd files in this project"

# Or use the script directly with --print flag
./scripts/claude-exec.sh --print "Generate a player script"

# TTY auto-detection: the script automatically detects if a TTY is available
# and adjusts behavior accordingly (no -it flags when running non-interactively)
docker exec agent claude "prompt"  # Works without -it in scripts
```

**Key features for automation:**
- `--print` flag outputs results without interactive prompts
- TTY auto-detection removes `-it` flags when no terminal is attached
- Claude Code permissions are bypassed via `--dangerously-skip-permissions` flag
- All tools (Write, Edit, Bash, etc.) work without approval prompts in both interactive and non-interactive modes
- Environment variables from `.env` are properly passed to the container

**Note:** The `--dangerously-skip-permissions` flag is safe to use in this sandboxed environment because security is enforced by container isolation (network restrictions, filesystem isolation, read-only rootfs) rather than Claude's permission system.

### Skill: Running Claude in the Sandbox (One-shot Mode)

For ephemeral sessions that don't persist context:

```bash
# Direct mode - Claude can modify files immediately
make run-direct PROJECT=/path/to/godot/project

# Staging mode - Safer, changes go to staging directory first
make run-staging STAGING=/path/to/staging

# Offline mode - No network access at all
make run-offline PROJECT=/path/to/godot/project
```

### Skill: Daily Workflow (Persistent Mode)

Recommended daily workflow using persistent agent:

```bash
# Start your day - bring up persistent agent
make up-agent PROJECT=~/my-game

# Throughout the day, quick Claude interactions
make claude P="What's the structure of this project?"
make claude P="Add player movement to player.gd"
make claude P="Fix the bug in collision.gd"

# For longer conversations
make claude

# Check agent is still running
make agent-status

# End of day - shut down
make down-agent
```

### Skill: Daily Workflow (One-shot Mode)

Alternative workflow using ephemeral sessions:

```bash
# Start your day - bring up services
make up

# Check everything is healthy
make status

# Run Claude with your project
make run-direct PROJECT=~/my-game

# When done - shut down services
make down
```

### Skill: Queue Mode (Async Task Processing)

Process tasks asynchronously while you're away:

```bash
# Start the queue processor daemon
make queue-start PROJECT=~/my-game

# Add tasks to the queue
make queue-add TASK="Add player movement" NAME=001-movement PROJECT=~/my-game
make queue-add TASK="Add enemy AI" NAME=002-enemies PROJECT=~/my-game
make queue-add TASK="Create main menu" NAME=003-menu PROJECT=~/my-game

# Or drop files directly
echo "Add a health bar UI" > ~/my-game/.claude/queue/004-health.md

# Check queue status
make queue-status PROJECT=~/my-game

# Watch the processor work
make queue-logs

# View results
make queue-results PROJECT=~/my-game
cat ~/my-game/.claude/results/001-movement.log

# Stop when done
make queue-stop
```

Queue directory structure:
```text
/project/.claude/
├── queue/           # Drop task files here
├── processing/      # Currently being processed  
├── completed/       # Successfully completed
├── failed/          # Failed tasks
└── results/         # Execution logs
```

**Task file format:** Plain text with the prompt for Claude:
```text
# Example: 001-movement.md
Add player movement with WASD controls.

Requirements:
- Use CharacterBody3D
- 10 units/second walk speed  
- Sprint with Shift key (2x speed)
```
The filename becomes the task identifier in results.

### Skill: Emergency Recovery

When everything is broken and normal commands fail:

```bash
# Nuclear option - remove ALL containers and volumes
make clean-all

# Or manually if make doesn't work:
docker compose -f compose/compose.base.yml down --volumes --remove-orphans
docker compose -f compose/compose.persistent.yml down --volumes --remove-orphans 2>/dev/null || true

# Verify clean state
docker ps -a | grep -E "(sandbox|proxy|dns|agent)"  # Should be empty
docker network ls | grep sandbox  # Should be empty

# Fresh start
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:latest
make up
```

### Skill: Updating to Latest Image

When a new version of the agent image is released:

```bash
# Pull latest from registry
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest

# Re-tag for local use
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:4.6

# If using persistent agent, restart it
make down-agent
make up-agent PROJECT=/path/to/project

# Verify new version
docker exec agent godot --version
docker exec agent claude --version
```

### Skill: Debugging Infrastructure Issues

When things aren't working:

```bash
# Check service health
make status

# View live logs from all services
make logs

# View only DNS filter logs (see what's being blocked)
make logs-dns

# View only proxy logs
make logs-proxy

# Full restart
make restart

# Nuclear option - stop everything and clean up
make clean-all
```

### Skill: Before Committing Changes

Always run these before committing:

```bash
# Validate all compose files parse correctly
make validate

# Lint shell scripts
make lint-scripts

# Run the full test suite
make test

# If you have `act` installed, run CI locally
make ci
```

### Skill: Scanning for Security Issues

After Claude modifies a project, scan for dangerous patterns:

```bash
# Scan a project directory
make scan PROJECT=/path/to/godot/project

# Or use the script directly for more options
./scripts/scan-dangerous.sh /path/to/project
```

### Skill: Working with Staging Mode

Safer workflow using staging:

```bash
# 1. Create staging directory
mkdir -p ~/godot-staging

# 2. Run Claude in staging mode
make run-staging STAGING=~/godot-staging

# 3. Review what changed
make diff-review STAGING=~/godot-staging LIVE=~/my-game

# 4. If satisfied, promote changes
make promote STAGING=~/godot-staging LIVE=~/my-game

# 4a. Or do a dry-run first
make promote-dry-run STAGING=~/godot-staging LIVE=~/my-game
```

### Skill: Running Godot Commands

Run Godot headless inside the sandbox:

```bash
# Check Godot version
make godot-version PROJECT=~/my-game

# Validate project structure
make godot-validate PROJECT=~/my-game

# Run project doctor
make godot-doctor PROJECT=~/my-game

# Run arbitrary Godot commands
make run-godot PROJECT=~/my-game ARGS="--export-release Linux build/game"
```

### Skill: Running Security Tests

The sandbox includes comprehensive security tests to verify network restrictions, container hardening, and filesystem isolation:

```bash
# Install test dependencies (requires uv: brew install uv)
make install-tests

# Run all security tests
make test-security

# Run tests in parallel (faster)
make test-security-parallel
```

**Expected output (all tests passing):**
```text
==================== test session starts ====================
collected 23 items
tests/test_dns_filtering.py ......                      [ 26%]
tests/test_network_restrictions.py ....                 [ 43%]
tests/test_container_hardening.py ......                [ 69%]
tests/test_filesystem_restrictions.py ....              [ 87%]
tests/test_offline_mode.py ...                          [100%]
==================== 23 passed in 45.32s ====================
```

```bash
# Run specific test modules
make test-dns          # DNS filtering tests
make test-network      # Network isolation tests
make test-hardening    # Container security tests
make test-filesystem   # Mount/volume tests
make test-offline      # Offline mode tests
```

#### What the tests verify:

| Test Module | Verifies |
|-------------|----------|
| `test_dns_filtering.py` | Allowed domains → proxy IPs, blocked → NXDOMAIN |
| `test_network_restrictions.py` | Agent isolated to sandbox_net, cannot reach internet |
| `test_container_hardening.py` | Read-only rootfs, dropped caps, non-root user, limits |
| `test_filesystem_restrictions.py` | Only /project mounted, no sensitive paths |
| `test_offline_mode.py` | Zero network with network_mode: none |

#### Running tests directly with pytest:

```bash
cd tests

# Verbose output
pytest -v

# Stop on first failure
pytest -x

# Run specific test
pytest test_dns_filtering.py::TestDNSAllowedDomains -v

# Skip network-dependent tests (for CI without external access)
CI_NO_NETWORK=1 pytest
```

### Skill: Testing CI Locally

Test GitHub Actions workflows without pushing:

```bash
# Install act (first time only)
brew install act

# List available jobs
make ci-list

# Dry run - see what would happen
make ci-dry-run

# Run the full CI workflow
make ci

# Run specific jobs
make ci-validate    # Linting and validation only
make ci-build       # Build test only
```

### Skill: Building with Different Godot Versions

The default is Godot 4.6 beta2. To build with a different version:

```bash
# Build with specific version and release type
make build GODOT_VERSION=4.5 GODOT_RELEASE_TYPE=stable

# Build with a release candidate
make build GODOT_VERSION=4.6 GODOT_RELEASE_TYPE=rc1

# Force rebuild without cache
make build-no-cache GODOT_VERSION=4.6 GODOT_RELEASE_TYPE=beta2
```

**Checksum verification is automatic** - the fetch script downloads Godot's official `SHA512-SUMS.txt` and verifies the correct checksum for each architecture.

**Architecture**: The fetch script auto-detects architecture:
- Apple Silicon (M1/M2/M3): Downloads `linux.arm64` binary
- Intel/AMD: Downloads `linux.x86_64` binary

### Skill: Adding a New Allowed Domain

To allow the sandbox to access a new domain:

1. **Add DNS entry** in `configs/coredns/hosts.allowlist`:
   ```
   10.100.1.XX newdomain.com
   ```

2. **Create proxy service** in `compose/compose.base.yml`:
   ```yaml
   proxy_newdomain:
     image: nginx:alpine
     # ... (copy pattern from existing proxies)
   ```

3. **Create nginx config** in `configs/nginx/proxy_newdomain.conf`

4. **Restart services**:
   ```bash
   make restart
   ```

### Skill: Sandboxed Agent Workflows

When Claude runs **inside the sandbox container**, it operates as an autonomous agent with specific workflows for handling tasks. The complete reference is in `image/config/sandbox-context.md`.

#### Three Operating Modes

| Mode | How Work Arrives | Use Case |
|------|------------------|----------|
| **Issue Mode** | Browse open GitHub issues | Standard feature work, bug fixes |
| **Queue Mode** | Read from `/project/.queue` file | Async batch processing |
| **Prompt Mode** | Direct instruction in prompt | Quick fixes, experiments |

#### Standard Issue Mode Workflow

```
1. FIND    → Use list_issues MCP tool to find unclaimed issues
2. CLAIM   → Use create_issue_comment to claim the issue
3. BRANCH  → git checkout -b claude/issue-N-description
4. CODE    → Implement the solution + write tests
5. TEST    → godot --headless -s res://tests/test_runner.gd
6. PUSH    → Use push_files or git push
7. PR      → Use create_pull_request MCP tool
8. WAIT    → Do NOT merge. Human reviews and merges.
```

#### Key Rules for Sandboxed Agents

1. **Use MCP tools for GitHub** - NOT `gh` CLI
2. **Always write tests** - Every change needs tests
3. **Claim before working** - Comment on issue to prevent duplicates
4. **Never merge PRs** - Human reviews and approves
5. **Never push to main** - Always use feature branches

#### Quick Reference for Sandboxed Agents

```bash
# Validate project
godot --headless --validate-project

# Run tests
godot --headless -s res://tests/test_runner.gd

# Create branch
git checkout -b claude/issue-42-feature-name

# Commit
git add -A && git commit -m "feat: description"
```

For the full sandboxed agent context, see `image/config/sandbox-context.md`.

---

## Repository Structure

```text
godot-agent/
├── compose/                 # Docker Compose configurations
│   ├── compose.base.yml     # Infrastructure: DNS filter + proxy services
│   ├── compose.direct.yml   # Agent with direct project mount (one-shot)
│   ├── compose.persistent.yml # Agent that stays running (recommended)
│   ├── compose.queue.yml    # Agent as async queue processor
│   ├── compose.staging.yml  # Agent with staging directory mount
│   └── compose.offline.yml  # Agent with no network access
├── configs/
│   ├── coredns/             # DNS allowlist configuration
│   └── nginx/               # TCP proxy configurations
├── docs/                    # Public documentation (user-facing guides)
│   ├── WORKFLOW_GUIDE.md    # Detailed workflow documentation
│   └── LOGS.md              # Logging guide
├── image/
│   ├── Dockerfile           # Agent container image
│   ├── config/
│   │   └── claude-settings.json  # Claude Code permissions (all granted)
│   ├── install/             # Installation scripts for Godot and Claude Code
│   └── scripts/
│       ├── entrypoint.sh    # Container entrypoint (sets up Claude config)
│       └── queue-watcher.js # Async task queue processor
├── notes/                    # Private notes (prompts, issues, personal notes from Claude)
│   ├── OPEN_ISSUES.md       # Tracked issues and TODOs
│   ├── issue.md              # Current issue being worked on
│   ├── prompt.md             # Prompts for Claude
│   └── *.md                  # Other personal notes
├── scripts/                 # Operational scripts (run from host)
├── tests/                   # Security test suite (pytest)
│   ├── conftest.py          # Docker Compose fixtures
│   ├── test_dns_filtering.py
│   ├── test_network_restrictions.py
│   ├── test_container_hardening.py
│   ├── test_filesystem_restrictions.py
│   └── test_offline_mode.py
├── .github/workflows/       # CI/CD pipelines
├── .githooks/               # Git hooks for secret scanning
└── logs/                    # Session logs (gitignored)
```

### Documentation Organization

**Public Documentation (`docs/`):**
- User-facing guides and documentation
- Examples: `WORKFLOW_GUIDE.md`, `LOGS.md`
- These are intended for users/contributors and should be well-maintained

**Private Notes (`notes/`):**
- Prompts, issues, and personal notes from Claude
- Examples: `OPEN_ISSUES.md`, `issue.md`, `prompt.md`
- These are for internal use and may contain work-in-progress content

## Logging

The sandbox provides comprehensive logging for all operations. See [docs/LOGS.md](docs/LOGS.md) for complete details.

### Quick Reference

**Session Logs (File-based):**
- **Location:** `./logs/` directory in project root
- **One-shot mode** (`make run-direct`, etc.): `logs/claude_<mode>_<timestamp>.log`
- **Persistent mode with prompts** (`make claude P="..."`): `logs/claude_prompt_<timestamp>.log`
- **Persistent mode interactive** (`make claude`): `logs/claude_interactive_<timestamp>.log` (start/end times only)
- **Queue mode**: `<project>/.claude/results/<task-name>.log`

**Docker Container Logs:**
```bash
# View all agent logs
docker logs agent

# Follow in real-time
docker logs -f agent

# Last 100 lines
docker logs --tail 100 agent
```
- Full output for interactive sessions
- All stdout/stderr from the container

**Infrastructure Logs:**
```bash
make logs          # All services
make logs-dns      # DNS filter only
make logs-proxy    # All proxies
make logs-report   # Generate activity report
```

For detailed logging information, see [docs/LOGS.md](docs/LOGS.md).

## Makefile Quick Reference

| Target | Description |
|--------|-------------|
| `make help` | Show all available targets |
| `make doctor` | Check environment health |
| `make auth` | Check authentication status |
| `make build` | Build the agent container image |
| `make up` | Start infrastructure (DNS + proxies) |
| `make down` | Stop all services |
| `make status` | Show service status |
| **Persistent Mode (Recommended)** | |
| `make up-agent PROJECT=...` | Start persistent agent container |
| `make claude` | Interactive Claude session |
| `make claude P="..."` | Single prompt execution |
| `make claude-print P="..."` | Non-interactive batch mode (for scripts/CI) |
| `make agent-status` | Check if agent is running |
| `make claude-shell` | Open bash shell in agent |
| `make down-agent` | Stop persistent agent |
| **Queue Mode (Async)** | |
| `make queue-start PROJECT=...` | Start queue processor daemon |
| `make queue-add TASK="..." NAME=...` | Add task to queue |
| `make queue-status PROJECT=...` | Show queue status |
| `make queue-logs` | Follow queue processor logs |
| `make queue-results PROJECT=...` | Show latest result |
| `make queue-stop` | Stop queue processor |
| **One-shot Mode** | |
| `make run-direct PROJECT=...` | Run Claude in direct mode |
| `make run-staging STAGING=...` | Run Claude in staging mode |
| `make scan PROJECT=...` | Scan for dangerous patterns |
| `make validate` | Validate compose files |
| `make test` | Run all checks |
| `make install-tests` | Install test dependencies |
| `make test-security` | Run security tests |
| `make ci` | Run CI workflow locally |
| `make install-hooks` | Install pre-commit hooks |

### Shortcuts

| Short | Full Target |
|-------|-------------|
| `make d` | `make doctor` |
| `make b` | `make build` |
| `make u` | `make up` |
| `make s` | `make status` |
| `make l` | `make logs` |
| `make c` | `make claude` |
| `make cp` | `make claude-print` |
| `make a` | `make agent-status` |
| `make q` | `make queue-status` |
| `make qs` | `make queue-start` |
| `make qx` | `make queue-stop` |

## Authentication

Two methods are supported (set in `.env` file):

1. **Claude Max OAuth Token** (recommended):
   ```bash
   claude setup-token         # Generate token on host
   # Add to .env: CLAUDE_CODE_OAUTH_TOKEN=sk-ant-...
   ```

2. **API Key** (pay-per-use):
   ```bash
   # Add to .env: ANTHROPIC_API_KEY=sk-ant-...
   ```

## Conventions

### Commit Messages
Use conventional commits:
```text
type(scope): short description

Optional longer explanation.
```
Types: `fix`, `feat`, `docs`, `ci`, `build`, `chore`, `refactor`

### Docker Compose
- Use modern syntax (`deploy.resources.limits.pids` not `pids_limit`)
- Default env vars to empty: `${VAR:-}` to suppress warnings in CI
- Never require `ANTHROPIC_API_KEY` in CI - always default to empty

### Shell Scripts
- Use `set -euo pipefail` at the top
- Use `shellcheck` for linting
- Add `# shellcheck disable=SCXXXX` comments with explanation when needed

### Python
- **Always use `uv` instead of `pip`** for Python package management
- Use `uv pip install` instead of `pip install`
- Use `uv venv` instead of `python -m venv`
- Use `uv run` to run Python scripts with dependencies
- Never use bare `pip` commands

## Files to Never Commit

- `.env` (contains secrets)
- `logs/` directory
- Any API keys or tokens

## Git Hooks

Install pre-commit hooks to automatically scan for secrets and lint shell scripts:
```bash
make install-hooks
```

This configures git to use `.githooks/pre-commit` which:
- Blocks commits containing secrets:
  - Anthropic API keys (`sk-ant-...`)
  - Docker PATs (`dckr_pat_...`)
  - OAuth tokens in code
  - The `.env` file itself
- Runs `shellcheck` on staged shell scripts (`.sh`, `.bash` files)
  - Requires `shellcheck` to be installed: `brew install shellcheck`
  - If not installed, the hook will warn but not block commits

## Common Issues

| Issue | Solution |
|-------|----------|
| DNS not working | `make restart` |
| Permission denied on scripts | `chmod +x scripts/*.sh` |
| Docker not running | Start Docker Desktop first |
| Auth errors | `make auth` to diagnose |
| CI failing locally | `make ci-dry-run` to debug |
| Compose validation errors | `make validate` to see details |
| Proxy containers restarting | Check nginx configs, see Lessons Learned below |
| Agent missing nslookup/curl | Use Node.js for network tests (see Lessons Learned #3) |
| Container exits immediately | Check logs: `docker logs agent`. Usually missing PROJECT or auth |
| "No such file" in container | PROJECT path must be absolute, not relative (`~/` is fine) |

---

## Lessons Learned (For Future Claude Instances)

### Initial Setup Sequence

When initializing this repo from scratch, follow this exact sequence:

1. **Check Docker is running**: `docker ps`
2. **Run environment check**: `make doctor`
3. **Verify authentication**: `make auth` (token should be in `.env`)
4. **Pull pre-built image** (skip building locally):
   ```bash
   docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest
   docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:latest
   docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:4.6
   ```
5. **Start infrastructure**: `./scripts/up.sh`
6. **Verify services**: `make status`

### Critical Issue #1: Nginx Stream Proxy Configuration

**Problem**: Nginx proxy containers crash-loop on startup with error:
```text
nginx: [emerg] "location" directive is not allowed here in /etc/nginx/conf.d/default.conf:8
```

**Root Cause**: The `nginx:1.25-alpine` image includes a default HTTP configuration file at `/etc/nginx/conf.d/default.conf`. Our `nginx.conf` uses a `stream {}` block that includes all `*.conf` files from that directory. Stream context doesn't allow HTTP directives like `location`.

**Solution**: Mount an empty file over the default config for each proxy service:

```yaml
# In compose/compose.base.yml
proxy_github:
  volumes:
    - ../configs/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ../configs/nginx/proxy_github.conf:/etc/nginx/conf.d/stream.conf:ro
    - ../configs/nginx/empty.conf:/etc/nginx/conf.d/default.conf:ro  # ← Add this
```

Create `configs/nginx/empty.conf`:
```bash
echo '# Empty file to prevent default nginx HTTP config' > configs/nginx/empty.conf
```

**Apply to all 5 proxy services**: `proxy_github`, `proxy_raw_githubusercontent`, `proxy_codeload_github`, `proxy_godot_docs`, `proxy_anthropic_api`

### Critical Issue #2: CoreDNS Configuration

**Problem 1**: DNS filter shows as `(unhealthy)` in `docker ps`

**Root Cause**: The CoreDNS image (`coredns/coredns:1.11.1`) is minimal/distroless and lacks common utilities (no wget, curl, ps, etc.).

**Solution**: Disable healthcheck. CoreDNS is simple enough that if the container is running, it's working. Also use `depends_on: condition: service_started` instead of `service_healthy` in compose files.

**Problem 2**: The `hosts` plugin with `fallthrough` didn't work correctly - all domains got NXDOMAIN.

**Root Cause**: When using `fallthrough` with the `template` plugin, the template was catching everything before hosts could match.

**Working Solution**: Use explicit domain zones in Corefile:

```text
# Allowed domains - return proxy IPs
github.com. www.github.com. raw.githubusercontent.com. ... {
    hosts /etc/coredns/hosts.allowlist
}

# Everything else - return NXDOMAIN
. {
    template IN A { rcode NXDOMAIN }
    template IN AAAA { rcode NXDOMAIN }
}
```

**Verification**:
```bash
docker compose -f compose/compose.base.yml logs dnsfilter
# Should show: "CoreDNS-1.11.1" and queries being logged
```

### Critical Issue #3: Agent Container is Minimal

**Problem**: Tests using `nslookup`, `wget`, `curl`, `ping`, or `ip` fail with "command not found"

**Root Cause**: The agent container only has essential tools: bash, git, nodejs, npm, and Godot. No network diagnostic utilities.

**Solution**: Use Node.js for network tests:

```javascript
// DNS lookup
const dns = require('dns');
const r = new dns.Resolver();
r.setServers(['10.100.1.2']);
r.resolve4('github.com', (err, addr) => console.log(err ? 'BLOCKED' : addr));

// HTTP request
const https = require('https');
https.get('https://github.com', (res) => console.log('STATUS:' + res.statusCode));

// TCP connection test
const net = require('net');
const socket = new net.Socket();
socket.connect(80, '8.8.8.8', () => console.log('CONNECTED'));
```

**Also**: Use `docker inspect` instead of `ip addr` for network configuration.

### Critical Issue #4: CI Test Project Permissions

**Problem**: Security tests fail in GitHub Actions with "Permission denied" on /project

**Root Cause**: The test project directory is created by the GitHub runner (root), but the container runs as `claude` (UID 1000).

**Solution**: Set ownership in CI workflow:
```yaml
- name: Create test project directory
  run: |
    mkdir -p tests/.test-project
    sudo chown -R 1000:1000 tests/.test-project
```

### Critical Issue #5: Prefer Pre-built Image Over Local Builds

**Recommendation**: Pull from GHCR instead of building locally

**Why**: Building locally takes time and requires network access. The pre-built image is already tested and available.

**Better Solution**: Pull from GitHub Container Registry instead of building:

```bash
# Do this:
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:latest

# Not this:
make build  # ← Only needed if modifying the Dockerfile
```

The CI/CD pipeline builds multi-arch images (amd64 + arm64) automatically on push to main.

### Critical Issue #6: Claude Configuration Files (MCP vs Settings)

**Problem**: MCP tools not detected, verification script reports "No MCP GitHub server configured"

**Root Cause**: Claude Code uses **two different configuration files** that are commonly confused:

| File | Purpose | Contains |
|------|---------|----------|
| `~/.claude.json` | **MCP server configuration** | `mcpServers` object with server definitions |
| `~/.claude/settings.json` | **Claude Code settings** | Permissions, auto-updater status, preferences |

**Solution**: Always configure MCP servers in `~/.claude.json`, NOT in `~/.claude/settings.json`:

```bash
# ✅ Correct: Check MCP servers in ~/.claude.json
cat ~/.claude.json | jq .mcpServers

# ❌ Wrong: settings.json doesn't have MCP servers
cat ~/.claude/settings.json | jq .mcpServers  # Returns null
```

**About `GITHUB_PERSONAL_ACCESS_TOKEN` in MCP config:**

Despite its name, this is NOT a personal access token. The GitHub MCP server uses this environment variable name, but we populate it with a **GitHub App installation token**:
- Auto-generated on container startup from GitHub App credentials
- Expires after ~1 hour (refreshed on container restart)
- **FOR MCP TOOLS ONLY** - never extract this for `gh` CLI or other uses

```bash
# ❌ NEVER do this - token is for MCP only, not gh CLI
export GH_TOKEN=$(cat ~/.claude.json | jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN')
gh issue list  # Don't hijack the MCP token!

# ✅ Instead, just use MCP tools - they handle auth automatically
# Use list_issues, create_pull_request, etc.
```

**Setup script already handles this**: The `setup-github-app.sh` script correctly writes MCP config to `~/.claude.json` and removes any incorrect MCP config from `settings.json`.

**Verification**: Use `/opt/scripts/verify-mcp.sh` inside the container to confirm MCP is properly configured.

### Critical Issue #7: Godot Download URLs

**Problem**: Godot beta/rc/dev releases return 404 from `github.com/godotengine/godot`

**Root Cause**: Godot uses **two separate GitHub repos** for releases:
- `godotengine/godot` - **stable releases only**
- `godotengine/godot-builds` - **all releases** (stable, beta, rc, dev)

**Correct URLs**:
```bash
# Stable releases (both work):
https://github.com/godotengine/godot/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip
https://github.com/godotengine/godot-builds/releases/download/4.5.1-stable/Godot_v4.5.1-stable_linux.x86_64.zip

# Pre-releases (ONLY godot-builds):
https://github.com/godotengine/godot-builds/releases/download/4.6-beta2/Godot_v4.6-beta2_linux.x86_64.zip
```

**TuxFamily** (`downloads.tuxfamily.org`) is an alternative mirror but often slower/less reliable.

The `fetch_godot.sh` script now auto-detects architecture and tries GitHub first:
- `linux.x86_64` for Intel/AMD
- `linux.arm64` for Apple Silicon (M1/M2/M3)

### Restart Services After Config Changes

After editing any `compose/*.yml` files or `configs/` files:

```bash
# Full path needed if not in repo root
cd /Users/williamdawson/development/godot-agent
./scripts/down.sh
./scripts/up.sh
```

Or from repo root:
```bash
make restart  # Uses scripts/down.sh && scripts/up.sh
```

### Working Directory Matters

Some commands require being in the repository root:
- `make` targets work from anywhere (they use absolute paths)
- Direct script execution needs full path or `cd` first:
  ```bash
  # Either:
  cd /Users/williamdawson/development/godot-agent && ./scripts/up.sh

  # Or:
  /Users/williamdawson/development/godot-agent/scripts/up.sh
  ```

### Verifying Successful Initialization

All these should be true:

```bash
# 1. Image exists locally
docker images | grep claude-godot-agent
# Should show: claude-godot-agent  latest  ...
#              claude-godot-agent  4.6     ...

# 2. All 6 services running
make status
# Should show 6 containers: dnsfilter + 5 proxies, all "Up"

# 3. Proxies are healthy (may take 30s for healthchecks)
make status | grep healthy
# Should show at least proxy_github as healthy

# 4. CoreDNS logs show startup
docker compose -f compose/compose.base.yml logs dnsfilter
# Should show "CoreDNS-1.11.1" without errors
```

### Network Architecture Reminder

```text
┌─────────────────────────────────────────────────────────┐
│  sandbox_net (10.100.1.0/24) - INTERNAL, NO INTERNET    │
│                                                          │
│  ┌──────────────┐                  ┌─────────────────┐  │
│  │  dnsfilter   │◄────DNS─────────│  agent (future) │  │
│  │  10.100.1.2  │                  │  10.100.1.100   │  │
│  └──────────────┘                  └─────────────────┘  │
│         │                                    │           │
│         │ returns proxy IPs                 │           │
│         ▼                                    │           │
│  10.100.1.10  proxy_github        ◄──────────┤           │
│  10.100.1.11  proxy_raw_githubusercontent   │           │
│  10.100.1.12  proxy_codeload_github          │           │
│  10.100.1.13  proxy_godot_docs               │           │
│  10.100.1.14  proxy_anthropic_api            │           │
│         │                                                │
└─────────┼────────────────────────────────────────────────┘
          │ egress_net - HAS INTERNET
          ▼
     INTERNET (github.com, api.anthropic.com, etc.)
```

- Agent can only reach IPs on `sandbox_net`
- DNS filter returns proxy IPs for allowed domains, NXDOMAIN for everything else
- Proxies bridge `sandbox_net` ↔ `egress_net` ↔ Internet
- Agent cannot reach egress_net directly

### Expected Service States

After successful `make up`:

| Service | Status | Notes |
|---------|--------|-------|
| dnsfilter | Up | May show unhealthy (expected, no healthcheck) |
| proxy_github | Up (healthy) | Has healthcheck with nginx -t |
| proxy_raw_githubusercontent | Up | No healthcheck configured |
| proxy_codeload_github | Up | No healthcheck configured |
| proxy_godot_docs | Up | No healthcheck configured |
| proxy_anthropic_api | Up | No healthcheck configured |

Only `proxy_github` has a healthcheck (`nginx -t`). Others are simple enough that if they're running, they work.
