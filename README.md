# Claude-Godot Sandbox

[![CI](https://github.com/YOUR_USERNAME/claude-godot-sandbox/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_USERNAME/claude-godot-sandbox/actions/workflows/ci.yml)
[![Build and Push](https://github.com/YOUR_USERNAME/claude-godot-sandbox/actions/workflows/build-and-push.yml/badge.svg)](https://github.com/YOUR_USERNAME/claude-godot-sandbox/actions/workflows/build-and-push.yml)

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
git clone https://github.com/your-org/claude-godot-sandbox.git
cd claude-godot-sandbox

# 2. Create environment file
cp .env.example .env
# Edit .env and add your ANTHROPIC_API_KEY

# 3. Run health check
make doctor

# 4. Build the agent image
make build

# 5. Start infrastructure
make up

# 6. Run Claude with your project
make run-direct PROJECT=/path/to/your/godot/project
```

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
| `make run-direct PROJECT=...` | `./scripts/run-claude.sh direct ...` |
| `make logs` | `docker compose logs -f` |

Run `make help` to see all available targets.

## Running Modes

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
docker pull ghcr.io/YOUR_USERNAME/claude-godot-agent:latest

# Or pull a specific version
docker pull ghcr.io/YOUR_USERNAME/claude-godot-agent:godot-4.3
```

To use the pre-built image instead of building locally, update your `.env`:

```bash
# Use pre-built image from GHCR
AGENT_IMAGE=ghcr.io/YOUR_USERNAME/claude-godot-agent:latest
```

### GitHub Actions Setup

The repository includes two workflows:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PRs, pushes | Validates compose, lints scripts, test builds |
| `build-and-push.yml` | Merge to main | Builds multi-arch image, pushes to GHCR |

#### Required Secrets

Set these in your repository settings (Settings → Secrets → Actions):

| Secret | Required | Description |
|--------|----------|-------------|
| `GITHUB_TOKEN` | Auto | Provided by GitHub, used for GHCR |
| `GODOT_SHA256` | Yes | SHA256 checksum for Godot binary |
| `DOCKERHUB_USERNAME` | Optional | For also pushing to Docker Hub |
| `DOCKERHUB_TOKEN` | Optional | Docker Hub access token |

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
            ghcr.io/YOUR_USERNAME/claude-godot-agent:latest \
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

The GitHub Action builds for both architectures automatically. For manual multi-arch builds:

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

**"GODOT_SHA256 is not set"**
```bash
# Download Godot and get checksum
curl -LO https://downloads.tuxfamily.org/godotengine/4.3/Godot_v4.3-stable_linux.x86_64.zip
sha256sum Godot_v4.3-stable_linux.x86_64.zip
# Add to .env: GODOT_SHA256=<the_checksum>
```

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
claude-godot-sandbox/
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
│   └── install/
│       ├── fetch_godot.sh    # Godot download + verification
│       └── install_claude_code.sh
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
├── logs/                      # Session logs (gitignored)
├── Makefile                  # Convenient make targets
├── .env.example              # Environment template
├── README.md
└── SECURITY.md
```

## License

[Your license here]

## Contributing

[Your contributing guidelines here]
