# Sandboxed Godot Agent Context

*Last updated: 2026-01-03*

You are running inside a **sandboxed Docker container** with restricted network access and security hardening. This file provides essential context about your environment and capabilities.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Environment Overview](#environment-overview)
3. [Your Mission: Autonomous Development](#your-mission-autonomous-development)
4. [Prompt Mode Workflow](#prompt-mode-workflow)
5. [Queue Mode Workflow](#queue-mode-workflow)
6. [Issue Mode Workflow](#issue-mode-workflow)
7. [Testing Requirements](#testing-requirements)
8. [GitHub Access via MCP Tools](#github-access-via-mcp-tools)
9. [Network Access](#network-access)
10. [Git Workflow](#git-workflow-when-using-git-cli)
11. [Filesystem](#filesystem)
12. [Security Boundaries](#security-boundaries)
13. [Best Practices](#best-practices)
14. [Troubleshooting](#troubleshooting)
15. [Getting Help](#getting-help)
16. [Appendix A: Godot Engine Reference](#appendix-a-godot-engine-reference)

---

## Quick Reference

### Common Commands

| Task | Command |
|------|---------|
| Validate project | `godot --headless --validate-project` |
| Run tests | `godot --headless -s res://tests/test_runner.gd` |
| Check git status | `git status && git diff` |
| Create branch | `git checkout -b claude/issue-N-description` |
| View recent commits | `git log --oneline -5` |

### MCP Tool Quick Reference

| Task | Tool |
|------|------|
| List issues | `list_issues` |
| Get issue details | `get_issue` |
| Claim issue | `create_issue_comment` |
| Create PR | `create_pull_request` |
| Read remote file | `get_file_contents` |
| Search code | `search_code` |
| Push files | `push_files` |

### Workflow Cheat Sheet

| Mode | First Step | After PR | Then... |
|------|-----------|----------|---------|
| **Issue** | `list_issues` to find work | Release issue (comment) | Check feedback → find new issue |
| **Queue** | Read `/project/.queue` | Release issue (comment) | Check feedback → find new issue |
| **Prompt** | Understand request | Report summary | Done (one-shot) |

### Continuous Loop (Issue/Queue Modes)

```
┌─────────────────────────────────────────────────────────┐
│  1. Check your open PRs for review feedback             │
│     → If feedback exists: address it first              │
│  2. Find unclaimed issue → claim → new branch from main │
│  3. Implement + test + PR + release                     │
│  4. Repeat from step 1                                  │
└─────────────────────────────────────────────────────────┘
```

### Branch Naming

| Mode | Pattern | Example |
|------|---------|---------|
| Issue | `claude/issue-N-desc` | `claude/issue-42-add-player-dash` |
| Queue | `claude/queue-id-desc` | `claude/queue-task001-add-dash` |
| Prompt | `claude/prompt-desc` | `claude/prompt-refactor-inventory` |

---

## Environment Overview

```
┌─────────────────────────────────────────────────────────────┐
│  SANDBOXED CONTAINER                                        │
│                                                             │
│  You are here: /project                                     │
│    - Isolated Mode: You cloned this repo yourself           │
│    - Mounted Mode: Mounted from host filesystem             │
│                                                             │
│  ✅ Available:                                              │
│    - GitHub MCP tools (for API: issues, PRs, remote files)  │
│    - Git CLI (for local ops + push via configured remote)   │
│    - Godot 4.x (headless mode only)                         │
│    - Node.js, Python 3, common dev tools                    │
│                                                             │
│  🔒 Restricted:                                             │
│    - Network: Only allowlisted domains via proxy            │
│    - Filesystem: Only /project is writable                  │
│    - No sudo/root access                                    │
│    - Read-only root filesystem                              │
└─────────────────────────────────────────────────────────────┘
```

### Isolated Mode vs Mounted Mode

You may be running in one of two deployment modes:

| Mode | How /project Works | Typical Use Case |
|------|-------------------|------------------|
| **Isolated** | You cloned the repo on startup | Autonomous agent, multi-agent workflows |
| **Mounted** | Host directory mounted in | Interactive development, quick iterations |

**How to tell which mode you're in:**
- Check if `/project/.git/config` remote matches `GITHUB_REPO` env var → Isolated
- Check if there's a `claude/work-*` branch already checked out → Isolated (auto-created)
- If unsure, check: `git remote -v`

**In Isolated Mode:**
- You already have a working branch (`claude/work-YYYYMMDD-HHMMSS`)
- The repo was cloned fresh at container startup
- Your workspace is destroyed when the container stops
- Push your work via MCP before the container stops!

## Your Mission: Autonomous Development

Your job is to work on tasks autonomously. You may operate in one of three modes:

| Mode | How Work Arrives | Creates Issue? | First Step |
|------|------------------|----------------|------------|
| **Issue Mode** | Browse open issues in the repo | No (exists) | Find an unclaimed issue |
| **Queue Mode** | Work items arrive via queue file | Yes (if needed) | Read queue, create issue |
| **Prompt Mode** | Direct instruction in your prompt | No | Create branch, start working |

---

## Prompt Mode Workflow

If you're running in **Prompt Mode**, you receive a specific task directly in your prompt—not tied to any GitHub issue.

### Prompt Mode Steps

```
┌──────────────────────────────────────────────────────────────┐
│  1. UNDERSTAND  → Read and understand the prompt request     │
│  2. BRANCH      → Create a feature branch for the work       │
│  3. CODE + TEST → Implement the solution with tests          │
│  4. VALIDATE    → Run all tests, validate the project        │
│  5. COMMIT      → Commit with clear, descriptive messages    │
│  6. PUSH        → Push your branch (PR optional)             │
│  7. REPORT      → Summarize what was done                    │
└──────────────────────────────────────────────────────────────┘
```

### Step P1: Understand the Request

Read your prompt carefully. The request might be:
- A specific feature to implement
- A bug to investigate and fix
- A refactoring task
- Code cleanup or optimization
- Documentation updates

**If the task is unclear**, ask for clarification before starting.

### Step P2: Create a Feature Branch

Even without an issue, always work on a branch:

```bash
# Branch naming for prompt tasks: claude/prompt-brief-description
git checkout -b claude/prompt-add-player-dash

# Or with a date for uniqueness
git checkout -b claude/prompt-20240115-refactor-inventory
```

### Step P3: Implement with Tests

**Tests are still required**, even for prompt-based work:

```bash
# Write tests for your changes
# Verify they pass
godot --headless -s res://tests/test_runner.gd
```

### Step P4: Validate

Run full validation before committing:

```bash
godot --headless --validate-project
godot --headless -s res://tests/test_runner.gd
git status
```

### Step P5: Commit with Clear Messages

Use descriptive commit messages that explain the work:

```bash
git add -A
git commit -m "feat: add player dash ability

- Implemented dash mechanic with velocity burst
- Added 0.5s cooldown between dashes
- Dash disabled while airborne
- Added tests for dash behavior"
```

### Step P6: Push the Branch

Push your work to the remote:

```bash
git push origin claude/prompt-add-player-dash
```

**Creating a PR is optional** for prompt mode—follow the instructions in your prompt. If a PR is requested:

```
Use create_pull_request:
  - owner: owner
  - repo: repo
  - title: "feat: add player dash ability"
  - body: |
      ## Summary
      Implemented player dash ability as requested.
      
      ## Changes
      - Added dash mechanic to player.gd
      - Added cooldown system
      - Added tests
      
      ## Prompt Reference
      This work was done via direct prompt request.
  - head: claude/prompt-add-player-dash
  - base: main
```

### Step P7: Report What Was Done

At the end of your work, provide a clear summary:

```
## Work Complete

### Changes Made
- Added dash ability to player.gd
- Implemented 0.5s cooldown system
- Added test_player_dash() with 4 test cases

### Branch
`claude/prompt-add-player-dash` pushed to origin

### Tests
All 12 tests passing

### Files Modified
- scripts/player.gd
- tests/test_player.gd
```

### Prompt Mode Summary

| Step | Action | Notes |
|------|--------|-------|
| P1 | Understand prompt | Ask if unclear |
| P2 | Create branch | `claude/prompt-*` naming |
| P3 | Code + test | Tests still required! |
| P4 | Validate | Full validation |
| P5 | Commit | Clear, descriptive messages |
| P6 | Push | PR optional per instructions |
| P7 | Report | Summarize changes |

### When to Use Prompt Mode vs Issue Mode

| Situation | Recommended Mode |
|-----------|-----------------|
| Quick fix or experiment | Prompt Mode |
| Tracked feature work | Issue Mode |
| One-off refactoring | Prompt Mode |
| User-facing feature | Issue Mode (for visibility) |
| Exploratory changes | Prompt Mode |

---

## Queue Mode Workflow

If you're running in **Queue Mode**, work items arrive via a queue file rather than existing GitHub issues.

### Queue Mode Steps

```
┌──────────────────────────────────────────────────────────────┐
│  1. READ QUEUE   → Take the next item from the queue file    │
│  2. CHECK        → Does an issue already exist for this?     │
│  3. CREATE       → If no issue exists, create one            │
│  4. CLAIM        → Comment on the issue to claim it          │
│  5. BRANCH       → Create a feature branch                   │
│  6. CODE + TEST  → Implement the solution with tests         │
│  7. PUSH         → Push branch and create a PR               │
│  8. WAIT         → Do NOT merge. A human will review.        │
└──────────────────────────────────────────────────────────────┘
```

### Step Q1: Read the Queue

Check for a queue file at `/project/.queue` or as specified by your configuration:

```bash
# Check if queue file exists
cat /project/.queue

# Queue items are typically JSON or one-per-line
```

A queue item might look like:

```json
{
  "id": "task-001",
  "type": "feature",
  "title": "Add player dash ability",
  "description": "Implement a dash mechanic for the player character...",
  "priority": "high"
}
```

### Step Q2: Check for Existing Issue

Before creating a new issue, search to see if one already exists:

```
Use search_issues or list_issues to check for:
- Issues with similar titles
- Issues mentioning the queue item ID
- Recently created issues matching the description
```

If an issue already exists, skip to Step Q4 (Claim).

### Step Q3: Create the Issue

If no issue exists, create one:

```
Use create_issue:
  - owner: owner
  - repo: repo
  - title: "feat: Add player dash ability"
  - body: |
      ## Description
      Implement a dash mechanic for the player character.
      
      ## Requirements
      - Dash should move player quickly in facing direction
      - Should have a cooldown period
      - Should not work while airborne
      
      ## Queue Reference
      Queue ID: task-001
      
      ---
      *This issue was created automatically from a work queue item.*
```

**Include the queue item ID** in the issue body for traceability.

### Step Q4: Claim and Continue

Once you have an issue (found or created), claim it and continue with the standard workflow:

```
Use create_issue_comment:
  - owner: owner
  - repo: repo
  - issue_number: <issue number>
  - body: |
      🤖 I'm claiming this issue and starting work on it now.
      Queue item: task-001
```

Then proceed to **[Step 3: Create a Feature Branch](#step-3-create-a-feature-branch)** in the Issue Mode workflow below.

### Queue Mode Summary

| Step | Action | Tool |
|------|--------|------|
| Q1 | Read queue file | `cat /project/.queue` |
| Q2 | Check for existing issue | `list_issues`, `search_issues` |
| Q3 | Create issue (if needed) | `create_issue` |
| Q4 | Claim issue | `create_issue_comment` |
| ... | Continue standard workflow | See below |

---

## Issue Mode Workflow (Standard)

If you're running in **Issue Mode**, you browse existing GitHub issues to find work.

### The Issue Workflow

```
┌──────────────────────────────────────────────────────────────┐
│  1. FIND    → List open issues, find one that's unclaimed    │
│  2. CLAIM   → Comment on the issue to claim it               │
│  3. BRANCH  → Create a feature branch for your work          │
│  4. CODE    → Implement the solution + write tests           │
│  5. TEST    → Run all tests, validate the project            │
│  6. PUSH    → Push your branch and create a PR               │
│  7. RELEASE → Comment that you're done, ready for review     │
│  8. LOOP    → Check for feedback, then find new work         │
│  9. REVISE  → If feedback exists, address it first           │
└──────────────────────────────────────────────────────────────┘
```

**Continuous Operation:** After releasing an issue, you should immediately check for review feedback on your open PRs, then find new unclaimed issues to work on. This is an ongoing loop—don't wait idle!

### Step 1: Find an Unclaimed Issue

Use MCP tools to list issues and find work:

```
Use list_issues on owner/repo to see open issues.
Look for issues that:
- Are open (not closed)
- Have no assignee
- Have no recent "claiming" comments from other agents
```

### Step 2: Claim the Issue

**Before starting work, comment on the issue to claim it:**

```
Use create_issue_comment:
  - owner: owner
  - repo: repo
  - issue_number: N
  - body: "🤖 I'm claiming this issue and starting work on it now."
```

This prevents duplicate work if multiple agents are running.

### Step 3: Create a Feature Branch

Always work on a feature branch, never on main:

```bash
# Branch naming convention: claude/issue-N-brief-description
git checkout -b claude/issue-42-add-player-dash
```

### Step 4: Implement + Write Tests

**⚠️ CRITICAL: Every change MUST include tests.**

| Change Type | Required Tests |
|-------------|---------------|
| New feature | Tests that verify the feature works |
| Bug fix | Test that reproduces the bug and proves it's fixed |
| Refactor | Tests that verify behavior is unchanged |
| Script changes | Unit tests for the script logic |

**No exceptions.** If you can't figure out how to test something, document why in the PR.

### Step 5: Validate Everything

Before pushing, always run:

```bash
# 1. Validate Godot project
godot --headless --validate-project

# 2. Run all tests
godot --headless -s res://tests/test_runner.gd

# 3. Check for uncommitted changes
git status
git diff
```

All tests must pass before pushing.

### Step 6: Push and Create PR

Push your branch and create a pull request:

```
Use create_pull_request:
  - owner: owner
  - repo: repo
  - title: "fix: add player dash ability (closes #42)"
  - body: |
      ## Summary
      Implemented player dash ability per issue #42.
      
      ## Changes
      - Added dash mechanic to player.gd
      - Added cooldown system
      
      ## Testing
      - Added test_player_dash() to test_runner.gd
      - All tests pass
      
      Closes #42
  - head: claude/issue-42-add-player-dash
  - base: main
```

**Include "Closes #N" in the PR body** to link it to the issue.

### Step 7: Release the Issue

After creating the PR, **comment on the issue to "release" it** (signal you're done with initial work):

```
Use create_issue_comment:
  - owner: owner
  - repo: repo
  - issue_number: N
  - body: |
      🤖 I've completed my work on this issue and created PR #XX.
      
      Releasing this issue - ready for human review.
      
      PR: #XX
```

⛔ **NEVER merge your own pull request.**
⛔ **NEVER close the issue yourself.**

A human will:
1. Review your code
2. Request changes if needed (see Step 8)
3. Merge the PR (which auto-closes the issue)

### Step 8: Continuous Workflow Loop

After releasing an issue, **immediately look for more work**:

```
┌──────────────────────────────────────────────────────────────┐
│  CONTINUOUS WORKFLOW LOOP                                    │
│                                                              │
│  1. CHECK YOUR OPEN PRs                                      │
│     → Do any of your PRs have review comments?              │
│     → If yes: address feedback first (see Step 9)           │
│                                                              │
│  2. FIND NEW WORK                                           │
│     → List open issues                                       │
│     → Find unclaimed issues (no recent agent claims)         │
│     → Claim and start working                                │
│                                                              │
│  3. FRESH START                                              │
│     → Switch back to main: git checkout main && git pull     │
│     → Create new branch for new issue                        │
│     → Repeat from Step 1 of Issue Mode                       │
└──────────────────────────────────────────────────────────────┘
```

**Important:** Always start new work from a fresh `main` branch:

```bash
# After releasing an issue, start fresh for the next one
git checkout main
git pull origin main
git checkout -b claude/issue-NEW-description
```

### Step 9: Addressing Review Feedback

If you encounter one of your PRs with unaddressed review comments:

**Priority:** Review feedback takes precedence over new issues.

```
┌──────────────────────────────────────────────────────────────┐
│  HANDLING REVIEW FEEDBACK                                    │
│                                                              │
│  1. CHECK who commented                                      │
│     → Ignore comments from godot-agent (that's you!)        │
│     → Focus on comments from humans/other reviewers          │
│                                                              │
│  2. UNDERSTAND the feedback                                  │
│     → Read all review comments carefully                     │
│     → Look for requested changes                             │
│     → Note any questions asked                               │
│                                                              │
│  3. RESPOND to questions                                     │
│     → Use create_issue_comment to answer questions           │
│     → Explain your reasoning if challenged                   │
│                                                              │
│  4. IMPLEMENT changes                                        │
│     → Checkout the PR branch                                 │
│     → Make requested modifications                           │
│     → Run tests again                                        │
│     → Push to the same branch (updates the PR)               │
│                                                              │
│  5. NOTIFY when done                                         │
│     → Comment that you've addressed the feedback             │
└──────────────────────────────────────────────────────────────┘
```

**Example: Responding to review feedback:**

```bash
# Switch to the existing PR branch
git checkout claude/issue-42-add-player-dash
git pull origin claude/issue-42-add-player-dash

# Make the requested changes
# ... edit files ...

# Test again
godot --headless -s res://tests/test_runner.gd

# Push updates (PR is automatically updated)
git add -A
git commit -m "fix: address review feedback - add null check"
git push
```

Then comment on the PR:

```
Use create_issue_comment (on the PR, not the issue):
  - body: |
      🤖 I've addressed the review feedback:
      
      - Added null check as requested
      - Updated tests to cover edge case
      
      Ready for another look!
```

### Identifying Your Open Work

To check if you have pending review feedback:

```
Use list_issues with state: open
Look for issues where:
  - You previously commented "I'm claiming this issue"
  - There are newer comments from users OTHER than godot-agent
  - The linked PR is still open (not merged)
```

**If you find pending feedback → address it first.**
**If all your PRs are clean → find new work.**

### Workflow Summary (All Modes)

| Action | Tool | Mode |
|--------|------|------|
| Read queue file | `cat /project/.queue` | Queue |
| Search for existing issue | `list_issues`, `search_issues` | Queue |
| Create new issue | `create_issue` | Queue (if needed) |
| List open issues | `list_issues` | Issue |
| Read issue details | `get_issue` | Issue, Queue |
| Claim issue | `create_issue_comment` | Issue, Queue |
| Create branch | `git checkout -b` | All modes |
| Code + write tests | — | All modes |
| Validate project | `godot --headless --validate-project` | All modes |
| Run tests | `godot --headless -s res://tests/test_runner.gd` | All modes |
| Push changes | `push_files` or git push | All modes |
| Create PR | `create_pull_request` | Issue, Queue (required) / Prompt (optional) |
| **Release issue** | `create_issue_comment` | Issue, Queue |
| **Check for feedback** | `list_issues`, review comments | Issue, Queue |
| **Address feedback** | Edit code, push to same branch | Issue, Queue |
| **Find new work** | `list_issues` → claim → new branch | Issue, Queue |
| Report summary | — | Prompt |
| ❌ Merge PR | NEVER | — |
| ❌ Close issue | NEVER | — |

---

## Testing Requirements

**Every change must include tests.** This is non-negotiable.

### Why Tests Are Required

1. **Verification**: Proves your code works
2. **Regression prevention**: Catches future breakage
3. **Documentation**: Tests show how code should behave
4. **Review confidence**: Reviewers can trust tested code

### Test Structure for Godot Projects

Place tests in `res://tests/`:

```
project/
├── tests/
│   ├── test_runner.gd      # Main test runner
│   ├── test_player.gd      # Player-specific tests
│   ├── test_inventory.gd   # Inventory tests
│   └── test_utils.gd       # Utility function tests
```

### Writing Good Tests

```gdscript
# res://tests/test_player.gd
extends Node

var tests_passed := 0
var tests_failed := 0

func run_all() -> Dictionary:
    test_player_initial_health()
    test_player_takes_damage()
    test_player_cannot_have_negative_health()
    test_player_dash_cooldown()
    return {"passed": tests_passed, "failed": tests_failed}

func assert_eq(actual, expected, test_name: String) -> void:
    if actual == expected:
        tests_passed += 1
        print("  ✓ %s" % test_name)
    else:
        tests_failed += 1
        print("  ✗ %s: expected %s, got %s" % [test_name, expected, actual])

func assert_true(condition: bool, test_name: String) -> void:
    assert_eq(condition, true, test_name)

func assert_false(condition: bool, test_name: String) -> void:
    assert_eq(condition, false, test_name)

# Test implementations
func test_player_initial_health() -> void:
    var player = preload("res://scenes/player.tscn").instantiate()
    assert_eq(player.health, 100, "Player starts with 100 health")
    player.free()

func test_player_takes_damage() -> void:
    var player = preload("res://scenes/player.tscn").instantiate()
    player.take_damage(30)
    assert_eq(player.health, 70, "Player health reduced by damage")
    player.free()

func test_player_cannot_have_negative_health() -> void:
    var player = preload("res://scenes/player.tscn").instantiate()
    player.take_damage(999)
    assert_true(player.health >= 0, "Health cannot go negative")
    player.free()

func test_player_dash_cooldown() -> void:
    var player = preload("res://scenes/player.tscn").instantiate()
    assert_true(player.can_dash(), "Can dash initially")
    player.dash()
    assert_false(player.can_dash(), "Cannot dash during cooldown")
    player.free()
```

### Test Runner Pattern

```gdscript
# res://tests/test_runner.gd
extends SceneTree

func _init() -> void:
    print("=" .repeat(50))
    print("Running Test Suite")
    print("=" .repeat(50))
    
    var total_passed := 0
    var total_failed := 0
    
    # Run each test module
    var test_modules = [
        "res://tests/test_player.gd",
        "res://tests/test_inventory.gd",
        "res://tests/test_utils.gd",
    ]
    
    for module_path in test_modules:
        if FileAccess.file_exists(module_path):
            print("\n[%s]" % module_path.get_file())
            var module = load(module_path).new()
            var results = module.run_all()
            total_passed += results.passed
            total_failed += results.failed
            module.free()
    
    print("\n" + "=" .repeat(50))
    print("Results: %d passed, %d failed" % [total_passed, total_failed])
    print("=" .repeat(50))
    
    quit(0 if total_failed == 0 else 1)
```

### What to Test

| Component | Test For |
|-----------|----------|
| Player mechanics | Movement, health, abilities, death |
| Inventory | Add/remove items, capacity limits, stacking |
| Combat | Damage calculation, knockback, invincibility frames |
| UI | State changes, button callbacks, display values |
| Save/Load | Data persistence, corruption handling |
| Utilities | Math helpers, string formatting, parsing |

---

## GitHub Access via MCP Tools

**Use MCP tools as your primary way to interact with GitHub.** The GitHub MCP server is pre-configured with authentication.

### Available MCP Tools

| Tool | Purpose |
|------|---------|
| `get_file_contents` | Read files from any accessible repository |
| `search_code` | Search code across repositories |
| `search_repositories` | Find repositories |
| `list_commits` | View commit history |
| `get_issue` / `list_issues` | Read issues |
| `create_issue` | Create new issues |
| `create_issue_comment` | Comment on issues (use to claim issues!) |
| `create_pull_request` | Create PRs |
| `get_pull_request` / `list_pull_requests` | Read PRs |
| `create_or_update_file` | Write files to repositories |
| `push_files` | Push multiple files |
| `create_branch` | Create new branches |
| `fork_repository` | Fork a repository |

### Example MCP Usage

```
# Read a file from a repo
Use get_file_contents:
  - owner: owner
  - repo: repo
  - path: path/to/file.gd

# Search for code
Use search_code:
  - q: "func _ready repo:owner/repo"

# Create an issue
Use create_issue:
  - owner: owner
  - repo: repo
  - title: "Issue title"
  - body: "Issue description"

# Create a pull request
Use create_pull_request:
  - owner: owner
  - repo: repo
  - title: "PR title"
  - body: "PR description"
  - head: feature-branch
  - base: main
```

### When to Use Git CLI Instead

Use `git` commands for **local operations** in `/project`:

```bash
# Check local status
git status
git diff

# Stage and commit locally
git add .
git commit -m "feat: add feature"

# View local history
git log --oneline
```

**For remote operations (push, pull, clone), prefer MCP tools** when possible as they provide better error handling and don't require manual credential management.

## Network Access

You can **only** reach these domains (via proxy):

| Domain | Purpose |
|--------|---------|
| github.com | Git operations |
| api.github.com | GitHub API (MCP tools use this) |
| raw.githubusercontent.com | Raw file content |
| codeload.github.com | Archive downloads |
| docs.godotengine.org | Godot documentation |
| api.anthropic.com | Claude API |

**All other domains are blocked.**

## Git Workflow (When Using Git CLI)

### Branch Protection (Enforced)

- ⛔ **Direct pushes to `main` or `master` are BLOCKED**
- ✅ Always create a feature branch first
- ✅ Push feature branches and create PRs via MCP tools

### Local Git Operations

```bash
# Create a feature branch
git checkout -b claude/my-feature

# Make changes, commit locally
git add .
git commit -m "feat: add new feature"

# Check what you've done
git status
git log --oneline -5
```

### Creating PRs

Use the MCP `create_pull_request` tool:

```
Use create_pull_request:
  - owner: owner
  - repo: repo
  - title: "Add new feature"
  - body: "Description of changes"
  - head: claude/my-feature
  - base: main
```

## Godot Engine

Godot 4.x is installed in **headless mode** (no display server).

### Essential Commands

```bash
godot --headless --version              # Check version
godot --headless --validate-project     # Validate scripts/scenes
godot --headless --check-only           # Parse without running
godot --headless -s res://tests/test_runner.gd  # Run tests
```

### Quick GDScript Reference

```gdscript
extends CharacterBody2D

@export var speed: float = 300.0
signal health_changed(new_health: int)

func _ready() -> void:
    print("Node ready")

func _physics_process(delta: float) -> void:
    var direction = Input.get_axis("ui_left", "ui_right")
    velocity.x = direction * speed
    move_and_slide()

func take_damage(amount: int) -> void:
    health -= amount
    health_changed.emit(health)
```

### Headless Limitations

- ❌ No graphics, audio, screenshots, or editor features
- ✅ Can validate, test, export, and automate

**For comprehensive Godot documentation, see [Appendix A: Godot Engine Reference](#appendix-a-godot-engine-reference).**

---

## Filesystem

| Path | Access | Purpose |
|------|--------|---------|
| `/project` | Read/Write | Your working directory (mounted from host) |
| `/home/claude` | Read/Write | Home directory (tmpfs, not persisted) |
| `/tmp` | Read/Write | Temporary files (tmpfs) |
| Everything else | Read-only | System files |

### Important Notes

- Changes to `/project` persist on the host
- Changes to `/home/claude` and `/tmp` are lost when container stops
- Cannot create files outside these locations

## Security Boundaries

This sandbox prevents damage to the host system and limits blast radius if something goes wrong.

### You CAN:
- Read/write files in `/project` *(your work needs to persist)*
- Use MCP tools to interact with GitHub *(authenticated, rate-limited)*
- Run Godot commands *(your core purpose)*
- Use git for local repository operations *(necessary for version control)*
- Run Node.js and Python scripts *(for tooling and automation)*

### You CANNOT:
- Access the internet freely *(prevents data exfiltration, attacks on external systems)*
- Modify system files *(immutable container ensures consistency)*
- Install system packages *(use what's pre-installed; request additions via issue)*
- Access host filesystem outside `/project` *(isolation protects host)*
- Run privileged operations *(no sudo/root access)*

**If you need capabilities not listed here, you're probably approaching the problem wrong.** Ask yourself: can this be done with MCP tools, existing commands, or a different approach?

## Best Practices

### 1. Always Write Tests

**Every change needs tests.** No exceptions.

```bash
# Before pushing, verify tests pass
godot --headless -s res://tests/test_runner.gd
```

If you're unsure how to test something, ask yourself:
- "How would I verify this works manually?"
- "What could break in the future?"
- "What are the edge cases?"

Then write tests for those scenarios.

### 2. Claim Issues Before Working

Always comment on an issue before starting work:
- Prevents duplicate effort from other agents
- Creates a paper trail of who's working on what
- Lets humans know the issue is being addressed

### 3. Use Feature Branches

Always work on a branch, never directly on main:

```bash
# Naming: claude/issue-N-description
git checkout -b claude/issue-15-fix-player-jump
```

### 4. Commit Often

Make frequent commits with meaningful messages:

```bash
git add -A && git commit -m "feat: add dash ability"
git add -A && git commit -m "test: add dash cooldown tests"
git add -A && git commit -m "fix: prevent dash while airborne"
```

### 5. Validate Before Pushing

Always run the full validation before pushing:

```bash
# 1. Validate Godot project
godot --headless --validate-project

# 2. Run ALL tests (must pass)
godot --headless -s res://tests/test_runner.gd

# 3. Review your changes
git status
git diff
git log --oneline -5
```

### 6. Link PRs to Issues

Always include "Closes #N" in your PR description:

```
## Summary
Added player dash ability.

Closes #42
```

This auto-closes the issue when the PR is merged.

### 7. ⛔ Never Merge Your Own PR

Your job ends when the PR is created. Humans will:
1. Review the code
2. Request changes if needed
3. Approve and merge

**Do not:**
- Merge pull requests
- Close issues manually
- Push directly to main/master

### 8. Use MCP Tools for GitHub

Prefer MCP tools over CLI commands:
- More reliable authentication
- Better error messages
- No credential management needed

---

## Troubleshooting

### Verify MCP is Working

**First step for any MCP issues:** Run the verification script:

```bash
# Quick verification
/opt/scripts/verify-mcp.sh

# Verbose output (shows more details)
GITHUB_DEBUG=1 /opt/scripts/verify-mcp.sh --verbose

# Test access to a specific repo
GITHUB_VERIFY_REPO=owner/repo /opt/scripts/verify-mcp.sh
```

The script checks:
- ✓ MCP configuration exists in ~/.claude.json
- ✓ GitHub token is present and valid
- ✓ Token has correct permissions for target repository

### Understanding Claude Configuration Files

**Important:** Claude Code uses **two different configuration files** for different purposes:

| File | Purpose | Contains |
|------|---------|----------|
| `~/.claude.json` | **MCP server configuration** | `mcpServers` object with server definitions |
| `~/.claude/settings.json` | **Claude Code settings** | Permissions, auto-updater status, preferences |

**Common mistake:** Looking for MCP servers in `settings.json` - they won't be there!

```bash
# ✅ Correct: MCP servers are in ~/.claude.json
cat ~/.claude.json | jq .mcpServers

# ❌ Wrong: settings.json is for permissions, not MCP
cat ~/.claude/settings.json | jq .mcpServers  # Will return null
```

**Example ~/.claude.json structure:**
```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@github/github-mcp-server"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "ghs_xxx..."
      }
    }
  }
}
```

**⚠️ About `GITHUB_PERSONAL_ACCESS_TOKEN`:**

Despite its name, this is NOT a personal access token. It's a **GitHub App installation token** that:
- Is auto-generated on container startup from GitHub App credentials
- Expires after ~1 hour (auto-refreshed if container restarts)
- Should **ONLY** be used for MCP tools, NOT for `gh` CLI

```bash
# ✅ Correct: MCP tools use this token automatically
# Just use the MCP tools - they read from ~/.claude.json

# ❌ WRONG: Never extract this token for gh CLI
gh auth login --with-token < ~/.claude.json  # DON'T DO THIS!
export GH_TOKEN=$(cat ~/.claude.json | jq -r ...)  # DON'T DO THIS!
```

The `gh` CLI is not available in the sandbox. Use MCP tools for all GitHub operations.

**Example ~/.claude/settings.json structure:**
```json
{
  "permissions": {
    "bypassPermissionsMode": true,
    "allow": ["*"],
    "deny": []
  },
  "autoUpdaterStatus": "disabled"
}
```

### MCP Tools Not Available

If MCP tools aren't working:

1. **Check if MCP server is configured:**
   ```bash
   cat ~/.claude.json | jq .mcpServers
   ```
   Should show a `github` object with command and token.

2. **Verify token is valid:**
   ```bash
   TOKEN=$(cat ~/.claude.json | jq -r '.mcpServers.github.env.GITHUB_PERSONAL_ACCESS_TOKEN')
   curl -H "Authorization: Bearer $TOKEN" https://api.github.com/rate_limit
   ```

3. **If token is missing or expired:**
   - Check container was started with correct GitHub App credentials
   - Verify `GITHUB_APP_ID` and `GITHUB_APP_INSTALLATION_ID` are set
   - Restart container to regenerate token (tokens expire after ~1 hour)

### MCP Tool Failures

| Error | Cause | Solution |
|-------|-------|----------|
| "Not Found" from `get_issue` | Issue doesn't exist or wrong repo | Verify `owner/repo` format and issue number |
| "Resource not accessible" | Permission issue | Check if repo is private; token may lack access |
| "Validation Failed" | Missing required fields | Check all required parameters are provided |
| Push/PR creation fails | Branch protection or conflict | Pull latest main, rebase your branch |
| "MCP tools not available" | Server not running | Run `/opt/scripts/verify-mcp.sh --verbose` |

### Network Issues

If network requests fail with timeout or connection errors:

1. **Verify you're using an allowlisted domain** (see [Network Access](#network-access))
2. **Check proxy is responding**: `curl -I https://api.github.com`
3. **Non-allowlisted domains will hang, then fail** - there's no quick timeout

```bash
# Test network connectivity
curl -s https://api.github.com/zen  # Should return a phrase
curl -s https://docs.godotengine.org -o /dev/null && echo "OK"
```

### Godot Errors

```bash
# "Invalid project" error
ls project.godot  # Confirm file exists in current directory

# Script parse errors - get specific error messages
godot --headless --check-only 2>&1 | head -30

# Scene load errors - check for broken resource paths
grep -r "res://" *.tscn 2>/dev/null | grep -v "^\[" 

# Full validation with error output
godot --headless --validate-project 2>&1
```

### Git Issues

| Error | Solution |
|-------|----------|
| "Push rejected" to main/master | You can't push to protected branches; create a feature branch first |
| "Authentication failed" | Use MCP tools (`push_files`) instead of `git push` |
| Merge conflicts | `git fetch origin main && git rebase origin/main`, resolve conflicts, test, then push |
| "Detached HEAD" | `git checkout -b claude/recovery-branch` to save your work |

### Common Workflow Problems

**Issue: Tests pass locally but fail in PR checks**
- Check if CI has additional validation steps
- Ensure all new files are committed (`git status`)
- Verify tests don't depend on local environment

**Issue: Can't find an issue to work on**
- All issues may be claimed - check comments for recent "claiming" messages
- Issues may be closed - use `list_issues` with `state: "open"`
- Try `search_issues` with different queries

**Issue: Godot project structure seems wrong**
- Look for `project.godot` - this defines the project root
- Run `godot --headless --validate-project` from that directory
- Check if you're in a subdirectory of the project

---

## Session Information

- **Container**: claude-godot-agent
- **Working Directory**: /project
- **User**: claude (uid 1000)
- **Shell**: /bin/bash

## Getting Help

### Godot Resources

- **Godot docs**: https://docs.godotengine.org (accessible via network allowlist)
- **CLI help**: `godot --headless --help`
- **Class reference**: Check docs for any class (Node2D, CharacterBody2D, etc.)
- **GDScript reference**: https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/

### Quick Reference Commands

```bash
# Godot CLI options
godot --headless --help

# What version?
godot --headless --version

# Is this a valid project?
godot --headless --validate-project

# What's in project.godot?
cat project.godot
```

### Project-Specific Help

- Check `/project/CLAUDE.md` for project-specific instructions
- Check `/project/README.md` for project documentation
- Look at existing code patterns in the project

---

## Appendix A: Godot Engine Reference

This appendix provides comprehensive Godot documentation for when you need detailed reference information.

### What is Godot?

Godot is a free, open-source game engine that uses a scene/node architecture:

- **Nodes**: The atomic building blocks (Sprite2D, CharacterBody2D, AudioStreamPlayer, etc.)
- **Scenes**: Compositions of nodes saved as `.tscn` files (text format) or `.scn` (binary)
- **Scripts**: GDScript (`.gd`), C# (`.cs`), or GDExtension for logic
- **Resources**: Reusable data objects (`.tres` text, `.res` binary)

### Godot Project Structure

A typical Godot project looks like:

```
project/
├── project.godot          # Project configuration (always at root)
├── icon.svg               # Project icon
├── export_presets.cfg     # Export configurations (if configured)
├── .godot/                # Cache directory (auto-generated, gitignored)
├── scenes/                # Scene files (.tscn)
│   ├── main.tscn
│   ├── player.tscn
│   └── ui/
├── scripts/               # GDScript files (.gd)
│   ├── player.gd
│   └── autoload/
├── assets/                # Textures, audio, fonts, etc.
│   ├── sprites/
│   ├── audio/
│   └── fonts/
├── addons/                # Plugins and extensions
└── resources/             # Custom resources (.tres)
```

**Key file**: `project.godot` - The presence of this file defines a Godot project. Always look for it first.

### GDScript Fundamentals

GDScript is Godot's primary language—Python-like syntax designed for game development:

```gdscript
extends CharacterBody2D  # Inheritance - this script extends a node type

# Constants and exports (configurable in editor)
const SPEED = 300.0
@export var jump_velocity: float = -400.0

# Signals for decoupled communication
signal health_changed(new_health: int)

# Lifecycle callbacks
func _ready() -> void:
    # Called when node enters scene tree
    print("Node is ready")

func _process(delta: float) -> void:
    # Called every frame (use for non-physics updates)
    pass

func _physics_process(delta: float) -> void:
    # Called every physics tick (use for movement)
    var direction = Input.get_axis("ui_left", "ui_right")
    velocity.x = direction * SPEED
    move_and_slide()

func _input(event: InputEvent) -> void:
    # Handle input events
    if event.is_action_pressed("jump"):
        velocity.y = jump_velocity

# Custom methods
func take_damage(amount: int) -> void:
    health -= amount
    health_changed.emit(health)
```

### Key GDScript Patterns

```gdscript
# Getting nodes
@onready var sprite = $Sprite2D                    # Child by name
@onready var player = $"../Player"                 # Sibling
var player = get_node("/root/Main/Player")         # Absolute path
var enemies = get_tree().get_nodes_in_group("enemies")  # Groups

# Instantiating scenes
var bullet_scene = preload("res://scenes/bullet.tscn")
var bullet = bullet_scene.instantiate()
add_child(bullet)

# Signals
button.pressed.connect(_on_button_pressed)         # Connect
some_signal.emit(arg1, arg2)                       # Emit

# Coroutines with await
await get_tree().create_timer(1.0).timeout        # Wait 1 second
await some_signal                                  # Wait for signal

# Type hints (recommended)
var health: int = 100
func get_position() -> Vector2:
    return position
```

### Common Node Types

| Category | Nodes | Purpose |
|----------|-------|---------|
| **2D** | `Node2D`, `Sprite2D`, `AnimatedSprite2D` | 2D game objects and sprites |
| **Physics 2D** | `CharacterBody2D`, `RigidBody2D`, `Area2D`, `CollisionShape2D` | 2D physics |
| **3D** | `Node3D`, `MeshInstance3D`, `Camera3D` | 3D game objects |
| **Physics 3D** | `CharacterBody3D`, `RigidBody3D`, `Area3D` | 3D physics |
| **UI** | `Control`, `Button`, `Label`, `TextEdit`, `VBoxContainer` | User interface |
| **Audio** | `AudioStreamPlayer`, `AudioStreamPlayer2D/3D` | Sound playback |
| **Utility** | `Timer`, `HTTPRequest`, `AnimationPlayer` | Common utilities |

### Headless Mode Commands

Always use `--headless` flag. No display server is available.

```bash
# Version and help
godot --headless --version
godot --headless --help

# Project validation (catches errors in scripts/scenes)
godot --headless --validate-project
godot --headless --check-only                    # Parse without running

# Run the project (main scene)
godot --headless

# Run a specific scene
godot --headless res://scenes/test_scene.tscn

# Run a script directly (must extend SceneTree or MainLoop)
godot --headless -s res://scripts/cli_tool.gd

# Run with arguments (access via OS.get_cmdline_args())
godot --headless -s res://scripts/tool.gd -- --input file.txt

# Import resources (useful for CI)
godot --headless --import

# Export builds (requires export_presets.cfg)
godot --headless --export-release "Linux/X11" ./build/game.x86_64
godot --headless --export-release "Web" ./build/index.html
godot --headless --export-debug "Linux/X11" ./build/game_debug.x86_64

# List export presets
godot --headless --export-list

# Doctool (generate documentation)
godot --headless --doctool ./docs

# Convert between text/binary formats
godot --headless --convert-3to4             # Upgrade Godot 3 project to 4
```

### Writing Headless CLI Scripts

Create scripts that run without GUI by extending `SceneTree`:

```gdscript
# res://scripts/cli_example.gd
extends SceneTree

func _init() -> void:
    print("=== Headless Script Running ===")
    
    # Get command line arguments
    var args = OS.get_cmdline_args()
    print("Arguments: ", args)
    
    # Do your work here
    var result = run_checks()
    
    # Exit with code (0 = success, non-zero = failure)
    quit(0 if result else 1)

func run_checks() -> bool:
    # Your logic here
    print("Running checks...")
    return true
```

Run it with: `godot --headless -s res://scripts/cli_example.gd`

### Working with Scene Files (.tscn)

Scene files are text-based and editable. Understanding their format helps with automation:

```ini
[gd_scene load_steps=3 format=3 uid="uid://abc123"]

[ext_resource type="Script" path="res://scripts/player.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/player.png" id="2"]

[sub_resource type="RectangleShape2D" id="RectangleShape2D_abc"]
size = Vector2(32, 48)

[node name="Player" type="CharacterBody2D"]
script = ExtResource("1")
speed = 300.0

[node name="Sprite" type="Sprite2D" parent="."]
texture = ExtResource("2")

[node name="Collision" type="CollisionShape2D" parent="."]
shape = SubResource("RectangleShape2D_abc")
```

You can safely edit these files to:
- Change property values
- Add/remove nodes
- Update resource paths
- Modify scripts

### Project Configuration (project.godot)

```ini
[application]
config/name="My Game"
config/version="1.0.0"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.2")

[autoload]
GameManager="*res://scripts/autoload/game_manager.gd"
AudioManager="*res://scripts/autoload/audio_manager.gd"

[input]
move_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"keycode":65)]
}

[rendering]
renderer/rendering_method="mobile"
```

### Headless Limitations

❌ **Cannot do in headless mode:**
- Display any graphics or windows
- Test visual rendering
- Play audio (no audio server)
- Capture screenshots
- Use editor-only features

✅ **Can do in headless mode:**
- Validate project and scripts
- Run unit tests on game logic
- Process and convert resources
- Export builds
- Run CLI tools
- Automate scene/resource manipulation
- Test non-visual gameplay systems

### Common Validation Workflow

Before committing changes, always validate:

```bash
# 1. Check project structure
ls -la project.godot  # Confirm we're in a Godot project

# 2. Validate all scripts and scenes
godot --headless --validate-project

# 3. Run project tests (if they exist)
godot --headless -s res://tests/test_runner.gd

# 4. Check for specific errors
godot --headless --check-only 2>&1 | grep -i error

# 5. Verify export presets (if relevant)
godot --headless --export-list
```

### Useful Environment Info

```bash
# Godot version
godot --headless --version

# Check what's available
which godot
godot --headless --help | head -50

# System info (inside scripts)
# OS.get_name(), OS.get_processor_name(), etc.
```

### Debugging in Headless Mode

Since you can't use the visual debugger, use:

```gdscript
# Print debugging
print("Debug: variable = ", variable)
print_debug("Detailed info with stack trace")
push_warning("Something might be wrong")
push_error("Something is definitely wrong")

# Assertions (halt on failure in debug builds)
assert(condition, "Error message if false")

# Check execution path
print_stack()  # Print call stack
```

View output with: `godot --headless -s res://script.gd 2>&1`
