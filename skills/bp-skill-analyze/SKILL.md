---
name: bp-skill-analyze
description: >
  This skill should be used when the user asks to "analyze workflow", "examine workflow.yaml",
  "workflow metrics", "assess workflow quality", "workflow complexity", "review workflow structure",
  or needs to understand an existing workflow.yaml's structure and quality. Triggers on
  "analyze workflow", "workflow analysis", "workflow quality", "workflow metrics",
  "examine workflow", "review workflow". Distinct from prose-analyze which examines SKILL.md files.
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Analyze Workflow Structure & Quality

Perform deep read-only analysis of an existing workflow.yaml file. Produces complexity metrics,
quality scores, pattern detection results, anti-pattern warnings, and prioritized recommendations.

> **Complexity Scoring:** `patterns/complexity-scoring-algorithm.md`
> **Quality Indicators:** `patterns/quality-indicators.md`
> **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

---

## Overview

This skill examines a **workflow.yaml** file that has already been generated (post-conversion).
It does NOT analyze prose-based SKILL.md files -- use `bp-prose-analyze` for that purpose.

The analysis produces five categories of output:

| Category | What It Measures |
|----------|-----------------|
| Complexity metrics | Node counts, branch depth, cyclomatic complexity, state variable count |
| Quality scores | Description coverage, error handling, subflow usage, naming consistency |
| Pattern detection | Gate patterns, loop patterns, delegation patterns |
| Anti-pattern warnings | Deep nesting, god nodes, missing error paths, orphan/dead-end nodes |
| Recommendations | Schema upgrades, refactoring opportunities, quality improvements |

All results are stored in `computed.*` namespaces and rendered as a final dashboard report.

---

## Phase 1: Load Workflow

### Step 1.1: Resolve Workflow Path

If the user provided a path argument, use it directly. Otherwise, attempt auto-detection:

```pseudocode
RESOLVE_WORKFLOW_PATH(args):
  IF args.path is provided:
    computed.workflow_path = resolve_absolute(args.path)
  ELSE:
    # Try current directory
    candidates = Glob("./workflow.yaml")
    IF len(candidates) == 1:
      computed.workflow_path = candidates[0]
    ELIF len(candidates) > 1:
      # Multiple candidates -- ask user to choose
      GOTO Step 1.2
    ELSE:
      # No workflow.yaml found nearby -- ask user
      GOTO Step 1.2
```

### Step 1.2: Ask User for Path

If auto-detection fails, prompt the user:

```json
{
  "questions": [{
    "question": "Which workflow.yaml file should I analyze?",
    "header": "Workflow",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter path manually",
        "description": "Provide the full or relative path to the workflow.yaml file"
      },
      {
        "label": "Search current plugin",
        "description": "Scan skills/ and skills-prose/ for workflow.yaml files"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PATH_RESPONSE(response):
  SWITCH response:
    CASE "Enter path manually":
      # AskUserQuestion for free-text path input
      computed.workflow_path = user_provided_path
    CASE "Search current plugin":
      candidates = Glob(CLAUDE_PLUGIN_ROOT + "/skills/*/workflow.yaml")
      candidates += Glob(CLAUDE_PLUGIN_ROOT + "/skills-prose/*/workflow.yaml")
      # Present candidates as options for selection
      computed.workflow_path = selected_candidate
```

### Step 1.3: Read and Validate

Read the resolved file and perform basic structural validation:

```pseudocode
LOAD_WORKFLOW():
  content = Read(computed.workflow_path)

  # Basic YAML structure checks
  ASSERT content contains "name:"
  ASSERT content contains "nodes:"
  ASSERT content contains "endings:"
  ASSERT content contains "start_node:"

  IF any assertion fails:
    DISPLAY "ERROR: File at {computed.workflow_path} does not appear to be a valid workflow.yaml."
    DISPLAY "Missing required sections. Ensure the file has name, nodes, endings, and start_node."
    EXIT

  computed.workflow_raw = content
  computed.workflow_name = extract_field(content, "name")
  computed.workflow_version = extract_field(content, "version")
  computed.workflow_description = extract_field(content, "description")
```

Store parsed workflow data in `computed.workflow_raw`, `computed.workflow_name`,
`computed.workflow_version`, and `computed.workflow_description`.

---

## Phase 2: Complexity Metrics

