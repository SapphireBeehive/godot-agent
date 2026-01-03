# Security Guide

This document describes the security model, configuration requirements, and best practices for the Claude-Godot Sandbox.

## Security Model Overview

The sandbox follows a defense-in-depth approach:

1. **Container Isolation**: Agent runs in a hardened container
2. **Network Allowlisting**: Only specific domains are accessible
3. **Filesystem Restrictions**: Limited to project directory
4. **Capability Dropping**: Minimal Linux capabilities
5. **Resource Limits**: Prevent DoS attacks

## Critical Don'ts ⛔

### NEVER mount these directories:

```yaml
# DANGEROUS - Exposes all your files
volumes:
  - $HOME:/home  # ❌ NEVER

# DANGEROUS - Exposes SSH keys and credentials  
volumes:
  - ~/.ssh:/root/.ssh  # ❌ NEVER
  - ~/.aws:/root/.aws  # ❌ NEVER
  - ~/.config:/root/.config  # ❌ NEVER

# DANGEROUS - Container escape vector
volumes:
  - /var/run/docker.sock:/var/run/docker.sock  # ❌ NEVER
```

### NEVER run with these flags:

```yaml
# DANGEROUS - Full host access
privileged: true  # ❌ NEVER

# DANGEROUS - All capabilities
cap_add:
  - ALL  # ❌ NEVER

# DANGEROUS - Root access
user: root  # ❌ NEVER

# DANGEROUS - Host networking
network_mode: host  # ❌ NEVER
```

### NEVER add broad network allowlists:

```
# DANGEROUS - In hosts.allowlist
*  # ❌ NEVER - allows all domains
*.com  # ❌ NEVER - too broad
*.amazonaws.com  # ❌ NEVER - includes S3, secrets
```

## Authentication Security

The sandbox supports two authentication methods. Choose the one appropriate for your use case.

### Claude Max OAuth Token (Recommended)

Using a Claude Max OAuth token is recommended because:
- Usage included with subscription (no surprise charges)
- Token is long-lived (1 year) but can be revoked
- Passed as environment variable (not stored in container)

**Setup**:
```bash
claude setup-token
# Add the token to .env: CLAUDE_CODE_OAUTH_TOKEN=sk-ant-...
```

**If your OAuth token is compromised**:
1. Generate a new token with `claude setup-token`
2. Update your `.env` file with the new token
3. The old token should be automatically invalidated

### API Key Authentication

If using an API key (pay-per-use):

**If Your Anthropic API Key is Exposed**:

1. **Immediately revoke the key**:
   - Go to https://console.anthropic.com/
   - Navigate to API Keys
   - Delete the compromised key
   - Generate a new key

2. **Review API usage**:
   - Check for unauthorized API calls
   - Review billing for unexpected charges

3. **Update your environment**:
   ```bash
   # Remove old .env
   rm .env
   
   # Create new one with new key
   cp .env.example .env
   # Edit with new ANTHROPIC_API_KEY
   ```

4. **Rotate any related credentials**:
   - If the key was committed to git, consider other secrets in that repo compromised
   - Rotate any tokens/passwords that might have been in the same files

### Best Practices

1. **Prefer Claude Max** over API keys when possible
2. **Use `.env` files** (gitignored) for API keys
3. **Never commit secrets** to version control
4. **Set up spending limits** in Anthropic console if using API keys
5. **Monitor usage** for anomalies
6. **Run `./scripts/setup-claude-auth.sh status`** to verify your configuration

## Reviewing Suspicious Code

### Dangerous Pattern Scan

Run the automated scanner:

```bash
./scripts/scan-dangerous.sh /path/to/project
```

### Manual Review Patterns

Look for these high-risk patterns in GDScript:

```gdscript
# Code Execution
OS.execute(...)           # Can run arbitrary commands
OS.create_process(...)    # Spawns external processes
Expression.execute(...)   # Dynamic code execution

# File System Access
FileAccess.open("/etc/passwd", ...)  # Reading system files
DirAccess.remove_absolute(...)        # Deleting files

# Network Operations
HTTPRequest.request(...)              # Arbitrary HTTP calls
TCPServer.listen(...)                 # Opening ports
```

### Grep Commands for Manual Review

```bash
# Find all OS.execute calls
grep -rn "OS\.execute" --include="*.gd" /path/to/project

# Find file access outside project
grep -rn 'FileAccess\.open.*"/' --include="*.gd" /path/to/project

# Find network code
grep -rn "HTTPRequest\|TCPServer\|UDPServer" --include="*.gd" /path/to/project

# Find dynamic code loading
grep -rn "load\|preload.*\.gd" --include="*.gd" /path/to/project
```

