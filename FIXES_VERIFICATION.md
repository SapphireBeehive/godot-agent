# Verification of Non-Interactive Execution Fixes

**Date**: January 2, 2026
**Commits Reviewed**: 87289d3...1c6fd00 (4 commits)
**Status**: ✅ ALL REPORTED ISSUES HAVE BEEN FIXED

---

## Overview

The godot-agent development team has successfully addressed all four critical issues reported for non-interactive/automation execution. Below is a detailed verification of each fix.

---

## ✅ Problem #1: Claude Code File Write Permissions

### Issue
Claude Code required interactive approval for file writes, blocking automation workflows.

### Fix Implemented
**Commits**: `54e683b`, `1fc0d28`

**Solution**:
1. **Pre-configured permissions file**: `image/config/claude-settings.json`
   ```json
   {
     "permissions": {
       "allow": [
         "Bash(*)", "Read(*)", "Write(*)", "Edit(*)",
         "MultiEdit(*)", "Glob(*)", "Grep(*)", "LS(*)",
         "NotebookRead(*)", "NotebookEdit(*)", "WebFetch(*)",
         "TodoRead(*)", "TodoWrite(*)", "mcp__*"
       ],
       "deny": []
     }
   }
   ```

2. **Container entrypoint**: `image/scripts/entrypoint.sh`
   - Copies settings to `~/.claude/settings.json` on each container start
   - Required because `/home/claude` is a tmpfs mount
   - Auto-accepts terms to prevent interactive prompts

3. **Dockerfile integration**:
   ```dockerfile
   # Install Claude Code settings
   RUN mkdir -p /etc/claude
   COPY config/claude-settings.json /etc/claude/settings.json

   # Install entrypoint script
   COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
   RUN chmod +x /usr/local/bin/entrypoint.sh

   ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
   ```

**Impact**:
- ✅ File writes no longer require approval
- ✅ Fully automated workflows now possible
- ✅ Security maintained via container isolation (not permission prompts)

**Documentation**: Added to `CLAUDE.md` under "Permissions" section

---

## ✅ Problem #2: Environment Variable Propagation

### Issue
Environment variables from `.env` were not passed to agent container because docker-compose was run from `compose/` subdirectory.

### Fix Implemented
**Commit**: `f6cd72c`

**Solution**: Added `--env-file ../.env` flag to all docker-compose commands

**Changes in Makefile**:
```makefile
up-agent: _check-project _check-auth
    @cd $(COMPOSE_DIR) && PROJECT_PATH=$(PROJECT_PATH) \
        docker compose --env-file ../.env \    # ← Added
        -f compose.base.yml -f compose.persistent.yml up -d agent

down-agent:
    @cd $(COMPOSE_DIR) && docker compose --env-file ../.env \  # ← Added
        -f compose.base.yml -f compose.persistent.yml down

queue-start: _check-project _check-auth
    @cd $(COMPOSE_DIR) && PROJECT_PATH=$(PROJECT_PATH) \
        docker compose --env-file ../.env \    # ← Added
        -f compose.base.yml -f compose.queue.yml up -d agent

# ... and queue-stop, queue-logs
```

**Impact**:
- ✅ `CLAUDE_CODE_OAUTH_TOKEN` now properly propagated
- ✅ `ANTHROPIC_API_KEY` now properly propagated
- ✅ No more authentication failures in agent container

---

## ✅ Problem #3: Container Detection and Error Messages

### Issue
Confusing error when one-shot container was running but `make claude` looked for persistent agent named `agent`.

### Fix Implemented
**Commit**: `f6cd72c`

**Solution**: Enhanced `scripts/claude-exec.sh` with intelligent detection and helpful error messages

**Before**:
```bash
if ! docker ps --format '{{.Names}}' | grep -q '^agent$'; then
    log_error "Agent container is not running."
    echo "Start it with: make up-agent PROJECT=/path"
    exit 1
fi
```

**After**:
```bash
if ! docker ps --format '{{.Names}}' | grep -q '^agent$'; then
    # Check if there's a one-shot agent running instead
    if docker ps --format '{{.Names}}' | grep -q 'claude-godot-sandbox-agent-run'; then
        log_error "A one-shot agent container is running..."
        echo ""
        echo "Stop the one-shot container with:"
        echo "  docker stop \$(docker ps -q -f name=claude-godot-sandbox-agent-run)"
        echo ""
        echo "Then start the persistent agent with:"
        echo "  make up-agent PROJECT=/path/to/your/project"
    else
        log_error "Agent container is not running."
        echo "Start it with: make up-agent PROJECT=/path"
    fi
    exit 1
fi
```

**Impact**:
- ✅ Clear guidance when wrong container type is running
- ✅ Specific commands provided for resolution
- ✅ Reduces user confusion and support burden

---

