# Claude Code Context for Boids Project

You are Claude, running inside a sandboxed container operated by godot-agent. Your purpose is to develop a Godot 4.x mecha combat game.

## Project Location

```
/project  →  mounted from host: /Users/work/workspace/github.com/johnrdd/godot/boids
```

All file operations happen within `/project`. You cannot access files outside this mount.

---

## Development Workflow Cycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DEVELOPMENT CYCLE                                │
│                                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐           │
│  │  DESIGN  │───▶│   PLAN   │───▶│  PROMPT  │───▶│  VERIFY  │           │
│  │   DOCS   │    │  (PLANs) │    │(Milestones)   │   (API)  │           │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘           │
│                                                         │                │
│                                                         ▼                │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐           │
│  │  COMMIT  │◀───│   TEST   │◀───│IMPLEMENT │◀───│  SCOPE   │           │
│  │          │    │          │    │          │    │  CONFIRM │           │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Phase 1: Design Documents

Read design documents to understand intent before implementing:

```
/project/design/
├── mechanics/           # Gameplay systems
│   └── gameplay_loop.md
├── claude-godot-prompt.md  # AI integration notes
└── ...
```

**Always check**: Does a design doc exist for this feature? If unclear, ask.

### Phase 2: Plans (PLAN-XX)

Plans break features into numbered milestones. Format:

```
/project/prompts/PLAN-XX-feature-name.md
```

Example structure:
```markdown
# PLAN-50: Damage and Death Effects

## Milestones
- M1: Audio infrastructure
- M2: Dissolve shader
- M3: Explosion particles
- M4: Smoke trail particles
- M5: Screen shake
- M6: Projectile visual enhancements
```

### Phase 3: Milestone Prompts

Each milestone gets a detailed prompt file:

```
/project/prompts/PROMPT-YYYYMMDD-XX-MN-DESCRIPTION.md
```

Example:
```
PROMPT-20260102-50-M4-SMOKE-INTERSECTOR-PARTICLES.md
         │       │  │   └── Description
         │       │  └── Milestone number
         │       └── Plan number
         └── Date
```

**Prompt contents should include**:
- Objective and context
- Technical approach
- File locations (create/modify)
- Acceptance criteria
- API references (if known)

### Phase 4: API Verification

**Before implementing, verify Godot APIs exist:**

```bash
# Check Godot documentation
# Network access: docs.godotengine.org is allowed

# Test API in headless mode
godot --headless -s /project/tests/api_check.gd
```

**Common verification patterns**:
- Class exists: `ClassDB.class_exists("ClassName")`
- Method exists: `object.has_method("method_name")`
- Property exists: Check docs or test assignment

**If API doesn't exist**: Update the prompt with correct API, note the discrepancy.

### Phase 5: Scope Confirmation

Before implementing, confirm scope with user:
- What files will be created/modified?
- Any architectural decisions needed?
- Dependencies on other systems?

### Phase 6: Implementation

Write code following project conventions:

```
/project/scripts/       # GDScript files
/project/scenes/        # .tscn scene files
/project/shaders/       # .gdshader files
/project/sounds/        # Audio assets
/project/assets/        # Models, textures
```

**Implementation guidelines**:
- Use existing patterns from codebase
- Prefer composition over inheritance
- Use signals for loose coupling
- Add `@export` for tunable parameters
- Include brief comments for non-obvious logic

### Phase 7: Testing

```bash
# Validate project structure
godot --headless --validate-project

# Run specific test scene
godot --headless -s /project/tests/run_tests.gd

# Quick smoke test
godot --headless --quit
```

### Phase 8: Commit

Format:
```
[PLAN-XX MN] Brief description

- Detail 1
- Detail 2

🤖 Generated with Claude Code
```

---

## Project Structure

```
/project/
├── scripts/
│   ├── ai/              # AI controllers, wing coordination
│   ├── ambac/           # Mecha AMBAC movement system
│   ├── boids/           # Core boid behavior
│   ├── combat/          # Weapons, projectiles, damage
│   ├── components/      # Reusable components (death, voicelines)
│   ├── ships/           # Capital ships
│   ├── spawning/        # Boid spawning, factories
│   └── ui/              # UI controllers
├── scenes/              # Godot scene files (.tscn)
├── shaders/
│   └── effects/         # Visual effect shaders
├── sounds/
│   ├── voicelines/      # Character audio
│   └── misc/            # SFX
├── design/              # Design documents (READ THESE)
├── prompts/             # Plans and milestone prompts
├── tests/               # Test scripts
└── workflow/
    └── sandbox.md       # Sandbox security architecture
```

