---
name: bp-maintain
description: >
  This skill should be used when the user asks to "validate workflow", "fix workflow",
  "upgrade schema", "refactor workflow", "check workflow errors", "restructure workflow",
  "migrate version", "lint workflow", "cleanup dead code", "extract subflow". Triggers on
  "validate", "fix", "upgrade", "refactor", "lint", "check", "migrate", "restructure",
  "schema", "cleanup", "broken workflow".
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion
inputs:
  - name: workflow_path
    type: string
    required: false
    description: Path to the workflow.yaml or skill directory (prompted if not provided)
outputs:
  - name: issues_found
    type: array
    description: List of issues found during diagnosis
  - name: changes_applied
    type: array
    description: List of changes applied (empty in validate-only mode)
---

# Maintain Workflow

Diagnose, validate, upgrade, and refactor existing workflow definitions. Consolidates validation
(schema, graph, types, state), version migration (2.0 to 2.4), and refactoring operations
(extract, inline, split, rename, cleanup) into a single maintenance workflow.

> **Graph Validation:** `patterns/graph-validation-algorithm.md`
> **Schema Validation:** `patterns/schema-validation-rules.md`
> **Type Validation:** `patterns/type-validation-rules.md`
> **Refactoring Operations:** `patterns/refactoring-operations.md`
> **Extract Subflow:** `patterns/extract-subflow-procedure.md`
> **Migration Table:** `patterns/migration-table.md`
> **Idempotency Guards:** `patterns/idempotency-guards.md`

---

## Overview

This skill performs three categories of maintenance on a single workflow.yaml file:

| Category | What It Does |
|----------|--------------|
| **Diagnose** | 5-dimension validation: schema, graph, types, state, blueprint — reports all issues |
| **Upgrade** | Versioned migration from 2.0 to 2.4, one step at a time, with backup and idempotency |
| **Refactor** | Structural operations: extract subflow, inline subflow, split, rename, cleanup dead code |

The skill always starts by diagnosing the workflow. Based on findings and flags, it either
stops (validate-only) or proceeds to apply upgrades and/or refactoring operations.

---

## Phase 1: Mode Detection

Parse invocation arguments to determine maintenance behavior.

### Step 1.1: Parse Flags

Inspect arguments for mode flags that control which phases execute:

```pseudocode
PARSE_MODE(args):
  computed.validate_only = false
  computed.upgrade_mode = false
  computed.upgrade_engine = false
  computed.refactor_op = null
  computed.workflow_path = null

  IF args contains "--validate-only":
    computed.validate_only = true
    # Stop after Phase 2 (Diagnose), display report, do not modify files

  IF args contains "--upgrade":
    computed.upgrade_mode = true
    # Jump to upgrade flow in Phase 4 after diagnosis

  IF args contains "--upgrade-engine":
    computed.upgrade_engine = true
    # Upgrade engine_entrypoint.md and config.yaml to v2.0

  IF args contains "--refactor <op>":
    computed.refactor_op = extract_value(args, "--refactor")
    # op must be one of: extract-subflow, inline-subflow, split, rename, cleanup
    VALID_OPS = ["extract-subflow", "inline-subflow", "split", "rename", "cleanup"]
    IF computed.refactor_op NOT IN VALID_OPS:
      DISPLAY "Unknown refactor operation: " + computed.refactor_op
      DISPLAY "Valid operations: " + join(VALID_OPS, ", ")
      EXIT

  IF args contains a bare path:
    computed.workflow_path = extract_path(args)
```

### Step 1.2: Resolve Workflow Path

If `computed.workflow_path` is not set from arguments, prompt the user:

```json
{
  "questions": [{
    "question": "Which workflow should I maintain?",
    "header": "Target Workflow",
    "multiSelect": false,
    "options": [
      {
        "label": "Provide path",
        "description": "I'll give you the path to a workflow.yaml or skill directory"
      },
      {
        "label": "Search current directory",
        "description": "Glob for **/workflow.yaml in the working directory"
      },
      {
        "label": "Search plugin skills",
        "description": "Glob for workflow files under the plugin root"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PATH_RESPONSE(response):
  SWITCH response:
    CASE "Provide path":
      # Ask follow-up for the path, then Read the file
      computed.workflow_path = user_provided_path
    CASE "Search current directory":
      files = Glob("**/workflow.yaml")
      files += Glob("**/workflows/*.yaml")
      files = filter(files, NOT contains("node_modules", ".hiivmind", "backup"))
      IF len(files) == 1:
        computed.workflow_path = files[0]
      ELIF len(files) > 1:
        # Present as follow-up AskUserQuestion
        computed.workflow_path = selected_file
      ELSE:
        DISPLAY "No workflow.yaml files found."
        EXIT
    CASE "Search plugin skills":
      files = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/workflow.yaml")
      files += Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/workflows/*.yaml")
      IF len(files) == 1:
        computed.workflow_path = files[0]
      ELIF len(files) > 1:
        computed.workflow_path = selected_file
      ELSE:
        DISPLAY "No workflow files found in plugin skills."
        EXIT
```

### Step 1.3: Handle Directory Path

If `computed.workflow_path` points to a directory (skill directory), resolve to the
workflow.yaml within it:

```pseudocode
RESOLVE_DIRECTORY(path):
  IF is_directory(path):
    # Check for workflow.yaml directly in the directory
    IF file_exists(path + "/workflow.yaml"):
      computed.workflow_path = path + "/workflow.yaml"
    # Check for workflows/ subdirectory
    ELIF directory_exists(path + "/workflows"):
      yaml_files = Glob(path + "/workflows/*.yaml")
      IF len(yaml_files) == 1:
        computed.workflow_path = yaml_files[0]
      ELIF len(yaml_files) > 1:
        # Present selection via AskUserQuestion
        computed.workflow_path = selected_file
      ELSE:
        DISPLAY "No workflow YAML files found in " + path
        EXIT
    ELSE:
      DISPLAY "No workflow.yaml found in directory: " + path
      EXIT
```

### Step 1.4: Load and Parse

Read and parse the workflow file:

```pseudocode
LOAD_WORKFLOW():
  computed.workflow_content = Read(computed.workflow_path)
  computed.workflow = parse_yaml(computed.workflow_content)

  # Verify minimal workflow structure
  required_fields = ["name", "start_node", "nodes", "endings"]
  missing = [f for f in required_fields if f NOT IN computed.workflow]
  IF len(missing) > 0:
    DISPLAY "Fatal: Missing required fields: " + join(missing, ", ")
    DISPLAY "This file is not a valid workflow.yaml."
    EXIT

  computed.workflow_name = computed.workflow.name
  computed.node_count = len(computed.workflow.nodes)
  computed.ending_count = len(computed.workflow.endings)
```

---

## Phase 2: Diagnose

Run 5-dimension validation on the loaded workflow. This phase is always executed regardless
of flags. If `computed.validate_only` is true, display the report and stop here.

Initialize issue collectors:

