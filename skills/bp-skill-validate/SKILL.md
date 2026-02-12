---
name: bp-skill-validate
description: >
  This skill should be used when the user asks to "validate workflow", "check workflow.yaml",
  "verify workflow structure", "lint workflow", "find workflow errors", "validate nodes",
  "check transitions", or needs to verify a workflow.yaml is correct. Triggers on
  "validate", "check workflow", "lint", "verify", "workflow errors", "broken workflow".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Validate Workflow

Comprehensive read-only validation of a workflow.yaml across 4 dimensions: schema, graph, types, and state. Reports all issues without modifying any files.

---

## Procedure Overview

```
┌──────────────────────┐
│ Phase 1: Load        │
│   Workflow            │
└──────────┬───────────┘
           │
┌──────────▼───────────┐
│ Phase 2: Select      │
│   Validation Mode    │
└──────────┬───────────┘
           │
     ┌─────┴─────┬──────────┬──────────┐
     ▼           ▼          ▼          ▼
┌─────────┐┌─────────┐┌─────────┐┌─────────┐
│ Schema  ││ Graph   ││ Types   ││ State   │
│ Phase 3 ││ Phase 4 ││ Phase 5 ││ Phase 6 │
└────┬────┘└────┬────┘└────┬────┘└────┬────┘
     └─────┬────┘──────┬───┘──────────┘
           ▼
┌──────────────────────┐
│ Phase 7: Report      │
└──────────────────────┘
```

---

## Phase 1: Load Workflow

### Step 1.1: Path Resolution

Determine the workflow.yaml to validate.

**If path was provided as argument:**

1. Read the file at the provided path.
2. If the file does not exist, report error and stop.
3. Store content in `computed.workflow_path` and proceed.

**If no path was provided:**

Present an AskUserQuestion to determine the workflow:

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "Which workflow.yaml should I validate?",
    "options": [
      {
        "id": "provide_path",
        "label": "I'll provide a path",
        "description": "Enter the path to a workflow.yaml file"
      },
      {
        "id": "search_current",
        "label": "Search current directory",
        "description": "Glob for **/workflow.yaml in the working directory"
      },
      {
        "id": "search_plugin",
        "label": "Search plugin root",
        "description": "Glob for **/workflow.yaml under the plugin root"
      }
    ]
  }
}
```

**Response handling:**

- `provide_path` -- Ask the user to enter the path, then Read it.
- `search_current` -- Use Glob for `**/workflow.yaml` in the current directory. If multiple found, present the list as a follow-up AskUserQuestion with each path as an option.
- `search_plugin` -- Use Glob for `**/workflow.yaml` under `${CLAUDE_PLUGIN_ROOT}`. If multiple found, present the list.

Store the resolved path in `computed.workflow_path`.

### Step 1.2: Parse YAML

1. Read the file at `computed.workflow_path`.
2. Parse the YAML content mentally. Store the parsed structure in `computed.workflow`.
3. Verify basic structure exists:
   - Has `name` (string)
   - Has `start_node` (string)
   - Has `nodes` (map)
   - Has `endings` (map)
4. If any of these are missing, record as a fatal schema error and stop validation (the file is not a valid workflow.yaml).

Store the full parsed workflow in `computed.workflow`.

---

## Phase 2: Select Validation Mode

Before running validation phases, ask which dimensions to check:

```json
{
  "questions": [{
    "question": "Which validation dimensions should I check?",
    "header": "Validation Mode Selection",
    "options": [
      {
        "label": "All dimensions",
        "description": "Schema + Graph + Types + State (recommended)"
      },
      {
        "label": "Schema only",
        "description": "Field requirements, node structure, version compatibility"
      },
      {
        "label": "Graph only",
        "description": "Reachability, cycles, dead ends, ending paths"
      },
      {
        "label": "Types only",
        "description": "Precondition and consequence type validation"
      },
      {
        "label": "State only",
        "description": "Variable initialization, undefined references, type consistency"
      }
    ],
    "multiSelect": false
  }]
}
```

**Response handling:**

```pseudocode
if user_response == "All dimensions":
    run Phases 3, 4, 5, and 6
elif user_response == "Schema only":
    run Phase 3 only
elif user_response == "Graph only":
    run Phase 4 only
elif user_response == "Types only":
    run Phase 5 only
elif user_response == "State only":
    run Phase 6 only
```

Store the selection in `computed.validation_mode`.

Initialize issue collectors:
```
computed.validation.schema_issues = []
computed.validation.graph_issues = []
computed.validation.type_issues = []
computed.validation.state_issues = []
```

---

## Phase 3: Schema Validation

> **Pattern reference:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/schema-validation-rules.md`

### Step 3.1: Required Sections

Check that the following top-level sections exist in `computed.workflow`:

| Section | Required | Notes |
|---------|----------|-------|
| `name` | Yes | String, non-empty |
| `version` | No | Recommended; semver string |
| `description` | No | Recommended |
| `definitions` | No | Should have `source` if present |
| `definitions.source` | No | Format: `owner/repo@version` or local path |
| `entry_preconditions` | No | Array of precondition objects |
| `initial_state` | No | Map |
| `start_node` | Yes | Must reference a key in `nodes` |
| `nodes` | Yes | Map with at least 1 node |
| `endings` | Yes | Map with at least 1 ending |

**Verify start_node references a valid node:**
```pseudocode
if computed.workflow.start_node not in computed.workflow.nodes:
    append to computed.validation.schema_issues:
        severity: "error"
        dimension: "schema"
        node: "start_node"
        message: "start_node '${start_node}' does not reference a valid node"
```

### Step 3.2: Node Type Validation

For each node in `computed.workflow.nodes`, verify:

1. Node has a `type` field.
2. `type` is one of: `action`, `conditional`, `user_prompt`, `reference`.
3. If `type` is missing or invalid, record an error.

```pseudocode
VALID_NODE_TYPES = ["action", "conditional", "user_prompt", "reference"]

for node_id, node in computed.workflow.nodes:
    if "type" not in node:
        append error: "Node '${node_id}' is missing required field 'type'"
    elif node.type not in VALID_NODE_TYPES:
        append error: "Node '${node_id}' has invalid type '${node.type}'"
```

### Step 3.3: Transition Field Validation

Each node type requires specific transition fields. Validate per the rules in the schema-validation-rules pattern:

**action nodes:**
- Required: `actions` (non-empty array), `on_success`, `on_failure`
- Each transition target must reference a valid node or ending

**conditional nodes:**
- Required: `condition` (object with `type`), `branches.on_true`, `branches.on_false`
- If `audit` present, check `audit.enabled` is boolean, `audit.output` is string

**user_prompt nodes:**
- Required: `prompt.question`, `prompt.header`, one of (`prompt.options` or `prompt.options_from_state`), `on_response`
- `on_response` must have at least 1 handler
- Each handler must have `next_node`

**reference nodes:**
- Required: one of (`doc` or `workflow`), `next_node`
- If `doc`, value should be a string path
- If `workflow`, format should be `owner/repo@version:workflow-name`

For every transition target (on_success, on_failure, branches.on_true, branches.on_false, on_response.*.next_node, next_node), verify it references a key in `nodes` or `endings`:

```pseudocode
function validate_target(target, node_id, field_name):
    // Skip dynamic targets (${...} interpolation)
    if target starts with "${":
        append info: "Node '${node_id}' field '${field_name}' uses dynamic target '${target}' - cannot validate statically"
        return
    if target not in computed.workflow.nodes AND target not in computed.workflow.endings:
        append error: "Node '${node_id}' field '${field_name}' references unknown target '${target}'"
```

### Step 3.4: Schema Version Check

Detect deprecated patterns that indicate an older workflow version:

| Deprecated Pattern | Detection | Suggestion |
|-------------------|-----------|------------|
| `type: validation_gate` | Node type check | Use `type: conditional` with `audit.enabled: true` |
| Separate `output` and `logging` sections | Both `output` and `logging` at top level | Use unified `output` config (v2.4+) |
| `type: read_file` | Consequence type check | Use `type: local_file_ops` with `operation: read` |
| `type: set_state` | Consequence type check | Use `type: mutate_state` with `operation: set` |

Record deprecated patterns as warnings:
```pseudocode
if any node has type == "validation_gate":
    append warning: "Node '${node_id}' uses deprecated type 'validation_gate'. Use conditional with audit mode instead."
```

Store all issues in `computed.validation.schema_issues`.

---

## Phase 4: Graph Validation

> **Pattern reference:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/graph-validation-algorithm.md`

### Step 4.1: BFS Reachability from Start

BFS from `start_node` through all transition targets. Extract targets per node type:
- action: `[on_success, on_failure]`
- conditional: `[branches.on_true, branches.on_false]`
- user_prompt: `[on_response.*.next_node]`
- reference: `[next_node]`

Skip dynamic targets (`${...}` interpolation) -- log as info, cannot validate statically.

```pseudocode
function bfs_reachability(start_node, nodes):
    visited = {start_node}
    queue = [start_node]
    while queue is not empty:
        current = queue.pop_front()
        if current not in nodes: continue
        for target in get_all_transition_targets(current, nodes[current]):
            if target starts with "${": continue
            if target not in visited:
                visited.add(target)
                if target in nodes: queue.append(target)
    orphans = set(nodes.keys()) - visited
    // Each orphan -> error: "Orphan node not reachable from start_node"