---

## Key Systems

### AMBAC (Active Mass Balance Auto Control)
Mecha movement system using limb repositioning for rotation without thrusters.
- `scripts/ambac/ambac_boid.gd` - Main controller
- `scripts/ambac/aim_controller.gd` - Weapon aiming

### Combat
- `scripts/combat/beam_rifle_projectile.gd` - Energy weapons
- `scripts/combat/recoilless_rifle_projectile.gd` - Ballistic weapons
- `scripts/components/death_sequence_controller.gd` - Death effects

### AI / Wing System
- `scripts/ai/intent_controller.gd` - High-level AI decisions
- `scripts/ai/wing/wing_coordinator.gd` - Squadron coordination
- `scripts/ai/wing/wing_doctrine.gd` - Tactical behaviors

---

## Conventions

### GDScript Style
```gdscript
class_name MyClass
extends Node3D

## Brief description of the node
## @tutorial: Optional link

signal something_happened(value: int)

@export_group("Category")
@export var tunable_param: float = 1.0

var _private_var: int = 0

func _ready() -> void:
    pass

func public_method() -> void:
    pass

func _private_method() -> void:
    pass
```

### Shader Style
```glsl
shader_type spatial;
render_mode blend_mix, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.5;

void vertex() {
    // Vertex manipulation
}

void fragment() {
    ALBEDO = base_color.rgb;
    ALPHA = base_color.a * intensity;
}
```

### Commit Messages
```
[PLAN-XX MN] Imperative description

- Bullet points for details
- Reference files changed

🤖 Generated with Claude Code
```

---

## Network Access

You have limited network access through proxies:

| Domain | Purpose |
|--------|---------|
| github.com | Source code, issues |
| docs.godotengine.org | Godot documentation |
| api.anthropic.com | Claude API (for your operation) |

All other domains are blocked. DNS queries for unlisted domains return NXDOMAIN.

---

## Constraints

1. **Filesystem**: Only `/project` is writable
2. **Network**: Only allowlisted domains accessible
3. **Execution**: No sudo, no package installation
4. **Resources**: Memory and CPU limited

---

## When Starting a Session

1. **Read the prompt file** if one was provided
2. **Check git status** to understand current state
3. **Review recent commits** for context
4. **Read relevant design docs** before implementing
5. **Verify APIs** before writing code that uses them

```bash
git status
git log --oneline -10
ls /project/prompts/
cat /project/design/mechanics/gameplay_loop.md
```

---

## When Completing a Session

1. **Verify changes work**: Run headless validation
2. **Check for regressions**: Review what might break
3. **Commit if requested**: Use proper format
4. **Update prompt status**: Note completion in prompt file
5. **Document lessons**: Add to CLAUDE.md if significant

---

## Lessons Learned

### Godot 4.x API Notes

| Task | Correct API |
|------|-------------|
| Particle scaling | `scale_curve` not `scale_over_lifetime` |
| Billboard shader | Modify `MODELVIEW_MATRIX` in vertex() |
| Deferred calls | `call_deferred("method")` for node tree changes |
| Bone attachment | `BoneAttachment3D` with `bone_idx` property |

### Shader Gotchas

- `VELOCITY` not available in spatial shaders for particles
- Use position-based hash for per-particle randomization
- Billboard: multiply MODELVIEW_MATRIX, preserve scale separately

### Common Patterns

**Safe node addition during physics**:
```gdscript
parent.add_child.call_deferred(child)
```

**Per-particle random value in shader**:
```glsl
float hash(vec3 p) {
    return fract(sin(dot(p, vec3(12.9898, 78.233, 45.164))) * 43758.5453);
}

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float random_value = hash(world_pos);
}
```

---

## Questions to Ask Before Implementing

1. Does a design document exist for this feature?
2. Is there an existing pattern in the codebase I should follow?
3. What Godot version APIs am I targeting? (Currently 4.3+)
4. Are there performance constraints (e.g., many particles)?
5. What's the acceptance criteria?

---

## Files to Never Modify

- `.env` files (secrets)
- `workflow/sandbox.md` (security config, modify via host)
- Anything in `.git/`

---

## Getting Help

If stuck:
1. Check Godot docs (network allowed)
2. Search codebase for similar patterns
3. Ask user for clarification
4. Note the blocker in the prompt file for next session
