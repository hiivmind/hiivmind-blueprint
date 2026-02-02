# Getting Started with hiivmind-blueprint

Convert prose-based Claude Code skills to deterministic YAML workflows.

## Prerequisites

- Claude Code CLI installed
- A target plugin with SKILL.md files to convert

## Installation

hiivmind-blueprint is a Claude Code plugin. Clone or install it to your plugins directory:

```bash
# Clone the repository
cd ~/.claude/plugins  # or your plugins location
git clone https://github.com/hiivmind/hiivmind-blueprint.git
```

## Basic Workflow

### 1. Discover Skills

Find skills that can be converted:

```
/hiivmind-blueprint discover
```

This scans for SKILL.md files and reports:
- Conversion status (converted, needs conversion)
- Complexity classification
- Recommended approach

### 2. Analyze a Skill

Deep analysis of a SKILL.md:

```
/hiivmind-blueprint analyze path/to/skills/my-skill/SKILL.md
```

Output includes:
- Phase breakdown
- Action detection
- Conditional mapping
- State variable tracking
- Complexity score

### 3. Convert to Workflow

Generate workflow.yaml from analysis:

```
/hiivmind-blueprint convert
```

This creates:
- `workflow.yaml` - Deterministic workflow definition
- Thin `SKILL.md` - Minimal loader that executes the workflow

### 4. Generate Files

Write files to disk:

```
/hiivmind-blueprint generate
```

Creates:
- `skills/my-skill/workflow.yaml`
- `skills/my-skill/SKILL.md` (thin loader)
- `.hiivmind/blueprint/engine.md` (workflow engine)

### 5. Validate

Verify the workflow is correct:

```
/hiivmind-blueprint validate path/to/workflow.yaml
```

Checks:
- JSON Schema compliance
- Referential integrity (all transitions valid)
- Graph analysis (no orphans, no dead ends)
- Type validation (known consequences/preconditions)

## Gateway Commands

For plugins with multiple skills, create a gateway:

```
/hiivmind-blueprint gateway
```

This generates:
- Gateway command with 3VL intent routing
- `intent-mapping.yaml` for flag/rule configuration

## Skill Reference

| Skill | When to Use |
|-------|-------------|
| `discover` | Find skills, check status |
| `analyze` | Deep analysis of SKILL.md |
| `convert` | Create workflow from analysis |
| `generate` | Write files to disk |
| `validate` | Check workflow correctness |
| `upgrade` | Update to latest schema |
| `gateway` | Create multi-skill gateway |
| `init` | Initialize blueprint project |

## Next Steps

- [Workflow Authoring Guide](workflow-authoring-guide.md) - Manual workflow creation
- [Skill Analysis Guide](skill-analysis-guide.md) - Understanding analysis output
- [Logging Reference](logging-reference.md) - Configure workflow logging
