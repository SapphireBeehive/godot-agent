# ATTN: Sandboxed Agent Context

> **Audience**: Claude instances working ON the godot-agent repository (maintaining the sandbox infrastructure), NOT agents running inside the sandbox.

---

## What This Repository Is

`godot-agent` is **sandbox infrastructure** for running Claude Code safely with Godot projects. It provides:

- Docker container with Godot headless + Claude Code CLI
- Network allowlisting via DNS filter + proxies
- Filesystem isolation (only `/project` mount is writable)
- Security hardening (read-only rootfs, dropped capabilities, resource limits)

**This repo does NOT contain game code.** It contains the tooling that lets Claude safely work on game code.

---

## The Two CLAUDEs

There are two distinct Claude contexts:

| File | Audience | Location |
|------|----------|----------|
| `CLAUDE.md` | You (working on godot-agent infra) | This repo root |
| `CLAUDE.agent.md` | Sandboxed Claude (working on games) | Mounted into container as `/project/CLAUDE.md` |

**Do not confuse these.**

- `CLAUDE.md` = How to maintain the sandbox
- `CLAUDE.agent.md` = Instructions for the agent inside the sandbox

---

## Primary Use Case

The sandbox runs Claude to develop the **boids project**:

```
Host:      /Users/work/workspace/github.com/johnrdd/godot/boids
Container: /project (mounted from host)
```

When updating `CLAUDE.agent.md`, you're writing instructions that the sandboxed Claude will read when working on the boids mecha combat game.

---

## Critical Files (Do Not Break)

| File | Impact if Broken |
|------|------------------|
| `compose/compose.base.yml` | All infrastructure fails to start |
| `configs/coredns/Corefile` | DNS filtering breaks |
| `configs/coredns/hosts.allowlist` | Network allowlist breaks |
| `image/Dockerfile` | Container won't build |
| `scripts/up.sh`, `scripts/down.sh` | Can't start/stop services |

**Always run `make validate` before committing changes to compose files.**

---

## Testing Changes

```bash
# Validate compose files parse correctly
make validate

# Lint shell scripts
make lint-scripts

# Full test suite
make test

# Actually start services and verify
make up
make status
make down
```

**Never commit without running `make validate` at minimum.**

---

## Network Architecture

```
sandbox_net (internal, no internet)
├── dnsfilter (10.100.1.2) - CoreDNS, returns proxy IPs or NXDOMAIN
├── proxy_github (10.100.1.10) - Bridges to github.com
├── proxy_godot_docs (10.100.1.13) - Bridges to docs.godotengine.org
├── proxy_anthropic_api (10.100.1.14) - Bridges to api.anthropic.com
└── agent (10.100.1.100) - Claude + Godot, only sees sandbox_net

egress_net (has internet)
└── proxy_* containers bridge sandbox_net ↔ egress_net ↔ internet
```

**The agent container CANNOT reach the internet directly.** It must go through proxies.

---

## Adding a New Allowed Domain

1. **Add DNS entry** in `configs/coredns/hosts.allowlist`:
   ```
   10.100.1.XX newdomain.com
   ```

2. **Create proxy service** in `compose/compose.base.yml` (copy existing pattern)

3. **Create nginx config** in `configs/nginx/proxy_newdomain.conf`

4. **Add empty.conf mount** to prevent nginx default config conflict

5. **Test**:
   ```bash
   make down && make up
   make status
   # Verify new proxy is running
   ```

---

## Updating CLAUDE.agent.md

When you update the sandboxed agent's instructions:

1. **Consider what the sandboxed Claude needs to know**:
   - Project structure and conventions
   - Workflow phases (design → plan → prompt → implement)
   - API gotchas and lessons learned
   - Constraints (network, filesystem)

2. **Keep it actionable** - The sandboxed agent should be able to follow instructions without ambiguity

3. **Add lessons learned** - When you discover something (API quirk, shader gotcha), add it to the Lessons Learned section

4. **Test the mount** - The file gets mounted at `/project/CLAUDE.md` in the container

---

## Common Maintenance Tasks

### Updating Godot Version

```bash
# Build with new version
make build GODOT_VERSION=4.4 GODOT_RELEASE_TYPE=stable

# Or for pre-releases
make build GODOT_VERSION=4.6 GODOT_RELEASE_TYPE=rc1
```

### Updating Claude Code

The container installs Claude Code via npm. To update:

1. Modify `image/install/install_claude_code.sh` if needed
2. Rebuild: `make build-no-cache`

### Debugging DNS Issues

```bash
# Check DNS filter logs
make logs-dns

# Test resolution from inside a container
docker run --rm --network godot-agent_sandbox_net busybox nslookup github.com 10.100.1.2
```

### Debugging Proxy Issues

```bash
# Check proxy logs
make logs-proxy

# Test connectivity through proxy
docker run --rm --network godot-agent_sandbox_net \
  --dns 10.100.1.2 \
  curlimages/curl curl -v https://github.com
```

---

## Relationship to Boids Project

```
godot-agent/                    ← You are here (infrastructure)
├── CLAUDE.md                   ← Instructions for YOU
├── CLAUDE.agent.md             ← Instructions for sandboxed Claude
└── ...

boids/                          ← Game project (separate repo)
├── CLAUDE.md                   ← Copy of CLAUDE.agent.md (mounted)
├── scripts/
├── scenes/
├── prompts/                    ← Task prompts for sandboxed Claude
├── design/                     ← Design docs sandboxed Claude reads
└── workflow/
    └── sandbox.md              ← References this godot-agent repo
```

**The sandboxed Claude sees `/project` which is the boids directory mounted in.**

---

## Security Mindset

When modifying this repo, always ask:

1. **Does this change expand what the agent can access?** (filesystem, network, capabilities)
2. **Could this be exploited by a malicious prompt?**
3. **Is there a way to do this with less privilege?**

The goal is **minimum viable access** for the sandboxed Claude to be productive.

---

## Quick Reference

| Task | Command |
|------|---------|
| Check everything works | `make doctor` |
| Validate compose files | `make validate` |
| Start infrastructure | `make up` |
| Stop infrastructure | `make down` |
| View all logs | `make logs` |
| Run Claude with boids | `make run-direct PROJECT=/path/to/boids` |
| Rebuild container | `make build` |
| Run CI locally | `make ci` |
