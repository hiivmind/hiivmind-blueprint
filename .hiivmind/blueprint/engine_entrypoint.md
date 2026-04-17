# Hiivmind Blueprint Engine Entrypoint
## Version: 2.0.0

This document defines the standardized execution protocol used by all hiivmind-blueprint gateway commands. It provides a deterministic 3-phase model for loading local files and executing YAML workflows. All type definitions and execution semantics are read from local files — no remote fetching.

---

## Purpose

This entrypoint protocol ensures that:
1. All gateway workflows execute consistently across different plugins
2. Local engine files (definitions.yaml, config.yaml, execution-guide.md) are loaded before execution
3. Workflow files are validated against local type definitions
4. Workflow traversal follows the standardized 3-phase execution model (Initialize → Execute → Complete)

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Install |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | `brew install jq` / `apt install jq` |
| `yq` | **Mandatory** | `command -v yq` | `brew install yq` / [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |
| `gh` | Recommended | `command -v gh` | `brew install gh` / `apt install gh` |

If mandatory tools are missing, exit with error listing the install commands above.

---

## Initial State Schema

All state variables initialized here. Comments indicate which Phase.Step populates them.

```yaml
state:
  _paths:
    workflow_path: ""                    # Phase 1, Step 1.1
    workflow_available: false            # Phase 1, Step 1.1
    intent_mapping_path: ""             # Phase 1, Step 1.1
    intent_mapping_available: false     # Phase 1, Step 1.1

  _local:
    definitions_loaded: false            # Phase 2, Step 2.1
    config_loaded: false                 # Phase 2, Step 2.2
    engine_version: ""                   # Phase 2, Step 2.2

  _workflow:
    loaded: false                        # Phase 2, Step 2.3
    content: null                        # Phase 2, Step 2.3
    intent_mapping: null                 # Phase 2, Step 2.4
    arguments: {}                        # Phase 2, Step 2.5

  _execution:
    current_node: ""                     # Phase 3 (via execution-guide.md)
    previous_node: ""                    # Phase 3
    history: []                          # Phase 3
    status: "pending"                    # Phase 3
```

---

## Phase 1: Prerequisites & Path Detection

### Step 1.1: Check Prerequisites

```pseudocode
CHECK_PREREQUISITES():
  missing = []
  IF NOT command_exists("jq"):
    missing.append("jq")
  IF NOT command_exists("yq"):
    missing.append("yq")

  IF len(missing) > 0:
    FAIL "Missing required tools: " + join(missing, ", ") +
         ". Install with: brew install " + join(missing, " ") +
         " (macOS) or apt install " + join(missing, " ") + " (Linux)"
```

### Step 1.2: Detect Available Files

```pseudocode
DETECT_PATHS(workflow_dir):
  workflow_path ← workflow_dir + "/workflow.yaml"
  intent_mapping_path ← workflow_dir + "/intent-mapping.yaml"

  IF file_exists(workflow_path):
    state._paths.workflow_available ← true
    state._paths.workflow_path ← workflow_path
  ELSE:
    FAIL "workflow.yaml is required at: " + workflow_path

  IF file_exists(intent_mapping_path):
    state._paths.intent_mapping_available ← true
    state._paths.intent_mapping_path ← intent_mapping_path
  ELSE:
    state._paths.intent_mapping_available ← false
```

### Step 1.V: Verify Phase 1 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._paths.workflow_available` | `true` | Fail — workflow.yaml is required |
| `state._paths.workflow_path` | Non-empty string | Fail — path detection failed |

---

## Phase 2: Load Local Files

Load all local engine files. No remote fetching — everything is read from `.hiivmind/blueprint/` and the workflow directory.

### Step 2.1: Load Definitions

Read the local type registry:

```pseudocode
LOAD_DEFINITIONS():
  definitions_path ← ".hiivmind/blueprint/definitions.yaml"

  IF NOT file_exists(definitions_path):
    FAIL "Missing definitions file: " + definitions_path +
         ". Run bp-build to provision this file."

  definitions ← READ_YAML(definitions_path)
  state._local.definitions_loaded ← true
```

### Step 2.2: Load Config

Read engine version and build provenance:

```pseudocode
LOAD_CONFIG():
  config_path ← ".hiivmind/blueprint/config.yaml"

  IF file_exists(config_path):
    config ← READ_YAML(config_path)
    state._local.engine_version ← config.engine_version
    state._local.config_loaded ← true
  ELSE:
    # Config is optional for backward compatibility
    state._local.engine_version ← "2.0.0"
    state._local.config_loaded ← false
```

### Step 2.3: Load Workflow File

```pseudocode
LOAD_WORKFLOW():
  content ← READ_YAML(state._paths.workflow_path)

  # Validate required top-level fields
  required_fields ← ["name", "start_node", "nodes", "endings"]
  missing ← [f for f IN required_fields IF f NOT IN content]
  IF len(missing) > 0:
    FAIL "Workflow missing required fields: " + join(missing, ", ")

  state._workflow.content ← content
  state._workflow.loaded ← true
```

### Step 2.4: Load Intent Mapping (Gateway-Specific)

Only for gateway commands — skill invocations skip this step.

```pseudocode
LOAD_INTENT_MAPPING():
  IF state._paths.intent_mapping_available:
    content ← READ_YAML(state._paths.intent_mapping_path)
    state._workflow.intent_mapping ← content
```

### Step 2.5: Parse Arguments

Parse command-line arguments and runtime flags:

```pseudocode
PARSE_ARGUMENTS(raw_args):
  state._workflow.arguments ← PARSE(raw_args)

  # Extract runtime flags
  IF "--verbose" IN raw_args OR "-v" IN raw_args:
    state._workflow.arguments.output_level ← "verbose"
  IF "--quiet" IN raw_args OR "-q" IN raw_args:
    state._workflow.arguments.output_level ← "quiet"
  IF "--debug" IN raw_args:
    state._workflow.arguments.output_level ← "debug"
  IF "--no-log" IN raw_args:
    state._workflow.arguments.log_enabled ← false
  IF "--ci" IN raw_args:
    state._workflow.arguments.ci_mode ← true
```

### Step 2.V: Verify Phase 2 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._local.definitions_loaded` | `true` | Fail — definitions.yaml is required |
| `state._workflow.loaded` | `true` | Fail — workflow load failed |
| `state._workflow.content` | Non-null object | Fail — workflow parse failed |

---

## Phase 3: Execute

Delegate to `.hiivmind/blueprint/execution-guide.md` for the standardized 3-phase workflow model.

### Step 3.1: Delegate to Execution Guide

Read and follow `.hiivmind/blueprint/execution-guide.md`, which defines:

1. **Initialize** — Build type registry from definitions.yaml, initialize state from workflow.initial_state, check entry preconditions
2. **Execute** — Main dispatch loop: resolve current node, dispatch by type (action, conditional, user_prompt), advance to next node
3. **Complete** — Handle ending node, display result, write log if enabled

```pseudocode
EXECUTE_VIA_GUIDE():
  # The execution guide is the authoritative reference for workflow traversal.
  # Follow its 3-phase model exactly:
  #   Phase 1: Initialize (definitions + state + preconditions)
  #   Phase 2: Execute (dispatch loop)
  #   Phase 3: Complete (endings + logging)

  execution_guide_path ← ".hiivmind/blueprint/execution-guide.md"

  IF NOT file_exists(execution_guide_path):
    FAIL "Missing execution guide: " + execution_guide_path +
         ". Run bp-build to provision this file."

  # Read and follow execution-guide.md
  READ_AND_FOLLOW(execution_guide_path)
```

### Step 3.2: Gateway-Specific Behavior

During workflow execution, gateway commands have additional responsibilities:

**Intent Routing:** If `state._workflow.intent_mapping` is loaded, use it to map user input to skill intents before entering the dispatch loop.

**`invoke_skill` Consequence:** When an `invoke_skill` consequence fires during execution:

```pseudocode
HANDLE_INVOKE_SKILL(consequence, state):
  skill_name ← interpolate(consequence.skill, state)
  args ← interpolate(consequence.args, state) IF consequence.args ELSE ""

  # Use the Skill tool to invoke the matched skill
  result ← Skill(skill: skill_name, args: args)

  IF consequence.store_as:
    set_nested(state.computed, consequence.store_as, result)
```

**CI Annotations:** If `state._workflow.arguments.ci_mode` is true, emit GitHub Actions annotations at completion:

```pseudocode
EMIT_CI_ANNOTATIONS(history):
  FOR entry IN history:
    IF entry.outcome.success == false:
      EMIT "::error::" + entry.node + ": " + entry.outcome.error
    ELIF entry.outcome.warning:
      EMIT "::warning::" + entry.node + ": " + entry.outcome.warning
```

### Step 3.V: Verify Phase 3 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._execution.status` | `"completed"` | Check for errors in execution history |
| `state._execution.current_node` | In `workflow.endings` | Execution did not reach an ending |

---

## Version History

| Version | Changes |
|---------|---------|
| 1.0.0 | Initial engine entrypoint protocol (5-phase, remote fetching) |
| 2.0.0 | Rewritten as 3-phase local-only protocol. Removed remote fetching (Phases 2-3 of v1.0.0). Removed `_bootstrap` and `_semantics` state namespaces. Added `_local` namespace. Delegates execution to local execution-guide.md. |

---

## References

- **Type Definitions:** `.hiivmind/blueprint/definitions.yaml` (local)
- **Execution Guide:** `.hiivmind/blueprint/execution-guide.md` (local)
- **Engine Config:** `.hiivmind/blueprint/config.yaml` (local)
- **Authoring Guide:** `lib/patterns/authoring-guide.md` (framework source)