### Before Running Godot Editor

1. **Stop Claude session** first
2. **Review git diff** of all changes
3. **Run the security scan**
4. **Don't run unknown scripts** without review

## Container Hardening Details

### Applied Security Measures

```yaml
# From compose files
security_opt:
  - no-new-privileges:true  # Prevents privilege escalation

cap_drop:
  - ALL  # Remove all capabilities

read_only: true  # Immutable root filesystem

tmpfs:
  - /tmp:size=100M  # Limited writable space

pids_limit: 256  # Prevent fork bombs

deploy:
  resources:
    limits:
      memory: 2G  # Prevent memory exhaustion
      cpus: "2.0"  # Limit CPU usage
```

### User Isolation

```dockerfile
# Agent runs as non-root user 'claude' (uid 1000)
USER claude
```

This means:
- No access to privileged operations
- Cannot modify system files
- Cannot bind to ports < 1024

## Network Security

### DNS Filtering

The CoreDNS filter:
- **Allows**: Specific domains (GitHub, Godot docs, Anthropic API)
- **Blocks**: Everything else (returns NXDOMAIN)
- **Logs**: All queries (for audit)

### Proxy Architecture

```
Agent → Can only reach → sandbox_net (internal)
                              ↓
                         Proxy containers
                              ↓
                        egress_net (internet)
                              ↓
                    Specific upstream hosts only
```

### Adding New Allowed Domains

If you need to allow additional domains:

1. **Evaluate the risk**: Does this domain need to be accessible?
2. **Edit** `configs/coredns/hosts.allowlist`:
   ```
   10.100.1.XX newdomain.com
   ```
3. **Create a new proxy** in `compose/compose.base.yml`
4. **Create nginx config** in `configs/nginx/proxy_newdomain.conf`
5. **Restart services**:
   ```bash
   ./scripts/down.sh && ./scripts/up.sh
   ```

## Failure Modes and Mitigations

### Misconfiguration Risks

| Risk | Impact | Prevention |
|------|--------|------------|
| Mounting $HOME | Full secrets exposure | Never modify volume mounts without review |
| Privileged mode | Container escape | Never add privileged: true |
| Docker socket mount | Full host control | Socket is not mounted by design |
| Broad DNS allowlist | Unrestricted network | Only add specific domains |

### Container/VM Escape

**Risk**: Theoretical exploits in containerd, runc, or hypervisor

**Mitigations**:
- Keep Docker Desktop updated
- Use "Enhanced Container Isolation" if available
- Monitor Docker security advisories
- Consider running in a dedicated VM for high-risk operations

### Prompt Injection

**Risk**: Malicious content in project files could influence Claude's behavior

**Mitigations**:
- Review unfamiliar files before adding to project
- Be skeptical of Claude suggestions that disable security measures
- Don't run `--privileged` even if Claude suggests it

### Social Engineering

**Risk**: Claude might suggest bypassing security measures

**Examples of suspicious suggestions**:
- "Let me access the Docker socket to help with containers"
- "Mount your home directory so I can find configuration files"
- "Run this with sudo to fix permissions"

**Response**:
- Refuse requests to weaken security configuration
- Review the security rationale in this document
- Ask "why is this necessary?" and verify independently

## Incident Response

### If You Suspect Compromise

1. **Stop all containers immediately**:
   ```bash
   ./scripts/down.sh
   docker stop $(docker ps -q)
   ```

2. **Disconnect from network** if actively under attack

3. **Preserve evidence**:
   ```bash
   docker logs dnsfilter > dns_logs.txt
   docker logs proxy_github > proxy_logs.txt
   ./scripts/logs-report.sh --output incident_report.txt
   ```

4. **Review file changes**:
   ```bash
   cd /path/to/project
   git status
   git diff
   ```

5. **Check for persistence**:
   - Review any new files in project
   - Check for modified scripts
   - Look for suspicious cron jobs or startup items

6. **Rotate credentials**:
   - API keys
   - Any secrets that might have been accessible

7. **Report** to appropriate parties if real compromise occurred

## Security Checklist

Before each Claude session:

- [ ] `.env` file is not committed to git
- [ ] Only necessary project directory is mounted
- [ ] Docker Desktop is up to date
- [ ] Previous session logs reviewed if suspicious activity
- [ ] Git repository is clean (to track changes)

After each Claude session:

- [ ] Review `git diff` for all changes
- [ ] Run `./scripts/scan-dangerous.sh`
- [ ] Check DNS logs for blocked requests
- [ ] Consider: "Would I write this code myself?"

## Contact

For security issues with this sandbox, contact: [your security contact]

For Anthropic/Claude security issues: security@anthropic.com