```pseudocode
computed.issues = {
  schema: [],
  graph: [],
  types: [],
  state: [],
  blueprint: []
}
```

### Step 2.1: Schema Validation

> **Pattern reference:** `patterns/schema-validation-rules.md`

Check structural correctness of the workflow definition:

```pseudocode
VALIDATE_SCHEMA(workflow):
  # 2.1a: Required top-level sections
  REQUIRED = {
    "name": "string, non-empty",
    "start_node": "must reference a key in nodes",
    "nodes": "map with at least 1 node",
    "endings": "map with at least 1 ending"
  }
  RECOMMENDED = ["version", "description", "definitions"]

  FOR field, constraint IN REQUIRED:
    IF field NOT IN workflow:
      append_issue("schema", "error", field, "Missing required field '" + field + "'")

  FOR field IN RECOMMENDED:
    IF field NOT IN workflow:
      append_issue("schema", "info", field, "Recommended field '" + field + "' is not present")

  # 2.1b: Verify start_node references a valid node
  IF workflow.start_node NOT IN workflow.nodes:
    append_issue("schema", "error", "start_node",
      "start_node '" + workflow.start_node + "' does not reference a valid node")

  # 2.1c: Node type validation
  VALID_NODE_TYPES = ["action", "conditional", "user_prompt"]
  FOR node_id, node IN workflow.nodes:
    IF "type" NOT IN node:
      append_issue("schema", "error", node_id, "Missing required field 'type'")
    ELIF node.type NOT IN VALID_NODE_TYPES:
      append_issue("schema", "error", node_id,
        "Invalid node type '" + node.type + "'. Valid: " + join(VALID_NODE_TYPES, ", "))

  # 2.1d: Transition field validation per node type
  FOR node_id, node IN workflow.nodes:
    IF node.type == "action":
      IF "actions" NOT IN node OR len(node.actions) == 0:
        append_issue("schema", "error", node_id, "Action node missing 'actions' array")
      IF "on_success" NOT IN node:
        append_issue("schema", "error", node_id, "Action node missing 'on_success'")
      IF "on_failure" NOT IN node:
        append_issue("schema", "error", node_id, "Action node missing 'on_failure'")
      # Validate targets
      FOR field IN ["on_success", "on_failure"]:
        IF field IN node:
          validate_target(node[field], node_id, field, workflow)

    ELIF node.type == "conditional":
      IF "condition" NOT IN node:
        append_issue("schema", "error", node_id, "Conditional node missing 'condition'")
      IF "branches" NOT IN node:
        append_issue("schema", "error", node_id, "Conditional node missing 'branches'")
      ELIF "on_true" NOT IN node.branches OR "on_false" NOT IN node.branches:
        append_issue("schema", "error", node_id,
          "Conditional branches missing 'on_true' or 'on_false'")
      FOR field IN ["on_true", "on_false"]:
        IF has_field(node, "branches." + field):
          validate_target(node.branches[field], node_id, "branches." + field, workflow)

    ELIF node.type == "user_prompt":
      IF "prompt" NOT IN node:
        append_issue("schema", "error", node_id, "User prompt node missing 'prompt'")
      ELIF "question" NOT IN node.prompt:
        append_issue("schema", "error", node_id, "Prompt missing 'question'")
      IF "on_response" NOT IN node OR len(node.on_response) == 0:
        append_issue("schema", "error", node_id, "User prompt missing 'on_response'")
      ELSE:
        FOR response_id, handler IN node.on_response:
          IF "next_node" NOT IN handler:
            append_issue("schema", "error", node_id,
              "on_response handler '" + response_id + "' missing 'next_node'")
          ELSE:
            validate_target(handler.next_node, node_id,
              "on_response." + response_id + ".next_node", workflow)

  # 2.1e: Deprecated pattern detection
  FOR node_id, node IN workflow.nodes:
    IF node.type == "validation_gate":
      append_issue("schema", "warning", node_id,
        "Deprecated node type 'validation_gate'. Use 'conditional' with audit.enabled: true")

  # Helper function for target validation
  function validate_target(target, node_id, field_name, workflow):
    IF target starts with "${":
      append_issue("schema", "info", node_id,
        "Field '" + field_name + "' uses dynamic target '" + target + "' — cannot validate statically")
      RETURN
    IF target NOT IN workflow.nodes AND target NOT IN workflow.endings:
      append_issue("schema", "error", node_id,
        "Field '" + field_name + "' references unknown target '" + target + "'")
```

### Step 2.2: Graph Validation

> **Pattern reference:** `patterns/graph-validation-algorithm.md`

Validate the workflow's directed graph structure:

```pseudocode
VALIDATE_GRAPH(workflow):
  # 2.2a: BFS reachability from start_node
  visited = {workflow.start_node}
  queue = [workflow.start_node]

  WHILE queue is not empty:
    current = queue.pop_front()
    IF current NOT IN workflow.nodes:
      CONTINUE
    FOR target IN get_all_transition_targets(current, workflow.nodes[current]):
      IF target starts with "${":
        CONTINUE  # Dynamic target, skip
      IF target NOT IN visited:
        visited.add(target)
        IF target IN workflow.nodes:
          queue.append(target)

  orphans = set(workflow.nodes.keys()) - visited
  FOR orphan IN orphans:
    append_issue("graph", "error", orphan,
      "Orphan node not reachable from start_node '" + workflow.start_node + "'")

  # 2.2b: Ending reachability (reverse BFS)
  reverse_graph = build_reverse_adjacency(workflow.nodes)
  can_reach_ending = bfs_from(set(workflow.endings.keys()), reverse_graph)
  stranded = set(workflow.nodes.keys()) - can_reach_ending
  FOR node_id IN stranded:
    append_issue("graph", "warning", node_id, "No path from this node to any ending")

  # 2.2c: Cycle detection (DFS 3-color)
  WHITE, GRAY, BLACK = 0, 1, 2
  color = {node_id: WHITE for node_id in workflow.nodes}
  cycles = []

  function dfs(node_id, path):
    color[node_id] = GRAY
    path.append(node_id)
    IF node_id IN workflow.nodes:
      FOR target IN get_all_transition_targets(node_id, workflow.nodes[node_id]):
        IF target starts with "${":
          CONTINUE
        IF target IN workflow.nodes:
          IF color[target] == GRAY:
            cycle_start = path.index(target)
            cycle = path[cycle_start:]
            cycles.append(cycle)
          ELIF color[target] == WHITE:
            dfs(target, path)
    color[node_id] = BLACK
    path.pop()

  FOR node_id IN workflow.nodes:
    IF color[node_id] == WHITE:
      dfs(node_id, [])

  FOR cycle IN cycles:
    has_break = any(
      any(t NOT IN cycle for t IN get_all_transition_targets(n, workflow.nodes[n])
          if NOT t.startswith("${"))
      for n IN cycle if n IN workflow.nodes
    )
    IF has_break:
      append_issue("graph", "info", cycle[0],
        "Bounded cycle detected: " + join(cycle, " -> ") + " (has exit condition)")
    ELSE:
      append_issue("graph", "error", cycle[0],
        "Infinite loop detected: " + join(cycle, " -> ") + " (no exit condition)")

  # 2.2d: Dead-end detection
  FOR node_id, node IN workflow.nodes:
    targets = get_all_transition_targets(node_id, node)
    valid_targets = [t for t IN targets if t]
    IF len(valid_targets) == 0:
      append_issue("graph", "error", node_id,
        "Dead-end node has no outgoing transitions")

  # Helper: extract all transition targets from a node
  function get_all_transition_targets(node_id, node):
    targets = []
    IF node.type == "action":
      targets = [node.on_success, node.on_failure]
    ELIF node.type == "conditional":
      targets = [node.branches.on_true, node.branches.on_false]
    ELIF node.type == "user_prompt":
      targets = [h.next_node for h in node.on_response.values()]
    RETURN [t for t IN targets if t is not null]
```

