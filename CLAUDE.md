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

### Skill: Running Security Tests

The sandbox includes comprehensive security tests to verify network restrictions, container hardening, and filesystem isolation:

```bash
# Install test dependencies (requires uv)
uv pip install -r tests/requirements.txt

# Run all security tests
make test-security

# Run tests in parallel (faster)
make test-security-parallel

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
| Proxy containers restarting | Check nginx configs, see Lessons Learned below |

---

## Lessons Learned (For Future Claude Instances)

### Initial Setup Sequence

When initializing this repo from scratch, follow this exact sequence:

1. **Check Docker is running**: `docker ps`
2. **Run environment check**: `make doctor`
3. **Verify authentication**: `make auth` (token should be in `.env`)
4. **Pull pre-built image** (skip building locally):
   ```bash
   docker pull ghcr.io/sapphirebeehive/claude-godot-agent:latest
   docker tag ghcr.io/sapphirebeehive/claude-godot-agent:latest claude-godot-agent:latest
   docker tag ghcr.io/sapphirebeehive/claude-godot-agent:latest claude-godot-agent:4.6
   ```
5. **Start infrastructure**: `./scripts/up.sh`
6. **Verify services**: `make status`

### Critical Issue #1: Nginx Stream Proxy Configuration

**Problem**: Nginx proxy containers crash-loop on startup with error:
```
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

### Critical Issue #2: CoreDNS Healthcheck Failures

**Problem**: DNS filter shows as `(unhealthy)` in `docker ps`

**Root Cause**: The CoreDNS image (`coredns/coredns:1.11.1`) is minimal/distroless and lacks common utilities:
- No `wget` (original healthcheck tried to use this)
- No `curl`
- No `ps`
- No `ls`
- Not even basic shell utilities

**Attempted Solutions That Failed**:
1. ✗ `wget -q -O - http://localhost:8080/health` - wget not found
2. ✗ `/dev/tcp/localhost/8080` - requires bash, not available in sh
3. ✗ `ps aux | grep coredns` - ps not found

**Working Solution**: Disable healthcheck entirely

The CoreDNS image is so minimal that healthchecks are impractical. CoreDNS is simple enough that if the container is running, it's working:

```yaml
# In compose/compose.base.yml
dnsfilter:
  # ... other config ...
  # Note: CoreDNS image is minimal (distroless), healthcheck disabled
```

**Verification**: Check logs show CoreDNS started:
```bash
docker compose -f compose/compose.base.yml logs dnsfilter
# Should show: "CoreDNS-1.11.1" and "linux/arm64, go1.20.7"
```

### Critical Issue #3: Prefer Pre-built Image Over Local Builds

**Recommendation**: Pull from GHCR instead of building locally

**Why**: Building locally takes time and requires network access. The pre-built image is already tested and available.

**Better Solution**: Pull from GitHub Container Registry instead of building:

```bash
# Do this:
docker pull ghcr.io/sapphirebeehive/claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehive/claude-godot-agent:latest claude-godot-agent:latest

# Not this:
make build  # ← Only needed if modifying the Dockerfile
```

The CI/CD pipeline builds multi-arch images (amd64 + arm64) automatically on push to main.

### Critical Issue #4: Godot Download URLs

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
#              claude-godot-agent  4.3     ...

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

```
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