Compute quantitative metrics that characterize the workflow's structural complexity.
All metrics are stored in `computed.metrics`.

### Step 2.1: Node Count by Type

Count each node type defined in the `nodes:` section:

```pseudocode
COUNT_NODES(workflow):
  computed.metrics.nodes = {
    action:      count(nodes where type == "action"),
    conditional: count(nodes where type == "conditional"),
    user_prompt: count(nodes where type == "user_prompt"),
    reference:   count(nodes where type == "reference"),
    total:       sum of all above
  }

  # Also count total actions across all action nodes
  computed.metrics.total_actions = 0
  FOR node IN nodes where type == "action":
    computed.metrics.total_actions += len(node.actions)
```

### Step 2.2: Ending Count

Count endings by type (success vs error):

```pseudocode
COUNT_ENDINGS(workflow):
  computed.metrics.endings = {
    success: count(endings where type == "success"),
    error:   count(endings where type == "error"),
    total:   sum of all above
  }

  # Track individual error ending IDs for later reference
  computed.metrics.error_ending_ids = [id for id, ending in endings if ending.type == "error"]
```

### Step 2.3: Max Branch Depth

Compute the deepest nesting level using depth-first search from the start node.
Branch depth measures the longest path through conditional branches before reaching an ending.

```pseudocode
MAX_BRANCH_DEPTH(workflow):
  visited = set()
  max_depth = 0

  function DFS(node_id, current_depth):
    IF node_id IN visited:
      RETURN  # Cycle detected, stop recursion
    IF node_id IN endings:
      max_depth = max(max_depth, current_depth)
      RETURN

    visited.add(node_id)
    node = nodes[node_id]

    SWITCH node.type:
      CASE "action":
        DFS(node.on_success, current_depth)
        IF node.on_failure:
          DFS(node.on_failure, current_depth)

      CASE "conditional":
        # Each branch adds a level of depth
        DFS(node.branches.on_true, current_depth + 1)
        DFS(node.branches.on_false, current_depth + 1)

      CASE "user_prompt":
        FOR option IN node.on_response:
          DFS(option.next_node, current_depth + 1)

      CASE "reference":
        DFS(node.next_node, current_depth)

    visited.remove(node_id)  # Allow revisiting on different paths

  DFS(workflow.start_node, 0)
  computed.metrics.max_branch_depth = max_depth
```

### Step 2.4: Cyclomatic Complexity

Calculate cyclomatic complexity using the graph formula. This measures the number of
independent paths through the workflow.

> **Detail:** See `patterns/complexity-scoring-algorithm.md` for the full formula,
> weighted scoring, and threshold definitions.

```pseudocode
CYCLOMATIC_COMPLEXITY(workflow):
  # Count edges (transitions between nodes and to endings)
  edges = 0
  FOR node IN all_nodes:
    SWITCH node.type:
      CASE "action":
        edges += 1  # on_success
        IF node.on_failure:
          edges += 1  # on_failure
      CASE "conditional":
        edges += 2  # on_true + on_false
      CASE "user_prompt":
        edges += len(node.on_response)  # one edge per option
      CASE "reference":
        edges += 1  # next_node

  # Count nodes (including ending nodes)
  nodes_count = computed.metrics.nodes.total + computed.metrics.endings.total

  # Connected components (typically 1 for a well-formed workflow)
  connected_components = 1

  # M = E - N + 2P
  computed.metrics.cyclomatic_complexity = edges - nodes_count + 2 * connected_components
```

### Step 2.5: State Variable Count

Scan the workflow for all state variables declared in `initial_state` and all state
mutations across the graph:

```pseudocode
COUNT_STATE_VARIABLES(workflow):
  # Variables declared in initial_state
  declared_vars = extract_all_keys(workflow.initial_state, recursive=true)

  # Variables mutated in nodes via set_state or mutate_state actions
  mutated_vars = set()
  FOR node IN all_nodes:
    IF node.type == "action":
      FOR action IN node.actions:
        IF action.type IN ("set_state", "mutate_state"):
          mutated_vars.add(action.field)

  # Variables referenced via ${...} interpolation
  referenced_vars = extract_all_matches(workflow_raw, /\$\{([^}]+)\}/)

  computed.metrics.state_variables = {
    declared:   len(declared_vars),
    mutated:    len(mutated_vars),
    referenced: len(referenced_vars),
    undeclared_mutations: mutated_vars - declared_vars,  # Potential issues
    unreferenced_declared: declared_vars - referenced_vars - mutated_vars  # Dead state
  }
```