### Step 2.3: Type Validation

> **Pattern reference:** `patterns/type-validation-rules.md`

Validate precondition and consequence types against the catalog:

```pseudocode
VALIDATE_TYPES(workflow):
  VALID_PRECONDITIONS = [
    "state_check", "path_check", "tool_check", "source_check", "log_state",
    "fetch_check", "evaluate_expression", "all_of", "any_of", "none_of", "xor_of",
    "python_module_available", "network_available"
  ]
  VALID_CONSEQUENCES = [
    "create_checkpoint", "rollback_checkpoint", "spawn_agent", "inline",
    "invoke_skill", "evaluate", "compute", "display", "init_log", "log_node",
    "log_entry", "log_session_snapshot", "finalize_log", "write_log",
    "apply_log_retention", "output_ci_summary", "set_flag", "mutate_state",
    "set_timestamp", "compute_hash", "evaluate_keywords", "parse_intent_flags",
    "match_3vl_rules", "dynamic_route", "local_file_ops", "git_ops_local",
    "web_ops", "run_command", "install_tool"
  ]
  DEPRECATED_CONSEQUENCES = {
    "read_file": ("local_file_ops", "read"),
    "write_file": ("local_file_ops", "write"),
    "set_state": ("mutate_state", "set"),
    "append_state": ("mutate_state", "append"),
    "log_event": ("log_entry", "info"),
    "log_warning": ("log_entry", "warning"),
    "log_error": ("log_entry", "error"),
    "clone_repo": ("git_ops_local", "clone"),
    "web_fetch": ("web_ops", "fetch")
  }
  DEPRECATED_PRECONDITIONS = {
    "flag_set": ("state_check", "true"),
    "state_equals": ("state_check", "equals"),
    "file_exists": ("path_check", "exists"),
    "tool_available": ("tool_check", "available")
  }
  COMPOSITE_TYPES = ["all_of", "any_of", "none_of", "xor_of"]

  # 2.3a: Validate preconditions in conditional nodes and entry_preconditions
  function validate_precondition(condition, node_id, context):
    IF "type" NOT IN condition:
      append_issue("types", "error", node_id, context + ": condition missing 'type'")
      RETURN
    IF condition.type NOT IN VALID_PRECONDITIONS:
      replacement = DEPRECATED_PRECONDITIONS.get(condition.type)
      IF replacement:
        append_issue("types", "warning", node_id,
          context + ": '" + condition.type + "' is deprecated. Use '" + replacement[0] + "'")
      ELSE:
        append_issue("types", "error", node_id,
          context + ": unknown precondition type '" + condition.type + "'")
    IF condition.type IN COMPOSITE_TYPES AND "conditions" IN condition:
      FOR i, sub IN enumerate(condition.conditions):
        validate_precondition(sub, node_id, context + ".conditions[" + str(i) + "]")

  FOR node_id, node IN workflow.nodes:
    IF node.type == "conditional" AND "condition" IN node:
      validate_precondition(node.condition, node_id, "condition")

  IF "entry_preconditions" IN workflow:
    FOR i, pre IN enumerate(workflow.entry_preconditions):
      validate_precondition(pre, "entry", "entry_preconditions[" + str(i) + "]")

  # 2.3b: Validate consequence types in action and user_prompt nodes
  FOR node_id, node IN workflow.nodes:
    IF node.type == "action" AND "actions" IN node:
      FOR i, action IN enumerate(node.actions):
        IF "type" NOT IN action:
          append_issue("types", "error", node_id, "actions[" + str(i) + "]: missing 'type'")
          CONTINUE
        IF action.type NOT IN VALID_CONSEQUENCES:
          replacement = DEPRECATED_CONSEQUENCES.get(action.type)
          IF replacement:
            append_issue("types", "warning", node_id,
              "actions[" + str(i) + "]: deprecated type '" + action.type +
              "'. Use '" + replacement[0] + "' with operation: '" + replacement[1] + "'")
          ELSE:
            append_issue("types", "error", node_id,
              "actions[" + str(i) + "]: unknown consequence type '" + action.type + "'")

    IF node.type == "user_prompt" AND "on_response" IN node:
      FOR resp_id, handler IN node.on_response:
        IF "consequence" IN handler:
          FOR i, action IN enumerate(handler.consequence):
            IF action.type NOT IN VALID_CONSEQUENCES:
              replacement = DEPRECATED_CONSEQUENCES.get(action.type)
              IF replacement:
                append_issue("types", "warning", node_id,
                  "on_response." + resp_id + ".consequence[" + str(i) + "]: deprecated '" +
                  action.type + "'. Use '" + replacement[0] + "'")
              ELSE:
                append_issue("types", "error", node_id,
                  "on_response." + resp_id + ".consequence[" + str(i) + "]: unknown '" +
                  action.type + "'")
```

### Step 2.4: State Consistency Validation

Check that state references in interpolations match definitions:

