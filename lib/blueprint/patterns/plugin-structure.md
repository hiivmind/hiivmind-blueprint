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
│       ├── types.lock             # Version pinning for types, engine, and logging
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
| `types.lock` | Version pinning for types, engine, and logging config |
| `logging.yaml` | Plugin-wide logging defaults (optional, see below) |

### engine.md

The workflow execution engine is copied to the plugin during generation. This ensures:

1. **Stability**: The engine version is pinned at generation time
2. **Offline Support**: No network required during skill execution
3. **Version Control**: Changes to engine.md are tracked with the plugin

Skills reference the engine via:
```markdown
**Engine:** `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md`
```

### types.lock

The lock file pins versions of the engine, type definitions, and logging config:

```yaml
# .hiivmind/blueprint/types.lock
schema: "1.1"                       # Bumped for logging support
generated_at: "2026-01-28T12:00:00Z"
generated_by: "hiivmind-blueprint v1.3.0"

engine:
  version: "1.3.0"
  sha256: "abc123..."
  source: "hiivmind/hiivmind-blueprint@v1.3.0"

types:
  hiivmind/hiivmind-blueprint-types:
    requested: "@v1"
    resolved: "v1.3.0"
    sha256: "def456..."
    fetched_at: "2026-01-28T05:30:00Z"

logging:                            # NEW: Logging config pins
  hiivmind/hiivmind-blueprint-types:
    resolved: "v1.0.0"
    sha256: "ghi789..."
    fetched_at: "2026-01-28T05:30:00Z"
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

## Global Cache

Types and engine versions are cached at the user level:

```
~/.claude/cache/hiivmind/blueprint/
├── types/
│   └── {owner}/
│       └── {repo}/
│           └── {version}/
│               ├── bundle.yaml
│               └── metadata.yaml
└── engine/
    └── {version}/
        └── engine.md
```

This cache is shared across all plugins to avoid redundant downloads.

---

## Version Management

### Version Resolution Rules

| Request | Matches | Behavior |
|---------|---------|----------|
| `@v1.2.3` | Exact | Use exact, never re-resolve |
| `@v1.2` | Latest v1.2.x | Re-resolve after 24h |
| `@v1` | Latest v1.x.x | Re-resolve after 24h |

### Checking for Updates

```bash
# Check for available updates
/hiivmind-blueprint upgrade --check
```

Output:
```
## Update Check

**Engine:** 1.1.0 → 1.2.0 (update available)
**Types:**
- hiivmind/hiivmind-blueprint-types: v1.3.2 → v1.4.0

Run `/hiivmind-blueprint upgrade` to apply updates.
```

### Applying Updates

```bash
# Apply all updates
/hiivmind-blueprint upgrade

# Apply only infrastructure updates (engine + types)
/hiivmind-blueprint upgrade --infra-only
```

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
3. Creates `types.lock` with pinned versions
4. Updates SKILL.md references

---

## Skill Reference Pattern

Thin loader SKILL.md files reference the engine:

```markdown
## Resources

| Resource | Path |
|----------|------|
| **Workflow** | `${CLAUDE_PLUGIN_ROOT}/skills/my-skill/workflow.yaml` |
| **Engine** | `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md` |
| **Types Lock** | `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/types.lock` |
```

---

## Alignment with hiivmind Ecosystem

The `.hiivmind/` directory pattern is consistent across hiivmind plugins:

| Plugin | Config Directory | Purpose |
|--------|------------------|---------|
| hiivmind-pulse-gh | `.hiivmind/github/` | GitHub workspace config, cached project IDs |
| hiivmind-blueprint | `.hiivmind/blueprint/` | Workflow engine, type version locks |
| hiivmind-corpus | `.hiivmind/corpus/` | (Future) Corpus-specific config |

This consistency helps users understand where plugin-specific configuration lives.

---

## Related Documentation

- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - External type resolution protocol
- **Workflow Engine:** `lib/workflow/engine.md` - Execution semantics
- **Type Loader:** `lib/workflow/type-loader.md` - Type loading protocol
- **Logging Config Loader:** `lib/workflow/logging-config-loader.md` - Logging configuration resolution
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Logging configuration options
- **Generate Skill:** `skills/hiivmind-blueprint-generate/SKILL.md` - Creates this structure
- **Upgrade Skill:** `skills/hiivmind-blueprint-upgrade/SKILL.md` - Updates versions
