```
  ██████╗  ██████╗ ██████╗  ██████╗ ████████╗     █████╗  ██████╗ ███████╗███╗   ██╗████████╗
 ██╔════╝ ██╔═══██╗██╔══██╗██╔═══██╗╚══██╔══╝    ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝
 ██║  ███╗██║   ██║██║  ██║██║   ██║   ██║       ███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║
 ██║   ██║██║   ██║██║  ██║██║   ██║   ██║       ██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║
 ╚██████╔╝╚██████╔╝██████╔╝╚██████╔╝   ██║       ██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║
  ╚═════╝  ╚═════╝ ╚═════╝  ╚═════╝    ╚═╝       ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝
```

# Claude-Godot Sandbox

[![CI](https://github.com/SapphireBeehiveStudios/godot-agent/actions/workflows/ci.yml/badge.svg)](https://github.com/SapphireBeehiveStudios/godot-agent/actions/workflows/ci.yml)
[![Build and Push](https://github.com/SapphireBeehiveStudios/godot-agent/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/SapphireBeehiveStudios/godot-agent/actions/workflows/build-and-push.yml)

A secure, sandboxed environment for running Claude Code with Godot game development projects on Apple Silicon Macs.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              HOST (Trusted)                                 │
│  ┌──────────────┐  ┌──────────────────────────────────────────────────────┐ │
│  │ Godot Editor │  │              Docker Desktop                          │ │
│  │   (macOS)    │  │  ┌─────────────────────────────────────────────────┐ │ │
│  │              │  │  │              egress_net (Internet)              │ │ │
│  └──────────────┘  │  │    ┌────────────────────────────────────────┐   │ │ │
│         │          │  │    │            PROXY LAYER                 │   │ │ │
│         │          │  │    │  ┌─────────┐ ┌─────────┐ ┌──────────┐  │   │ │ │
│         │          │  │    │  │ proxy_  │ │ proxy_  │ │ proxy_   │  │   │ │ │
│         │          │  │    │  │ github  │ │ godot   │ │anthropic │  │   │ │ │
│         │          │  │    │  │         │ │ _docs   │ │ _api     │  │   │ │ │
│         │          │  │    │  └────┬────┘ └────┬────┘ └────┬─────┘  │   │ │ │
│         │          │  │    └───────┼──────────┼────────────┼────────┘   │ │ │
│         │          │  └────────────┼──────────┼────────────┼────────────┘ │ │
│         │          │  ┌────────────┼──────────┼────────────┼────────────┐ │ │
│         │          │  │  sandbox_net (Internal, No Internet)            │ │ │
│         │          │  │    ┌───────┴──────────┴────────────┴───────┐    │ │ │
│         │          │  │    │             AGENT CONTAINER           │    │ │ │
│         │          │  │    │  ┌──────────────┐  ┌───────────────┐  │    │ │ │
│         │          │  │    │  │ Claude Code  │  │ Godot Headless│  │    │ │ │
│         │          │  │    │  │     CLI      │  │    Runtime    │  │    │ │ │
│  ┌──────┴───────┐  │  │    │  └──────────────┘  └───────────────┘  │    │ │ │
│  │   /project   │◄─┼──┼────┼───────────┐                           │    │ │ │
│  │ (Godot proj) │  │  │    │           │  /project (mount)         │    │ │ │
│  └──────────────┘  │  │    └───────────┴───────────────────────────┘    │ │ │
│                    │  │                        │                        │ │ │
│  Trust Boundary ═══╪══╪══════════════════════════════════════════════════╪ │
│       ▼            │  │    ┌───────────────────┴───────────────────┐    │ │ │
│                    │  │    │              dnsfilter                │    │ │ │
│                    │  │    │              (CoreDNS)                │    │ │ │
│                    │  │    │   Allowlist → proxy IPs               │    │ │ │
│                    │  │    │   Block all → NXDOMAIN                │    │ │ │
│                    │  │    └───────────────────────────────────────┘    │ │ │
│                    │  └─────────────────────────────────────────────────┘ │ │
│                    └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │   INTERNET (Untrusted)│
                          │  - GitHub             │
                          │  - Godot Docs         │
                          │  - Anthropic API      │
                          └───────────────────────┘
```

### Trust Boundaries

| Zone | Trust Level | Access |
|------|-------------|--------|
| Host | Trusted | Full system access, Godot Editor |
| Agent Container | Untrusted | Sandboxed, only /project mount |
| Proxies | Semi-trusted | Bridge between sandbox and internet |
| DNS Filter | Semi-trusted | Controls network access |
| Internet | Untrusted | Allowlisted domains only |

## Prerequisites

### macOS Apple Silicon Setup

1. **Install Docker Desktop**
   ```bash
   # Download from: https://www.docker.com/products/docker-desktop/
   # Or via Homebrew:
   brew install --cask docker
   ```

2. **Enable Enhanced Container Isolation** (Recommended)
   - Open Docker Desktop → Settings → General
   - Enable "Use containerd for pulling and storing images"
   - Under Settings → Resources → Advanced, enable "VirtioFS" for best performance
   - Under Settings → Features in Development, consider enabling "Enhanced Container Isolation" if available (Business/Team plans)

3. **Alternative: Podman**
   ```bash
   brew install podman
   podman machine init --cpus 4 --memory 4096
   podman machine start
   # Note: Compose commands use podman-compose
   ```

### Filesystem Sharing Notes

Docker Desktop on macOS uses VirtioFS or gRPC FUSE for file sharing:
- **VirtioFS** (default): Best performance, recommended
- **gRPC FUSE**: Legacy option, slower but more compatible

If you experience file sync issues, try adding your project directory to Docker Desktop → Settings → Resources → File Sharing.

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/SapphireBeehiveStudios/godot-agent.git
cd godot-agent

# 2. Set up authentication (choose one method)
cp .env.example .env

# Option A: Claude Max subscription (recommended - included with subscription)
claude setup-token
# Then add token to .env: CLAUDE_CODE_OAUTH_TOKEN=sk-ant-...

# Option B: API key (pay-per-use)
# Edit .env and add your ANTHROPIC_API_KEY

# 3. Run health check
make doctor

# 4. Build the agent image
make build

# 5. Start persistent agent (recommended)
make up-agent PROJECT=/path/to/your/godot/project

# 6. Run Claude commands
make claude                        # Interactive session
make claude P="your prompt here"   # Single prompt
make claude-print P="prompt"       # Non-interactive batch mode

# 7. When done
make down-agent
```

### Quick Start (One-shot Mode)

For ephemeral sessions that don't persist:

```bash
make up                                           # Start infrastructure
make run-direct PROJECT=/path/to/your/godot/project  # One-shot session
```

## Authentication

Claude Code supports two authentication methods. Choose the one that works best for you:

### Option 1: Claude Max Subscription (Recommended)

If you have a Claude Max subscription, generate an OAuth token:

```bash
# Generate a long-lived OAuth token (valid for 1 year)
claude setup-token

# Add the token to your .env file
echo 'CLAUDE_CODE_OAUTH_TOKEN=sk-ant-...' >> .env

# Verify it's configured
./scripts/setup-claude-auth.sh status
```

### Option 2: API Key (Pay-per-use)

Get an API key from [Anthropic Console](https://console.anthropic.com/) and add it to your `.env` file:

```bash
echo 'ANTHROPIC_API_KEY=sk-ant-...' >> .env
```

### Checking Authentication Status

```bash
./scripts/setup-claude-auth.sh status
```

This shows which authentication method is configured and ready to use.

**Note**: If both are set, `ANTHROPIC_API_KEY` takes priority over `CLAUDE_CODE_OAUTH_TOKEN`.

### Option 3: GitHub Access (Choose One)

To enable Claude to clone, commit, push, and manage issues/PRs:

#### Option A: GitHub App (Recommended)

GitHub Apps provide **short-lived tokens** (1 hour) with fine-grained permissions. See [docs/GITHUB_APP_SETUP.md](docs/GITHUB_APP_SETUP.md) for full setup instructions.

```bash
# Quick setup (after creating GitHub App - see docs)
echo 'GITHUB_APP_ID=123456' >> .env
echo 'GITHUB_APP_INSTALLATION_ID=12345678' >> .env
echo 'GITHUB_APP_PRIVATE_KEY_PATH=./secrets/github-app-private-key.pem' >> .env

# Test the configuration
make github-app-test
```

**Benefits:**
- ✅ Tokens auto-expire in 1 hour (no cleanup needed)
- ✅ Fine-grained per-repository access
- ✅ Audit logs show "github-app/your-app" (not your username)
- ✅ Higher API rate limits

#### Option B: Personal Access Token (Legacy)

```bash
# Create a PAT with the right permissions for your repo
make github-pat REPO=owner/repo

# Or manually at: https://github.com/settings/tokens
# Then add to .env file
echo 'GITHUB_PAT=github_pat_...' >> .env
```

**Required PAT Permissions:**

| Operation | Classic Token | Fine-grained Token |
|-----------|---------------|-------------------|
| Clone/push private repos | `repo` | Contents: Read/Write |
| Clone/push public repos | `public_repo` | Contents: Read/Write |
| Create/close issues | `repo` | Issues: Read/Write |
| Create/merge PRs | `repo` | Pull requests: Read/Write |
| Create releases | `repo` | Contents: Read/Write |
| View repo metadata | (included) | Metadata: Read (required) |

**Security Notes:**
- Use fine-grained tokens when possible (more granular, can limit to specific repos)
- PAT is stored in `.env` (gitignored, not committed)
- Set token expiration (90 days recommended)

#### Common Features (Both Options)

**Branch Protection (built-in):**
- ⛔ Direct pushes to `main`/`master` branches are **blocked**
- ✅ Repos are cloned to a `claude/work-*` branch automatically
- ✅ Force pushes and remote branch deletions are disabled
- Changes must be merged via pull request (`gh pr create`)

**Usage:**
```bash
# Inside the container, git and gh are automatically configured

# Clone a repository:
/opt/scripts/clone-repo.sh owner/repo

# Or use git directly:
git clone https://github.com/owner/repo.git
git add .
git commit -m "Changes made by Claude"
git push

# GitHub CLI (gh) is also available for repo management:
gh issue list
gh issue create --title "Bug" --body "Description"
gh pr create --title "Fix bug" --body "Description"
gh pr list
gh pr merge 123
```

**MCP Integration (GitHub App only):**

When using GitHub App authentication, Claude Code automatically has access to GitHub MCP tools:
- `get_file_contents` - Read files from repos
- `search_code` - Search across repositories
- `create_issue` / `create_pull_request` - Manage issues and PRs
- `list_commits` - View commit history

### Using Make vs Scripts

The Makefile is for **you (the human)** to run on your Mac — it manages the sandbox from outside. Claude runs inside the container and doesn't use the Makefile.

```
┌─────────────────────────────────────────────────────────┐
│                    YOUR MAC (Host)                      │
│                                                         │
│   You run:  make build                                  │
│             make up                                     │
│             make run-direct PROJECT=~/my-game           │
│                        │                                │
│                        ▼                                │
│            ┌───────────────────────┐                    │
│            │   Makefile targets    │                    │
│            │   (calls scripts)     │                    │
│            └───────────────────────┘                    │
│                        │                                │
│                        ▼                                │
│            ┌───────────────────────┐                    │
│            │    Docker Desktop     │                    │
│            │  ┌─────────────────┐  │                    │
│            │  │ Agent Container │  │ ← Claude runs here │
│            │  │ (Godot + Claude)│  │                    │
│            │  └─────────────────┘  │                    │
│            └───────────────────────┘                    │
└─────────────────────────────────────────────────────────┘
```

You can use either `make` targets or scripts directly:

| Make Command | Script Equivalent |
|--------------|-------------------|
| `make doctor` | `./scripts/doctor.sh` |
| `make build` | `./scripts/build.sh` |
| `make up` | `./scripts/up.sh` |
| `make up-agent PROJECT=...` | Start persistent agent container |
| `make claude` | Interactive Claude session |
| `make claude P="..."` | Single prompt execution |
| `make claude-print P="..."` | Non-interactive batch mode (for scripts/CI) |
| `make down-agent` | Stop persistent agent |
| `make queue-start PROJECT=...` | Start async queue processor |
| `make queue-add TASK="..." NAME=...` | Add task to queue |
| `make queue-status PROJECT=...` | Show queue status |
| `make queue-stop` | Stop queue processor |
| `make run-direct PROJECT=...` | `./scripts/run-claude.sh direct ...` |
| `make logs` | `docker compose logs -f` |
| `make ci` | Run CI workflow locally with `act` |

Run `make help` to see all available targets.

### Testing CI Locally

You can run the GitHub Actions CI workflow locally using [act](https://github.com/nektos/act):

```bash
# Install act
brew install act

# Run the full CI workflow
make ci

# Or run specific jobs
make ci-validate    # Lint and validate
make ci-build       # Build test
make ci-dry-run     # Preview without running
```

## Persistent Mode (Recommended)

Persistent mode keeps the agent container running, allowing you to:
- **Instant Claude access** - No container startup delay
- **Context persistence** - Claude remembers previous interactions within a session
- **Quick prompts** - Run single commands without entering interactive mode

```bash
# Start your work session
make up-agent PROJECT=~/my-godot-game

# Throughout the day, run Claude commands instantly
make claude P="What files are in this project?"
make claude P="Add a jump mechanic to player.gd"
make claude P="Fix the collision detection bug"

# For automation/scripts, use print mode (no interactive prompts)
make claude-print P="List all scene files"

# For longer conversations, use interactive mode
make claude

# Open a shell for manual exploration
make claude-shell

# Check agent status
make agent-status

# End of day - stop the agent
make down-agent
```

**Benefits over one-shot mode:**
- No 3-5 second container startup for each interaction
- Claude maintains conversation context across commands
- Multiple terminal windows can attach to the same session

## Queue Mode (Async Processing)

Queue mode lets you add tasks to a directory and have Claude process them automatically in the background. Perfect for:
- Batch processing multiple tasks overnight
- Queueing work and walking away
- Integrating with scripts and automation

```bash
# Start the queue processor
make queue-start PROJECT=~/my-godot-game

# Add tasks (multiple methods)
make queue-add TASK="Add player movement" NAME=001-movement PROJECT=~/my-godot-game
echo "Fix collision detection" > ~/my-godot-game/.claude/queue/002-collision.md

# Check status
make queue-status PROJECT=~/my-godot-game

# View logs
make queue-logs

# View results
cat ~/my-godot-game/.claude/results/001-movement.log

# Stop when done
make queue-stop
```

### Queue Directory Structure

```
/project/.claude/
├── queue/           # Drop task files here (*.md or *.txt)
├── processing/      # Currently being processed
├── completed/       # Successfully completed tasks
├── failed/          # Failed tasks
└── results/         # Execution logs
```

### Task File Format

Simple text or markdown:

```markdown
# Add Player Movement

Create a player.gd script with:
- WASD movement controls
- Gravity and jumping
- Collision detection

Attach it to the player scene.
```

Tasks are processed in alphabetical order. Use numeric prefixes for ordering:
- `001-setup.md`
- `002-player.md`
- `003-enemies.md`

## Running Modes (One-shot)

The following modes start a new container for each session. Use these when you don't need persistence or want maximum isolation.

### Direct Mode (Fast)

Agent writes directly to your project directory:

```bash
./scripts/run-claude.sh direct /path/to/project
```

**Risks:**
- Agent can delete/overwrite project files immediately
- Agent could plant malicious scripts or assets
- Godot Editor running on host could execute modified game scripts

**Mitigations:**
- Use git to track changes and review diffs
- Run `./scripts/scan-dangerous.sh` to detect suspicious patterns
- Don't run Godot Editor while Claude is modifying files

### Staging Mode (Safer)

Agent writes to a separate staging directory:

```bash
# Create staging directory
mkdir -p ~/godot-staging

# Run Claude in staging mode
./scripts/run-claude.sh staging ~/godot-staging

# Review changes
./scripts/diff-review.sh ~/godot-staging /path/to/live/project

# Promote after review
./scripts/promote.sh ~/godot-staging /path/to/live/project
```

### Offline Mode (Maximum Isolation)

No network access at all:

```bash
./scripts/run-claude.sh offline /path/to/project
```

Use this for:
- Reviewing suspicious code
- Testing without API access
- Maximum security when needed

## Godot Operations

Run Godot headless commands inside the sandbox:

```bash
# Check version
./scripts/run-godot.sh /path/to/project --version

# Run a test script
./scripts/run-godot.sh /path/to/project -s res://tests/run.gd

# Validate project
./scripts/run-godot.sh /path/to/project --validate-project

# Export project
./scripts/run-godot.sh /path/to/project --export-release "Linux" build/game.x86_64
```

## Security Tests

The sandbox includes comprehensive pytest-based security tests that verify all security features are properly enforced.

### Running Tests

```bash
# Install test dependencies (requires uv: brew install uv)
make install-tests

# Run all security tests
make test-security

# Run in parallel (faster)
make test-security-parallel

# Run specific test suites
make test-dns          # DNS filtering
make test-network      # Network isolation
make test-hardening    # Container security
make test-filesystem   # Mount restrictions
make test-offline      # Offline mode
```

### What's Tested

| Test Suite | Verifies |
|------------|----------|
| DNS Filtering | Allowed domains resolve to proxy IPs, blocked domains return NXDOMAIN |
| Network Restrictions | Agent isolated to sandbox_net, cannot reach internet directly |
| Container Hardening | Read-only rootfs, dropped capabilities, non-root user, resource limits |
| Filesystem Restrictions | Only /project mounted, no sensitive host paths exposed |
| Offline Mode | Zero network access with `network_mode: none` |

### Test Structure

```
tests/
├── conftest.py                  # Docker Compose fixtures
├── test_dns_filtering.py        # DNS allowlist/blocklist
├── test_network_restrictions.py # Network isolation
├── test_container_hardening.py  # Security hardening
├── test_filesystem_restrictions.py # Mount verification
└── test_offline_mode.py         # Offline mode
```

Tests run automatically in CI on every push and pull request.

## Observability

### View Logs

```bash
# Live logs from all services
docker compose -f compose/compose.base.yml logs -f

# DNS filter logs only
docker compose -f compose/compose.base.yml logs -f dnsfilter

# Generate summary report
./scripts/logs-report.sh
./scripts/logs-report.sh --since 1h
./scripts/logs-report.sh --output report.txt
```

### What's Logged

| Component | What's Logged |
|-----------|---------------|
| dnsfilter | All DNS queries (allowed + blocked) |
| proxy_* | Connection attempts, bytes transferred, timing |
| agent | Session logs in `./logs/` directory |

## Threat Model

### What This Protects Against

1. **Arbitrary network access**: Agent can only reach allowlisted domains via proxies
2. **Host filesystem access**: Agent can only access `/project` mount
3. **Privilege escalation**: Non-root user, dropped capabilities, no-new-privileges
4. **Persistence**: Read-only rootfs, tmpfs for writable areas
5. **Resource exhaustion**: Memory/CPU limits, PID limits

### Claude Code Permissions

Claude Code has its own permission system that normally requires user approval for file edits, command execution, etc. Since security in this sandbox is enforced by **container isolation** (network allowlisting, filesystem restrictions, dropped capabilities), Claude is pre-configured with all permissions granted.

This is configured in `image/config/claude-settings.json` and applied automatically on container start via the entrypoint script. The granted permissions include:

- **Bash(*)**: Execute any shell command
- **Read(*), Write(*), Edit(*)**: Full file access within `/project`
- **WebFetch(*)**: Network requests (constrained by DNS allowlist)
- **mcp__***: MCP tool integrations

This approach means Claude can work autonomously without permission prompts, while the container sandbox enforces the actual security boundary.

**Note:** In non-interactive mode (scripts, CI/CD, queue processing), Claude Code CLI's Write/Edit tools request permission even with `bypassPermissionsMode: true` configured. Since there's no interactive terminal to grant permission, these tools are effectively unavailable. Claude automatically uses the Bash tool for file operations in these contexts, which works reliably. Impact: Low - all file operations continue to function via Bash commands.

### What This Does NOT Protect Against

1. **Malicious code in project**: If Claude writes malicious GDScript, the Godot Editor on host could execute it
2. **Container/VM escapes**: Theoretical exploits in Docker/containerd
3. **Social engineering**: Claude could try to convince you to bypass protections
4. **Prompt injection**: Malicious content in project files could influence Claude

### How Network Allowlisting Works

```
Agent wants to access "github.com"
    │
    ▼
DNS Query → dnsfilter (CoreDNS)
    │
    ├─ github.com? → Returns 10.100.1.10 (proxy_github IP)
    │
    └─ evil.com? → Returns NXDOMAIN (blocked)
    
Agent connects to 10.100.1.10:443
    │
    ▼
proxy_github receives connection
    │
    ▼
proxy_github forwards to real github.com:443
```

### Mount Strategy

| Path | Direct Mode | Staging Mode | Offline Mode |
|------|-------------|--------------|--------------|
| /project | Host project (RW) | Staging dir (RW) | Host project (RW) |
| Host secrets | NOT mounted | NOT mounted | NOT mounted |
| Docker socket | NOT mounted | NOT mounted | NOT mounted |

## Cloud Transition

### Using Pre-built Images

This repository includes GitHub Actions that automatically build and push images to GitHub Container Registry on merge to main.

```bash
# Pull the latest image (multi-arch: works on both arm64 and amd64)
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest

# Or pull a specific version
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:godot-4.6
```

To use the pre-built image instead of building locally, update your `.env`:

```bash
# Use pre-built image from GHCR
AGENT_IMAGE=ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest
```

### GitHub Actions Setup

The repository includes two workflows:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PRs, pushes | Validates compose, lints scripts, test builds, 95 security tests |
| `build-and-push.yml` | Merge to main | Builds multi-arch image, pushes to GHCR |

#### Required Setup

Set these in your repository settings:

**Secrets** (Settings → Secrets and variables → Actions → Secrets):

| Secret | Required | Description |
|--------|----------|-------------|
| `GITHUB_TOKEN` | Auto | Provided by GitHub, used for GHCR |
| `DOCKERHUB_USERNAME` | Optional | For also pushing to Docker Hub |
| `DOCKERHUB_TOKEN` | Optional | Docker Hub access token |

**Environment** (Settings → Environments):

Create a `production` environment for the build-and-push workflow. Optionally add required reviewers for deployment approval gates.

#### Manual Build Trigger

You can manually trigger a build with custom Godot version:

1. Go to Actions → "Build and Push Docker Image"
2. Click "Run workflow"
3. Enter Godot version (e.g., `4.4`)
4. Run

### Running in CI/CD

Use the pre-built image in your own workflows:

```yaml
# GitHub Actions example
jobs:
  godot-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run Godot validation
        run: |
          docker run --rm \
            -v ${{ github.workspace }}:/project \
            ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest \
            godot --headless --validate-project
```

Or build locally in CI:

```yaml
jobs:
  godot-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build agent
        run: docker build -t claude-godot-agent:latest ./image
      - name: Run Godot validation
        run: |
          docker run --rm \
            -v ${{ github.workspace }}:/project \
            claude-godot-agent:latest \
            godot --headless --validate-project
```

### Multi-Architecture Builds

The GitHub Action builds for both architectures automatically with automatic checksum verification:

```
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Workflow                       │
│                 platforms: linux/amd64,linux/arm64               │
└─────────────────────────────────────────────────────────────────┘
                              │
            ┌─────────────────┴─────────────────┐
            ▼                                   ▼
   ┌─────────────────┐                 ┌─────────────────┐
   │  linux/amd64    │                 │  linux/arm64    │
   │  (x86_64)       │                 │  (Apple Silicon)│
   └────────┬────────┘                 └────────┬────────┘
            │                                   │
            ▼                                   ▼
   ┌─────────────────┐                 ┌─────────────────┐
   │ fetch_godot.sh  │                 │ fetch_godot.sh  │
   │ detects x86_64  │                 │ detects arm64   │
   └────────┬────────┘                 └────────┬────────┘
            │                                   │
            ▼                                   ▼
   ┌─────────────────────────────────────────────────────┐
   │         Downloads SHA512-SUMS.txt (same file)       │
   │  Contains official checksums for ALL architectures  │
   └─────────────────────────────────────────────────────┘
            │                                   │
            ▼                                   ▼
   ┌─────────────────┐                 ┌─────────────────┐
   │ Downloads:      │                 │ Downloads:      │
   │ ...x86_64.zip   │                 │ ...arm64.zip    │
   │ Auto-verifies   │                 │ Auto-verifies   │
   │ with SHA512     │                 │ with SHA512     │
   └─────────────────┘                 └─────────────────┘
```

**How it works:**
1. Docker buildx runs parallel builds for each architecture
2. Each container detects its own architecture via `uname -m`
3. Downloads the correct arch-specific Godot binary
4. Fetches Godot's official `SHA512-SUMS.txt` from the release
5. Automatically extracts and verifies the correct checksum

For manual multi-arch builds:

```bash
# Set up buildx
docker buildx create --name multiarch --use

# Build for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t claude-godot-agent:latest \
  --push \
  ./image
```

### Git-Based Handoff

Recommended workflow for hybrid local/cloud development:

1. Claude modifies files locally
2. Human reviews with `git diff`
3. Human commits approved changes
4. CI/CD runs automated checks
5. Deploy if checks pass

## Troubleshooting

### Common Issues

**"Docker daemon is not running"**
```bash
open -a Docker  # macOS
# Wait for Docker Desktop to start
```

**DNS resolution failing**
```bash
# Check if dnsfilter is healthy
docker compose -f compose/compose.base.yml ps

# Restart services
./scripts/down.sh
./scripts/up.sh
```

**"Permission denied" on scripts**
```bash
chmod +x scripts/*.sh
```

### Performance Issues

1. **Slow file sync**: Enable VirtioFS in Docker Desktop settings
2. **High memory usage**: Adjust `AGENT_MEMORY_LIMIT` in `.env`
3. **Slow Godot**: Native arm64 Godot builds (when available) will be faster than x86_64 emulation

## Development

### Project Structure

```
godot-agent/
├── .github/
│   └── workflows/
│       ├── build-and-push.yml  # Build + push on merge to main
│       └── ci.yml              # Validate + test on PRs
├── compose/
│   ├── compose.base.yml      # Networks + DNS + proxies
│   ├── compose.direct.yml    # Direct mount agent
│   ├── compose.staging.yml   # Staging mount agent
│   └── compose.offline.yml   # Offline mode
├── configs/
│   ├── coredns/
│   │   ├── Corefile          # DNS filtering rules
│   │   └── hosts.allowlist   # Allowed domains → proxy IPs
│   └── nginx/
│       └── proxy_*.conf      # TCP proxy configs
├── image/
│   ├── Dockerfile            # Agent container image
│   ├── config/
│   │   └── claude-settings.json  # Claude Code permissions (all granted)
│   ├── install/
│   │   ├── fetch_godot.sh    # Godot download + verification
│   │   └── install_claude_code.sh
│   └── scripts/
│       ├── entrypoint.sh     # Container entrypoint (sets up Claude config)
│       └── queue-watcher.js  # Async task queue processor
├── scripts/
│   ├── run-claude.sh         # Main entry point
│   ├── run-godot.sh          # Godot headless runner
│   ├── promote.sh            # Staging → live promotion
│   ├── diff-review.sh        # Change report generator
│   ├── scan-dangerous.sh     # Security pattern scanner
│   ├── logs-report.sh        # Log analyzer
│   ├── doctor.sh             # Environment health check
│   ├── up.sh / down.sh       # Service lifecycle
│   └── build.sh              # Image builder
├── tests/                     # Security test suite
│   ├── conftest.py           # Docker Compose fixtures
│   ├── test_dns_filtering.py
│   ├── test_network_restrictions.py
│   ├── test_container_hardening.py
│   ├── test_filesystem_restrictions.py
│   └── test_offline_mode.py
├── logs/                      # Session logs (gitignored)
├── Makefile                  # Convenient make targets
├── .env.example              # Environment template
├── .cursorrules              # AI assistant conventions
├── README.md
├── CICD_SETUP.md             # Step-by-step CI/CD setup guide
└── SECURITY.md
```

## Documentation

- **[Workflow Guide](docs/WORKFLOW_GUIDE.md)** - Detailed guide for Persistent and Queue modes
- **[GitHub App Setup](docs/GITHUB_APP_SETUP.md)** - Configure GitHub App for secure repo access
- **[GitHub App MCP Integration](docs/GITHUB_APP_MCP_INTEGRATION.md)** - Technical implementation details
- **[Logging Guide](docs/LOGS.md)** - Where logs are stored and how to access them
- **[CLAUDE.md](CLAUDE.md)** - Context file for Claude instances
- **[SECURITY.md](SECURITY.md)** - Threat model and security considerations
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Contribution guidelines

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
