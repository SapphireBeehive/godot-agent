# Agent Task Management

## Issue Header Format (Required for PM Management)

**Only issues with this header are managed by the PM agent.** Issues without this header are ignored.

Add this YAML block at the **very top** of any issue body that should be processed by agents:

```yaml
agent_task: true
depends_on: []
```

### With Dependencies

If this task must wait for other issues to complete first:

```yaml
agent_task: true
depends_on:
  - "#81"
  - "#82"
```

The PM agent will:
- Keep this issue **blocked** (no `agent-ready` label) until ALL dependencies have `agent-complete`
- Automatically add `agent-ready` when dependencies are satisfied

### No Dependencies

If this task can start immediately:

```yaml
agent_task: true
depends_on: []
```

---

## Label System

| Label | Meaning | Who Sets It |
|-------|---------|-------------|
| `agent-ready` | Available for worker agents to claim | PM agent |
| `in-progress` | A worker agent is actively working on this | Worker agent |
| `agent-complete` | Work finished successfully, PR created | Worker agent |
| `agent-failed` | Agent encountered an error | Worker agent |

---

## Workflow

```
[Issue Created]
     │
     ▼
┌─────────────────────────────────────────┐
│ Has `agent_task: true` header?          │
└─────────────────────────────────────────┘
     │ NO → PM ignores (not an agent task)
     │ YES ↓
┌─────────────────────────────────────────┐
│ All dependencies have `agent-complete`? │
└─────────────────────────────────────────┘
     │ NO → Remains blocked (no label)
     │ YES ↓
     ▼
[PM adds `agent-ready`]
     │
     ▼
[Worker claims → `in-progress`]
     │
     ▼
[Worker completes → `agent-complete`]
     │
     ▼
[PM detects → releases dependent issues]
```

---

## Creating Agent-Ready Issues

### Template for New Agent Tasks

~~~markdown
```yaml
agent_task: true
depends_on: []
```

## Overview

[Brief description of what needs to be done]

## Requirements

- [ ] Requirement 1
- [ ] Requirement 2

## Acceptance Criteria

- [ ] Tests pass
- [ ] Code reviewed
~~~

### Template for Dependent Tasks

~~~markdown
```yaml
agent_task: true
depends_on:
  - "#123"
```

## Overview

This task depends on #123 being completed first.

[Rest of issue body...]
~~~

---

## Important Rules

1. **No header = Not an agent task** - PM will never touch it
2. **Empty depends_on `[]`** = Ready immediately when PM runs
3. **Dependencies must use issue numbers** with `#` prefix: `"#123"`
4. **All dependencies must complete** before task is released
5. **Never manually add `agent-ready`** to issues with dependencies - let PM manage it
