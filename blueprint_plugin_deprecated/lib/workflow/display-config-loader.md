# Display Config Loader Protocol

This document provides a user-facing reference for display configuration resolution. The authoritative loading semantics are defined in YAML.

> **Authoritative Source:** `hiivmind-blueprint-lib/execution/display.yaml`

---

## Overview

Display configuration controls real-time output during workflow execution. This is distinct from `logging:` which writes to files—`display:` controls what appears in the terminal as the workflow runs.

```yaml
# workflow.yaml
initial_state:
  display:
    verbosity: "terse"     # Skill-specific (priority 2)

# Plugin-level: .hiivmind/blueprint/display.yaml
display:
  verbosity: "normal"      # Plugin-wide (priority 3)

# Framework defaults: fetched from lib
display:
  verbosity: "normal"      # Framework (priority 4)
```

---

## 4-Tier Priority Hierarchy

> **Source:** `hiivmind-blueprint-lib/execution/display.yaml` → `priority_hierarchy`

```
1. Runtime flags (--verbose, --quiet, --terse)   ← Highest priority
2. Workflow initial_state.display                ← Skill-specific
3. Plugin .hiivmind/blueprint/display.yaml       ← Plugin-wide
4. Remote defaults from lib (always fetched)     ← Framework defaults
```

---

## Verbosity Levels

| Level | Description | Output |
|-------|-------------|--------|
| `silent` | Minimal output | Only user prompts + final result |
| `terse` | Batched summaries | Batch summaries + user prompts + result |
| `normal` | Standard output | Node transitions + batch internal nodes (default) |
| `verbose` | Detailed output | All node details, condition evaluations |
| `debug` | Full diagnostics | Full state dumps, all internal details |

### Output Examples

**silent:**
```
? Select option: [Shows user prompt]
✓ Workflow completed successfully
```

**terse:**
```
Routing... [3 nodes] → show_main_menu
? Select option: [Shows user prompt]
Processing... [2 nodes] → success
✓ Workflow completed successfully
```

**normal:**
```
→ check_arguments
→ show_main_menu
? Select option: [Shows user prompt]
→ process_selection
→ execute_action
✓ Workflow completed successfully
```

**verbose:**
```
● Workflow State:
  - phase: "routing"
  - has_arguments: false

  Node: check_arguments → Evaluating condition: arguments != null
  - Result: false
  - Branch: on_false → show_main_menu

→ show_main_menu
? Select option: [Shows user prompt]
...
```

---

## Runtime Flag Mappings

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `display.verbosity: "verbose"` |
| `--quiet`, `-q` | `display.verbosity: "silent"` |
| `--terse` | `display.verbosity: "terse"` |
| `--debug` | `display.verbosity: "debug"` |
| `--no-batch` | `display.batch.enabled: false` |
| `--no-display` | `display.enabled: false` |

---

## Configuration Options

```yaml
display:
  enabled: true              # Master switch
  verbosity: "normal"        # silent | terse | normal | verbose | debug

  batch:
    enabled: true            # Collapse non-interactive segments
    threshold: 3             # Min nodes to trigger batching
    show_summary: true       # Show "3 nodes executed"
    show_node_list: false    # Show node IDs in summary
    expand_on_error: true    # Expand details if node fails

  show:                      # Fine-grained content filters
    workflow_state: true     # Show state at verbose+
    node_transitions: true   # Show "→ node_name" arrows
    condition_eval: false    # Show condition expressions
    branch_result: true      # Show branch decisions
    user_prompts: true       # Cannot be disabled
    tool_output: true        # Show tool execution output
    final_result: true       # Cannot be disabled
    phase_markers: false     # Show phase boundaries
    spinner_text: true       # Show activeForm text in spinner

  format:
    style: "structured"      # structured | minimal | inline
    indent: 2                # Indentation for nested output
    use_icons: true          # Use ✓ → ? icons
    timestamp: false         # Show timestamps
```

---

## Batch Mode

When enabled, consecutive non-interactive nodes are collapsed into summary lines:

```
Routing... [3 nodes] → show_main_menu
```

### Batch Breaking Conditions

Batching breaks (flushes accumulated nodes) when:

| Condition | Reason |
|-----------|--------|
| `user_prompt` node | Requires user interaction |
| Node with user-visible output | Tool output to show |
| Error occurs | Expand on error for debugging |
| `verbose` or `debug` verbosity | Detailed output requested |
| Threshold not met | Less than N consecutive nodes |

### Batch Configuration

```yaml
batch:
  enabled: true          # Master switch for batching
  threshold: 3           # Only batch when >= 3 consecutive nodes
  show_summary: true     # "3 nodes executed" vs just the routing
  show_node_list: false  # Include node IDs: "[a, b, c]"
  expand_on_error: true  # Show full details if any node fails
```

---

## Deep Merge Behavior

Configuration is merged from lowest to highest priority:

```yaml
# Framework (lowest)
display:
  verbosity: "normal"
  batch:
    enabled: true
    threshold: 3

# Plugin
display:
  verbosity: "terse"

# Skill (highest)
display:
  batch:
    threshold: 5

# Result
display:
  verbosity: "terse"           # From plugin
  batch:
    enabled: true              # From framework
    threshold: 5               # From skill
```

---

## Sub-Workflow Inheritance

Sub-workflows inherit parent's display config by default (shared state).

To override for a specific sub-workflow:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
    display:
      verbosity: "verbose"
      batch:
        enabled: false
  next_node: execute_dynamic_route
```

---

## Display vs Logging

| Aspect | `display:` | `logging:` |
|--------|-----------|-----------|
| **Purpose** | Real-time terminal output | Persistent file records |
| **When** | During execution | After execution |
| **Target** | User watching terminal | Later debugging/audit |
| **Verbosity** | silent→terse→normal→verbose→debug | error→warn→info→debug→trace |

Both can be used simultaneously:

```yaml
initial_state:
  display:
    verbosity: "terse"     # Minimal terminal output
  logging:
    level: "debug"         # Full details in log file
```

---

## Verbosity Level Details

### silent

Shows only:
- User prompts (cannot be disabled)
- Final result (cannot be disabled)

Use for production or when embedding workflows in larger processes.

### terse

Shows:
- Batch summaries for non-interactive segments
- User prompts
- Final result

Use for normal user-facing operation where feedback is helpful but verbosity is distracting.

### normal (default)

Shows:
- Node transition arrows (→ node_name)
- Batch internal nodes when threshold met
- User prompts
- Final result

Use during development or when troubleshooting basic issues.

### verbose

Shows:
- Workflow state at phase boundaries
- All node details
- Condition evaluation expressions
- Branch decisions
- No batching (all nodes shown)

Use when debugging workflow logic or unexpected routing.

### debug

Shows:
- Full state dumps at each node
- All internal details
- Interpolation steps
- Type resolution details

Use only for deep debugging of engine behavior.

---

## Validation

Valid values:
- **verbosity:** silent, terse, normal, verbose, debug
- **format.style:** structured, minimal, inline

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine overview
- **Logging Config Loader:** `lib/workflow/logging-config-loader.md` - File-based logging
- **Display Schema:** `hiivmind-blueprint-lib/schema/display-config.json` - JSON Schema
- **Display Examples:** `references/display-config-examples.md` - Usage examples