## ✅ Problem #4: TTY Requirements for Non-Interactive Execution

### Issue
`docker exec -it` requires a TTY, which fails in scripts, CI/CD, and automation contexts.

### Fix Implemented
**Commit**: `f6cd72c`

**Solution**: Auto-detect TTY availability and conditionally use `-it` flags

**Implementation in `scripts/claude-exec.sh`**:
```bash
# Detect TTY availability for docker exec flags
if [[ -t 0 ]] && [[ "$PRINT_MODE" != "true" ]]; then
    # TTY available and not in print mode - use interactive mode
    TTY_FLAGS="-it"
else
    # No TTY or print mode - non-interactive mode
    TTY_FLAGS=""
    if [[ -z "$PROMPT" ]] && [[ "$OPEN_SHELL" != "true" ]]; then
        log_warn "No TTY available. Running in non-interactive mode."
    fi
fi

# Later in the script:
exec docker exec $TTY_FLAGS agent claude $CLAUDE_ARGS "$PROMPT"
```

**Additional Feature**: Print mode for batch operations

```bash
# New --print flag added
--print|-p)
    PRINT_MODE=true
    shift
    ;;

# Build Claude CLI arguments
CLAUDE_ARGS=""
if [[ "$PRINT_MODE" == "true" ]]; then
    CLAUDE_ARGS="--print"
fi
```

**New Makefile Target**:
```makefile
claude-print: ## Run Claude in print mode for automation
ifndef P
    @echo "Error: P (prompt) is required for print mode"
    @exit 1
endif
    @./$(SCRIPT_DIR)/claude-exec.sh --print "$(P)"
```

**Impact**:
- ✅ Works in scripts without TTY
- ✅ Works in CI/CD pipelines
- ✅ Dedicated print mode for non-interactive output
- ✅ Automatic TTY detection (no user action needed)

---

## Additional Improvements

### New Documentation
**Commit**: `1c6fd00`

1. **SECURITY.md** - New file documenting security model and critical don'ts
2. **CLAUDE.md** - Added "Non-Interactive / Automation Mode" skill section
3. **README.md** - Updated with automation capabilities

### Documentation Additions in CLAUDE.md

**New Skill Section**:
```markdown
### Skill: Non-Interactive / Automation Mode

For running Claude from scripts, CI/CD pipelines, or other automation contexts:

```bash
# Print mode - outputs result without interactive prompts
make claude-print P="List all .gd files in this project"

# Or use the script directly with --print flag
./scripts/claude-exec.sh --print "Generate a player script"

# TTY auto-detection: the script automatically detects if a TTY is available
docker exec agent claude "prompt"  # Works without -it in scripts
```

**Key features for automation:**
- `--print` flag outputs results without interactive prompts
- TTY auto-detection removes `-it` flags when no terminal is attached
- Claude Code permissions are pre-granted (no approval prompts needed)
- Environment variables from `.env` are properly passed to the container
```

**New Shortcuts**:
- `make cp` → `make claude-print`

---

## Testing Recommendations

To verify the fixes work in your environment:

### Test 1: File Write Permissions
```bash
make up-agent PROJECT=/path/to/project
docker exec agent claude 'Create a test file at /project/test.txt with content "hello"'
# Should complete without permission prompt
```

### Test 2: Environment Variables
```bash
make up-agent PROJECT=/path/to/project
docker exec agent env | grep CLAUDE_CODE_OAUTH_TOKEN
# Should show your token (first 20 chars)
```

### Test 3: Non-Interactive Mode
```bash
# From a script (no TTY)
make claude-print P="List all .gd files" > output.txt
# Should work without "not a TTY" error
```

### Test 4: Container Detection
```bash
# Start one-shot container
docker run --name test-container claude-godot-agent:latest sleep 60 &

# Try to use make claude
make claude
# Should detect wrong container and provide helpful message
```

---

## Commit History

```
1c6fd00 - docs: add non-interactive automation mode documentation
f6cd72c - fix(automation): resolve non-interactive agent execution issues
1fc0d28 - feat(permissions): grant Claude Code all permissions in sandbox
54e683b - feat(image): grant Claude Code all permissions in non-interactive mode
```

---

## Conclusion

All four reported issues have been comprehensively addressed:

1. ✅ **File write permissions** - Pre-granted via settings file
2. ✅ **Environment variables** - Propagated with `--env-file`
3. ✅ **Container detection** - Improved error messages
4. ✅ **TTY requirements** - Auto-detection + print mode

The godot-agent sandbox is now fully suitable for:
- Automated workflows
- CI/CD pipelines
- Batch processing
- Queue-based task processing
- Programmatic orchestration

**Security Note**: Permissions are granted freely because security is enforced at the container level (network isolation, filesystem restrictions, capability dropping), not through Claude's permission system.
