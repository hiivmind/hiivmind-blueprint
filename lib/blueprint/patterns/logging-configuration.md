# Logging Configuration Pattern

Defines the layered configuration system for workflow logging. Configuration can be set at multiple levels, with higher-priority levels overriding lower ones.

---

## Configuration Hierarchy

Priority from highest to lowest:

```
1. Runtime flags (--log-level=debug)     ← Immediate override
2. Workflow initial_state                 ← Skill-specific defaults
3. Plugin logging config                  ← Plugin-wide defaults
4. Blueprint defaults                     ← Framework defaults
```

### Resolution Algorithm

```python
def get_log_config(field):
    """Resolve logging config value using priority cascade."""
    return (
        runtime.flags.logging.get(field)      # 1. Runtime override
        ?? initial_state.logging.get(field)    # 2. Skill-specific
        ?? plugin.logging.get(field)           # 3. Plugin-wide
        ?? BLUEPRINT_DEFAULTS.get(field)       # 4. Framework default
    )
```

---

## Complete Configuration Schema

```yaml
logging:
  # ─────────────────────────────────────────────────
  # Master Controls
  # ─────────────────────────────────────────────────
  enabled: true              # false to disable all logging
  level: "info"              # trace | debug | info | warn | error

  # ─────────────────────────────────────────────────
  # Automatic Behavior
  # ─────────────────────────────────────────────────
  auto:
    init: true               # Auto init_log at workflow start
    finalize: true           # Auto finalize_log at endings
    write: true              # Auto write_log after finalize
    node_tracking: true      # Auto log_node for each node

  # ─────────────────────────────────────────────────
  # Capture Settings (level-aware)
  # ─────────────────────────────────────────────────
  capture:
    nodes: true              # Record node_history (info+)
    state_changes: false     # Log state mutations (trace only)
    user_responses: true     # Log user prompt selections (debug+)
    timing: true             # Record timestamps (always)

  # ─────────────────────────────────────────────────
  # Output Configuration
  # ─────────────────────────────────────────────────
  output:
    format: "yaml"           # yaml | json | markdown
    location: ".logs/"       # Relative to skill/plugin root
    filename: "{skill_name}-{timestamp}.{ext}"

  # ─────────────────────────────────────────────────
  # Retention Policy
  # ─────────────────────────────────────────────────
  retention:
    strategy: "count"        # none | days | count
    days: 30                 # If strategy=days
    count: 10                # If strategy=count

  # ─────────────────────────────────────────────────
  # CI/CD Integration
  # ─────────────────────────────────────────────────
  ci:
    format: "none"           # none | github | plain | json
    annotations: true        # GitHub annotations for errors/warnings
```

---

## Level Semantics

| Level | Description | Records |
|-------|-------------|---------|
| `error` | Production, minimal | Errors only |
| `warn` | Production default | Errors + warnings |
| `info` | Normal operation | + node history, events, summaries |
| `debug` | Development | + user responses, detailed context |
| `trace` | Full debugging | + state changes, all mutations |

### Level Comparison

Levels form a hierarchy: `trace > debug > info > warn > error`

```python
def level_enabled(current_level, required_level):
    """Check if required_level is enabled given current_level."""
    hierarchy = ["error", "warn", "info", "debug", "trace"]
    return hierarchy.index(current_level) >= hierarchy.index(required_level)
```

---

## Configuration Examples

### 1. Blueprint Defaults (Framework Level)

These are the built-in defaults used when no other configuration exists:

```yaml
# Framework defaults (lowest priority)
logging:
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

### 2. Plugin Configuration

Plugin-wide defaults in plugin manifest or separate config:

```yaml
# .claude-plugin/logging.yaml or in plugin.json
logging:
  level: "warn"              # Less verbose for all skills
  output:
    location: "data/logs/"   # Plugin prefers data/ directory
    format: "yaml"
  retention:
    strategy: "days"
    days: 14
  ci:
    format: "github"         # Plugin runs in GitHub Actions
```

### 3. Skill-Specific Configuration

Per-skill defaults in workflow's initial_state:

```yaml
# In skill's workflow.yaml
initial_state:
  logging:
    level: "debug"           # This skill needs more detail
    auto:
      init: false            # Skill handles its own init
    capture:
      state_changes: true    # Track state for debugging