```

### Step 4.2: Ending Reachability

Build reverse adjacency list, BFS backward from all ending IDs. Nodes not reached are stranded (warning: no path to any ending).

```pseudocode
function reverse_reachability(nodes, endings):
    reverse_graph = build_reverse_adjacency(nodes)  // target -> set of predecessors
    can_reach_ending = bfs_from(endings.keys(), reverse_graph)
    stranded = set(nodes.keys()) - can_reach_ending
    // Each stranded node -> warning: "No path to any ending"
```

### Step 4.3: Cycle Detection

DFS with 3-color marking (WHITE/GRAY/BLACK). Back edge to GRAY node indicates cycle. For each cycle, check for break conditions:

- A cycle has a break if any node in it has a transition target outside the cycle
- user_prompt nodes and conditional nodes are typical break points
- Cycle without break -> error (infinite loop)
- Cycle with break -> info (bounded loop)

Full algorithm with pseudocode: see graph-validation-algorithm pattern.

### Step 4.4: Dead-End Detection

Nodes with zero valid outgoing transitions (after filtering nulls/empty strings):

```pseudocode
for node_id, node in nodes:
    targets = get_all_transition_targets(node_id, node)
    if len([t for t in targets if t]) == 0:
        append error: "Dead-end node '${node_id}' has no outgoing transitions"
```

Store all issues in `computed.validation.graph_issues`.

---

## Phase 5: Type Validation

> **Pattern reference:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/type-validation-rules.md`

### Step 5.1: Precondition Type Validation

Check all condition types in conditional nodes and entry_preconditions against the {computed.lib_version} catalog. Valid types: `state_check`, `path_check`, `tool_check`, `source_check`, `log_state`, `fetch_check`, `evaluate_expression`, `all_of`, `any_of`, `none_of`, `xor_of`, `python_module_available`, `network_available`.

```pseudocode
function validate_precondition(condition, node_id, context):
    if "type" not in condition:
        append error: "${context}: condition missing 'type'"
        return
    if condition.type not in VALID_PRECONDITIONS:
        replacement = DEPRECATED_PRECONDITIONS.get(condition.type)
        if replacement:
            append warning: "${context}: '${condition.type}' is deprecated. Use '${replacement.new_type}'."
        else:
            append error: "${context}: unknown precondition type '${condition.type}'"
    // Recurse into composite conditions (all_of, any_of, none_of, xor_of)
    if condition.type in COMPOSITE_TYPES:
        for i, sub in enumerate(condition.conditions):
            validate_precondition(sub, node_id, "${context}.conditions[${i}]")
```

Also validate `entry_preconditions` array if present.

### Step 5.2: Consequence Type Validation

Check all consequence types in action nodes and user_prompt response handlers against the {computed.lib_version} catalog. Valid types: `create_checkpoint`, `rollback_checkpoint`, `spawn_agent`, `inline`, `invoke_skill`, `evaluate`, `compute`, `display`, `init_log`, `log_node`, `log_entry`, `log_session_snapshot`, `finalize_log`, `write_log`, `apply_log_retention`, `output_ci_summary`, `set_flag`, `mutate_state`, `set_timestamp`, `compute_hash`, `evaluate_keywords`, `parse_intent_flags`, `match_3vl_rules`, `dynamic_route`, `local_file_ops`, `git_ops_local`, `web_ops`, `run_command`, `install_tool`.

```pseudocode
for each action in node.actions:
    if action.type not in VALID_CONSEQUENCES:
        replacement = DEPRECATED_CONSEQUENCES.get(action.type)
        if replacement:
            append warning: "deprecated '${action.type}', use '${replacement.new_type}' with operation: '${replacement.operation}'"
        else:
            append error: "unknown consequence type '${action.type}'"
```

Also check consequences inside `on_response.*.consequence` arrays in user_prompt nodes.

### Step 5.3: Deprecated Type Detection

Cross-reference against the full migration tables in the type-validation-rules pattern file. Key deprecated type families:

| Old Pattern | New Type | Migration |
|-------------|----------|-----------|
| `read_file`, `write_file`, `create_directory`, `delete_file` | `local_file_ops` | Add `operation` param |
| `clone_repo`, `git_pull`, `git_fetch`, `get_sha` | `git_ops_local` | Add `operation` param |
| `web_fetch`, `cache_web_content` | `web_ops` | Add `operation` param |
| `set_state`, `append_state`, `clear_state`, `merge_state` | `mutate_state` | Add `operation` param |
| `log_event`, `log_warning`, `log_error` | `log_entry` | Add `level` param |
| `flag_set`, `state_equals`, `state_not_null`, etc. | `state_check` | Add `operator` param |
| `file_exists`, `directory_exists` | `path_check` | Add `check` param |
| `tool_available`, `tool_version_gte`, etc. | `tool_check` | Add `capability` param |
| `validation_gate` (node type) | `conditional` + `audit` | Add `audit.enabled: true` |

