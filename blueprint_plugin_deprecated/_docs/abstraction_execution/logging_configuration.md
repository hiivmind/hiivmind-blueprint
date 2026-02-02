# Logging Configuration - Distributed Model Integration

## Goal

Define how logging configuration integrates with the distributed composable workflows model, including loading protocol, engine integration, and sub-workflow inheritance.

---

## Current State

**What exists:**
- `templates/logging-config.yaml.template` - Config template with all fields
- `lib/blueprint/patterns/logging-configuration.md` - Documents 4-tier hierarchy
- `lib/consequences/definitions/core/logging.yaml` - 10 logging consequence types
- `lib/preconditions/definitions/core/logging.yaml` - 3 logging precondition types
- `lib/schema/logging-schema.json` - JSON Schema for log output

**Documented hierarchy:**
```
1. Runtime flags (--log-level=debug)     ← Highest
2. Workflow initial_state.logging        ← Skill-specific
3. Plugin logging config                 ← Plugin-wide (NOT YET SPECIFIED)
4. Blueprint defaults                    ← Framework defaults (NOT YET DISTRIBUTED)
```

**Gap identified:**
- `type-loader.md` handles distributed type definitions ✅
- `workflow-loader.md` handles distributed workflows ✅
- **NO `logging-config-loader.md`** for distributed logging config ❌

---

## Design Decisions

| Question | Decision |
|----------|----------|
| Where does plugin-level config live? | `.hiivmind/blueprint/logging.yaml` |
| Should logging config be in the bundle? | Yes, as `logging_defaults` section |
| How does auto-injection work? | Engine injects based on `auto.*` flags |
| Sub-workflow inheritance? | Inherited by default, override via `context.logging` |
| Separate bundle or same bundle? | Same bundle (bump to v1.3) |

---

## Implementation Plan

### Phase 1: Create Logging Config Loader Protocol

**File:** `lib/workflow/logging-config-loader.md`

Loading algorithm:
```
FUNCTION load_logging_config(workflow, plugin_root, runtime_flags):
    # Priority 1: Runtime flags
    runtime_config = extract_logging_from_runtime(runtime_flags)

    # Priority 2: Skill config (initial_state.logging)
    skill_config = workflow.initial_state.logging ?? {}

    # Priority 3: Plugin config (.hiivmind/blueprint/logging.yaml)
    plugin_config_path = "{plugin_root}/.hiivmind/blueprint/logging.yaml"
    IF file_exists(plugin_config_path):
        plugin_config = read_yaml(plugin_config_path)
    ELSE:
        plugin_config = {}

    # Priority 4: Framework defaults (from bundle)
    framework_config = load_framework_defaults(workflow.definitions)

    # Merge: runtime > skill > plugin > framework
    RETURN deep_merge(framework_config, plugin_config, skill_config, runtime_config)
```

Cache structure:
```
~/.claude/cache/hiivmind/blueprint/
├── types/                          # Existing
├── workflows/                      # Existing (v1.2)
├── logging/                        # NEW (v1.3)
│   └── {owner}/{repo}/{version}/
│       ├── defaults.yaml
│       └── metadata.yaml
└── engine/
```

### Phase 2: Engine Integration

**File:** `lib/workflow/engine.md`

Update initialization phase to:
1. Load and resolve logging config (call `load_logging_config`)
2. Store resolved config in `state.logging`
3. Auto-inject `init_log` if `auto.init: true`

Update execution loop to:
1. Auto-inject `log_node` after each node if `auto.node_tracking: true`
2. Auto-inject `finalize_log` at endings if `auto.finalize: true`
3. Auto-inject `write_log` after finalize if `auto.write: true`

### Phase 3: Bundle Extension

**File:** `lib/types/bundle.yaml` (bump to v1.3)

Add `logging_defaults` section:
```yaml
schema_version: "1.3"

consequences: { ... }
preconditions: { ... }
workflows: { ... }

logging_defaults:
  version: "1.0.0"
  description: "Framework-wide logging defaults"
  content:
    enabled: true
    level: "info"
    auto:
      init: true
      finalize: true
      write: true
      node_tracking: true
    capture:
      nodes: true
      state_changes: false
      user_responses: true
      timing: true
    output:
      format: "yaml"
      location: ".logs/"
      filename: "{skill_name}-{timestamp}.{ext}"
    retention:
      strategy: "count"
      count: 10
    ci:
      format: "none"
      annotations: true
```

### Phase 4: Plugin Structure Update

**File:** `lib/blueprint/patterns/plugin-structure.md`

Add `logging.yaml` to structure:
```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md
│       ├── types.lock
│       └── logging.yaml          # NEW: Plugin-wide logging defaults
├── skills/
│   └── my-skill/
│       ├── SKILL.md
│       └── workflow.yaml
```

### Phase 5: Lock File Extension

**File:** `lib/schema/types-lock-schema.json`

Add logging section:
```yaml
# .hiivmind/blueprint/types.lock
logging:
  hiivmind/hiivmind-blueprint-lib:
    resolved: "v1.0.0"
    sha256: "..."
    fetched_at: "..."
```

---

## Files to Create

| File | Purpose |
|------|---------|
| `lib/workflow/logging-config-loader.md` | Logging config loading protocol |
| `lib/schema/logging-config-schema.json` | JSON Schema for plugin logging.yaml |