Store all metrics in `computed.metrics`.

---

## Phase 3: Quality Assessment

Evaluate qualitative aspects of the workflow. Each dimension produces a score from 0 to 100.
All quality scores are stored in `computed.quality`.

> **Detail:** See `patterns/quality-indicators.md` for the full scoring rubric, severity
> levels, and detection rules for each quality dimension.

### Step 3.1: Description Coverage

Measure what percentage of nodes include a `description` field. Good descriptions make
workflows self-documenting and easier to maintain.

```pseudocode
DESCRIPTION_COVERAGE():
  total_nodes = computed.metrics.nodes.total
  nodes_with_description = count(nodes where "description" field is present AND non-empty)

  coverage_pct = (nodes_with_description / total_nodes) * 100

  IF coverage_pct == 100:
    computed.quality.description = { score: 100, rating: "excellent", detail: "All nodes documented" }
  ELIF coverage_pct >= 80:
    computed.quality.description = { score: round(coverage_pct), rating: "good", detail: "{coverage_pct}% coverage" }
  ELIF coverage_pct >= 50:
    computed.quality.description = { score: round(coverage_pct), rating: "fair", detail: "{coverage_pct}% coverage" }
  ELSE:
    computed.quality.description = { score: round(coverage_pct), rating: "poor", detail: "Only {coverage_pct}% of nodes have descriptions" }

  # Track which nodes are missing descriptions
  computed.quality.description.missing = [id for id, node in nodes if "description" not in node]
```

### Step 3.2: Error Handling Coverage

Measure what percentage of action nodes have `on_failure` transitions pointing to
meaningful error endings (not just a generic catch-all).

```pseudocode
ERROR_HANDLING_COVERAGE():
  action_nodes = [n for n in nodes if n.type == "action"]
  total_action = len(action_nodes)

  IF total_action == 0:
    computed.quality.error_handling = { score: 100, rating: "n/a", detail: "No action nodes" }
    RETURN

  nodes_with_failure = count(n for n in action_nodes if n.on_failure is defined)
  nodes_with_meaningful_failure = count(n for n in action_nodes
    if n.on_failure is defined
    AND n.on_failure != "cancelled"  # Generic catch-all does not count
    AND n.on_failure in computed.metrics.error_ending_ids)

  # Base score from having on_failure at all
  basic_pct = (nodes_with_failure / total_action) * 100

  # Bonus for meaningful (specific) error endings
  meaningful_pct = (nodes_with_meaningful_failure / total_action) * 100

  # Weighted: 60% for having on_failure, 40% for specific error ending
  score = round(basic_pct * 0.6 + meaningful_pct * 0.4)

  IF score >= 90:
    rating = "excellent"
  ELIF score >= 70:
    rating = "good"
  ELIF score >= 50:
    rating = "fair"
  ELSE:
    rating = "poor"

  computed.quality.error_handling = {
    score: score,
    rating: rating,
    detail: "{nodes_with_failure}/{total_action} have on_failure, {nodes_with_meaningful_failure} with specific error endings",
    missing: [id for id, n in action_nodes if n.on_failure is not defined]
  }
```

### Step 3.3: Subflow Usage

Detect `reference` nodes that delegate to subflows. More subflow usage indicates better
modularity and reuse.

```pseudocode
SUBFLOW_USAGE():
  reference_nodes = [n for n in nodes if n.type == "reference"]
  ref_count = len(reference_nodes)
  total_nodes = computed.metrics.nodes.total

  IF total_nodes <= 5:
    # Small workflows do not need subflows
    computed.quality.modularity = { score: 100, rating: "n/a", detail: "Workflow too small to require subflows" }
    RETURN

  # Ratio of reference nodes to total nodes
  ref_ratio = ref_count / total_nodes

  IF ref_count >= 3 OR ref_ratio >= 0.2:
    score = 100
    rating = "excellent"
    detail = "{ref_count} subflow delegations ({round(ref_ratio * 100)}% of nodes)"
  ELIF ref_count >= 1:
    score = 70
    rating = "good"
    detail = "{ref_count} subflow delegation(s)"
  ELIF total_nodes > 15:
    score = 30
    rating = "poor"
    detail = "No subflow delegations in a {total_nodes}-node workflow -- consider extracting reusable subflows"
  ELSE:
    score = 60
    rating = "fair"
    detail = "No subflow delegations, but workflow is moderately sized"

  computed.quality.modularity = {
    score: score,
    rating: rating,
    detail: detail,
    references: [{ id: n.id, doc: n.doc } for n in reference_nodes]
  }
```