Full deprecated type lookup tables: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/type-validation-rules.md`

Store all issues in `computed.validation.type_issues`.

---

## Phase 6: State Validation

### Step 6.1: Variable Initialization Tracking

Collect all variables from two sources:

1. **initial_state** -- Recursively walk the initial_state map, collecting all key paths (e.g., `flags.initialized`, `computed`, `output.level`).
2. **Runtime setters** -- Scan all action nodes for `mutate_state` (field), `set_flag` (flags.{flag}), and `store_as` fields. Record which node first sets each variable.

```pseudocode
initialized_vars = collect_keys_recursive(computed.workflow.initial_state)
set_vars = {}  // var_name -> first_node_that_sets_it
for each action node, scan actions for mutate_state.field, set_flag.flag, store_as
```

### Step 6.2: Undefined References

Scan all string values in the workflow for `${...}` interpolation patterns. For each reference found:

1. Skip expressions containing operators or function calls (`(`, `)`, `==`, etc.).
2. Extract the base namespace (first segment before `.`).
3. Well-known namespaces that are always valid: `computed`, `flags`, `arguments`, `user_responses`, `phase`, `prompts`, `output`, `logging`, `_semantics`, `_semantics_loaded`.
4. For any reference whose base is not a well-known namespace and not found in initialized_vars or set_vars, report a warning.

```pseudocode
all_refs = find_all_interpolations(computed.workflow)  // recursive scan for ${...}
known = initialized_vars | set(set_vars.keys()) | WELL_KNOWN_NAMESPACES
for ref in all_refs:
    if ref.base_var not in known:
        append warning: "'${ref.var_name}' at ${ref.location} may be undefined"
```

### Step 6.3: Type Consistency

Collect all `mutate_state` operations per field. Flag conflicts:

- **set + append** on same field -> warning (scalar vs. array mismatch)
- **clear + merge/append** on same field -> info (ensure ordering is correct)

```pseudocode
for each field with multiple mutate_state operations:
    if "set" in ops and "append" in ops:
        append warning: "'${field}' used as both scalar (set) and array (append)"
    if "clear" in ops and ("merge" in ops or "append" in ops):
        append info: "'${field}' is cleared and re-used -- verify ordering"
```

Store all issues in `computed.validation.state_issues`.

---

## Phase 7: Report

### Step 7.1: Severity Classification

| Severity | Meaning | Examples |
|----------|---------|---------|
| **error** | Must fix | Missing fields, orphan nodes, unknown types, invalid targets |
| **warning** | Should fix | Deprecated types, undefined variables, type mismatch |
| **info** | Observation | Dynamic targets, bounded cycles |

### Step 7.2: Per-Dimension Summary

For each dimension, count errors/warnings/info and assign status: FAIL (has errors), WARN (no errors but has warnings), PASS (clean). Display as table:

```
| Dimension | Status | Errors | Warnings | Info |
|-----------|--------|--------|----------|------|
| Schema    | PASS   | 0      | 1        | 0    |
| Graph     | FAIL   | 2      | 0        | 1    |
| Types     | WARN   | 0      | 3        | 0    |
| State     | PASS   | 0      | 0        | 2    |
```

### Step 7.3: Overall Assessment

- **FAIL** if any errors exist. Message: "${N} error(s) found. Workflow will not execute correctly."
- **WARN** if no errors but warnings exist. Message: "No errors, but ${N} warning(s) should be addressed."
- **PASS** if clean. Message: "Workflow validation passed."

### Step 7.4: Issue Details

Display each issue grouped by dimension, then by severity (errors first). Format:
- `[ERROR]` / `[WARN]` / `[INFO]` prefix
- Dimension and node (if applicable)
- Message and fix suggestion

### Step 7.5: Fix Suggestions

| Error | Fix Suggestion |
|-------|---------------|
| Orphan node | Add a transition targeting it, or remove it |
| Missing `on_success` / `on_failure` | Add the missing transition field |
| Unknown target | Add target to nodes/endings, or fix the reference |
| Deprecated type | Replace with {computed.lib_version} equivalent (see type-validation-rules pattern) |
| Invalid node type | Use one of: action, conditional, user_prompt, reference |
| No path to ending | Ensure at least one transition path reaches an ending |
| Undefined variable | Add to initial_state or ensure it is set before use |

---

## Reference Documentation

- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Consequences Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
- **Preconditions Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
- **Node Features:** `${CLAUDE_PLUGIN_ROOT}/references/node-features.md`
- **Schema Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/schema-validation-rules.md`
- **Graph Validation Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/graph-validation-algorithm.md`
- **Type Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/type-validation-rules.md`

---

## Related Skills

- **Visualize workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-visualize/SKILL.md`
- **Convert skill to workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
- **Regenerate SKILL.md from workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-regenerate/SKILL.md`