```pseudocode
VALIDATE_STATE(workflow):
  # 2.4a: Collect initialized variables
  initialized_vars = set()
  IF "initial_state" IN workflow:
    initialized_vars = collect_keys_recursive(workflow.initial_state)

  # 2.4b: Collect runtime setters
  set_vars = {}  # var_name -> first_node_that_sets_it
  FOR node_id, node IN workflow.nodes:
    IF node.type == "action" AND "actions" IN node:
      FOR action IN node.actions:
        IF "field" IN action:
          set_vars[action.field] = node_id
        IF "store_as" IN action:
          set_vars[action.store_as] = node_id
        IF action.type == "set_flag" AND "flag" IN action:
          set_vars["flags." + action.flag] = node_id

  # 2.4c: Scan for undefined references
  WELL_KNOWN = {"computed", "flags", "arguments", "user_responses", "phase",
                "prompts", "output", "logging", "_semantics", "_semantics_loaded"}
  all_refs = find_all_interpolations(workflow)  # Recursive scan for ${...} patterns

  FOR ref IN all_refs:
    # Skip expressions with operators or function calls
    IF ref.content contains ("(", ")", "==", "!=", ">", "<"):
      CONTINUE
    base_var = ref.content.split(".")[0]
    IF base_var NOT IN WELL_KNOWN AND base_var NOT IN initialized_vars AND base_var NOT IN set_vars:
      append_issue("state", "warning", ref.location,
        "'" + ref.content + "' may be undefined — not found in initial_state or runtime setters")

  # 2.4d: Type consistency checks
  ops_by_field = {}  # field -> list of operation types
  FOR node_id, node IN workflow.nodes:
    IF node.type == "action" AND "actions" IN node:
      FOR action IN node.actions:
        IF action.type == "mutate_state" AND "field" IN action AND "operation" IN action:
          IF action.field NOT IN ops_by_field:
            ops_by_field[action.field] = []
          ops_by_field[action.field].append(action.operation)

  FOR field, ops IN ops_by_field:
    IF "set" IN ops AND "append" IN ops:
      append_issue("state", "warning", field,
        "'" + field + "' used as both scalar (set) and array (append)")
    IF "clear" IN ops AND ("merge" IN ops OR "append" IN ops):
      append_issue("state", "info", field,
        "'" + field + "' is cleared and re-used — verify ordering")
```

### Step 2.5: Blueprint Infrastructure Validation

Validate the `.hiivmind/blueprint/` directory and its contents for consistency.

```pseudocode
VALIDATE_BLUEPRINT(workflow):
  # Determine plugin type
  has_gateway = len(Glob("commands/*.md")) > 0 OR len(Glob("commands/*/SKILL.md")) > 0
  has_workflow_skills = len(Glob("skills/*/workflows/*.yaml")) > 0

  # 2.5a: Directory existence
  IF NOT directory_exists(".hiivmind/blueprint/"):
    IF has_gateway OR has_workflow_skills:
      append_issue("blueprint", "error", ".hiivmind/blueprint/",
        "Blueprint directory missing. Fix: Run bp-build to provision .hiivmind/blueprint/ files")
    RETURN  # No point checking files if directory missing

  # 2.5b: Required files based on plugin type
  IF has_workflow_skills:
    IF NOT file_exists(".hiivmind/blueprint/execution-guide.md"):
      append_issue("blueprint", "error", "execution-guide.md",
        "Missing execution-guide.md (required for workflow-backed skills). " +
        "Fix: Run bp-build or copy from ${CLAUDE_PLUGIN_ROOT}/lib/patterns/execution-guide.md")
    IF NOT file_exists(".hiivmind/blueprint/definitions.yaml"):
      append_issue("blueprint", "error", "definitions.yaml",
        "Missing definitions.yaml (required for workflow-backed skills). " +
        "Fix: Run bp-build to scan workflow types and generate definitions")

  IF has_gateway:
    IF NOT file_exists(".hiivmind/blueprint/engine_entrypoint.md"):
      append_issue("blueprint", "error", "engine_entrypoint.md",
        "Missing engine_entrypoint.md (required for gateway plugins). " +
        "Fix: Run bp-build or populate from ${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template")
    IF NOT file_exists(".hiivmind/blueprint/config.yaml"):
      append_issue("blueprint", "error", "config.yaml",
        "Missing config.yaml (required for gateway plugins). " +
        "Fix: Run bp-build or populate from ${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template")

  # 2.5c: definitions.yaml type completeness
  IF file_exists(".hiivmind/blueprint/definitions.yaml"):
    definitions = READ_YAML(".hiivmind/blueprint/definitions.yaml")
    defined_consequences = set(definitions.consequences.keys()) IF definitions.consequences ELSE set()
    defined_preconditions = set(definitions.preconditions.keys()) IF definitions.preconditions ELSE set()

    # Scan workflow for referenced types
    FOR node_id, node IN workflow.nodes:
      IF node.type == "action" AND "actions" IN node:
        FOR action IN node.actions:
          IF "type" IN action AND action.type NOT IN defined_consequences:
            append_issue("blueprint", "error", node_id,
              "Consequence type '" + action.type + "' used in workflow but missing from definitions.yaml. " +
              "Fix: Add '" + action.type + "' to definitions.yaml consequences section from catalog")
      IF node.type == "conditional" AND "condition" IN node:
        IF node.condition.type NOT IN defined_preconditions:
          append_issue("blueprint", "error", node_id,
            "Precondition type '" + node.condition.type + "' used in workflow but missing from definitions.yaml. " +
            "Fix: Add '" + node.condition.type + "' to definitions.yaml preconditions section from catalog")

  # 2.5d: Version consistency (config.yaml vs engine_entrypoint.md)
  IF file_exists(".hiivmind/blueprint/config.yaml") AND file_exists(".hiivmind/blueprint/engine_entrypoint.md"):
    config = READ_YAML(".hiivmind/blueprint/config.yaml")
    entrypoint_content = Read(".hiivmind/blueprint/engine_entrypoint.md")
    # Parse version from "## Version: X.Y.Z" header
    entrypoint_version = extract_pattern(entrypoint_content, /## Version: (\S+)/)

    IF config.engine_version != entrypoint_version:
      append_issue("blueprint", "warning", "config.yaml",
        "engine_version '" + config.engine_version + "' in config.yaml does not match '" +
        entrypoint_version + "' in engine_entrypoint.md. " +
        "Fix: Update config.yaml engine_version to '" + entrypoint_version + "'")

  # 2.5e: Obsolete remote-fetching artifacts
  IF file_exists(".hiivmind/blueprint/config.yaml"):
    config_content = Read(".hiivmind/blueprint/config.yaml")
    IF "lib_raw_url" IN config_content:
      append_issue("blueprint", "warning", "config.yaml",
        "Obsolete field 'lib_raw_url' found (runtime fetching artifact). " +
        "Fix: Remove lib_raw_url from config.yaml — upgrade to engine v2.0")

  IF file_exists(".hiivmind/blueprint/engine_entrypoint.md"):
    entrypoint_content = Read(".hiivmind/blueprint/engine_entrypoint.md")
    IF "Fetch Execution Semantics" IN entrypoint_content OR "gh api repos/hiivmind" IN entrypoint_content:
      append_issue("blueprint", "warning", "engine_entrypoint.md",
        "Obsolete remote-fetching protocol detected (v1.0.0 artifact). " +
        "Fix: Upgrade to engine_entrypoint.md v2.0 — run bp-maintain --upgrade-engine")
```

### Step 2.6: Aggregate and Report

Aggregate findings by severity:

```pseudocode
AGGREGATE_ISSUES():
  computed.issue_summary = {
    schema:    { errors: 0, warnings: 0, info: 0 },
    graph:     { errors: 0, warnings: 0, info: 0 },
    types:     { errors: 0, warnings: 0, info: 0 },
    state:     { errors: 0, warnings: 0, info: 0 },
    blueprint: { errors: 0, warnings: 0, info: 0 }
  }

  FOR dimension IN ["schema", "graph", "types", "state", "blueprint"]:
    FOR issue IN computed.issues[dimension]:
      computed.issue_summary[dimension][issue.severity] += 1

  computed.total_errors = sum(d.errors for d in computed.issue_summary.values())
  computed.total_warnings = sum(d.warnings for d in computed.issue_summary.values())
  computed.total_info = sum(d.info for d in computed.issue_summary.values())

  # Per-dimension status
  FOR dimension IN computed.issue_summary:
    IF computed.issue_summary[dimension].errors > 0:
      computed.issue_summary[dimension].status = "FAIL"
    ELIF computed.issue_summary[dimension].warnings > 0:
      computed.issue_summary[dimension].status = "WARN"
    ELSE:
      computed.issue_summary[dimension].status = "PASS"
```

Display the diagnosis report:

```
## Diagnosis Report: {computed.workflow_name}

**Path:** {computed.workflow_path}
**Nodes:** {computed.node_count} | **Endings:** {computed.ending_count}

| Dimension | Status | Errors | Warnings | Info |
|-----------|--------|--------|----------|------|
| Schema    | {status} | {n} | {n} | {n} |
| Graph     | {status} | {n} | {n} | {n} |
| Types     | {status} | {n} | {n} | {n} |
| State     | {status} | {n} | {n} | {n} |
| Blueprint | {status} | {n} | {n} | {n} |

**Overall:** {FAIL if total_errors > 0 else WARN if total_warnings > 0 else PASS}

### Issues

{for dimension in ["schema", "graph", "types", "state", "blueprint"]}
{if computed.issues[dimension]}
#### {dimension}

{for issue in computed.issues[dimension] sorted by severity (error first)}
- [{issue.severity}] **{issue.node}**: {issue.message}
{/for}
{/if}
{/for}
```

**IF `computed.validate_only` is true:** Display the report and STOP. Set
`computed.changes_applied = []` and exit.

---

## Phase 3: Plan

Present findings and recommend operations based on the diagnosis.

### Step 3.1: Detect Recommended Operations

Analyze the issues to suggest appropriate maintenance operations:

```pseudocode
PLAN_OPERATIONS():
  computed.recommendations = []

  # Schema version issues -> suggest upgrade
  has_deprecated_types = any(i.severity == "warning" AND "deprecated" IN i.message
                            for dim IN computed.issues.values() for i IN dim)
  has_deprecated_nodes = any(i.message contains "validation_gate"
                             for i IN computed.issues.schema)
  IF has_deprecated_types OR has_deprecated_nodes:
    computed.recommendations.append({
      operation: "upgrade",
      priority: 1,
      reason: "Deprecated types or node patterns detected — upgrade to latest schema"
    })

  # Structural issues -> suggest refactoring
  has_orphans = any(i.message contains "Orphan" for i IN computed.issues.graph)
  has_dead_ends = any(i.message contains "Dead-end" for i IN computed.issues.graph)
  IF has_orphans OR has_dead_ends:
    computed.recommendations.append({
      operation: "cleanup",
      priority: 2,
      reason: "Unreachable or dead-end nodes detected — cleanup dead code"
    })

  # God nodes (action nodes with many actions) -> suggest extract
  FOR node_id, node IN computed.workflow.nodes:
    IF node.type == "action" AND has_field(node, "actions") AND len(node.actions) > 5:
      computed.recommendations.append({
        operation: "extract-subflow",
        priority: 3,
        reason: "Node '" + node_id + "' has " + str(len(node.actions)) + " actions (threshold: 5)"
      })

  # Blueprint infrastructure issues -> suggest engine upgrade
  has_remote_artifacts = any(i.message contains "remote-fetching" OR i.message contains "lib_raw_url"
                             for i IN computed.issues.blueprint)
  has_missing_blueprint = any(i.severity == "error" for i IN computed.issues.blueprint)
  IF has_remote_artifacts:
    computed.recommendations.append({
      operation: "upgrade-engine",
      priority: 1,
      reason: "Obsolete remote-fetching artifacts detected — upgrade to engine v2.0"
    })
  IF has_missing_blueprint:
    computed.recommendations.append({
      operation: "rebuild-blueprint",
      priority: 1,
      reason: "Missing .hiivmind/blueprint/ files — run bp-build to provision"
    })

  # No issues found
  IF computed.total_errors == 0 AND computed.total_warnings == 0:
    computed.recommendations.append({
      operation: "none",
      priority: 0,
      reason: "Workflow is healthy — no maintenance needed"
    })
```

### Step 3.2: Present Plan

If `computed.upgrade_mode`, `computed.upgrade_engine`, or `computed.refactor_op` is set from
flags, skip the menu and proceed directly to Phase 4 with the specified operation.

Otherwise, present findings and let the user choose:

```json
{
  "questions": [{
    "question": "Based on the diagnosis, what would you like to do?",
    "header": "Maintenance Operations",
    "multiSelect": false,
    "options": [
      {
        "label": "Upgrade schema version",
        "description": "Migrate from current version to latest (2.0 -> 2.4)"
      },
      {
        "label": "Refactor: extract subflow",
        "description": "Move a group of nodes into a separate subflow file"
      },
      {
        "label": "Refactor: inline subflow",
        "description": "Expand a reference node back into the parent workflow"
      },
      {
        "label": "Refactor: split workflow",
        "description": "Break one large workflow into two smaller ones"
      },
      {
        "label": "Refactor: rename nodes",
        "description": "Rename node IDs and update all references"
      },
      {
        "label": "Refactor: cleanup dead code",
        "description": "Remove unreachable nodes, unused endings, unused state"
      },
      {
        "label": "Upgrade engine to v2.0",
        "description": "Replace engine_entrypoint.md, update config.yaml, deploy execution-guide.md"
      },
      {
        "label": "No changes",
        "description": "Review complete — do not modify the workflow"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PLAN(response):
  SWITCH response:
    CASE "Upgrade schema version":
      computed.selected_operation = "upgrade"
      GOTO Phase 4: Upgrade Flow
    CASE "Refactor: extract subflow":
      computed.selected_operation = "extract-subflow"
      GOTO Phase 4: Refactor Flow
    CASE "Refactor: inline subflow":
      computed.selected_operation = "inline-subflow"
      GOTO Phase 4: Refactor Flow
    CASE "Refactor: split workflow":
      computed.selected_operation = "split"
      GOTO Phase 4: Refactor Flow
    CASE "Refactor: rename nodes":
      computed.selected_operation = "rename"
      GOTO Phase 4: Refactor Flow
    CASE "Refactor: cleanup dead code":
      computed.selected_operation = "cleanup"
      GOTO Phase 4: Refactor Flow
    CASE "Upgrade engine to v2.0":
      computed.selected_operation = "upgrade-engine"
      GOTO Phase 4: Engine Upgrade Flow
    CASE "No changes":
      DISPLAY "Maintenance complete. No changes applied."
      EXIT
```

If multiple operations are recommended (e.g., upgrade + refactor), suggest order:
engine upgrade first, then schema upgrade, then refactor. This ensures infrastructure is
correct before type migrations and structural changes.