### Step 3.4: Naming Consistency

Check whether node IDs follow a consistent naming convention. Well-named nodes use
snake_case and optionally include a type prefix.

```pseudocode
NAMING_CONSISTENCY():
  node_ids = list(nodes.keys())
  total = len(node_ids)

  # Check snake_case compliance
  snake_case_pattern = /^[a-z][a-z0-9]*(_[a-z0-9]+)*$/
  snake_case_count = count(id for id in node_ids if matches(id, snake_case_pattern))

  # Check for type-prefix convention (e.g., "check_", "prompt_", "ref_")
  type_prefixes = {
    "action":      ["do_", "run_", "exec_", "perform_", "set_", "save_", "load_", "write_", "read_"],
    "conditional":  ["check_", "is_", "has_", "validate_", "verify_", "if_"],
    "user_prompt":  ["prompt_", "ask_", "select_", "choose_", "confirm_"],
    "reference":    ["ref_", "sub_", "call_", "invoke_"]
  }

  prefix_matches = 0
  FOR id, node IN nodes:
    expected_prefixes = type_prefixes.get(node.type, [])
    IF any(id.startswith(prefix) for prefix in expected_prefixes):
      prefix_matches += 1

  snake_pct = (snake_case_count / total) * 100
  prefix_pct = (prefix_matches / total) * 100

  # Weighted: 70% snake_case, 30% type prefix
  score = round(snake_pct * 0.7 + prefix_pct * 0.3)

  IF score >= 90:
    rating = "excellent"
  ELIF score >= 70:
    rating = "good"
  ELIF score >= 50:
    rating = "fair"
  ELSE:
    rating = "poor"

  computed.quality.naming = {
    score: score,
    rating: rating,
    detail: "{snake_case_count}/{total} snake_case, {prefix_matches}/{total} type-prefixed",
    violations: [id for id in node_ids if not matches(id, snake_case_pattern)]
  }
```

> **Detail:** See `patterns/quality-indicators.md` for the complete scoring rubric.

Store all quality scores in `computed.quality`.

---

## Phase 4: Pattern Detection

Identify common structural patterns and anti-patterns in the workflow graph.
Results are stored in `computed.patterns` and `computed.anti_patterns`.

### Step 4.1: Gate Pattern

A gate pattern is a conditional node that validates a precondition, routes to an action
on success, and routes to an error ending on failure. This is the workflow equivalent of
a guard clause.

```pseudocode
DETECT_GATE_PATTERN():
  computed.patterns.gates = []

  FOR id, node IN nodes:
    IF node.type != "conditional":
      CONTINUE

    true_target = nodes.get(node.branches.on_true)
    false_target_is_ending = node.branches.on_false IN endings

    IF true_target AND true_target.type == "action" AND false_target_is_ending:
      computed.patterns.gates.append({
        gate_node: id,
        pass_target: node.branches.on_true,
        fail_ending: node.branches.on_false,
        condition_type: node.condition.type
      })

  computed.patterns.gate_count = len(computed.patterns.gates)
```

### Step 4.2: Loop Pattern

A loop pattern occurs when a node (or a chain of nodes) eventually references itself,
creating a cycle. Loops must have an explicit break condition (a conditional that exits
the cycle).

