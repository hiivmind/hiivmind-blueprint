# Plan: Display Verbosity Configuration for Workflow Execution

## Problem Statement

Current workflow execution outputs verbose real-time feedback for every node traversal, state update, and routing decision. Example from user transcript:

```
● Workflow State:
  - phase: "routing"
  - has_arguments: false

  Node: check_arguments → Evaluating condition: arguments != null && arguments.trim() != ''
  - Result: false
  - Branch: on_false → show_main_menu
```

This is excessive for production use. Users want:
1. A configuration option to control display verbosity
2. A "terse mode" that compresses non-interactive node traversals into single steps

## Design Summary

Add a new `display:` configuration block in `initial_state`, parallel to existing `logging:` and `prompts:` blocks.

### Key Concepts

| Concept | Description |
|---------|-------------|
| **`display:`** | New config block for real-time output (distinct from `logging:` which writes to files) |
| **Verbosity levels** | `silent` → `terse` → `normal` → `verbose` → `debug` |
| **Batch mode** | Collapse non-interactive nodes into summary lines |
| **4-tier hierarchy** | Runtime flags → skill → plugin → framework defaults |

### Verbosity Level Outputs

| Level | Output |
|-------|--------|
| `silent` | Only user prompts + final result |
| `terse` | Batch summaries + user prompts + result |
| `normal` | Node transitions + batch internal nodes (default) |
| `verbose` | All node details, condition evaluations |
| `debug` | Full state dumps, all internal details |

### Batch Mode

When enabled, consecutive non-interactive nodes collapse into:
```
Routing... [3 nodes] → show_main_menu
```

Batching breaks at:
- `user_prompt` nodes
- Nodes with user-visible output
- When `verbosity` is `verbose` or `debug`

## Implementation Plan

### Phase 1: Schema & Documentation (hiivmind-blueprint)

| File | Action | Description |
|------|--------|-------------|
| `lib/workflow/display-config-loader.md` | Create | User-facing reference (parallel to logging-config-loader.md) |
| `lib/workflow/engine.md` | Edit | Add Display Configuration summary section |
| `lib/blueprint/patterns/plugin-structure.md` | Edit | Document `display.yaml` in `.hiivmind/blueprint/` |
| `references/display-config-examples.md` | Create | Usage examples |
| `templates/display-config.yaml.template` | Create | Template for plugin/skill configs |
| `templates/workflow.yaml.template` | Edit | Add `display:` block to `initial_state` |
| `CLAUDE.md` | Edit | Add to cross-cutting concerns table |

### Phase 2: Lib Definitions (hiivmind-blueprint-lib)

| File | Action | Description |
|------|--------|-------------|
| `schema/display-config.json` | Create | JSON Schema for validation |
| `execution/display.yaml` | Create | Authoritative loading algorithm |
| Update `schema/workflow.json` | Edit | Add display to initial_state schema |

### Phase 3: Traversal Integration (hiivmind-blueprint-lib)

| File | Action | Description |
|------|--------|-------------|
| `execution/traversal.yaml` | Edit | Add batch buffer, display functions |

## Configuration Schema

```yaml
initial_state:
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
      workflow_state: true
      node_transitions: true
      condition_eval: false
      branch_result: true
      user_prompts: true       # Cannot be disabled
      tool_output: true
      final_result: true       # Cannot be disabled
      phase_markers: false
      spinner_text: true

    format:
      style: "structured"      # structured | minimal | inline
      indent: 2
      use_icons: true
      timestamp: false
```

## Runtime Flag Mappings

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `display.verbosity: "verbose"` |
| `--quiet`, `-q` | `display.verbosity: "silent"` |
| `--terse` | `display.verbosity: "terse"` |
| `--debug` | `display.verbosity: "debug"` |
| `--no-batch` | `display.batch.enabled: false` |

## Verification

1. **Schema validation**: Run `check-jsonschema` against new display-config.json
2. **Example workflows**: Update hiivmind-nexus-demo with `display: { verbosity: "terse" }`
3. **Manual test**: Execute decision-maker skill and verify reduced output:
   - `terse` should show batch summaries, user prompts, final result only
   - `silent` should show only user prompts and final result

## Files to Modify/Create

### In hiivmind-blueprint (this repo):
- `lib/workflow/display-config-loader.md` (new)
- `lib/workflow/engine.md` (edit)
- `lib/blueprint/patterns/plugin-structure.md` (edit)
- `references/display-config-examples.md` (new)
- `templates/display-config.yaml.template` (new)
- `templates/workflow.yaml.template` (edit)
- `CLAUDE.md` (edit)

### In hiivmind-blueprint-lib:
- `schema/display-config.json` (new)
- `schema/workflow.json` (edit)
- `execution/display.yaml` (new)
- `execution/traversal.yaml` (edit)

## Questions Resolved

- **Distinct from logging?** Yes - `logging:` records to files, `display:` controls real-time output
- **How does batching work?** Buffer non-interactive nodes, flush when hitting user_prompt or threshold
- **Default behavior?** `verbosity: "normal"` with batching enabled (threshold: 3)