---

## Phase 4: Apply

Two distinct flows depending on `computed.selected_operation`. Both flows create a
timestamped backup before modifying files.

### Step 4.0: Create Backup

```pseudocode
CREATE_BACKUP():
  computed.backup_timestamp = format_timestamp(now(), "YYYYMMDD_HHmmss")
  computed.backup_path = computed.workflow_path + ".backup." + computed.backup_timestamp
  original_content = Read(computed.workflow_path)
  Write(computed.backup_path, original_content)
  computed.original_hash = sha256(original_content)
  DISPLAY "Backup created: " + computed.backup_path
```

---

### Upgrade Flow

> **Pattern reference:** `patterns/migration-table.md`
> **Pattern reference:** `patterns/idempotency-guards.md`

Executes when `computed.selected_operation == "upgrade"` or `computed.upgrade_mode == true`.

#### Step 4U.1: Detect Current Schema Version

```pseudocode
DETECT_VERSION(workflow):
  has_output = has_field(workflow, "initial_state.output")
  has_prompts = has_field(workflow, "initial_state.prompts")
  has_gate_nodes = any(n.type == "validation_gate" for n in workflow.nodes.values())
  has_unified_output = has_output AND has_field(workflow, "initial_state.output.log_enabled")
  has_separate_logging = has_field(workflow, "initial_state.logging") AND NOT has_unified_output

  IF has_output AND has_prompts AND has_unified_output:
    computed.current_version = "2.4"
  ELIF has_prompts:
    computed.current_version = "2.3"
  ELIF has_unified_output:
    computed.current_version = "2.2"
  ELIF NOT has_gate_nodes:
    computed.current_version = "2.1"
  ELSE:
    computed.current_version = "2.0"

  computed.target_version = "2.4"

  IF computed.current_version == computed.target_version:
    DISPLAY "Workflow is already at schema version " + computed.target_version + ". No upgrade needed."
    GOTO Phase 5
```

#### Step 4U.2: Build Migration Plan

```pseudocode
BUILD_MIGRATION_PLAN():
  VERSION_SEQUENCE = ["2.0", "2.1", "2.2", "2.3", "2.4"]
  current_idx = VERSION_SEQUENCE.index(computed.current_version)
  target_idx = VERSION_SEQUENCE.index(computed.target_version)

  computed.migration_steps = []
  FOR i IN range(current_idx, target_idx):
    from_ver = VERSION_SEQUENCE[i]
    to_ver = VERSION_SEQUENCE[i + 1]
    computed.migration_steps.append({
      from_version: from_ver,
      to_version: to_ver,
      changes: get_changes_for_step(from_ver, to_ver)
    })
```

Migration changes per step (see `patterns/migration-table.md` for complete YAML examples):

| From | To | Changes |
|------|----|---------|
| 2.0 | 2.1 | Replace `validation_gate` nodes with `conditional` + `audit` config |
| 2.1 | 2.2 | Unify separate `logging`/`display` into `initial_state.output` |
| 2.2 | 2.3 | Add `initial_state.prompts` for multi-modal support |
| 2.3 | 2.4 | Make `output` and `prompts` required, fill missing defaults |

#### Step 4U.3: Idempotency Check

```pseudocode
CHECK_IDEMPOTENCY():
  FOR step IN computed.migration_steps:
    step.already_applied = false

    IF step is 2.0->2.1:
      step.already_applied = NOT any(n.type == "validation_gate" for n in workflow.nodes.values())
    ELIF step is 2.1->2.2:
      step.already_applied = has_unified_output AND NOT has_field(workflow, "initial_state.logging")
    ELIF step is 2.2->2.3:
      step.already_applied = has_field(workflow, "initial_state.prompts")
    ELIF step is 2.3->2.4:
      step.already_applied = has_all_required_output_fields(workflow) AND
                             has_all_required_prompts_fields(workflow)

  computed.pending_steps = [s for s in computed.migration_steps if NOT s.already_applied]
  computed.skipped_steps = [s for s in computed.migration_steps if s.already_applied]
```

#### Step 4U.4: Confirm and Apply

Present the plan for confirmation:

```json
{
  "questions": [{
    "question": "Migration plan: {current} -> {target} ({n} pending, {m} skipped). Proceed?",
    "header": "Confirm Upgrade",
    "multiSelect": false,
    "options": [
      {"label": "Apply all pending migrations", "description": "Upgrade in batch"},
      {"label": "Apply step-by-step", "description": "Confirm each migration individually"},
      {"label": "Cancel", "description": "Do not modify the workflow"}
    ]
  }]
}
```

Apply each pending migration sequentially. Each migration function transforms
`computed.workflow` in place. After all migrations, write the result:

```pseudocode
APPLY_MIGRATIONS():
  computed.applied_changes = []

  FOR step IN computed.pending_steps:
    IF computed.apply_mode == "interactive":
      confirmed = AskUserQuestion("Apply " + step.from_version + " -> " + step.to_version + "?")
      IF confirmed == "Skip": CONTINUE
      IF confirmed == "Stop": BREAK

    changes = apply_migration(computed.workflow, step.from_version, step.to_version)
    computed.applied_changes.extend(changes)

  # Type consolidation pass (deprecated v2.x types -> current)
  type_changes = consolidate_deprecated_types(computed.workflow)
  computed.applied_changes.extend(type_changes)

  # Write result
  Write(computed.workflow_path, serialize_yaml(computed.workflow))
```

The detailed migration functions for each version step are documented in
`patterns/migration-table.md`. Each function is idempotent per `patterns/idempotency-guards.md`.

---

### Engine Upgrade Flow

Executes when `computed.upgrade_engine == true`. Upgrades the `.hiivmind/blueprint/` engine
infrastructure from v1.0.0 (remote fetching) to v2.0 (local only).