```pseudocode
DETECT_LOOP_PATTERN():
  computed.patterns.loops = []

  # For each node, trace forward to see if we revisit it
  FOR start_id IN nodes:
    visited = set()
    path = []

    function TRACE(current_id):
      IF current_id == start_id AND len(path) > 0:
        # Found a cycle back to start
        computed.patterns.loops.append({
          loop_start: start_id,
          cycle_path: list(path),
          cycle_length: len(path)
        })
        RETURN

      IF current_id IN visited OR current_id IN endings:
        RETURN

      visited.add(current_id)
      path.append(current_id)
      node = nodes[current_id]

      # Follow all outgoing edges
      SWITCH node.type:
        CASE "action":
          TRACE(node.on_success)
        CASE "conditional":
          TRACE(node.branches.on_true)
          TRACE(node.branches.on_false)
        CASE "user_prompt":
          FOR option IN node.on_response:
            TRACE(option.next_node)
        CASE "reference":
          TRACE(node.next_node)

      path.pop()
      visited.remove(current_id)

    TRACE(start_id)

  # Check loops have break conditions
  FOR loop IN computed.patterns.loops:
    has_break = any(
      nodes[n].type == "conditional" AND
      (nodes[n].branches.on_true NOT IN loop.cycle_path OR
       nodes[n].branches.on_false NOT IN loop.cycle_path)
      for n in loop.cycle_path if n in nodes
    )
    loop.has_break_condition = has_break

  computed.patterns.loop_count = len(computed.patterns.loops)
```

### Step 4.3: Delegation Pattern

A delegation pattern uses `invoke_skill` consequence types within action nodes to hand off
work to another skill. This is a horizontal composition pattern distinct from subflow
references (vertical composition).

```pseudocode
DETECT_DELEGATION_PATTERN():
  computed.patterns.delegations = []

  FOR id, node IN nodes:
    IF node.type != "action":
      CONTINUE

    FOR action IN node.actions:
      IF action.type == "invoke_skill":
        computed.patterns.delegations.append({
          source_node: id,
          target_skill: action.skill,
          args: action.get("args", {}),
          context: action.get("context", {})
        })

  computed.patterns.delegation_count = len(computed.patterns.delegations)
```

### Step 4.4: Anti-Patterns

Detect structural problems that indicate poor workflow design. Each anti-pattern has a
severity level: `warning` (should fix) or `error` (must fix).

#### Deep Nesting (Warning)

Branch depth exceeding 4 levels makes workflows hard to follow and maintain:

```pseudocode
DETECT_DEEP_NESTING():
  IF computed.metrics.max_branch_depth > 4:
    computed.anti_patterns.deep_nesting = {
      severity: "warning",
      depth: computed.metrics.max_branch_depth,
      message: "Max branch depth is {depth}. Consider extracting deep branches into subflows.",
      threshold: 4
    }
```

#### God Nodes (Warning)

Action nodes with more than 5 actions pack too much logic into a single step:

```pseudocode
DETECT_GOD_NODES():
  computed.anti_patterns.god_nodes = []

  FOR id, node IN nodes:
    IF node.type == "action" AND len(node.actions) > 5:
      computed.anti_patterns.god_nodes.append({
        severity: "warning",
        node_id: id,
        action_count: len(node.actions),
        message: "Node '{id}' has {len(node.actions)} actions. Split into multiple nodes for clarity."
      })
```

#### Missing Error Paths (Error)

Action nodes without `on_failure` transitions create implicit failure behavior:

```pseudocode
DETECT_MISSING_ERROR_PATHS():
  computed.anti_patterns.missing_error_paths = []

  FOR id, node IN nodes:
    IF node.type == "action" AND node.on_failure is not defined:
      computed.anti_patterns.missing_error_paths.append({
        severity: "error",
        node_id: id,
        message: "Node '{id}' has no on_failure transition. Add explicit error handling."
      })
```

#### Orphan Nodes (Error)

Nodes that are unreachable from the start node. These indicate dead code in the workflow:

```pseudocode
DETECT_ORPHAN_NODES():
  # BFS from start_node to find all reachable nodes
  reachable = set()
  queue = [workflow.start_node]

  WHILE queue is not empty:
    current = queue.pop(0)
    IF current IN reachable OR current IN endings:
      CONTINUE
    reachable.add(current)
    node = nodes.get(current)
    IF node is None:
      CONTINUE

    # Add all outgoing targets to queue
    SWITCH node.type:
      CASE "action":
        queue.append(node.on_success)
        IF node.on_failure:
          queue.append(node.on_failure)
      CASE "conditional":
        queue.append(node.branches.on_true)
        queue.append(node.branches.on_false)
      CASE "user_prompt":
        FOR option IN node.on_response:
          queue.append(option.next_node)
      CASE "reference":
        queue.append(node.next_node)

  all_node_ids = set(nodes.keys())
  orphans = all_node_ids - reachable

  computed.anti_patterns.orphan_nodes = [
    {
      severity: "error",
      node_id: id,
      message: "Node '{id}' is unreachable from start_node '{workflow.start_node}'. Remove or reconnect."
    }
    for id in orphans
  ]
```

