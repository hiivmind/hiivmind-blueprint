# Plan: Generic Logging System for hiivmind-blueprint

## Goal

Adapt the logging patterns from hiivmind-corpus into a generic, reusable logging framework for all blueprint-based workflows. The system should be:
- **Flexible** - Work for any skill/plugin domain
- **Configurable** - Persistent defaults + runtime overrides
- **Granular** - Per-skill, per-level, per-component control

---

## Source Analysis

### From hiivmind-corpus (already implemented)

**Generic consequences (portable):**
| Consequence | Purpose | Portable? |
|-------------|---------|-----------|
| `init_log` | Initialize log structure | ✓ Generic |
| `log_node` | Record node execution | ✓ Generic |
| `log_warning` | Add warning message | ✓ Generic |
| `log_error` | Add error with details | ✓ Generic |
| `finalize_log` | Complete with timing/outcome | ✓ Generic |
| `write_log` | Write to file (yaml/json/md) | ✓ Generic |
| `apply_log_retention` | Cleanup old logs | ✓ Generic |
| `output_ci_summary` | CI-formatted output | ✓ Generic |

**Domain-specific (stay in hiivmind-corpus):**
| Consequence | Purpose | Why Domain-Specific |
|-------------|---------|---------------------|
| `log_source_status` | Record source check results | Corpus sources concept |
| `log_source_changes` | Record file changes | Corpus indexing concept |
| `log_index_update` | Record index modifications | Corpus index concept |

---

## Design: Layered Configuration

### Configuration Hierarchy (highest to lowest priority)

```
1. Runtime flags (--log-level=debug)     ← Immediate override
2. Workflow initial_state                 ← Skill-specific defaults
3. Plugin logging config                  ← Plugin-wide defaults
4. Blueprint defaults                     ← Framework defaults
```

### Configuration Schema

```yaml
# Can appear in: plugin config, workflow initial_state, or runtime
logging:
  # Master controls
  enabled: true              # false to disable all logging
  level: "info"              # trace | debug | info | warn | error

  # What to capture
  capture:
    nodes: true              # Record node_history
    state_changes: false     # Log state mutations (verbose)
    user_responses: true     # Log user prompt selections
    timing: true             # Record timestamps

  # Output configuration
  output:
    format: "yaml"           # yaml | json | markdown
    location: "data/logs/"   # Relative to skill/plugin root
    filename: "{skill}-{timestamp}.{ext}"

  # Retention policy
  retention:
    strategy: "none"         # none | days | count
    days: 30                 # If strategy=days
    count: 20                # If strategy=count

  # CI/CD integration
  ci:
    format: "none"           # none | github | plain | json
    annotations: true        # GitHub annotations for errors/warnings
```

### Level Semantics

| Level | Records | Use Case |
|-------|---------|----------|
| `error` | Errors only | Production, minimal |
| `warn` | Errors + warnings | Production default |
| `info` | + outcomes, summaries | Normal operation |
| `debug` | + node history, decisions | Development |
| `trace` | + state changes, full detail | Debugging |

---

## Implementation Plan

### Phase 1: Create Generic Logging Extension

**File:** `lib/workflow/consequences/extensions/logging.md`

Copy and adapt the 8 generic consequences from hiivmind-corpus, making them truly domain-agnostic:

1. **`init_log`** - Initialize with workflow metadata, no corpus-specific fields
2. **`log_node`** - Unchanged (already generic)
3. **`log_event`** - NEW: Generic structured event logging (replaces domain-specific log_source_*)
4. **`log_warning`** - Unchanged
5. **`log_error`** - Unchanged
6. **`finalize_log`** - Unchanged
7. **`write_log`** - Unchanged
8. **`apply_log_retention`** - Unchanged
9. **`output_ci_summary`** - Unchanged

### Phase 2: Create Logging Configuration Pattern

**File:** `lib/blueprint/patterns/logging-configuration.md`

Document the layered configuration system:
- Configuration schema with all options
- Resolution algorithm (runtime > workflow > plugin > defaults)
- Examples for each configuration level
- Integration with workflow initial_state

### Phase 3: Create Log Schema Pattern

**File:** `lib/workflow/logging-schema.md`

Generic log structure that plugins can extend:

```yaml
# Generic log structure (framework-provided)
metadata:
  workflow_name: string
  workflow_version: string
  skill_name: string
  plugin_name: string
  execution_path: string

parameters:
  # Captured from initial_state.flags

execution:
  start_time: ISO8601
  end_time: ISO8601
  duration_seconds: number
  outcome: "success" | "partial" | "error" | "cancelled"
  ending_node: string

node_history:
  - node: string
    timestamp: ISO8601
    outcome: string
    details: object

events:           # NEW: Generic extensible event log
  - type: string  # Domain-specific event type
    timestamp: ISO8601
    data: object  # Domain-specific payload

errors: []
warnings: []
summary: string

# Domain extensions go here (corpus adds sources, changes, index_updates)
```

### Phase 4: Update Existing Extensions README

**File:** `lib/workflow/consequences/extensions/README.md`

Add logging to the extension catalog and document how domains can extend the generic log structure.

### Phase 5: Add Preconditions for Logging

**File:** `lib/workflow/preconditions.md` (append)

Add logging-related preconditions:
- `log_initialized` - Check if log structure exists
- `log_level_enabled` - Check if current level >= threshold

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/workflow/consequences/extensions/logging.md` | CREATE | Generic logging consequences |
| `lib/blueprint/patterns/logging-configuration.md` | CREATE | Configuration pattern |
| `lib/workflow/logging-schema.md` | CREATE | Generic log structure |
| `lib/workflow/consequences/extensions/README.md` | MODIFY | Add logging to catalog |
| `lib/workflow/preconditions.md` | MODIFY | Add logging preconditions |

---

## Key Design Decisions

### 1. Generic Events (Primary Mechanism)

**Decision:** Use `log_event` as the primary structured event logger.

```yaml
# Generic event logging (recommended pattern)
- type: log_event
  event_type: "source_checked"
  data:
    source_id: "${source.id}"
    status: "${computed.status}"
    commits_behind: "${computed.commits_behind}"
```

**Rationale:**
- Flexible schema - no new consequence code needed per event type
- Plugins define their event vocabulary in documentation
- Type safety via convention, not enforcement
- Domain-specific consequences only needed for complex validation/logic

### 2. Configuration Resolution

**Decision:** Runtime flags always win, then cascade down.

```
get_log_config(field):
  return runtime.flags[field]
      ?? initial_state.logging[field]
      ?? plugin.logging[field]
      ?? BLUEPRINT_DEFAULTS[field]
```

### 3. Automatic Logging (Configurable Default)

**Decision:** Plugin/skill config determines the default behavior.

```yaml
# Plugin-level default (in plugin logging config)
logging:
  auto:
    init: true           # auto init_log at workflow start
    finalize: true       # auto finalize_log at endings
    write: true          # auto write_log after finalize
    node_tracking: true  # auto log_node for each node

# Skill can override
initial_state:
  logging:
    auto:
      init: false        # This skill manages its own init
```

### 4. Log Location

**Decision:** `.logs/` hidden directory (often gitignored by default).

```yaml
output:
  location: ".logs/"     # Hidden, typically gitignored
  filename: "{skill}-{timestamp}.{ext}"
```

**Rationale:**
- Hidden reduces clutter in directory listings
- Easy to gitignore: `.logs/` in plugin root
- Still accessible for debugging when needed

---

## Updated Configuration Schema

```yaml
logging:
  # Master controls
  enabled: true              # false to disable all logging
  level: "info"              # trace | debug | info | warn | error

  # Automatic behavior (configurable per-skill)
  auto:
    init: true               # Auto init_log at workflow start
    finalize: true           # Auto finalize_log at endings
    write: true              # Auto write_log after finalize
    node_tracking: true      # Auto log_node for each executed node

  # What to capture (level-aware)
  capture:
    nodes: true              # Record node_history (info+)
    state_changes: false     # Log state mutations (trace only)
    user_responses: true     # Log user prompt selections (debug+)
    timing: true             # Record timestamps (always)

  # Output configuration
  output:
    format: "yaml"           # yaml | json | markdown
    location: ".logs/"       # Hidden directory, relative to root
    filename: "{skill}-{timestamp}.{ext}"

  # Retention policy
  retention:
    strategy: "count"        # none | days | count
    days: 30                 # If strategy=days
    count: 10                # If strategy=count (sensible default)

  # CI/CD integration
  ci:
    format: "none"           # none | github | plain | json
    annotations: true        # GitHub annotations for errors/warnings
```

---

## Verification

1. **Schema validation**: New consequences match extension template structure
2. **Documentation consistency**: All consequences have parameters table, effect pseudocode
3. **Integration test**: Create minimal workflow using logging, verify output
4. **Configuration test**: Verify layered config resolution works as designed
5. **Gitignore check**: Verify `.logs/` pattern works for exclusion
