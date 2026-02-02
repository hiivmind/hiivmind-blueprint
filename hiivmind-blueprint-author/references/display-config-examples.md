# Display Configuration Examples

Examples of configuring workflow display verbosity and batching.

---

## Default Configuration (No Configuration)

When `initial_state.display` is omitted, default settings are used:

```yaml
name: "my-skill"
version: "1.0.0"

initial_state:
  phase: "start"
  # No display config - defaults to normal verbosity with batching

nodes:
  # ...workflow nodes...
```

**Behavior:** Normal verbosity with batching enabled (threshold: 3).

---

## Terse Mode for Production

Minimal feedback without losing important information:

```yaml
initial_state:
  display:
    verbosity: "terse"
```

**Output:**

```
Routing... [3 nodes] → show_main_menu
? Select operation: build, validate, deploy
Processing... [2 nodes] → success
✓ Workflow completed successfully
```

---

## Silent Mode for Automation

Maximum brevity when embedding workflows:

```yaml
initial_state:
  display:
    verbosity: "silent"
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
  display:
    verbosity: "verbose"
```

**Output:**

```
● Workflow State:
  - phase: "routing"
  - has_arguments: false

  Node: check_arguments → Evaluating condition: arguments != null && arguments.trim() != ''
  - Result: false
  - Branch: on_false → show_main_menu

→ show_main_menu
? Select operation: build, validate, deploy

● User Response:
  - Selection: "build"
  - Handler: "build"

→ execute_build
  Node: execute_build → Executing actions
  - Action 1: set_state(operation: "build")
  - Action 2: run_build(target: "all")

→ success
✓ Workflow completed successfully
  - operation: build
  - duration: 2.3s
```

---

## Debug Mode for Development

Full diagnostic output:

```yaml
initial_state:
  display:
    verbosity: "debug"
```

**Output:**

```
[DEBUG] Loading workflow: decision-maker
[DEBUG] Resolved types from: hiivmind/hiivmind-blueprint-lib@v2.1.0
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
[DEBUG] Interpolating: arguments → null
[DEBUG] Result: false
[DEBUG] Routing to: show_main_menu

...
```

---

## Custom Batch Threshold

Require more nodes before batching:

```yaml
initial_state:
  display:
    verbosity: "terse"
    batch:
      enabled: true
      threshold: 5           # Only batch when >= 5 consecutive nodes
```

---

## Disable Batching

Show every node transition:

```yaml
initial_state:
  display:
    verbosity: "normal"
    batch:
      enabled: false
```

**Output:**

```
→ check_arguments
→ validate_config
→ parse_options
→ show_main_menu
? Select operation: ...
```

---

## Batch with Node List

Show which nodes were batched:

```yaml
initial_state:
  display:
    verbosity: "terse"
    batch:
      enabled: true
      threshold: 3
      show_node_list: true   # Include node IDs
```

**Output:**

```
Routing... [check_arguments, validate_config, parse_options] → show_main_menu
```

---

## Fine-Grained Show Controls

Customize what's displayed at each verbosity level:

```yaml
initial_state:
  display:
    verbosity: "normal"
    show:
      workflow_state: false      # Don't show state dumps
      node_transitions: true     # Show → arrows
      condition_eval: true       # Show condition expressions
      branch_result: true        # Show branch decisions
      phase_markers: true        # Show phase boundaries
      spinner_text: true         # Show spinner during long operations
```

**Output:**

```
── Phase: Initialize ──
→ check_arguments
  Condition: arguments != null
  Branch: on_false → show_main_menu
→ show_main_menu
── Phase: Execute ──
? Select operation: ...
```

---

## Minimal Format Style

Reduce visual noise:

```yaml
initial_state:
  display:
    verbosity: "normal"
    format:
      style: "minimal"
      use_icons: false
      indent: 0
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

## Inline Format Style

Single-line output:

```yaml
initial_state:
  display:
    verbosity: "terse"
    format:
      style: "inline"
```

**Output:**

```
Routing [3] → show_main_menu | ? operation | Processing [2] → success | ✓ Done
```

---

## Timestamps

Add timestamps to output:

```yaml
initial_state:
  display:
    verbosity: "verbose"
    format:
      timestamp: true
```

**Output:**

```
[10:23:45.123] → check_arguments
[10:23:45.145] → show_main_menu
[10:23:47.891] ? Select operation: ...
[10:23:52.234] → execute_build
```

---

## Combined Display and Logging

Use terse display with detailed file logging:

```yaml
initial_state:
  display:
    verbosity: "terse"         # Minimal terminal output
    batch:
      enabled: true
      threshold: 3
  logging:
    enabled: true
    level: "debug"             # Full details in log file
    auto:
      init: true
      node_tracking: true
      finalize: true
      write: true
```

**Terminal shows:** Minimal batched output
**Log file contains:** Full execution trace with all details

---

## Plugin-Level Display Configuration

Create `.hiivmind/blueprint/display.yaml` for plugin-wide defaults:

```yaml
# .hiivmind/blueprint/display.yaml
display:
  verbosity: "terse"
  batch:
    enabled: true
    threshold: 3
  format:
    use_icons: true
```

Skills can override:

```yaml
# skills/my-skill/workflow.yaml
initial_state:
  display:
    verbosity: "verbose"  # Override for this skill only
```

---

## Runtime Flag Overrides

Users can override any display setting via command line:

```bash
# Force verbose output
claude --verbose /my-skill

# Force silent output
claude --quiet /my-skill

# Force terse output
claude --terse /my-skill

# Disable batching
claude --no-batch /my-skill

# Debug mode
claude --debug /my-skill
```

---

## Sub-Workflow Display Override

Override display for a referenced sub-workflow:

```yaml
nodes:
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v2.1.0:intent-detection
    context:
      arguments: "${arguments}"
      display:
        verbosity: "verbose"    # More detail for intent detection
        batch:
          enabled: false        # Show all nodes
    next_node: execute_dynamic_route
```

---

## Expand on Error

Automatically show details when an error occurs:

```yaml
initial_state:
  display:
    verbosity: "terse"
    batch:
      enabled: true
      threshold: 3
      expand_on_error: true    # Show batch contents on failure
```

**Normal output (success):**
```
Processing... [3 nodes] → success
```

**Expanded output (error):**
```
Processing... [3 nodes] ─ EXPANDED DUE TO ERROR:
  → validate_input: passed
  → check_permissions: passed
  → execute_action: FAILED
    Error: Permission denied for /etc/config
```

---

## Conditional Verbosity by Environment

Use environment-based configuration:

```yaml
# In workflow.yaml - check environment
initial_state:
  display:
    verbosity: "${env.BLUEPRINT_VERBOSITY:-normal}"
```

Or in plugin-level config:

```yaml
# .hiivmind/blueprint/display.yaml
display:
  verbosity: "${CI:-false}" == "true" ? "silent" : "normal"
```

---

## Related Documentation

- **Config Loader:** `lib/workflow/display-config-loader.md`
- **Execution:** `hiivmind-blueprint-lib/execution/display.yaml`
- **Schema:** `hiivmind-blueprint-lib/schema/display-config.json`
- **Logging Examples:** `references/logging-config-examples.md` (for file-based logging)