#### Dead-End Nodes (Warning)

Nodes with no outgoing transitions that are not endings. These cause the workflow to stall:

```pseudocode
DETECT_DEAD_END_NODES():
  computed.anti_patterns.dead_ends = []

  FOR id, node IN nodes:
    has_outgoing = false

    SWITCH node.type:
      CASE "action":
        has_outgoing = node.on_success is defined
      CASE "conditional":
        has_outgoing = node.branches.on_true is defined AND node.branches.on_false is defined
      CASE "user_prompt":
        has_outgoing = len(node.on_response) > 0
      CASE "reference":
        has_outgoing = node.next_node is defined

    IF NOT has_outgoing:
      computed.anti_patterns.dead_ends.append({
        severity: "warning",
        node_id: id,
        node_type: node.type,
        message: "Node '{id}' ({node.type}) has no outgoing transitions. Add a transition or convert to an ending."
      })
```

Store all pattern and anti-pattern results in `computed.patterns` and `computed.anti_patterns`.

---

## Phase 5: Recommendations

Generate prioritized recommendations based on the metrics, quality scores, patterns, and
anti-patterns collected in Phases 2-4. Recommendations are stored in `computed.recommendations`
as an ordered list.

### Step 5.1: Schema Upgrade Suggestions

```pseudocode
SCHEMA_RECOMMENDATIONS():
  computed.recommendations.schema = []

  # Check for deprecated node types
  IF any(node.type == "validation_gate" for node in nodes):
    computed.recommendations.schema.append({
      priority: "high",
      category: "schema",
      message: "Replace validation_gate nodes with conditional + audit mode (deprecated in v2.0).",
      affected: [id for id, n in nodes if n.type == "validation_gate"]
    })

  # Check definitions source version
  IF workflow.definitions.source is defined:
    current_version = extract_version(workflow.definitions.source)
    # Compare against latest known version from BLUEPRINT_LIB_VERSION.yaml
    IF current_version < latest_lib_version:
      computed.recommendations.schema.append({
        priority: "medium",
        category: "schema",
        message: "Update definitions source from {current_version} to {latest_lib_version}."
      })

  # Check for missing output/prompts config (required in v2.4+)
  IF workflow.initial_state.output is not defined:
    computed.recommendations.schema.append({
      priority: "medium",
      category: "schema",
      message: "Add output configuration to initial_state (required since v2.4)."
    })

  IF workflow.initial_state.prompts is not defined:
    computed.recommendations.schema.append({
      priority: "medium",
      category: "schema",
      message: "Add prompts configuration to initial_state (required since v2.4)."
    })
```

### Step 5.2: Refactoring Opportunities

```pseudocode
REFACTORING_RECOMMENDATIONS():
  computed.recommendations.refactoring = []

  # Extract subflows from deep branches
  IF computed.metrics.max_branch_depth > 3:
    computed.recommendations.refactoring.append({
      priority: "medium",
      category: "refactoring",
      message: "Branch depth of {computed.metrics.max_branch_depth} detected. Extract nested branches into subflows to reduce depth."
    })

  # Split god nodes
  FOR anti IN computed.anti_patterns.god_nodes:
    computed.recommendations.refactoring.append({
      priority: "medium",
      category: "refactoring",
      message: "Split node '{anti.node_id}' ({anti.action_count} actions) into smaller, focused action nodes."
    })

  # Large workflow extraction
  IF computed.metrics.nodes.total > 20:
    computed.recommendations.refactoring.append({
      priority: "low",
      category: "refactoring",
      message: "Workflow has {computed.metrics.nodes.total} nodes. Consider decomposing into subflows for maintainability."
    })

  # Loops without break conditions
  FOR loop IN computed.patterns.loops:
    IF NOT loop.has_break_condition:
      computed.recommendations.refactoring.append({
        priority: "high",
        category: "refactoring",
        message: "Loop starting at '{loop.loop_start}' has no break condition. Add a conditional node to exit the cycle."
      })
```

### Step 5.3: Quality Improvements

