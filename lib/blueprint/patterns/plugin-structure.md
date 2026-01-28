# Plugin Structure Pattern

This document describes the standard directory structure for Blueprint-enabled plugins.

---

## Overview

Blueprint-enabled plugins use a consistent directory structure that aligns with the hiivmind ecosystem pattern (similar to `.hiivmind/github/` for hiivmind-pulse-gh).

---

## Directory Layout

```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Workflow execution engine (copied)
│       └── logging.yaml           # Plugin-wide logging defaults (optional)
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # Thin loader referencing engine
│       └── workflow.yaml          # Deterministic workflow definition
├── commands/
│   └── my-command/
│       ├── my-command.md
│       └── workflow.yaml          # Optional workflow for command
└── plugin.json                    # Plugin manifest
```

---

## .hiivmind/blueprint/ Directory

The `.hiivmind/blueprint/` directory contains shared Blueprint infrastructure for the plugin.

### Files

| File | Purpose |
|------|---------|
| `engine.md` | Workflow execution engine (copied from hiivmind-blueprint) |
| `logging.yaml` | Plugin-wide logging defaults (optional, see below) |

### engine.md

The workflow execution engine is copied to the plugin during generation. This ensures:

1. **Stability**: The engine version is pinned at generation time
2. **Version Control**: Changes to engine.md are tracked with the plugin

Skills reference the engine via:
```markdown
**Engine:** `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md`
```

### logging.yaml

Optional plugin-wide logging defaults. See `lib/workflow/logging-config-loader.md` for the 4-tier configuration hierarchy.

```yaml
# .hiivmind/blueprint/logging.yaml
#
# Plugin-wide logging defaults (priority 3 in the 4-tier hierarchy)
# Overrides framework defaults, overridden by skill config and runtime flags

logging:
  level: "warn"                    # Less verbose by default for this plugin
  output:
    location: "data/logs/"         # Plugin prefers data/ directory
    format: "yaml"
  retention:
    strategy: "days"
    days: 14
  ci:
    format: "github"               # Plugin runs in GitHub Actions
```

**When to use:**
- Plugin has multiple skills that should share logging settings
- Plugin needs different defaults than framework (e.g., CI integration)
- Plugin wants logs in a specific location (e.g., `data/logs/` instead of `.logs/`)

**When NOT to use:**
- Each skill has unique logging needs (use `initial_state.logging` instead)
- Framework defaults are sufficient

---

## Type Definitions

Types are fetched directly from the hiivmind-blueprint-lib repository at runtime. No local caching or bundling is required.

### Workflow Reference

Workflows reference type definitions via the `definitions` block:

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

nodes:
  my_action:
    type: action
    actions:
      - type: clone_repo          # Resolved from external definitions
        url: "${source.url}"
```

### Version Pinning

| Request | Matches | Recommendation |
|---------|---------|----------------|
| `@v2.0.0` | Exact | Production (recommended) |
| `@v2.0` | Latest v2.0.x | Development |
| `@v2` | Latest v2.x.x | Development |

Use exact versions for reproducible builds.

---

## Skill Reference Pattern

Thin loader SKILL.md files reference the engine:

```markdown
## Resources

| Resource | Path |
|----------|------|
| **Workflow** | `${CLAUDE_PLUGIN_ROOT}/skills/my-skill/workflow.yaml` |
| **Engine** | `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md` |
```

---

## Alignment with hiivmind Ecosystem

The `.hiivmind/` directory pattern is consistent across hiivmind plugins:

| Plugin | Config Directory | Purpose |
|--------|------------------|---------|
| hiivmind-pulse-gh | `.hiivmind/github/` | GitHub workspace config, cached project IDs |
| hiivmind-blueprint | `.hiivmind/blueprint/` | Workflow engine, logging config |
| hiivmind-corpus | `.hiivmind/corpus/` | (Future) Corpus-specific config |

This consistency helps users understand where plugin-specific configuration lives.

---

## Migration from Legacy Structure

Older plugins may have workflow files in `lib/workflow/`:

```
# Legacy structure
lib/
└── workflow/
    ├── schema.md
    ├── execution.md
    ├── preconditions.md
    └── consequences.md
```

The upgrade skill migrates to the new structure:

```bash
/hiivmind-blueprint upgrade
```

Changes:
1. Creates `.hiivmind/blueprint/` directory
2. Copies engine.md to `.hiivmind/blueprint/engine.md`
3. Updates SKILL.md references

---

## Related Documentation

- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - External type resolution protocol
- **Workflow Engine:** `lib/workflow/engine.md` - Execution semantics
- **Type Loader:** `lib/workflow/type-loader.md` - Type loading protocol
- **Logging Config Loader:** `lib/workflow/logging-config-loader.md` - Logging configuration resolution
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Logging configuration options
- **Generate Skill:** `skills/hiivmind-blueprint-generate/SKILL.md` - Creates this structure
- **Upgrade Skill:** `skills/hiivmind-blueprint-upgrade/SKILL.md` - Updates versions
