# Logging Configuration Pattern

Layered configuration system for workflow logging with 4-tier priority override.

---

## Configuration Hierarchy

Priority from highest to lowest:

```
1. Runtime flags (--log-level=debug)           ← Immediate override
2. Workflow initial_state.logging              ← Skill-specific defaults
3. Plugin .hiivmind/blueprint/logging.yaml     ← Plugin-wide defaults
4. Remote defaults from lib (always fetched)   ← Framework defaults
```

**Resolution:** For any field, the first non-null value wins. See `lib/workflow/logging-config-loader.md` for the loading algorithm.

---

## Configuration Schema

```yaml
logging:
  enabled: true              # false to disable all logging
  level: "info"              # trace | debug | info | warn | error

  auto:
    init: true               # Auto init_log at workflow start
    finalize: true           # Auto finalize_log at endings
    write: true              # Auto write_log after finalize
    node_tracking: true      # Auto log_node for each node

  output:
    format: "yaml"           # yaml | json | markdown
    location: ".logs/"       # Relative to skill/plugin root

  retention:
    strategy: "count"        # none | days | count
    count: 10                # If strategy=count

  ci:
    format: "none"           # none | github | plain | json
```

**Schema validation:** `hiivmind-blueprint-lib/schema/logging-config.json`

---

## Level Semantics

| Level | Records |
|-------|---------|
| `error` | Errors only |
| `warn` | Errors + warnings |
| `info` | + node history, events (default) |
| `debug` | + user responses, detailed context |
| `trace` | + state changes, all mutations |

---

## Configuration Examples

### Plugin-Wide (Tier 3)

```yaml
# .hiivmind/blueprint/logging.yaml
logging:
  level: "warn"
  output:
    location: "data/logs/"
  ci:
    format: "github"
```

### Skill-Specific (Tier 2)

```yaml
# In workflow.yaml initial_state
initial_state:
  logging:
    level: "debug"
    capture:
      state_changes: true
```

---

## Sub-Workflow Inheritance

Sub-workflows inherit parent's logging config automatically. Override via `context.logging`:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    logging:
      level: "debug"    # Override for this sub-workflow
  next_node: execute_dynamic_route
```

---

## Related Documentation

- **Loading Protocol:** `lib/workflow/logging-config-loader.md`
- **Engine Integration:** `lib/workflow/engine.md`
- **Schema:** `hiivmind-blueprint-lib/schema/logging-config.json`
- **Consequence Types:** `hiivmind-blueprint-lib/consequences/core/logging.yaml`