```pseudocode
QUALITY_RECOMMENDATIONS():
  computed.recommendations.quality = []

  IF computed.quality.description.score < 80:
    computed.recommendations.quality.append({
      priority: "low",
      category: "quality",
      message: "Add descriptions to undocumented nodes: {', '.join(computed.quality.description.missing)}."
    })

  IF computed.quality.error_handling.score < 70:
    computed.recommendations.quality.append({
      priority: "high",
      category: "quality",
      message: "Add on_failure transitions to action nodes: {', '.join(computed.quality.error_handling.missing)}."
    })

  IF computed.quality.naming.score < 70:
    computed.recommendations.quality.append({
      priority: "low",
      category: "quality",
      message: "Rename non-conforming node IDs to snake_case: {', '.join(computed.quality.naming.violations)}."
    })

  IF len(computed.metrics.state_variables.undeclared_mutations) > 0:
    computed.recommendations.quality.append({
      priority: "medium",
      category: "quality",
      message: "Declare missing state variables in initial_state: {', '.join(computed.metrics.state_variables.undeclared_mutations)}."
    })

  IF len(computed.metrics.state_variables.unreferenced_declared) > 0:
    computed.recommendations.quality.append({
      priority: "low",
      category: "quality",
      message: "Remove unused state variables from initial_state: {', '.join(computed.metrics.state_variables.unreferenced_declared)}."
    })
```

Merge all recommendation lists and sort by priority (high > medium > low):

```pseudocode
FINALIZE_RECOMMENDATIONS():
  all_recs = (
    computed.recommendations.schema
    + computed.recommendations.refactoring
    + computed.recommendations.quality
  )

  priority_order = { "high": 0, "medium": 1, "low": 2 }
  computed.recommendations.all = sorted(all_recs, key=lambda r: priority_order[r.priority])
  computed.recommendations.total = len(all_recs)
  computed.recommendations.by_priority = {
    "high":   count(r for r in all_recs if r.priority == "high"),
    "medium": count(r for r in all_recs if r.priority == "medium"),
    "low":    count(r for r in all_recs if r.priority == "low")
  }
```

---

## Phase 6: Report

### Step 6.1: Render Analysis Dashboard

Present the complete analysis as a structured report. Compute an overall health score
as a weighted average of all quality dimensions:

```pseudocode
COMPUTE_OVERALL_SCORE():
  weights = {
    description: 0.20,
    error_handling: 0.35,
    modularity: 0.20,
    naming: 0.10,
    anti_patterns: 0.15
  }

  # Anti-pattern score: start at 100, deduct per finding
  anti_pattern_count = (
    len(computed.anti_patterns.deep_nesting or [])
    + len(computed.anti_patterns.god_nodes)
    + len(computed.anti_patterns.missing_error_paths)
    + len(computed.anti_patterns.orphan_nodes)
    + len(computed.anti_patterns.dead_ends)
  )
  anti_pattern_score = max(0, 100 - (anti_pattern_count * 15))

  computed.overall_score = round(
    computed.quality.description.score * weights.description
    + computed.quality.error_handling.score * weights.error_handling
    + computed.quality.modularity.score * weights.modularity
    + computed.quality.naming.score * weights.naming
    + anti_pattern_score * weights.anti_patterns
  )
```

Display the dashboard:

```
## Workflow Analysis Report: {computed.workflow_name}

**Path:** {computed.workflow_path}
**Version:** {computed.workflow_version}
**Overall Health:** {computed.overall_score}/100

---

### Complexity Metrics

| Metric | Value |
|--------|-------|
| Total nodes | {computed.metrics.nodes.total} |
| Action nodes | {computed.metrics.nodes.action} |
| Conditional nodes | {computed.metrics.nodes.conditional} |
| User prompt nodes | {computed.metrics.nodes.user_prompt} |
| Reference nodes | {computed.metrics.nodes.reference} |
| Total actions | {computed.metrics.total_actions} |
| Endings (success/error) | {computed.metrics.endings.success} / {computed.metrics.endings.error} |
| Max branch depth | {computed.metrics.max_branch_depth} |
| Cyclomatic complexity | {computed.metrics.cyclomatic_complexity} |
| State variables (declared) | {computed.metrics.state_variables.declared} |
| State variables (mutated) | {computed.metrics.state_variables.mutated} |

### Quality Scores

| Dimension | Score | Rating | Detail |
|-----------|-------|--------|--------|
| Description coverage | {computed.quality.description.score}/100 | {computed.quality.description.rating} | {computed.quality.description.detail} |
| Error handling | {computed.quality.error_handling.score}/100 | {computed.quality.error_handling.rating} | {computed.quality.error_handling.detail} |
| Modularity (subflows) | {computed.quality.modularity.score}/100 | {computed.quality.modularity.rating} | {computed.quality.modularity.detail} |
| Naming consistency | {computed.quality.naming.score}/100 | {computed.quality.naming.rating} | {computed.quality.naming.detail} |
| **Overall health** | **{computed.overall_score}/100** | | |

### Patterns Detected

| Pattern | Count | Details |
|---------|-------|---------|
| Gate patterns | {computed.patterns.gate_count} | {for g in computed.patterns.gates: g.gate_node -> g.pass_target} |
| Loop patterns | {computed.patterns.loop_count} | {for l in computed.patterns.loops: l.loop_start (len={l.cycle_length}, break={l.has_break_condition})} |
| Delegation patterns | {computed.patterns.delegation_count} | {for d in computed.patterns.delegations: d.source_node -> d.target_skill} |

### Anti-Pattern Warnings

{IF no anti-patterns found:}
No anti-patterns detected.

{ELSE for each anti-pattern category with findings:}
| Severity | Anti-Pattern | Node | Message |
|----------|-------------|------|---------|
{for ap in all_anti_patterns, sorted by severity descending:}
| {ap.severity} | {ap.category} | {ap.node_id} | {ap.message} |
{/for}

### Recommendations ({computed.recommendations.total})

Sorted by priority: {computed.recommendations.by_priority.high} high,
{computed.recommendations.by_priority.medium} medium, {computed.recommendations.by_priority.low} low.

{for i, rec in enumerate(computed.recommendations.all):}
{i+1}. **[{rec.priority}]** [{rec.category}] {rec.message}
{/for}
```

### Step 6.2: Offer Next Actions

After presenting the report, ask what the user wants to do next:

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {
        "label": "Refactor workflow",
        "description": "Apply recommended refactorings to improve the workflow"
      },
      {
        "label": "Validate workflow",
        "description": "Run full schema and structural validation"
      },
      {
        "label": "Visualize workflow",
        "description": "Generate a Mermaid diagram of the workflow graph"
      },
      {
        "label": "Export report",
        "description": "Save the analysis report to a file"
      },
      {
        "label": "Done",
        "description": "No further action needed"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_ACTION(response):
  SWITCH response:
    CASE "Refactor workflow":
      DISPLAY "To refactor this workflow, invoke:"
      DISPLAY "  Skill(skill: 'bp-skill-refactor', args: '{computed.workflow_path}')"
      DISPLAY "The refactor skill will use the analysis data from computed.* to apply changes."
    CASE "Validate workflow":
      DISPLAY "To validate this workflow, invoke:"
      DISPLAY "  Skill(skill: 'bp-skill-validate', args: '{computed.workflow_path}')"
      DISPLAY "Validation checks schema compliance, reachability, and type safety."
    CASE "Visualize workflow":
      DISPLAY "To visualize this workflow, invoke:"
      DISPLAY "  Skill(skill: 'bp-visualize', args: '{computed.workflow_path}')"
      DISPLAY "Generates a Mermaid flowchart diagram from the workflow graph."
    CASE "Export report":
      # Write the dashboard to a markdown file alongside the workflow
      report_path = parent_directory(computed.workflow_path) + "/analysis-report.md"
      DISPLAY "Analysis report saved to {report_path}."
    CASE "Done":
      DISPLAY "Analysis complete. {computed.recommendations.total} recommendations generated for {computed.workflow_name}."
      EXIT
```

---

## Reference Documentation

- **Complexity Scoring Algorithm:** `patterns/complexity-scoring-algorithm.md` (local to this skill)
- **Quality Indicators:** `patterns/quality-indicators.md` (local to this skill)
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Blueprint Lib Version:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`

---

## Related Skills

- Prose-based skill analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-prose-analyze/SKILL.md`
- Workflow validation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/SKILL.md`
- Workflow refactoring: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-refactor/SKILL.md`
- Workflow visualization: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-visualize/SKILL.md`
- Plugin-level analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-plugin-analyze/SKILL.md`
