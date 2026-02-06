# Hiivmind Blueprint Engine Entrypoint
## Version: 1.0.0

This document defines the standardized execution protocol used by all hiivmind-blueprint gateway commands and workflow-based skills. It provides a deterministic 5-phase model for loading external execution semantics and executing YAML workflows.

---

## Purpose

This entrypoint protocol ensures that:
1. All workflows execute consistently across different plugins
2. External library versions are bootstrapped before fetching semantics
3. Execution semantics are fetched from the correct version of hiivmind-blueprint-lib
4. Local workflow files are validated against fetched type definitions
5. Workflow traversal follows standardized 3-phase execution

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
    intent_mapping_path: ""              # Phase 1, Step 1.1
    intent_mapping_available: false      # Phase 1, Step 1.1

  _bootstrap:
    lib_version: ""                      # Phase 2, Step 2.1
    output:                              # Phase 2, Step 2.2
      level: "normal"
      display_enabled: true
      batch_enabled: true
      batch_threshold: 3
      use_icons: true
      log_enabled: true
      log_format: "yaml"
      log_location: ".logs/"
      ci_mode: false
    prompts:                             # Phase 2, Step 2.3
      interface: "auto"
      modes:
        claude_code: "interactive"
        web: "forms"
        api: "structured"
        agent: "autonomous"

  _semantics:
    bootstrap:
      phases: []                         # Phase 3, Step 3.1
      required_sections: []              # Phase 3, Step 3.1
    traversal:
      phases: []                         # Phase 3, Step 3.2
      node_types: []                     # Phase 3, Step 3.2

  _workflow:
    loaded: false                        # Phase 4, Step 4.1
    content: null                        # Phase 4, Step 4.1
    intent_mapping: null                 # Phase 4, Step 4.2
    arguments: {}                        # Phase 4, Step 4.3

  _execution:
    current_node: ""                     # Phase 5, Step 5.1
    previous_node: ""                    # Phase 5, Step 5.2
    history: []                          # Phase 5, Step 5.2
    status: "pending"                    # Phase 5, Step 5.3
```

---

## Phase 1: Initialize Paths

### Step 1.1: Detect Available Files

```pseudocode
DETECT_PATHS(workflow_dir):
  workflow_path ← workflow_dir + "/workflow.yaml"
  intent_mapping_path ← workflow_dir + "/intent-mapping.yaml"

  IF file_exists(workflow_path):
    state._paths.workflow_available ← true
    state._paths.workflow_path ← workflow_path
  ELSE:
    FAIL "workflow.yaml is required"

  IF file_exists(intent_mapping_path):
    state._paths.intent_mapping_available ← true
    state._paths.intent_mapping_path ← intent_mapping_path
  ELSE:
    state._paths.intent_mapping_available ← false
```

### Step 1.V: Verify Phase 1 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._paths.workflow_available` | `true` | Fail - workflow.yaml is required |
| `state._paths.workflow_path` | Non-empty string | Fail - path detection failed |

---

## Phase 2: Bootstrap Library Version

**Extract the library version before fetching anything else.**

### Step 2.1: Extract Version from Workflow

```bash
LIB_VERSION=$(yq '.definitions.version' "${state._paths.workflow_path}")
```

Store in state: `state._bootstrap.lib_version = "${LIB_VERSION}"`

**Do NOT parse arguments or read intent-mapping.yaml yet.**

### Step 2.2: Extract Output Config

Extract unified output configuration (logging + display) from workflow.

```bash
OUTPUT_CONFIG=$(yq '.initial_state.output // {}' "${state._paths.workflow_path}")
```

Merge with defaults:
- If workflow specifies `output`, use those values
- Fill missing fields with defaults from `output-config.json`

```pseudocode
EXTRACT_OUTPUT_CONFIG():
  workflow_output ← READ_YAML_PATH(workflow_path, '.initial_state.output')

  defaults ← {
    level: "normal",
    display_enabled: true,
    batch_enabled: true,
    batch_threshold: 3,
    use_icons: true,
    log_enabled: true,
    log_format: "yaml",
    log_location: ".logs/",
    ci_mode: false
  }

  state._bootstrap.output ← MERGE(defaults, workflow_output)
```

### Step 2.3: Extract Prompts Config

Extract user prompt execution configuration.

```bash
PROMPTS_CONFIG=$(yq '.initial_state.prompts // {}' "${state._paths.workflow_path}")
```

