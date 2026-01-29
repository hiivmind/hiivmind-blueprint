# Workflow Loader Protocol

This document provides a user-facing reference for remote workflow loading. The authoritative loading semantics are defined in YAML.

> **Authoritative Source:** `hiivmind-blueprint-lib/resolution/workflow-loader.yaml`

---

## Overview

Workflows can reference reusable sub-workflows via the `reference` node type:

```yaml
# workflow.yaml
nodes:
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
    context:
      arguments: "${arguments}"
      intent_flags: "${intent_flags}"
    next_node: execute_dynamic_route
```

The workflow loader resolves these references before or during execution.

---

## Reference Format

**Pattern:** `{owner}/{repo}@{version}:{workflow-name}`

**Examples:**
- `hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection`
- `mycorp/custom-workflows@v1.0.0:validation-pipeline`

---

## Loading Process

> **Source:** `hiivmind-blueprint-lib/resolution/workflow-loader.yaml` → `loading_algorithm`

1. Parse reference to extract owner, repo, version, workflow-name
2. Construct raw GitHub URL for workflow index
3. Verify workflow exists in index
4. Fetch workflow content
5. Validate workflow and dependencies

---

## Local vs Remote References

| Parameter | Use Case |
|-----------|----------|
| `workflow:` | Remote workflow from GitHub |
| `doc:` | Local document/workflow file |

```yaml
# Remote workflow
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  next_node: next

# Local document
show_help:
  type: reference
  doc: "lib/workflows/intent-detection.yaml"
  next_node: next
```

---

## Input/Output Mapping

**Inputs:** Mapped via `context` parameter:

```yaml
context:
  arguments: "${arguments}"           # State field
  intent_flags: "${intent_flags}"     # State field
  fallback_action: "show_main_menu"   # Literal value
```

**Outputs:** Automatically available in parent state:

```yaml
# After intent-detection completes:
# - state.computed.matched_action is set
# - state.computed.intent_flags is set

# Use directly in parent:
next_action:
  type: action
  actions:
    - type: dynamic_route
      action: "${computed.matched_action}"
  on_success: "${computed.dynamic_target}"
```

---

## State Sharing

Reference nodes SHARE state with parent workflow. For isolated execution with explicit mapping, use `invoke_skill`:

| Type | State | Use Case |
|------|-------|----------|
| `reference` | Shared | Composable workflows, pattern libraries |
| `invoke_skill` | Isolated | Reusable skills, clean boundaries |

---

## Version Pinning

| Format | Behavior |
|--------|----------|
| `@v2.0.0` | Exact version (recommended) |
| `@v2.0` | Latest patch in v2.0.x |
| `@v2` | Latest minor in v2.x.x |

---

## Dynamic Routing

The `next_node` supports variable interpolation:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
  next_node: "${computed.dynamic_target}"  # Interpolated!
```

---

## Error Messages

```
Error: Workflow not found

Reference: hiivmind/hiivmind-blueprint-lib@v2.0.0:my-workflow

Available workflows in this version:
- intent-detection (v1.0.0)

Suggestions:
- Check the workflow name for typos
- Verify the workflow exists in the specified version
```

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine overview
- **Type Loader:** `lib/workflow/type-loader.md` - Type loading protocol
- **Reference Node:** `hiivmind-blueprint-lib/nodes/core/reference.yaml` - Node type definition
