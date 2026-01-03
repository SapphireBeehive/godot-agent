# Logging Guide

This document explains where logs are stored and how to access them.

## Log Locations

### 1. Session Logs (File-based)

**Location:** `./logs/` directory in the project root

**When created:**
- **One-shot mode** (`make run-direct`, `make run-staging`, `make run-offline`):
  - Logs are automatically created: `claude_<mode>_<timestamp>.log`
  - Full session output is captured

- **Persistent mode** (`make claude`):
  - **With prompts** (`make claude P="your prompt"`):
    - Logs created: `claude_prompt_<timestamp>.log`
    - Full prompt and response captured
  - **Interactive sessions** (`make claude`):
    - Logs created: `claude_interactive_<timestamp>.log`
    - Contains session start/end times only
    - Full output available via `docker logs agent` (see below)

- **Queue mode** (`make queue-start`):
  - Logs created in: `<project>/.claude/results/<task-name>.log`
  - Full task execution logs

### 2. Docker Container Logs

**Location:** Docker's internal logging

**Access:**
```bash
# View all agent container logs
docker logs agent

# Follow logs in real-time
docker logs -f agent

# View last 100 lines
docker logs --tail 100 agent

# View logs since specific time
docker logs --since 1h agent
```

**When to use:**
- Interactive Claude sessions (full output)
- Debugging container issues
- Viewing all stdout/stderr from the container

### 3. Infrastructure Service Logs

**Location:** Docker Compose logs

**Access:**
```bash
# All services
make logs

# DNS filter only
make logs-dns

# All proxies
make logs-proxy

# Generate report
make logs-report
```

**What's logged:**
- DNS queries (allowed and blocked)
- Proxy connections
- Network activity

## Quick Reference

| Mode | Log File Location | Full Output? |
|------|------------------|--------------|
| `make run-direct` | `logs/claude_direct_*.log` | ✅ Yes |
| `make run-staging` | `logs/claude_staging_*.log` | ✅ Yes |
| `make run-offline` | `logs/claude_offline_*.log` | ✅ Yes |
| `make claude P="..."` | `logs/claude_prompt_*.log` | ✅ Yes |
| `make claude` (interactive) | `logs/claude_interactive_*.log` | ⚠️ Start/end only |
| `make queue-start` | `<project>/.claude/results/*.log` | ✅ Yes |

## Troubleshooting

### No logs appearing?

1. **Check if logs directory exists:**
   ```bash
   ls -la logs/
   ```

2. **Check if agent container is running:**
   ```bash
   docker ps | grep agent
   ```

3. **For interactive sessions, check Docker logs:**
   ```bash
   docker logs agent
   ```

4. **Verify log file permissions:**
   ```bash
   ls -la logs/
   ```

### Viewing recent logs

```bash
# List all log files
ls -lt logs/

# View most recent log
tail -f logs/$(ls -t logs/ | head -1)

# Search logs for specific content
grep -r "error" logs/
```

## Log File Naming

- Format: `claude_<mode>_<YYYYMMDD_HHMMSS>.log`
- Example: `claude_prompt_20240102_143022.log`
- Sorted by timestamp (newest first)