Merge with defaults:
- If workflow specifies `prompts`, use those values
- Fill missing fields with defaults from `prompts-config.json`

```pseudocode
EXTRACT_PROMPTS_CONFIG():
  workflow_prompts ← READ_YAML_PATH(workflow_path, '.initial_state.prompts')

  defaults ← {
    interface: "auto",
    modes: {
      claude_code: "interactive",
      web: "forms",
      api: "structured",
      agent: "autonomous"
    }
  }

  state._bootstrap.prompts ← MERGE(defaults, workflow_prompts)
```

### Step 2.V: Verify Phase 2 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._bootstrap.lib_version` | Semantic version (e.g., `v3.0.0`) | Fail - version extraction failed |
| `state._bootstrap.output.level` | One of: silent/quiet/normal/verbose/debug | Use default "normal" |
| `state._bootstrap.prompts.interface` | One of: auto/claude_code/web/api/agent | Use default "auto" |

---

## Phase 3: Fetch Execution Semantics

**MANDATORY:** Fetch execution semantics BEFORE loading local files. You cannot correctly interpret workflow.yaml without these semantics.

**Fetching Protocol (try in order):**
1. gh api (primary): `gh api repos/{owner}/{repo}/contents/{path}?ref={version} --jq '.content' | base64 -d`
2. raw URL (fallback): `https://raw.githubusercontent.com/{owner}/{repo}/{version}/{path}`

### Step 3.0: Fetch Shared Resolution Patterns

```bash
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/resolution/fetch-patterns.yaml?ref=${state._bootstrap.lib_version} \
  --jq '.content' | base64 -d
```

This loads `parse_source()` and `fetch()` primitives into context. All subsequent fetches in Phase 3 use these shared patterns.

### Step 3.1: Fetch Bootstrap & Section Registry

```bash
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/resolution/execution-loader.yaml?ref=${state._bootstrap.lib_version} \
  --jq '.content' | base64 -d | yq '{
    "phases": [.resolution.execution_loader.bootstrap.fetch_order.phases[].id],
    "required_sections": [.resolution.execution_loader.section_registry.sections | to_entries[] | select(.value.required == true) | .key]
  }'
```

**Store in state:**
- `state._semantics.bootstrap.phases` = `["bootstrap", "execution_semantics", "types", "initialize", "execute"]`
- `state._semantics.bootstrap.required_sections` = `["traversal", "state", "precondition_dispatch", "consequence_dispatch"]`

### Step 3.2: Fetch Traversal Entrypoints

```bash
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/execution/engine_execution.yaml?ref=${state._bootstrap.lib_version} \
  --jq '.content' | base64 -d | yq '{
    "phases": [.execution.traversal.phases[].id],
    "node_types": ["action", "conditional", "user_prompt", "reference"]
  }'
```

**Store in state:**
- `state._semantics.traversal.phases` = `["initialize", "execute", "complete"]`
- `state._semantics.traversal.node_types` = `["action", "conditional", "user_prompt", "reference"]`

### Step 3.V: Verify Phase 3 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._semantics.bootstrap.phases` | 5 items ending with "execute" | Retry fetch |
| `state._semantics.bootstrap.required_sections` | Exactly 4 items | Retry fetch |
| `state._semantics.traversal.phases` | `["initialize", "execute", "complete"]` | Retry fetch |

---

## Phase 4: Load Local Files

**Now that semantics are available, load and validate local files.**

### Step 4.1: Load Workflow File

1. Re-read workflow.yaml with validation per `state._semantics`
2. Validate against fetched type definitions

```pseudocode
LOAD_WORKFLOW():
  content ← READ_YAML(state._paths.workflow_path)
  VALIDATE_STRUCTURE(content, state._semantics.bootstrap.required_sections)
  state._workflow.content ← content
  state._workflow.loaded ← true
```

### Step 4.2: Load Intent Mapping (if applicable)

Only for gateways - skills may skip this step.

```pseudocode
LOAD_INTENT_MAPPING():
  IF state._paths.intent_mapping_available:
    content ← READ_YAML(state._paths.intent_mapping_path)
    state._workflow.intent_mapping ← content
```

### Step 4.3: Parse Arguments

Parse command-line arguments and flags.

```pseudocode
PARSE_ARGUMENTS(raw_args):
  state._workflow.arguments ← PARSE(raw_args)
```

