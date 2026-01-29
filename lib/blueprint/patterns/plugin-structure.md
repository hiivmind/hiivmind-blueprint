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
│       └── logging.yaml           # Plugin-wide logging defaults (optional)
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # Thin loader with remote execution references
│       └── workflow.yaml          # Deterministic workflow definition
├── commands/
│   └── my-command/
│       ├── my-command.md
│       └── workflow.yaml          # Optional workflow for command
└── plugin.json                    # Plugin manifest
```

**Note:** `engine.md` is no longer copied to plugins. Execution semantics are fetched from
hiivmind-blueprint-lib at runtime via raw GitHub URLs.

---

## .hiivmind/blueprint/ Directory

The `.hiivmind/blueprint/` directory contains optional shared Blueprint infrastructure for the plugin.

### Files

| File | Purpose |
|------|---------|
| `logging.yaml` | Plugin-wide logging defaults (optional, see below) |
| `display.yaml` | Plugin-wide display defaults (optional, see below) |

**Note:** `engine.md` is no longer used. Execution semantics are fetched directly from hiivmind-blueprint-lib.

### Remote Execution References

Skills reference execution semantics via raw GitHub URLs to hiivmind-blueprint-lib:

```markdown
## Execution Reference

Execution semantics from [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) (version: v2.0.0):

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/state.yaml) |
| Consequences | [consequence-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/consequence-dispatch.yaml) |
| Preconditions | [precondition-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/precondition-dispatch.yaml) |
```

This ensures:
1. **Standalone operation**: Plugins work without local lib dependencies
2. **Version alignment**: Execution version matches `definitions.source` in workflow.yaml
3. **Zero maintenance**: No local engine.md to update

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

### display.yaml

Optional plugin-wide display defaults. See `lib/workflow/display-config-loader.md` for the 4-tier configuration hierarchy.

```yaml
# .hiivmind/blueprint/display.yaml
#
# Plugin-wide display defaults (priority 3 in the 4-tier hierarchy)
# Overrides framework defaults, overridden by skill config and runtime flags

display:
  verbosity: "terse"             # Less verbose by default for this plugin
  batch:
    enabled: true
    threshold: 3
  show:
    node_transitions: true
    condition_eval: false
  format:
    use_icons: true
```

**When to use:**
- Plugin has multiple skills that should share display settings
- Plugin prefers terse output by default
- Plugin runs in environments where minimal output is preferred

**When NOT to use:**
- Each skill has unique display needs (use `initial_state.display` instead)
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

Thin loader SKILL.md files include an Execution Reference table with remote URLs:

```markdown
## Resources

| Resource | Path |
|----------|------|
| **Workflow** | `${CLAUDE_PLUGIN_ROOT}/skills/my-skill/workflow.yaml` |

## Execution Reference

Execution semantics from [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) (version: v2.0.0):

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/state.yaml) |
| ... | ... |
```

The version in the URLs should match the `definitions.source` in workflow.yaml.

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

Older plugins may have workflow files in `lib/workflow/` or `.hiivmind/blueprint/engine.md`:

```
# Legacy structure (pre-2.2.0)
lib/
└── workflow/
    ├── schema.md
    ├── execution.md
    ├── preconditions.md
    └── consequences.md

# OR
.hiivmind/
└── blueprint/
    └── engine.md          # Obsolete - now fetched from lib
```

The upgrade skill migrates to the new structure:

```bash
/hiivmind-blueprint upgrade
```

Changes:
1. Updates SKILL.md files to use remote execution URLs
2. Removes obsolete `.hiivmind/blueprint/engine.md`
3. Preserves `logging.yaml` if present

---

## Related Documentation

- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - External type resolution protocol
- **Workflow Engine:** `lib/workflow/engine.md` - Execution semantics
- **Type Loader:** `lib/workflow/type-loader.md` - Type loading protocol
- **Logging Config Loader:** `lib/workflow/logging-config-loader.md` - Logging configuration resolution
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Logging configuration options
- **Generate Skill:** `skills/hiivmind-blueprint-generate/SKILL.md` - Creates this structure
- **Upgrade Skill:** `skills/hiivmind-blueprint-upgrade/SKILL.md` - Updates versions
