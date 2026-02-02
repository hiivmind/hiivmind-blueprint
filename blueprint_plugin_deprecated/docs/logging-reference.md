# Logging Reference

Comprehensive reference for workflow logging configuration.

## Configuration Hierarchy

Logging configuration resolves using a 4-tier priority system:

```
1. Runtime flags (--log-level=debug)           ← Highest priority
2. Workflow initial_state.logging              ← Skill-specific
3. Plugin .hiivmind/blueprint/logging.yaml     ← Plugin-wide
4. Remote defaults from lib (always fetched)   ← Lowest priority
```

For any field, the first non-null value wins.

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

## Level Semantics

| Level | Description | Records |
|-------|-------------|---------|
| `error` | Production, minimal | Errors only |
| `warn` | Production default | Errors + warnings |
| `info` | Normal operation | + node history, events, summaries |
| `debug` | Development | + user responses, detailed context |
| `trace` | Full debugging | + state changes, all mutations |

Levels form a hierarchy: `trace > debug > info > warn > error`

## Configuration Examples

### Framework Defaults (Tier 4)

Fetched from `hiivmind-blueprint-lib/logging/defaults.yaml`:

```yaml
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
  retention:
    strategy: "count"
    count: 10
  ci:
    format: "none"
```

### Plugin-Wide Configuration (Tier 3)

Create `.hiivmind/blueprint/logging.yaml`:

```yaml
logging:
  level: "warn"              # Less verbose for all skills
  output:
    location: "data/logs/"   # Plugin prefers data/ directory
    format: "yaml"
  retention:
    strategy: "days"
    days: 14
  ci:
    format: "github"         # Enable GitHub annotations
```

### Skill-Specific Configuration (Tier 2)

In workflow's `initial_state`:

```yaml
initial_state:
  logging:
    level: "debug"           # This skill needs more detail
    auto:
      init: false            # Skill handles its own init
    capture:
      state_changes: true    # Track state for debugging
```

### Runtime Overrides (Tier 1)

```bash
# Via command line
/my-skill --verbose          # Maps to level: debug
/my-skill --quiet            # Maps to level: error
/my-skill --log-format=json  # Maps to output.format: json
```

## Auto-Mode Details

When `logging.auto.*` settings are enabled, the framework automatically injects consequences:

### auto.init

Inserts `init_log` before first node:

```yaml
- type: init_log
  workflow_name: "${workflow.id}"
  workflow_version: "${workflow.version}"
```

### auto.node_tracking

After each node completes, inserts:

```yaml
- type: log_node
  node: "${completed_node.id}"
  outcome: "${completed_node.outcome}"
```

### auto.finalize

At endings, inserts:

```yaml
- type: finalize_log
  outcome: "${ending.outcome}"
  ending_node: "${ending.node_id}"
```

### auto.write

After finalize, inserts:

```yaml
- type: write_log
  format: "${logging.output.format}"
  path: "${logging.output.location}/${computed_filename}"
```

## Disabling Auto-Logging

For manual control:

```yaml
initial_state:
  logging:
    auto:
      init: false          # Skill calls init_log explicitly
      node_tracking: false # Skill logs nodes selectively
      finalize: false      # Custom finalization
      write: false         # Write at specific time
```

### When to Disable

| Scenario | Disable |
|----------|---------|
| Custom metadata in init_log | `auto.init` |
| Log only certain nodes | `auto.node_tracking` |
| Custom outcome determination | `auto.finalize` |
| Write log to custom location | `auto.write` |
| Aggregate logs across phases | `auto.write` |

## Sub-Workflow Inheritance

Sub-workflows inherit parent's logging config. Override for specific sub-workflows:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    logging:
      level: "debug"          # More verbose for this sub-workflow
      auto:
        node_tracking: true
  next_node: execute_dynamic_route
```

### Log Nesting

Sub-workflow logs nest within parent's `node_history`:

```yaml
node_history:
  - id: validate_input
    outcome: success

  - id: detect_intent
    outcome: success
    sub_workflow:              # Nested log
      name: "intent-detection"
      node_history:
        - id: parse_flags
          outcome: success

  - id: execute_action
    outcome: success
```

## Logging Consequences

| Consequence | Description |
|-------------|-------------|
| `init_log` | Initialize log structure |
| `log_node` | Record node execution |
| `log_event` | Custom event entry |
| `log_warning` | Add warning |
| `log_error` | Add error |
| `log_session_snapshot` | Mid-session checkpoint |
| `finalize_log` | Close log with outcome |
| `write_log` | Write to file |
| `apply_log_retention` | Clean old logs |
| `output_ci_summary` | Generate CI output |

## Logging Preconditions

| Precondition | Description |
|--------------|-------------|
| `log_initialized` | Log has been initialized |
| `log_level_enabled` | Check if level permits action |
| `log_finalized` | Log has been finalized |

## Common Flag Mappings

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `logging.level: "debug"` |
| `--quiet`, `-q` | `logging.level: "error"` |
| `--trace` | `logging.level: "trace"` |
| `--log-format=X` | `logging.output.format: X` |
| `--log-dir=X` | `logging.output.location: X` |
| `--no-log` | `logging.enabled: false` |
| `--ci` | `logging.ci.format: "github"` |

## Schema Validation

```bash
SCHEMA_DIR="../hiivmind-blueprint-lib/schema"
~/.rye/shims/check-jsonschema \
  --base-uri "file://${SCHEMA_DIR}/" \
  --schemafile "$SCHEMA_DIR/logging-config.json" \
  .hiivmind/blueprint/logging.yaml
```

## Gitignore

The default `.logs/` location should be gitignored:

```gitignore
.logs/
```

For CI artifacts that should be committed, use `data/logs/` instead.

## Related Documentation

- **Loading Protocol:** `lib/workflow/logging-config-loader.md`
- **Session Tracking:** [Session Tracking Guide](session-tracking-guide.md)
- **Schema:** `hiivmind-blueprint-lib/schema/logging-config.json`
