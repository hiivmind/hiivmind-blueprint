# Logging Config Loader Protocol

This document provides a user-facing reference for logging configuration resolution. The authoritative loading semantics are defined in YAML.

> **Authoritative Source:** `hiivmind-blueprint-lib/execution/logging.yaml`

---

## Overview

Logging configuration can be specified at multiple levels, with higher-priority levels overriding lower ones:

```yaml
# workflow.yaml
initial_state:
  logging:
    level: "debug"     # Skill-specific (priority 2)

# Plugin-level: .hiivmind/blueprint/logging.yaml
logging:
  level: "warn"        # Plugin-wide (priority 3)

# Framework defaults: fetched from lib
logging:
  level: "info"        # Framework (priority 4)
```

---

## 4-Tier Priority Hierarchy

> **Source:** `hiivmind-blueprint-lib/execution/logging.yaml` → `priority_hierarchy`

```
1. Runtime flags (--log-level=debug)           ← Highest priority
2. Workflow initial_state.logging              ← Skill-specific
3. Plugin .hiivmind/blueprint/logging.yaml     ← Plugin-wide
4. Remote defaults from lib (always fetched)   ← Framework defaults
```

---

## Runtime Flag Mappings

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `logging.level: "debug"` |
| `--quiet`, `-q` | `logging.level: "error"` |
| `--trace` | `logging.level: "trace"` |
| `--log-level=X` | `logging.level: X` |
| `--log-format=X` | `logging.output.format: X` |
| `--log-dir=X` | `logging.output.location: X` |
| `--no-log` | `logging.enabled: false` |
| `--ci` | `logging.ci.format: "github"` |

---

## Configuration Options

```yaml
logging:
  enabled: true
  level: "info"              # error | warn | info | debug | trace

  auto:
    init: true               # Auto-inject init_log
    finalize: true           # Auto-inject finalize_log
    write: true              # Auto-inject write_log
    node_tracking: true      # Auto-inject log_node after each node

  capture:
    nodes: true
    state_changes: false
    user_responses: true
    timing: true

  output:
    format: "yaml"           # yaml | json | markdown
    location: ".logs/"
    filename: "{skill_name}-{timestamp}.{ext}"

  retention:
    strategy: "count"        # none | days | count
    count: 10

  ci:
    format: "none"           # none | github | plain | json
    annotations: true
```

---

## Deep Merge Behavior

Configuration is merged from lowest to highest priority:

```yaml
# Framework (lowest)
logging:
  level: "info"
  auto:
    init: true
    node_tracking: true

# Plugin
logging:
  level: "warn"

# Skill (highest)
logging:
  auto:
    node_tracking: false

# Result
logging:
  level: "warn"              # From plugin
  auto:
    init: true               # From framework
    node_tracking: false     # From skill
```

---

## Sub-Workflow Inheritance

Sub-workflows inherit parent's logging config by default (shared state).

To override for a specific sub-workflow:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
    logging:
      level: "debug"
      auto:
        node_tracking: true
  next_node: execute_dynamic_route
```

---

## Auto-Injection

| Flag | Injects | Phase |
|------|---------|-------|
| `auto.init` | `init_log` | Initialize (Phase 1) |
| `auto.node_tracking` | `log_node` | Execute (Phase 2) |
| `auto.finalize` | `finalize_log` | Complete (Phase 3) |
| `auto.write` | `write_log` | Complete (Phase 3) |

---

## Validation

Valid values:
- **level:** error, warn, info, debug, trace
- **output.format:** yaml, json, markdown
- **retention.strategy:** none, days, count
- **ci.format:** none, github, plain, json

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine overview
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Pattern documentation
- **Logging Schema:** `hiivmind-blueprint-lib/schema/logging-config.json` - JSON Schema
