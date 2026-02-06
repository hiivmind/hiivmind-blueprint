# Output Configuration Examples

Examples of configuring workflow output (display + logging) using the unified `output` config.

> **Schema:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/schema/config/output-config.json`

---

## Default Configuration (No Configuration)

When `initial_state.output` is omitted, default settings are used:

```yaml
name: "my-skill"
version: "1.0.0"

initial_state:
  phase: "start"
  # No output config - defaults to level: normal, batch_enabled: true

nodes:
  # ...workflow nodes...
```

**Behavior:** Normal verbosity with batching enabled (threshold: 3), logging enabled.

---

## Quiet Mode for Production

Minimal feedback without losing important information:

```yaml
initial_state:
  output:
    level: "quiet"
```

**Output:**

```
Routing... [3 nodes] -> show_main_menu
? Select operation: build, validate, deploy
Processing... [2 nodes] -> success
✓ Workflow completed successfully
```

---

## Silent Mode for Automation

Maximum brevity when embedding workflows:

```yaml
initial_state:
  output:
    level: "silent"
```

**Output:**

```
? Select operation: build, validate, deploy
✓ Workflow completed successfully
```

---

## Verbose Mode for Debugging

Detailed feedback when troubleshooting:

```yaml
initial_state:
  output:
    level: "verbose"
```

**Output:**

```
● Workflow State:
  - phase: "routing"
  - has_arguments: false

  Node: check_arguments -> Evaluating condition: arguments != null && arguments.trim() != ''
  - Result: false
  - Branch: on_false -> show_main_menu

-> show_main_menu
? Select operation: build, validate, deploy

● User Response:
  - Selection: "build"
  - Handler: "build"

-> execute_build
  Node: execute_build -> Executing actions
  - Action 1: mutate_state(operation: set, field: operation)
  - Action 2: run_command(script: build.sh)

-> success
✓ Workflow completed successfully
  - operation: build
  - duration: 2.3s
```

---

## Debug Mode for Development

Full diagnostic output:

```yaml
initial_state:
  output:
    level: "debug"
```

**Output:**

```
[DEBUG] Loading workflow: decision-maker
[DEBUG] Resolved types from: hiivmind/hiivmind-blueprint-lib@v3.0.0
[DEBUG] Initialized state: { phase: "routing", flags: {}, computed: {} }

● Full State Dump:
  workflow_name: "decision-maker"
  workflow_version: "1.0.0"
  current_node: "check_arguments"
  previous_node: null
  interface: "claude_code"
  flags: {}
  computed: {}
  user_responses: {}

[DEBUG] Evaluating node: check_arguments (type: conditional)
[DEBUG] Condition: arguments != null && arguments.trim() != ''
[DEBUG] Interpolating: arguments -> null
[DEBUG] Result: false
[DEBUG] Routing to: show_main_menu

...
```

---

## Custom Batch Threshold

Require more nodes before batching:

```yaml
initial_state:
  output:
    level: "quiet"
    batch_enabled: true
    batch_threshold: 5       # Only batch when >= 5 consecutive nodes
```

---

## Disable Batching

Show every node transition:

```yaml
initial_state:
  output:
    level: "normal"
    batch_enabled: false
```

**Output:**

```
-> check_arguments
-> validate_config
-> parse_options
-> show_main_menu
? Select operation: ...
```

---

## Disable Icons

Remove visual icons from output:

```yaml
initial_state:
  output:
    level: "normal"
    use_icons: false
```

**Output:**

```
check_arguments
show_main_menu
Select operation: build, validate, deploy
execute_build
success
Workflow completed successfully
```

---

## Combined Display and Logging

Use quiet display with detailed file logging:

```yaml
initial_state:
  output:
    level: "quiet"           # Minimal terminal output
    batch_enabled: true
    batch_threshold: 3
    log_enabled: true         # Full details in log file
    log_format: "yaml"
    log_location: ".logs/"
```

**Terminal shows:** Minimal batched output
**Log file contains:** Full execution trace with all details

---

## Disable File Logging

Terminal output only, no log files:

```yaml
initial_state:
  output:
    level: "normal"
    log_enabled: false
```

---

## CI Mode

Enable GitHub Actions integration:

```yaml
initial_state:
  output:
    level: "quiet"
    ci_mode: true
    display_enabled: false    # No terminal output in CI
    log_enabled: true
    log_format: "json"
```

**Behavior:** Emits GitHub annotations for errors and warnings. No terminal display.

---

## Plugin-Level Output Configuration

Create `.hiivmind/blueprint/output.yaml` for plugin-wide defaults:

```yaml
# .hiivmind/blueprint/output.yaml
output:
  level: "quiet"
  batch_enabled: true
  batch_threshold: 3
  use_icons: true
  log_enabled: true
  log_format: "yaml"
  log_location: ".logs/"
```

Skills can override:

```yaml
# skills/my-skill/workflow.yaml
initial_state:
  output:
    level: "verbose"   # Override for this skill only
```

---

## Runtime Flag Overrides

Users can override any output setting via command line:

```bash
# Force verbose output
/my-skill --verbose

# Force quiet output
/my-skill --quiet

# Debug mode
/my-skill --debug

# Disable file logging
/my-skill --no-log

# Disable terminal display
/my-skill --no-display

# CI mode
/my-skill --ci
```

### Flag Mapping Reference

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `output.level: verbose` |
| `--quiet`, `-q` | `output.level: quiet` |
| `--debug` | `output.level: debug` |
| `--no-log` | `output.log_enabled: false` |
| `--no-display` | `output.display_enabled: false` |
| `--ci` | `output.ci_mode: true` |

---

## Sub-Workflow Output Override

Override output for a referenced sub-workflow:

```yaml
nodes:
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v3.0.0:intent-detection
    context:
      arguments: "${arguments}"
      output:
        level: "verbose"       # More detail for intent detection
        batch_enabled: false   # Show all nodes
    next_node: execute_dynamic_route
```

---

## Level Behavior Reference

| Level | Terminal Shows | Log Captures |
|-------|--------------|--------------|
| `silent` | Prompts, final result | Errors |
| `quiet` | + batch summaries | + warnings |
| `normal` | + node transitions | + info |
| `verbose` | + condition details, branch decisions, state | + debug |
| `debug` | + interpolation steps, type resolution | + trace |

---

## Fetching Examples

```bash
# Output config schema
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/schema/config/output-config.json?ref=v3.0.0 \
  --jq '.content' | base64 -d

# Schema properties
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/schema/config/output-config.json?ref=v3.0.0 \
  --jq '.content' | base64 -d | jq '."$defs".outputConfig.properties'

# Runtime flag mappings
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/schema/config/output-config.json?ref=v3.0.0 \
  --jq '.content' | base64 -d | jq '.runtime_flags'
```

---

## Related Documentation

- **Schema:** `hiivmind-blueprint-lib/schema/config/output-config.json`
- **Execution:** `hiivmind-blueprint-lib/execution/engine_execution.yaml`
- **Prompts Config:** `references/prompts-config-examples.md`