### Step 4.V: Verify Phase 4 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._workflow.loaded` | `true` | Fail - workflow load failed |
| `state._workflow.content` | Non-null object | Fail - workflow parse failed |

---

## Phase 5: Execute Workflow

Follow the 3-phase model from `state._semantics.traversal.phases`.

### Step 5.1: Initialize State

Initialize state per the fetched execution semantics:

```pseudocode
INITIALIZE_EXECUTION():
  # Load workflow initial_state into execution state
  state ← MERGE(state, workflow.initial_state)

  # Use extracted output config (from Phase 2, Step 2.2)
  output_config ← state._bootstrap.output

  # Use extracted prompts config (from Phase 2, Step 2.3)
  prompts_config ← state._bootstrap.prompts

  # Validate schema and types
  VALIDATE_SCHEMA(workflow, state._semantics)

  # Check entry preconditions
  CHECK_PRECONDITIONS(workflow.start_node)

  # Set starting position
  state._execution.current_node ← workflow.start_node
  state._execution.status ← "running"
```

### Step 5.2: Execute Traversal Loop

Start at `start_node` from workflow.yaml and execute each node per `execution.traversal` pseudocode.

```pseudocode
EXECUTE_LOOP():
  LOOP:
    node ← workflow.nodes[state._execution.current_node]

    # Check for ending BEFORE dispatch
    IF state._execution.current_node IN workflow.endings:
      flush_batch()
      GOTO Step 5.3

    # Flush batch before user_prompt nodes
    IF node.type == "user_prompt":
      flush_batch()

    # Dispatch based on node type
    outcome ← dispatch_node(node)

    # Handle awaiting_input (multi-turn pause)
    IF outcome.awaiting_input:
      PAUSE execution
      RETURN

    # Record history, update position
    state._execution.history.append({ node: state._execution.current_node, outcome })
    state._execution.previous_node ← state._execution.current_node
    state._execution.current_node ← outcome.next_node
```

**Gateway-Specific:** When `invoke_skill` consequence fires, use the Skill tool to invoke the matched skill.

For `reference` nodes, load sub-workflows per `workflow-loader.yaml`.

### Step 5.3: Handle Completion

Handle workflow completion and cleanup:

```pseudocode
HANDLE_COMPLETION():
  # Finalize and write log if logging enabled
  IF logging_enabled:
    WRITE_LOG(state._execution.history)

  # Display result to user (unless display disabled)
  IF display_enabled:
    DISPLAY_RESULT(ending.type, ending.message)

  # Emit CI annotations if enabled
  IF ci_mode:
    EMIT_ANNOTATIONS(state._execution.history)

  state._execution.status ← "completed"
```

### Step 5.V: Verify Phase 5 Complete

| Field | Expected | Action if Wrong |
|-------|----------|-----------------|
| `state._execution.status` | `"completed"` | Check for errors in history |
| `state._execution.current_node` | In `workflow.endings` | Execution did not reach ending |

---

## On-Demand Detail Fetching

When dispatching a node type for the first time, fetch its specific semantics:

| Node Type | Fetch Command |
|-----------|---------------|
| `conditional` | `yq '.execution.traversal.dispatch.effect' engine_execution.yaml \| grep -A25 'CASE "conditional"'` |
| `user_prompt` | Read `nodes/core/user_prompt.yaml` from hiivmind-blueprint-lib@${lib_version} |
| `reference` | Read full `resolution/workflow-loader.yaml` for sub-workflow loading |

Alternatively, check `resolution/entrypoints.yaml` for pre-composed detail queries.

---

## Fetching Protocol Guide

### Primary: gh api with base64 decode

```bash
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/{path}?ref=${lib_version} \
  --jq '.content' | base64 -d
```

### Fallback: Raw GitHub URL

```bash
curl -sL https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/${lib_version}/{path}
```

### Error Handling

- If `gh api` fails (rate limit, auth), fall back to raw URL
- If raw URL fails (network), exit with error
- If file not found (404), exit with error indicating version mismatch

---

## Version History

| Version | Changes |
|---------|---------|
| 1.0.0 | Initial engine entrypoint protocol |

---

## References

- **Type Definitions:** [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib)
- **Execution Semantics:** `execution/engine_execution.yaml`
- **Fetch Patterns:** `resolution/fetch-patterns.yaml`
- **Bootstrap Loader:** `resolution/execution-loader.yaml`