```

### 4. Runtime Overrides

User-provided flags at execution time:

```bash
# Via command line (if supported)
claude-code skill --log-level=trace --log-format=json

# Via skill invocation
/my-skill --verbose    # Maps to level: debug
/my-skill --quiet      # Maps to level: error
```

```yaml
# Mapped to runtime config
runtime:
  flags:
    logging:
      level: "trace"
      output:
        format: "json"
```

---

## Integration with Workflow

### Accessing Logging Config in Workflow

```yaml
# In consequences or preconditions
- type: log_node
  node: "${current_node.id}"
  outcome: "success"
  # Respects: get_log_config("level")
```

### Conditional Logging Based on Level

```yaml
- id: verbose_logging
  type: conditional
  preconditions:
    - type: log_level_enabled
      level: "debug"
  then: log_detailed_info
  else: skip_verbose
```

### Checking Log Initialization

```yaml
- id: ensure_logging
  type: validation-gate
  validations:
    - type: log_initialized
      error_message: "Logging not initialized. Add init_log consequence."
```

---

## Auto-Mode Details

When `logging.auto` settings are enabled, the framework injects logging consequences automatically:

### auto.init

Inserts `init_log` before the first node of the workflow:

```yaml
# Framework inserts:
- type: init_log
  workflow_name: "${workflow.id}"
  workflow_version: "${workflow.version}"
  skill_name: "${initial_state.skill_name}"
```

### auto.node_tracking

After each node completes, inserts `log_node`:

```yaml
# Framework inserts after each node:
- type: log_node
  node: "${completed_node.id}"
  outcome: "${completed_node.outcome}"
```

### auto.finalize

At any node marked with `ending: true`, inserts `finalize_log`:

```yaml
# Framework inserts at endings:
- type: finalize_log
  outcome: "${ending.outcome}"
  ending_node: "${ending.node_id}"
```

### auto.write

Immediately after `finalize_log`, inserts `write_log`:

```yaml
# Framework inserts after finalize:
- type: write_log
  format: "${get_log_config('output.format')}"
  path: "${get_log_config('output.location')}/${computed_filename}"
```

---

## Disabling Auto-Logging

Skills that need manual control can disable auto features:

```yaml
initial_state:
  logging:
    auto:
      init: false        # Skill will call init_log explicitly
      node_tracking: false   # Skill logs nodes selectively
      finalize: false    # Skill has custom finalization
      write: false       # Skill writes log at specific time
```

### When to Disable Auto-Logging

| Scenario | Disable |
|----------|---------|
| Need custom metadata in init_log | auto.init |
| Only log certain nodes | auto.node_tracking |
| Custom outcome determination | auto.finalize |
| Write log to custom location | auto.write |
| Aggregate logs across phases | auto.write |

---

## Configuration Validation

The framework validates logging configuration at workflow start:

```yaml
# Validation rules
validation:
  level:
    type: enum
    values: [error, warn, info, debug, trace]
  retention.strategy:
    type: enum
    values: [none, days, count]
  retention.days:
    required_if: retention.strategy == "days"
    type: positive_integer
  retention.count:
    required_if: retention.strategy == "count"
    type: positive_integer
  output.format:
    type: enum
    values: [yaml, json, markdown]
  ci.format:
    type: enum
    values: [none, github, plain, json]
```

---

## Common Flag Mappings

Standard CLI flags that map to logging configuration:

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `logging.level: "debug"` |
| `--quiet`, `-q` | `logging.level: "error"` |
| `--trace` | `logging.level: "trace"` |
| `--log-format=X` | `logging.output.format: X` |
| `--log-dir=X` | `logging.output.location: X` |
| `--no-log` | `logging.enabled: false` |
| `--ci` | `logging.ci.format: "github"` |

---

## Gitignore Considerations

The default `.logs/` location should typically be gitignored:

```gitignore
# In plugin's .gitignore
.logs/
```

For plugins that want logs committed (e.g., for CI artifacts):

```yaml
# Use data/ instead of .logs/
logging:
  output:
    location: "data/logs/"
```

---

## Related Documentation

- **Consequences:** `lib/workflow/consequences/core/logging.md`
- **Schema:** `lib/workflow/logging-schema.md`
- **Preconditions:** `lib/workflow/preconditions.md` - log_initialized, log_level_enabled
- **State:** `lib/workflow/state.md` - Runtime state structure
