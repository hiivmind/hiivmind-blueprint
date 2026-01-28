# Workflow Execution Engine

This document provides a user-facing reference for workflow execution. The authoritative execution semantics are defined in YAML files within `hiivmind-blueprint-lib`.

---

## Authoritative Sources

The execution logic has been extracted to structured YAML for self-describing workflows:

| Content | Authoritative Source |
|---------|---------------------|
| Core execution loop (Phase 1-2-3) | `hiivmind-blueprint-lib/execution/traversal.yaml` |
| State structure and interpolation | `hiivmind-blueprint-lib/execution/state.yaml` |
| Consequence dispatch | `hiivmind-blueprint-lib/execution/consequence-dispatch.yaml` |
| Precondition evaluation | `hiivmind-blueprint-lib/execution/precondition-dispatch.yaml` |
| Logging configuration | `hiivmind-blueprint-lib/execution/logging.yaml` |
| Type loading protocol | `hiivmind-blueprint-lib/resolution/type-loader.yaml` |
| Workflow loading protocol | `hiivmind-blueprint-lib/resolution/workflow-loader.yaml` |
| Node type execution | `hiivmind-blueprint-lib/nodes/core/*.yaml` |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      SKILL.md (Thin Loader)                     │
│  References workflow.yaml, loads execution semantics from lib   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│               hiivmind-blueprint-lib (Self-Describing)          │
│  execution/*.yaml - Core loop, state, dispatch                  │
│  resolution/*.yaml - Type and workflow loading                  │
│  nodes/core/*.yaml - Node type execution                        │
│  consequences/*.yaml - Consequence type definitions             │
│  preconditions/*.yaml - Precondition type definitions           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Core Principle: LLM-Native Execution

This workflow engine is NOT compiled code. It's a **pattern document** that the LLM interprets directly:

| Benefit | How It Works |
|---------|--------------|
| **Extensibility** | New types require only definition files, not engine changes |
| **Self-describing** | Type definitions fully specify behavior via pseudocode effects |
| **Natural handling** | The LLM naturally handles interpolation, error recovery, tool calls |
| **Zero deployment** | Updates to types or engine apply to all skills immediately |

---

## Workflow Schema (Quick Reference)

```yaml
# Required: Workflow identity
name: "skill-name"
version: "1.0.0"
description: "Trigger description"

# Optional: External type definitions
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

# Required: Entry gate
entry_preconditions:
  - type: config_exists

# Required: Initial state
initial_state:
  phase: "start"
  flags:
    config_found: false
  computed: {}

# Required: Starting point
start_node: first_node

# Required: Workflow graph
nodes:
  first_node:
    type: action
    # ... node definition

# Required: Terminal states
endings:
  success:
    type: success
    message: "Completed successfully"
```

For complete schema details, see the `workflow.json` schema in `hiivmind-blueprint-lib/schema/`.

---

## Execution Model (Summary)

The execution follows a 3-phase model:

### Phase 1: Initialization
> **Source:** `hiivmind-blueprint-lib/execution/traversal.yaml` → `phases[0]`

1. Load workflow.yaml
2. Load type definitions (→ `resolution/type-loader.yaml`)
3. Load logging config (→ `execution/logging.yaml`)
4. Validate schema and graph
5. Check entry preconditions
6. Initialize state (→ `execution/state.yaml`)
7. Auto-inject init_log if enabled

### Phase 2: Execution Loop
> **Source:** `hiivmind-blueprint-lib/execution/traversal.yaml` → `phases[1]`

```
LOOP:
    node = workflow.nodes[current_node]
    IF current_node IN endings: GOTO Phase 3
    outcome = dispatch_node(node, types, state)
    record_history(node, outcome)
    current_node = outcome.next_node
UNTIL ending
```

### Phase 3: Completion
> **Source:** `hiivmind-blueprint-lib/execution/traversal.yaml` → `phases[2]`

1. Auto-inject finalize_log if enabled
2. Auto-inject write_log if enabled
3. Display result to user

---

## Node Types (Summary)

| Type | Purpose | Authoritative Source |
|------|---------|---------------------|
| `action` | Execute operations, route on success/failure | `nodes/core/action.yaml` |
| `conditional` | Branch on precondition, optional audit mode | `nodes/core/conditional.yaml` |
| `user_prompt` | Get user input, route on response | `nodes/core/user-prompt.yaml` |
| `reference` | Execute local doc or remote workflow | `nodes/core/reference.yaml` |
| `validation_gate` | **DEPRECATED** - Use conditional with audit | `nodes/core/validation-gate.yaml` |

---

## State Structure (Summary)

> **Source:** `hiivmind-blueprint-lib/execution/state.yaml`

```yaml
state:
  # Identity
  workflow_name: "skill-name"
  workflow_version: "1.0.0"

  # Position
  current_node: "node_id"
  previous_node: "last_node_id"

  # Runtime
  interface: "claude_code"  # or "claude_ai"

  # Data
  computed: {}         # Results from consequences
  flags: {}            # Boolean routing flags
  user_responses: {}   # Results from user_prompt nodes

  # Logging
  logging: {}          # Resolved config
  log: {}              # Log session

  # Rollback
  checkpoints: {}
  history: []
```

---

## Variable Interpolation (Summary)

> **Source:** `hiivmind-blueprint-lib/execution/state.yaml` → `interpolation`

```yaml
# State field reference
expression: "${source_type}"

# Computed value
url: "${computed.repo_url}"

# Flag check
condition: "${flags.manifest_detected}"

# User response
section: "${user_responses.select_sections}"

# Nested path
name: "${computed.config.corpus.name}"
```

---

## Consequence Dispatch (Summary)

> **Source:** `hiivmind-blueprint-lib/execution/consequence-dispatch.yaml`

Consequences are dispatched by `payload.kind`:

| Kind | Description | Examples |
|------|-------------|----------|
| `state_mutation` | Modify state directly | set_flag, set_state |
| `computation` | Evaluate and store | evaluate, parse_intent_flags |
| `tool_call` | Execute Claude tool | clone_repo, read_file |
| `composite` | Multiple sub-consequences | add_source |
| `side_effect` | Display without mutation | display_message |

---

## Precondition Evaluation (Summary)

> **Source:** `hiivmind-blueprint-lib/execution/precondition-dispatch.yaml`

Preconditions are boolean evaluations:

| Category | Types |
|----------|-------|
| Filesystem | file_exists, directory_exists |
| State | flag_set, state_equals, state_not_null |
| Composite | all_of, any_of, xor_of, none_of |
| Expression | evaluate_expression |
| Tool | tool_available |

---

## Logging Configuration (Summary)

> **Source:** `hiivmind-blueprint-lib/execution/logging.yaml`

4-tier priority hierarchy:
1. Runtime flags (`--verbose`, `--log-level`)
2. Skill config (`workflow.initial_state.logging`)
3. Plugin config (`.hiivmind/blueprint/logging.yaml`)
4. Framework defaults (from lib)

---

## Type Loading (Summary)

> **Source:** `hiivmind-blueprint-lib/resolution/type-loader.yaml`

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
  extensions:
    - mycorp/custom-types@v1.0.0
```

Types are lazy-loaded from GitHub raw URLs on first use.

---

## Workflow Loading (Summary)

> **Source:** `hiivmind-blueprint-lib/resolution/workflow-loader.yaml`

Reference nodes can load remote workflows:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
  next_node: execute_dynamic_route
```

---

## Related Documentation

- **Type Loader:** `lib/workflow/type-loader.md` - User-facing reference
- **Workflow Loader:** `lib/workflow/workflow-loader.md` - User-facing reference
- **Logging Config Loader:** `lib/workflow/logging-config-loader.md` - User-facing reference
- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - Pattern documentation
- **Intent Composition:** `lib/blueprint/patterns/intent-composition.md` - Dynamic routing patterns
