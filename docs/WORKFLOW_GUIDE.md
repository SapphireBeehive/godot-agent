# Claude-Godot Workflow Guide

A comprehensive guide to using Claude Code with Godot projects in the secure sandbox.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Persistent Mode](#persistent-mode-interactive-development)
- [Queue Mode](#queue-mode-async-processing)
- [Choosing a Workflow](#choosing-a-workflow)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

The godot-agent provides two workflows for interacting with Claude:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                                                                         │
│   PERSISTENT MODE                      QUEUE MODE                       │
│   ───────────────                      ──────────                       │
│                                                                         │
│   ┌─────────┐                          ┌─────────┐                      │
│   │   You   │◄────────────────────────►│   You   │                      │
│   └────┬────┘  Interactive chat        └────┬────┘                      │
│        │                                    │                           │
│        │ make claude                        │ Drop files in queue/      │
│        │ make claude P="..."                │                           │
│        ▼                                    ▼                           │
│   ┌─────────┐                          ┌─────────┐                      │
│   │ Claude  │                          │ Claude  │ (daemon)             │
│   │(running)│                          │(watches)│                      │
│   └────┬────┘                          └────┬────┘                      │
│        │                                    │                           │
│        │ Immediate changes                  │ Processes async           │
│        ▼                                    ▼                           │
│   ┌─────────┐                          ┌─────────┐                      │
│   │ Project │                          │ Project │ + Results in         │
│   │  Files  │                          │  Files  │   .claude/results/   │
│   └─────────┘                          └─────────┘                      │
│                                                                         │
│   Best for:                            Best for:                        │
│   • Active development                 • Batch processing               │
│   • Conversations                      • Overnight tasks                │
│   • Quick questions                    • Automation/scripts             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

Before using either workflow, ensure you have:

### 1. Docker Running

```bash
# Verify Docker is running
docker ps
```

### 2. Authentication Configured

```bash
# Check auth status
make auth

# If not configured, add to .env:
# Option A: Claude Max subscription (recommended)
echo 'CLAUDE_CODE_OAUTH_TOKEN=your-token-here' >> .env

# Option B: API key (pay-per-use)
echo 'ANTHROPIC_API_KEY=your-key-here' >> .env
```

### 3. Agent Image Built

```bash
# Build the agent image
make build

# Or pull pre-built image
docker pull ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest
docker tag ghcr.io/sapphirebeehivestudios/claude-godot-agent:latest claude-godot-agent:latest
```

### 4. Environment Check

```bash
# Run the doctor to verify everything
make doctor
```

### Note: Claude Permissions

Claude Code runs with **all permissions pre-granted** inside the sandbox. This means:
- No permission prompts for file edits, command execution, etc.
- Claude can work autonomously on tasks
- Security is enforced by the container sandbox (network allowlist, filesystem restrictions, dropped capabilities), not by Claude's internal permission system

This is configured in `image/config/claude-settings.json` and applied automatically on container start.

---

## Persistent Mode (Interactive Development)

Persistent mode keeps Claude running in a container, allowing instant access for interactive work.

### Starting a Session

```bash
# Start the persistent agent with your project
make up-agent PROJECT=/path/to/your/godot/project

# Example:
make up-agent PROJECT=~/Games/my-platformer
```

This:
1. Starts infrastructure (DNS filter + network proxies)
2. Starts the agent container (stays running)
3. Mounts your project at `/project` inside the container

### Running Claude Commands

#### Interactive Session

```bash
# Start an interactive Claude session (REPL-style)
make claude
```

This opens a conversation where you can chat back and forth:

```
You: What files are in this project?
Claude: I can see the following structure...

You: Add a player controller script
Claude: I'll create scripts/player_controller.gd...

You: exit
```

#### Single Prompts

```bash
# Run a single prompt and return
make claude P="List all GDScript files in this project"

# Complex prompts with quotes
make claude P="Create a player.gd script with WASD movement, jumping with Space, and gravity"

# Multi-line prompts (use shell quoting)
make claude P="Refactor the enemy.gd script to:
1. Use a state machine
2. Add patrol behavior
3. Add chase behavior when player is near"
```

#### Non-Interactive / Automation Mode

For running from scripts, CI/CD, or other automation contexts:

```bash
# Print mode - outputs result without interactive prompts
make claude-print P="Generate a list of all scene files"

# Or use the script directly
./scripts/claude-exec.sh --print "Your prompt here"
```

**TTY Auto-Detection**: The script automatically detects whether a terminal is attached and adjusts behavior:
- With TTY: Uses `-it` flags for interactive mode
- Without TTY: Runs non-interactively (safe for scripts and CI)

**Note on Non-Interactive Mode:** In non-interactive contexts (scripts, CI/CD), Claude Code CLI's Write/Edit tools request permission even with `bypassPermissionsMode: true` configured. Since there's no terminal to grant permission, these tools are effectively unavailable. Claude automatically uses the Bash tool for file operations in these cases, which works reliably. Impact: Low - file creation and modification still work correctly via Bash commands.

### Checking Status

```bash
# Check if agent is running
make agent-status

# Or use the shortcut
make a
```

### Opening a Shell

For manual exploration or debugging:

```bash
# Open bash shell in the container
make claude-shell

# Inside the container:
ls -la
godot --version
cat scripts/player.gd
```

### Stopping the Agent

```bash
# Stop the agent container
make down-agent
```

### Complete Example Session

```bash
# Morning: Start your session
make up-agent PROJECT=~/Games/my-platformer

# Work throughout the day
make claude P="What's the current project structure?"
make claude P="Add a main menu scene with Start and Quit buttons"
make claude P="Create a game manager singleton"

# Longer conversation for complex feature
make claude
> Let's implement a save/load system
> ...back and forth conversation...
> exit

# Check something in the container
make claude-shell
$ cat scripts/game_manager.gd
$ exit

# End of day
make down-agent
```

---

## Queue Mode (Async Processing)

Queue mode runs Claude as a background daemon that processes task files automatically.

### Starting the Queue Processor

```bash
# Start the queue processor
make queue-start PROJECT=/path/to/your/godot/project

# Example:
make queue-start PROJECT=~/Games/my-platformer
```

This:
1. Creates queue directories in your project (`.claude/queue/`, etc.)
2. Starts the queue watcher daemon
3. Begins monitoring for task files

### Adding Tasks

#### Using make queue-add

```bash
# Add a task with a name
make queue-add TASK="Add player movement" NAME=001-movement PROJECT=~/Games/my-platformer

# Add another task
make queue-add TASK="Add enemy AI with patrol and chase" NAME=002-enemies PROJECT=~/Games/my-platformer
```

#### Dropping Files Directly

Create `.md` or `.txt` files in the queue directory:

```bash
# Simple one-liner
echo "Add a health bar UI" > ~/Games/my-platformer/.claude/queue/003-health.md

# More detailed task file
cat > ~/Games/my-platformer/.claude/queue/004-inventory.md << 'EOF'
# Implement Inventory System

## Requirements
- Create an Inventory class that can hold items
- Each item has: name, icon, stack_size, description
- UI panel that shows inventory grid (4x4)
- Drag and drop support

## Files to create
- scripts/inventory/inventory.gd
- scripts/inventory/item.gd
- scenes/ui/inventory_panel.tscn

## Notes
- Use a Resource for item definitions
- Inventory should be a singleton for global access
EOF
```

### Task File Naming

Tasks are processed in **alphabetical order**. Use numeric prefixes to control order:

```
.claude/queue/
├── 001-setup-project.md      # Processed first
├── 002-add-player.md         # Processed second
├── 003-add-enemies.md        # Processed third
└── 010-polish-effects.md     # Processed later
```

### Monitoring Progress

#### Check Queue Status

```bash
make queue-status PROJECT=~/Games/my-platformer
```

Output:
```
╔══════════════════════════════════════════════════════════════════════╗
║                         Queue Status                                 ║
╚══════════════════════════════════════════════════════════════════════╝

📬 Pending tasks:
   - 003-health.md
   - 004-inventory.md

⚙️  Processing:
   - 002-enemies.md

✅ Completed (last 5):
   - 001-movement.md

❌ Failed:
   (none)

🟢 Queue processor: RUNNING
```

#### Watch Logs in Real-Time

```bash
make queue-logs
```

This streams the queue processor output so you can watch Claude work.

#### View Results

```bash
# Show the latest result
make queue-results PROJECT=~/Games/my-platformer

# View a specific result
cat ~/Games/my-platformer/.claude/results/001-movement.log
```

### Queue Directory Structure

After running, your project will have:

```
your-project/
├── .claude/
│   ├── queue/           # Drop new tasks here
│   │   └── 005-next-task.md
│   ├── processing/      # Currently being worked on
│   │   └── 004-inventory.md
│   ├── completed/       # Successfully finished
│   │   ├── 001-movement.md
│   │   ├── 002-enemies.md
│   │   └── 003-health.md
│   ├── failed/          # Tasks that errored
│   │   └── (hopefully empty)
│   └── results/         # Execution logs
│       ├── 001-movement.log
│       ├── 002-enemies.log
│       └── 003-health.log
├── scripts/
├── scenes/
└── project.godot
```

### Stopping the Queue

```bash
make queue-stop
```

### Complete Example: Overnight Batch Processing

```bash
# Evening: Set up batch processing
make queue-start PROJECT=~/Games/my-platformer

# Add all your tasks for overnight
make queue-add TASK="Implement player movement with WASD and jumping" \
    NAME=001-player PROJECT=~/Games/my-platformer

make queue-add TASK="Create 3 enemy types: slime, bat, skeleton" \
    NAME=002-enemies PROJECT=~/Games/my-platformer

make queue-add TASK="Add collectible coins with particle effects" \
    NAME=003-coins PROJECT=~/Games/my-platformer

make queue-add TASK="Create main menu with animated background" \
    NAME=004-menu PROJECT=~/Games/my-platformer

make queue-add TASK="Add save/load system using ConfigFile" \
    NAME=005-save PROJECT=~/Games/my-platformer

# Check they're queued
make queue-status PROJECT=~/Games/my-platformer

# Go to sleep 😴

# Morning: Check results
make queue-status PROJECT=~/Games/my-platformer
cat ~/Games/my-platformer/.claude/results/001-player.log

# Stop the queue
make queue-stop

# Review changes in git
cd ~/Games/my-platformer
git status
git diff
```

---

## Choosing a Workflow

| Scenario | Recommended | Why |
|----------|-------------|-----|
| Active coding session | **Persistent** | Interactive feedback, conversation context |
| Quick question | **Persistent** | Instant response |
| Multiple known tasks | **Queue** | Set and forget |
| Overnight processing | **Queue** | Runs while you sleep |
| Exploring/learning | **Persistent** | Back-and-forth dialogue |
| Batch refactoring | **Queue** | Process many files systematically |
| Debugging an issue | **Persistent** | Iterative investigation |
| Feature implementation | **Persistent** | Complex, needs guidance |
| Code generation tasks | **Queue** | Well-defined, independent |
| CI/CD integration | **Persistent + Print** | Use `make claude-print` for scripted execution |
| Shell script automation | **Persistent + Print** | Non-interactive, TTY auto-detection |

### Can I Use Both?

**Not simultaneously** - both use the same `agent` container name. But you can:

1. Use Persistent mode during work hours
2. Switch to Queue mode for overnight batch processing

```bash
# Switch from Persistent to Queue
make down-agent
make queue-start PROJECT=~/Games/my-platformer

# Switch from Queue to Persistent
make queue-stop
make up-agent PROJECT=~/Games/my-platformer
```

---

## Best Practices

### 1. Use Git for Safety

Always track your project with git so you can review/revert Claude's changes:

```bash
cd ~/Games/my-platformer

# Before starting a session
git status  # Make sure working tree is clean
git checkout -b feature/claude-additions

# After Claude makes changes
git diff
git add -p  # Selectively stage changes
git commit -m "feat: add player movement (Claude-assisted)"
```

### 2. Write Clear Task Descriptions

Bad:
```
Add stuff to the game
```

Good:
```
Create a player controller script (scripts/player.gd) with:
- WASD movement using CharacterBody2D
- Jump with Space key (jump_velocity = -400)
- Gravity (use project settings)
- Coyote time (0.1 seconds)
- Jump buffering (0.1 seconds)
```

### 3. Review Before Running in Godot

Claude can write plausible-looking code that has bugs. Before running in Godot:

1. Review the generated code
2. Check for obvious issues
3. Run the security scanner: `make scan PROJECT=~/Games/my-platformer`

### 4. Use Staging Mode for Untrusted Tasks

If you're not sure about a task, use staging mode to isolate changes:

```bash
# Create staging area
mkdir -p ~/godot-staging
cp -r ~/Games/my-platformer/* ~/godot-staging/

# Run in staging mode
make run-staging STAGING=~/godot-staging

# Review changes
make diff-review STAGING=~/godot-staging LIVE=~/Games/my-platformer

# If satisfied, promote
make promote STAGING=~/godot-staging LIVE=~/Games/my-platformer
```

### 5. Break Down Complex Tasks

Instead of:
```
Build the entire game
```

Break it into:
```
001-project-setup.md     - Set up project structure and folders
002-player.md            - Create player with movement
003-enemies.md           - Add basic enemies
004-level.md             - Create first level layout
005-ui.md                - Add HUD and menus
```

### 6. Include Context in Queue Tasks

Queue tasks run independently without conversation context. Include relevant info:

```markdown
# Add Enemy AI

## Current Project Context
- Using Godot 4.x with GDScript
- Player script is at scripts/player.gd
- Using CharacterBody2D for physics entities
- Art style is pixel art (16x16 sprites)

## Task
Create an enemy that patrols and chases the player...
```

---

## Troubleshooting

### Agent Won't Start

```bash
# Check Docker is running
docker ps

# Check for port conflicts or existing containers
docker ps -a | grep agent
docker rm -f agent  # Remove if stuck

# Restart everything
make down
make up-agent PROJECT=~/Games/my-platformer
```

### Claude Not Responding

```bash
# Check authentication
make auth

# Check agent is running
make agent-status

# Check logs for errors
docker logs agent
```

### Queue Not Processing

```bash
# Check queue processor is running
make queue-status PROJECT=~/Games/my-platformer

# Check logs for errors
make queue-logs

# Restart queue
make queue-stop
make queue-start PROJECT=~/Games/my-platformer
```

### Permission Issues

```bash
# If .claude directories have wrong permissions
sudo chown -R $(whoami) ~/Games/my-platformer/.claude
```

### Container Exits Immediately

```bash
# Check container logs
docker logs agent

# Common causes:
# - Missing auth credentials
# - Invalid project path
# - Docker resource limits
```

### Network Issues (Claude can't reach API)

```bash
# Check infrastructure is running
make status

# Check DNS filter logs
make logs-dns

# Restart infrastructure
make restart
```

---

## Quick Reference

### Persistent Mode Commands

| Command | Description |
|---------|-------------|
| `make up-agent PROJECT=...` | Start persistent agent |
| `make claude` | Interactive session |
| `make claude P="..."` | Single prompt |
| `make claude-print P="..."` | Non-interactive batch mode |
| `make agent-status` | Check if running |
| `make claude-shell` | Open bash shell |
| `make down-agent` | Stop agent |

### Queue Mode Commands

| Command | Description |
|---------|-------------|
| `make queue-start PROJECT=...` | Start queue processor |
| `make queue-add TASK="..." NAME=...` | Add task |
| `make queue-status PROJECT=...` | Show queue status |
| `make queue-logs` | Follow processor logs |
| `make queue-results PROJECT=...` | Show latest result |
| `make queue-stop` | Stop processor |

### Shortcuts

| Short | Full |
|-------|------|
| `make c` | `make claude` |
| `make cp` | `make claude-print` |
| `make a` | `make agent-status` |
| `make q` | `make queue-status` |
| `make qs` | `make queue-start` |
| `make qx` | `make queue-stop` |

---

## Getting Help

- **Project README**: General setup and architecture
- **CLAUDE.md**: Context for Claude instances
- **SECURITY.md**: Threat model and security considerations
- **GitHub Issues**: Report bugs or request features

Happy game development! 🎮