```pseudocode
UPGRADE_ENGINE():
  # Step 1: Detect current engine version
  config_path = ".hiivmind/blueprint/config.yaml"
  IF file_exists(config_path):
    config = READ_YAML(config_path)
    current_version = config.engine_version OR "unknown"
  ELSE:
    current_version = "unknown"

  # Step 2: Idempotency check — already at v2.0?
  IF current_version == "2.0.0":
    DISPLAY "Engine already at v2.0.0 — no upgrade needed"
    RETURN

  DISPLAY "Upgrading engine from " + current_version + " to 2.0.0..."
  computed.engine_changes = []

  # Step 3: Replace engine_entrypoint.md with v2.0
  entrypoint_path = ".hiivmind/blueprint/engine_entrypoint.md"
  IF file_exists(entrypoint_path):
    existing_content = Read(entrypoint_path)
    # Check for local customizations (drift detection)
    template_path = "${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template"
    template = Read(template_path)
    v2_content = replace(template, "{{engine_version}}", "2.0.0")
    v2_content = replace(v2_content, "{{#if_gateway}}", "")
    v2_content = replace(v2_content, "{{/if_gateway}}", "")

    # Create backup of existing entrypoint
    backup_path = entrypoint_path + ".v1-backup"
    Write(backup_path, existing_content)
    DISPLAY "  Backed up: " + entrypoint_path + " → " + backup_path

    Write(entrypoint_path, v2_content)
    computed.engine_changes.append("Replaced engine_entrypoint.md with v2.0")
  ELSE:
    # No existing entrypoint — create from template
    v2_content = Read("${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template")
    v2_content = replace(v2_content, "{{engine_version}}", "2.0.0")
    v2_content = replace(v2_content, "{{#if_gateway}}", "")
    v2_content = replace(v2_content, "{{/if_gateway}}", "")
    Bash("mkdir -p .hiivmind/blueprint/")
    Write(entrypoint_path, v2_content)
    computed.engine_changes.append("Created engine_entrypoint.md v2.0")

  # Step 4: Update config.yaml — bump version, remove lib_raw_url
  IF file_exists(config_path):
    config.engine_version = "2.0.0"
    IF "lib_raw_url" IN config:
      DELETE config.lib_raw_url
      computed.engine_changes.append("Removed lib_raw_url from config.yaml")
    Write(config_path, YAML_DUMP(config))
    computed.engine_changes.append("Updated config.yaml engine_version to 2.0.0")
  ELSE:
    # Create config from template
    config_template = Read("${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template")
    config_content = replace(config_template, "{{engine_version}}", "2.0.0")
    config_content = replace(config_content, "{{lib_version}}", "v3.1.1")
    config_content = replace(config_content, "{{lib_ref}}", "hiivmind/hiivmind-blueprint-lib@v3.1.1")
    config_content = replace(config_content, "{{schema_version}}", "2.3")
    Write(config_path, config_content)
    computed.engine_changes.append("Created config.yaml with engine_version 2.0.0")

  # Step 5: Deploy execution-guide.md if missing
  IF NOT file_exists(".hiivmind/blueprint/execution-guide.md"):
    source = Read("${CLAUDE_PLUGIN_ROOT}/lib/patterns/execution-guide.md")
    Write(".hiivmind/blueprint/execution-guide.md", source)
    computed.engine_changes.append("Deployed execution-guide.md")

  # Report changes
  DISPLAY ""
  DISPLAY "## Engine Upgrade Complete"
  DISPLAY ""
  FOR change IN computed.engine_changes:
    DISPLAY "  ✓ " + change
  DISPLAY ""
  DISPLAY "Engine upgraded to v2.0.0 (local-only model)"
```

---

### Refactor Flow

> **Pattern reference:** `patterns/refactoring-operations.md`
> **Pattern reference:** `patterns/extract-subflow-procedure.md`

Executes when `computed.selected_operation` is one of the refactoring operations.

#### Step 4R.1: Route to Operation

```pseudocode
ROUTE_REFACTOR():
  SWITCH computed.selected_operation:
    CASE "extract-subflow":  GOTO Step 4R.2
    CASE "inline-subflow":   GOTO Step 4R.3
    CASE "split":            GOTO Step 4R.4
    CASE "rename":           GOTO Step 4R.5
    CASE "cleanup":          GOTO Step 4R.6
```

#### Step 4R.2: Extract Subflow

> **Detail:** `patterns/extract-subflow-procedure.md`

Select nodes to extract, identify boundary (entry nodes, exit transitions, shared state),
create a new subflow file, and rewire the parent workflow:

```pseudocode
EXTRACT_SUBFLOW():
  # Build node list for selection
  computed.node_list = [
    { id: node_id, label: node_id,
      description: node.type + " — " + (node.description or "no description") }
    for node_id, node in computed.workflow.nodes
    if node_id != computed.workflow.start_node
  ]
```

```json
{
  "questions": [{
    "question": "Which nodes should be extracted into a subflow?",
    "header": "Select Nodes",
    "multiSelect": true,
    "options_from_state": "computed.node_list"
  }]
}
```

```pseudocode
  computed.extract_nodes = user_selected_node_ids

  # Identify boundary
  computed.boundary = identify_boundary(computed.extract_nodes, computed.workflow)

  IF len(computed.boundary.entry) == 0:
    DISPLAY "Error: selected nodes are disconnected from the workflow."
    EXIT
  IF len(computed.boundary.entry) > 1:
    DISPLAY "Warning: multiple entry points detected. Subflow should have single entry."

  # Create subflow
  computed.subflow = {
    name: auto_or_user_name,
    start_node: computed.boundary.entry[0],
    nodes: {id: computed.workflow.nodes[id] for id in computed.extract_nodes},
    endings: {}
  }
  # Map exit transitions to subflow endings
  FOR exit IN computed.boundary.exits:
    IF exit.is_ending:
      computed.subflow.endings[exit.target] = computed.workflow.endings[exit.target]
    ELSE:
      ending_id = "resume_" + exit.target
      computed.subflow.endings[ending_id] = { type: "success", message: "Resume at " + exit.target }
      rewire_transition(computed.subflow.nodes[exit.from_node], exit.target, ending_id)

  computed.subflow_path = parent_dir(computed.workflow_path) + "/subflows/" + computed.subflow.name + ".yaml"
  Write(computed.subflow_path, serialize_yaml(computed.subflow))

  # Remove extracted nodes from parent, rewire transitions
  FOR node_id IN computed.extract_nodes:
    del computed.workflow.nodes[node_id]
  resume_target = computed.boundary.exits[0].target
  FOR node_id, node IN computed.workflow.nodes:
    update_transition_targets(node, computed.boundary.entry[0], resume_target)

  Write(computed.workflow_path, serialize_yaml(computed.workflow))
  computed.applied_changes.append("Extracted " + str(len(computed.extract_nodes)) +
    " nodes to " + computed.subflow_path)
```

#### Step 4R.3: Inline Subflow (Legacy)

Applies only to pre-v5.0.0 workflows containing `reference` nodes. Find reference nodes,
read the referenced subflow, copy its nodes into the parent with collision-safe prefixing,
rewire transitions, and remove the reference node.

See `patterns/refactoring-operations.md` for the complete inline procedure.

```pseudocode
INLINE_SUBFLOW():
  reference_nodes = [n for n in computed.workflow.nodes if n.type == "reference"]
  IF len(reference_nodes) == 0:
    DISPLAY "No reference nodes found. This operation applies only to legacy workflows."
    EXIT

  # Select reference node, read subflow, copy nodes, rewire, remove reference
  # Full procedure in patterns/refactoring-operations.md
```

#### Step 4R.4: Split Workflow

Choose a split point, partition nodes via BFS, create two workflow files with handoff
between them.

```json
{
  "questions": [{
    "question": "Which node should be the split boundary?",
    "header": "Split Point",
    "multiSelect": false,
    "options_from_state": "computed.node_list_ordered"
  }]
}
```

See `patterns/refactoring-operations.md` for the complete split procedure including
BFS partitioning and invoke_skill handoff wiring.