## Files to Modify

| File | Change |
|------|--------|
| `lib/workflow/engine.md` | Add logging config resolution + auto-injection |
| `lib/workflow/type-loader.md` | Add logging cache structure docs |
| `lib/types/bundle.yaml` | Add `logging_defaults`, bump to v1.3 |
| `lib/blueprint/patterns/plugin-structure.md` | Add `logging.yaml` to structure |
| `lib/blueprint/patterns/logging-configuration.md` | Add distributed loading details |
| `lib/schema/types-lock-schema.json` | Add `logging` section |
| `templates/logging-config.yaml.template` | Add bundle reference comment |
| `CLAUDE.md` | Update architecture docs |

---

## Sub-Workflow Inheritance

When a `reference` node invokes a sub-workflow:

1. **Default**: Sub-workflow inherits parent's `state.logging`
2. **Override**: Pass `context.logging` to override specific fields

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
  context:
    arguments: "${arguments}"
    logging:                        # Optional override
      level: "debug"                # More verbose for this sub-workflow
      auto:
        node_tracking: true
  next_node: execute_dynamic_route
```

Sub-workflow logs are nested in parent's `node_history[].sub_workflow`.

---

## Verification

1. Create a plugin with `.hiivmind/blueprint/logging.yaml`
2. Verify cascade: runtime > skill > plugin > framework defaults
3. Verify auto-injection produces log files in `.logs/`
4. Test sub-workflow inheritance and override
5. Verify lock file pins logging version

---

## Summary

| Component | Status | Change |
|-----------|--------|--------|
| Logging config template | ✅ Exists | Add bundle reference |
| 4-tier hierarchy doc | ✅ Exists | Add distributed loading |
| Consequence types (10) | ✅ Exists | No change |
| Precondition types (3) | ✅ Exists | No change |
| Log schema | ✅ Exists | No change |
| Logging config loader | ❌ Missing | **CREATE** |
| Plugin structure update | ❌ Missing | **ADD** logging.yaml |
| Bundle logging_defaults | ❌ Missing | **ADD** to bundle v1.3 |
| Engine auto-injection | ❌ Not implemented | **ADD** to engine.md |


All tasks are completed. Let me provide a summary of the changes made.

  Summary

  I've implemented the logging configuration distributed model integration plan. Here's what was created and modified:

  New Files Created

  1. lib/workflow/logging-config-loader.md - The main protocol document defining:
    - 4-tier loading algorithm (runtime > skill > plugin > framework)
    - Runtime flag extraction mappings
    - Framework defaults loading from bundle
    - Cache structure for logging defaults
    - Plugin-level configuration discovery
    - Deep merge strategy
    - Sub-workflow inheritance and override patterns
    - Validation rules
    - Lock file support
  2. lib/schema/logging-config-schema.json - JSON Schema for validating plugin-level .hiivmind/blueprint/logging.yaml files, including:
    - loggingConfig with enabled, level, auto, capture, output, retention, ci sections
    - Conditional validation (e.g., days required when strategy is "days")
    - Examples for common configurations

  Files Modified

  3. lib/workflow/engine.md - Added logging integration:
    - Phase 1: Load logging config, initialize state.logging and state.log, auto-inject init_log
    - Phase 2: Auto-inject log_node after each node execution
    - Phase 3: Auto-inject finalize_log and write_log at endings
    - Added logging fields to State Structure documentation
    - Updated Related Documentation
  4. lib/types/bundle.yaml - Bumped to v1.3:
    - Schema version 1.2 → 1.3
    - Version 1.0.0 → 1.3.0
    - Added logging_defaults section with complete framework defaults
    - Updated stats to include logging_defaults_version
  5. lib/blueprint/patterns/plugin-structure.md - Added:
    - logging.yaml to directory layout
    - Documentation for logging.yaml file with examples
    - When to use/not use plugin-level logging config
    - Updated lock file example to schema 1.1 with logging section
  6. lib/schema/types-lock-schema.json - Extended:
    - Schema version note (1.1 adds logging)
    - New logging section for pinning logging config versions
    - Added v1.1 example with logging
  7. lib/workflow/type-loader.md - Added:
    - logging/ to cache structure documentation
    - Reference to logging-config-loader.md
  8. lib/blueprint/patterns/logging-configuration.md - Enhanced:
    - Distributed loading table
    - Bundle reference for framework defaults
    - Plugin configuration location
    - Sub-workflow inheritance section with examples
    - Log nesting documentation
    - Updated Related Documentation
  9. templates/logging-config.yaml.template - Added:
    - Priority hierarchy comment
    - References to new documentation files
  10. CLAUDE.md - Updated architecture documentation:
    - Added logging-config-loader.md to workflow section
    - Updated bundle.yaml description to v1.3 with logging_defaults
    - Added logging-config-schema.json to schema section
    - Added logging-configuration.md to patterns section
    - Updated Target Plugin Structure with logging.yaml and v1.1 lock file
    - Updated Global Cache with logging and workflows directories
    - Updated Type Inventory to v1.3.0 with logging defaults
    - Added Logging Configuration section explaining 4-tier hierarchy
    - Added logging-related cross-cutting concerns
