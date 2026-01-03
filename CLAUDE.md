# Claude Code Context for godot-agent

This repository provides a secure, sandboxed Docker environment for running Claude Code with Godot game development projects.

## Project Purpose

The sandbox isolates Claude Code in a container with:
- **Network allowlisting**: Only GitHub, Godot docs, and Anthropic API are accessible
- **Filesystem isolation**: Only the mounted project directory is writable
- **Security hardening**: Read-only rootfs, dropped capabilities, resource limits

This protects against Claude accidentally (or maliciously) accessing sensitive data or making unwanted network connections.

## Pre-built Image

The agent image is automatically built and pushed to GitHub Container Registry:
```
ghcr.io/sapphirebeehive/claude-godot-agent
```

### Available Tags

| Tag | Example | Description |
|-----|---------|-------------|
| `latest` | `:latest` | Most recent build from main branch |
| `godot-X.Y` | `:godot-4.3` | Tagged by Godot version |
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

# 5. Build the agent image
make build

# 6. Start infrastructure services
make up
```

### Skill: Running Claude in the Sandbox

To run Claude Code inside the sandbox with a Godot project:

```bash
# Direct mode - Claude can modify files immediately
make run-direct PROJECT=/path/to/godot/project

# Staging mode - Safer, changes go to staging directory first
make run-staging STAGING=/path/to/staging

# Offline mode - No network access at all
make run-offline PROJECT=/path/to/godot/project
```

### Skill: Daily Workflow

Typical daily operations:

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

Override the default Godot version:

```bash
# Build with Godot 4.4
make build GODOT_VERSION=4.4

# Build with a release candidate
make build GODOT_VERSION=4.4 GODOT_RELEASE_TYPE=rc1

# Force rebuild without cache
make build-no-cache GODOT_VERSION=4.3
```

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

---

## Repository Structure

```
godot-agent/
├── compose/                 # Docker Compose configurations
│   ├── compose.base.yml     # Infrastructure: DNS filter + proxy services
│   ├── compose.direct.yml   # Agent with direct project mount
│   ├── compose.staging.yml  # Agent with staging directory mount
│   └── compose.offline.yml  # Agent with no network access
├── configs/
│   ├── coredns/             # DNS allowlist configuration
│   └── nginx/               # TCP proxy configurations
├── image/
│   ├── Dockerfile           # Agent container image
│   └── install/             # Installation scripts for Godot and Claude Code
├── scripts/                 # Operational scripts (run from host)
├── .github/workflows/       # CI/CD pipelines
├── .githooks/               # Git hooks for secret scanning
└── logs/                    # Session logs (gitignored)
```

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
| `make run-direct PROJECT=...` | Run Claude in direct mode |
| `make run-staging STAGING=...` | Run Claude in staging mode |
| `make scan PROJECT=...` | Scan for dangerous patterns |
| `make validate` | Validate compose files |
| `make test` | Run all checks |
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
```
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

## Files to Never Commit

- `.env` (contains secrets)
- `logs/` directory
- Any API keys or tokens

## Git Hooks

Install pre-commit hooks to automatically scan for secrets:
```bash
make install-hooks
```

This configures git to use `.githooks/pre-commit` which blocks commits containing:
- Anthropic API keys (`sk-ant-...`)
- Docker PATs (`dckr_pat_...`)
- OAuth tokens in code
- The `.env` file itself

## Common Issues

| Issue | Solution |
|-------|----------|
| DNS not working | `make restart` |
| Permission denied on scripts | `chmod +x scripts/*.sh` |
| Docker not running | Start Docker Desktop first |
| Auth errors | `make auth` to diagnose |
| CI failing locally | `make ci-dry-run` to debug |
| Compose validation errors | `make validate` to see details |