#### Step 4R.5: Rename Nodes

```json
{
  "questions": [{
    "question": "How would you like to rename nodes?",
    "header": "Rename Mode",
    "multiSelect": false,
    "options": [
      {"label": "Single node", "description": "Change one node ID and update all references"},
      {"label": "Add/change prefix", "description": "Add or replace a prefix on all node IDs"},
      {"label": "Batch rename", "description": "Provide multiple old -> new mappings"}
    ]
  }]
}
```

Build `computed.rename_map` based on mode. Apply renames to node keys, all transition
targets (on_success, on_failure, branches, on_response.*.next_node), and start_node.

See `patterns/refactoring-operations.md` for the complete rename procedure.

#### Step 4R.6: Cleanup Dead Code

Remove unreachable nodes, unused endings, and unused state variables:

```pseudocode
CLEANUP_DEAD_CODE():
  computed.dead_code = {
    orphan_nodes: find_orphans(computed.workflow),
    unused_endings: find_unused_endings(computed.workflow),
    unused_state: find_unused_state(computed.workflow)
  }
```

Present for confirmation:

```json
{
  "questions": [{
    "question": "Which dead code items should be removed?",
    "header": "Cleanup Targets",
    "multiSelect": true,
    "options": [
      {"label": "Unreachable nodes", "description": "Remove nodes not reachable from start_node"},
      {"label": "Unused endings", "description": "Remove endings not referenced by any node"},
      {"label": "Unused state variables", "description": "Remove initial_state fields that appear unused"},
      {"label": "All of the above", "description": "Remove all detected dead code"}
    ]
  }]
}
```

```pseudocode
APPLY_CLEANUP(response):
  IF "Unreachable nodes" IN response OR "All" IN response:
    FOR node_id IN computed.dead_code.orphan_nodes:
      del computed.workflow.nodes[node_id]
    computed.applied_changes.append("Removed " + str(len(computed.dead_code.orphan_nodes)) + " orphan nodes")

  IF "Unused endings" IN response OR "All" IN response:
    FOR ending_id IN computed.dead_code.unused_endings:
      del computed.workflow.endings[ending_id]
    computed.applied_changes.append("Removed " + str(len(computed.dead_code.unused_endings)) + " unused endings")

  IF "Unused state variables" IN response OR "All" IN response:
    FOR var IN computed.dead_code.unused_state:
      del computed.workflow.initial_state[var]
    computed.applied_changes.append("Removed " + str(len(computed.dead_code.unused_state)) + " unused state vars")

  Write(computed.workflow_path, serialize_yaml(computed.workflow))
```

---

## Phase 5: Verify

Re-run diagnosis on the modified workflow and compare against Phase 2 results.

### Step 5.1: Re-run Diagnosis

```pseudocode
VERIFY():
  # Save original issue counts
  computed.before_counts = {
    errors: computed.total_errors,
    warnings: computed.total_warnings,
    info: computed.total_info
  }

  # Re-run all 4 validation dimensions on the modified workflow
  computed.workflow = parse_yaml(Read(computed.workflow_path))
  computed.issues = { schema: [], graph: [], types: [], state: [] }
  VALIDATE_SCHEMA(computed.workflow)
  VALIDATE_GRAPH(computed.workflow)
  VALIDATE_TYPES(computed.workflow)
  VALIDATE_STATE(computed.workflow)
  AGGREGATE_ISSUES()
```

### Step 5.2: Compare Before/After

```pseudocode
COMPARE():
  computed.after_counts = {
    errors: computed.total_errors,
    warnings: computed.total_warnings,
    info: computed.total_info
  }

  computed.error_delta = computed.after_counts.errors - computed.before_counts.errors
  computed.warning_delta = computed.after_counts.warnings - computed.before_counts.warnings
```

### Step 5.3: Display Change Summary

```
## Verification: {computed.workflow_name}

**Operation:** {computed.selected_operation}
**Backup:** {computed.backup_path}

### Issue Counts

| | Before | After | Delta |
|--|--------|-------|-------|
| Errors | {before} | {after} | {delta} |
| Warnings | {before} | {after} | {delta} |
| Info | {before} | {after} | {delta} |

### Changes Applied

{for change in computed.applied_changes}
- {change}
{/for}
```

### Step 5.4: Handle New Issues

If the operation introduced new issues (error delta > 0):

```json
{
  "questions": [{
    "question": "The operation introduced {n} new error(s). How would you like to proceed?",
    "header": "New Issues Detected",
    "multiSelect": false,
    "options": [
      {"label": "Review new issues", "description": "Display the new errors for manual review"},
      {"label": "Revert from backup", "description": "Restore original workflow from backup"},
      {"label": "Keep changes", "description": "Accept the changes despite new issues"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEW_ISSUES(response):
  SWITCH response:
    CASE "Review new issues":
      # Display all current errors
      GOTO Step 5.4  # Re-prompt after review
    CASE "Revert from backup":
      backup_content = Read(computed.backup_path)
      Write(computed.workflow_path, backup_content)
      DISPLAY "Reverted to backup: " + computed.backup_path
    CASE "Keep changes":
      DISPLAY "Changes kept. Backup preserved at " + computed.backup_path
```

If no new issues were introduced, display success:

```
Maintenance complete. {computed.selected_operation} applied successfully.
{if error_delta < 0}Resolved {abs(error_delta)} error(s).{/if}
{if warning_delta < 0}Resolved {abs(warning_delta)} warning(s).{/if}
Backup preserved at {computed.backup_path}.
```

---

## State Flow

```
Phase 1            Phase 2              Phase 3              Phase 4              Phase 5
───────────────────────────────────────────────────────────────────────────────────────────
computed           computed.issues      computed              computed             computed
.validate_only     computed               .recommendations     .backup_path         .before_counts
.upgrade_mode        .issue_summary     computed               computed             computed
.refactor_op       computed               .selected_operation   .applied_changes     .after_counts
.workflow_path       .total_errors      (routes to            computed             computed
.workflow          computed               upgrade or            .migration_steps     .error_delta
.workflow_name       .total_warnings      refactor flow)       computed
.node_count                                                     .pending_steps
.ending_count
```

---

## Reference Documentation

- **Graph Validation Algorithm:** `patterns/graph-validation-algorithm.md` (local)
- **Schema Validation Rules:** `patterns/schema-validation-rules.md` (local)
- **Type Validation Rules:** `patterns/type-validation-rules.md` (local)
- **Refactoring Operations:** `patterns/refactoring-operations.md` (local)
- **Extract Subflow Procedure:** `patterns/extract-subflow-procedure.md` (local)
- **Migration Table:** `patterns/migration-table.md` (local)
- **Idempotency Guards:** `patterns/idempotency-guards.md` (local)
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Consequences Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
- **Preconditions Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`

---

## Related Skills

- **Assess skill coverage:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- **Enhance skill structure:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-enhance/SKILL.md`
- **Extract to workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-extract/SKILL.md`
- **Build new skills:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
- **Visualize workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
