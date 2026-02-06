---
name: bp-author-skill-refactor
description: >
  This skill should be used when the user asks to "refactor workflow", "restructure workflow",
  "extract subflow", "inline subflow", "split workflow", "merge workflows", "rename nodes",
  "cleanup workflow", or needs to restructure a workflow.yaml. Triggers on "refactor",
  "restructure", "extract subflow", "inline", "split", "merge", "rename nodes", "cleanup dead code".
allowed-tools: Read, Write, Edit, Glob, AskUserQuestion
---

# Refactor Workflow

Guided restructuring of a workflow.yaml through extract, inline, split, merge, rename, and cleanup operations. Analyzes the workflow, identifies refactoring candidates, and executes the selected operation with full transition rewiring and validation.

---

## Procedure Overview

```
┌──────────────────────────┐
│ Phase 1: Load & Analyze  │
│   Parse workflow, detect  │
│   refactoring candidates  │
└────────────┬─────────────┘
             │
┌────────────▼─────────────┐
│ Phase 2: Select Operation│
│   User chooses operation  │
└────────────┬─────────────┘
             │
     ┌───────┴───────┬──────────┬──────────┬──────────┐
     ▼               ▼          ▼          ▼          ▼
┌─────────┐   ┌──────────┐┌─────────┐┌─────────┐┌─────────┐
│ 3A:     │   │ 3B:      ││ 3C:     ││ 3D:     ││ 3E:     │
│ Extract │   │ Inline   ││ Split   ││ Rename  ││ Cleanup │
│ Subflow │   │ Subflow  ││ Workflow││ Nodes   ││ Dead    │
└────┬────┘   └────┬─────┘└────┬────┘└────┬────┘└────┬────┘
     └───────┬─────┘───────┬───┘──────────┘──────────┘
             ▼
┌──────────────────────────┐
│ Phase 4: Validate        │
│   Check result, show diff│
└──────────────────────────┘
```

---

## Phase 1: Load & Analyze

### Step 1.1: Path Resolution

Determine the workflow.yaml to refactor.

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
    "question": "Which workflow.yaml should I refactor?",
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

### Step 1.2: Parse Workflow and Run Quick Analysis

1. Read the file at `computed.workflow_path`.
2. Parse the YAML content. Store the parsed structure in `computed.workflow`.
3. Verify basic structure exists: `name`, `start_node`, `nodes`, `endings`. If any are missing, report error and stop.
4. Compute quick analysis metrics:

```
computed.analysis = {
  node_count:     len(computed.workflow.nodes),
  ending_count:   len(computed.workflow.endings),
  node_types:     count_by_type(computed.workflow.nodes),    # {action: N, conditional: N, ...}
  branch_depth:   max_branch_depth(computed.workflow),
  reference_nodes: [id for id, n in nodes if n.type == "reference"],
  action_counts:  {id: len(n.actions) for id, n in nodes if n.type == "action"},
  has_subflows:   any(n.type == "reference" for n in nodes.values()),
  complexity:     "low" if node_count <= 8 else "medium" if node_count <= 20 else "high"
}
```

Where `max_branch_depth` performs a DFS tracking the maximum nesting level of conditional and user_prompt branches:

```pseudocode
function max_branch_depth(workflow):
  visited = set()
  max_depth = 0

  function dfs(node_id, current_depth):
    if node_id in visited or node_id not in workflow.nodes:
      return
    visited.add(node_id)
    node = workflow.nodes[node_id]

    if node.type in ["conditional", "user_prompt"]:
      branch_depth = current_depth + 1
      max_depth = max(max_depth, branch_depth)
      for target in get_all_transition_targets(node_id, node):
        dfs(target, branch_depth)
    else:
      for target in get_all_transition_targets(node_id, node):
        dfs(target, current_depth)

  dfs(workflow.start_node, 0)
  return max_depth
```

### Step 1.3: Identify Refactoring Candidates

Scan the workflow structure for patterns that suggest specific refactoring operations:

```pseudocode
computed.candidates = []

# God nodes: action nodes with too many consequences
for node_id, node in computed.workflow.nodes:
  if node.type == "action" and len(node.actions) > 5:
    computed.candidates.append({
      type: "extract",
      node: node_id,
      reason: "god node",
      detail: "Action node '${node_id}' has ${len(node.actions)} actions (threshold: 5). Consider extracting into a subflow."
    })

# Trivial subflows: reference nodes pointing to very small workflows
for node_id, node in computed.workflow.nodes:
  if node.type == "reference":
    if has_field(node, "workflow") or has_field(node, "doc"):
      target_path = resolve_reference_path(node)
      if target_path and file_exists(target_path):
        target_content = Read(target_path)
        target_workflow = parse_yaml(target_content)
        if target_workflow and len(target_workflow.get("nodes", {})) <= 3:
          computed.candidates.append({
            type: "inline",
            node: node_id,
            reason: "trivial subflow",
            detail: "Reference node '${node_id}' points to a subflow with only ${len(target_workflow.nodes)} nodes. Consider inlining."
          })

# Large workflows: suggest splitting
if computed.analysis.node_count > 20:
  computed.candidates.append({
    type: "split",
    reason: "large workflow",
    detail: "Workflow has ${computed.analysis.node_count} nodes. Consider splitting into smaller focused workflows."
  })

# Deep branching: suggest restructuring
if computed.analysis.branch_depth > 3:
  computed.candidates.append({
    type: "extract",
    reason: "deep branching",
    detail: "Branch depth is ${computed.analysis.branch_depth}. Consider extracting deeply nested branches into subflows."
  })

# Orphan detection: unreachable nodes
computed.orphans = find_orphans(computed.workflow)
if computed.orphans:
  computed.candidates.append({
    type: "cleanup",
    nodes: computed.orphans,
    reason: "dead code",
    detail: "Found ${len(computed.orphans)} unreachable node(s): ${computed.orphans}. Consider removing."
  })

# Unused endings: endings not referenced by any node
computed.unused_endings = find_unused_endings(computed.workflow)
if computed.unused_endings:
  computed.candidates.append({
    type: "cleanup",
    nodes: computed.unused_endings,
    reason: "unused endings",
    detail: "Found ${len(computed.unused_endings)} ending(s) not referenced by any node: ${computed.unused_endings}."
  })
```

Where `find_orphans` performs BFS from `start_node` and returns unvisited node IDs:

```pseudocode
function find_orphans(workflow):
  visited = set()
  queue = [workflow.start_node]
  while queue:
    current = queue.pop(0)
    if current in visited or current not in workflow.nodes:
      continue
    visited.add(current)
    for target in get_all_transition_targets(current, workflow.nodes[current]):
      if target not in visited and not target.startswith("${"):
        queue.append(target)
  return set(workflow.nodes.keys()) - visited
```

Where `find_unused_endings` collects all transition targets and compares against ending IDs:

```pseudocode
function find_unused_endings(workflow):
  all_targets = set()
  for node_id, node in workflow.nodes:
    for target in get_all_transition_targets(node_id, node):
      all_targets.add(target)
  return set(workflow.endings.keys()) - all_targets
```

### Step 1.4: Present Analysis and Candidates

Display the analysis summary and candidates to the user:

```
## Workflow Analysis: {computed.workflow.name}

**Path:** {computed.workflow_path}
**Nodes:** {computed.analysis.node_count} ({computed.analysis.node_types})
**Endings:** {computed.analysis.ending_count}
**Branch depth:** {computed.analysis.branch_depth}
**Complexity:** {computed.analysis.complexity}
**Has subflows:** {computed.analysis.has_subflows}

### Refactoring Candidates

{if computed.candidates}
{for i, candidate in enumerate(computed.candidates)}
{i+1}. **{candidate.type}** -- {candidate.detail}
{/for}
{else}
No automatic refactoring candidates detected. You can still perform manual operations.
{/if}
```

---

## Phase 2: Select Operation

Present the user with the available refactoring operations. Include additional context-sensitive options based on the candidates detected in Phase 1.

```json
{
  "questions": [{
    "question": "Which refactoring operation would you like to perform?",
    "header": "Operation",
    "multiSelect": false,
    "options": [
      {
        "label": "Extract subflow",
        "value": "extract",
        "description": "Move a group of nodes into a separate subflow file"
      },
      {
        "label": "Inline subflow",
        "value": "inline",
        "description": "Expand a reference node back into the parent workflow"
      },
      {
        "label": "Split workflow",
        "value": "split",
        "description": "Break one large workflow into two smaller ones"
      },
      {
        "label": "Rename nodes",
        "value": "rename",
        "description": "Rename node IDs and update all references"
      },
      {
        "label": "Cleanup dead code",
        "value": "cleanup",
        "description": "Remove unreachable nodes and unused state variables"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
computed.selected_operation = user_response.questions[0].answer

# If user chose an operation with a specific candidate, pre-populate the target
if computed.selected_operation == "extract" and any(c.type == "extract" for c in computed.candidates):
  computed.suggested_nodes = [c.node for c in computed.candidates if c.type == "extract"]
if computed.selected_operation == "inline" and any(c.type == "inline" for c in computed.candidates):
  computed.suggested_nodes = [c.node for c in computed.candidates if c.type == "inline"]
if computed.selected_operation == "cleanup":
  computed.cleanup_targets = {
    orphans: computed.orphans or [],
    unused_endings: computed.unused_endings or []
  }
```

Store in `computed.selected_operation` and route to the corresponding Phase 3 sub-phase.

---

## Phase 3: Execute Operation

Each operation is a self-contained sub-phase. Route based on `computed.selected_operation`.

### Phase 3A: Extract Subflow

> **Detail:** See `patterns/extract-subflow-procedure.md` for the complete step-by-step with before/after YAML examples.

#### Step 3A.1: Select Nodes for Extraction

If `computed.suggested_nodes` is populated from candidate detection, present them as defaults. Otherwise, ask the user to select nodes:

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "Which nodes should be extracted into a subflow?",
    "header": "Nodes",
    "multiSelect": true,
    "options_from_state": "computed.node_list"
  }
}
```

Where `computed.node_list` is built from the workflow nodes:

```pseudocode
computed.node_list = [
  {
    id: node_id,
    label: node_id,
    description: "${node.type} - ${node.description or 'no description'} (${len(node.actions) if node.type == 'action' else 'N/A'} actions)"
  }
  for node_id, node in computed.workflow.nodes
  if node_id != computed.workflow.start_node  # Don't extract start node
]
```

Store selected node IDs in `computed.extract_nodes`.

#### Step 3A.2: Identify Extraction Boundary

Analyze the selected nodes to determine the interface between the parent workflow and the new subflow:

```pseudocode
function identify_boundary(selected_nodes, workflow):
  selected_set = set(selected_nodes)
  all_nodes = workflow.nodes

  # Entry nodes: selected nodes with incoming transitions from outside the selection
  entry_nodes = []
  for node_id in selected_nodes:
    for other_id, other_node in all_nodes:
      if other_id not in selected_set:
        targets = get_all_transition_targets(other_id, other_node)
        if node_id in targets:
          entry_nodes.append(node_id)
          break

  # Exit transitions: transitions from selected nodes to nodes outside the selection
  exit_transitions = []
  for node_id in selected_nodes:
    node = all_nodes[node_id]
    for target in get_all_transition_targets(node_id, node):
      if target not in selected_set and not target.startswith("${"):
        exit_transitions.append({
          from_node: node_id,
          target: target,
          is_ending: target in workflow.endings
        })

  # Shared state: state variables read or written by both inside and outside nodes
  inside_reads = collect_state_reads(selected_nodes, all_nodes)
  inside_writes = collect_state_writes(selected_nodes, all_nodes)
  outside_reads = collect_state_reads(
    [n for n in all_nodes if n not in selected_set], all_nodes
  )
  outside_writes = collect_state_writes(
    [n for n in all_nodes if n not in selected_set], all_nodes
  )

  input_state = inside_reads & outside_writes    # Subflow reads what parent writes
  output_state = inside_writes & outside_reads   # Parent reads what subflow writes

  return {
    entry: entry_nodes,
    exits: exit_transitions,
    input_state: input_state,
    output_state: output_state
  }

computed.boundary = identify_boundary(computed.extract_nodes, computed.workflow)
```

If `len(computed.boundary.entry) > 1`, warn the user:

> Multiple entry points detected: {computed.boundary.entry}. A subflow should have a single entry. Consider selecting a contiguous group of nodes.

If `len(computed.boundary.entry) == 0`, error:

> No entry points found. The selected nodes are disconnected from the rest of the workflow.

#### Step 3A.3: Create Subflow File

Ask the user for the subflow name and file location:

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "What should the subflow be named?",
    "header": "Name",
    "options": [
      {
        "id": "auto",
        "label": "Auto-generate from nodes",
        "description": "Derive name from the extracted node IDs"
      },
      {
        "id": "custom",
        "label": "Custom name",
        "description": "I'll provide a name"
      }
    ]
  }
}
```

Build the subflow workflow.yaml:

```pseudocode
computed.subflow_name = auto_name or user_provided_name
computed.subflow_path = parent_directory(computed.workflow_path) + "/subflows/" + computed.subflow_name + ".yaml"

computed.subflow = {
  name: computed.subflow_name,
  version: computed.workflow.version or "1.0.0",
  description: "Subflow extracted from ${computed.workflow.name}",
  start_node: computed.boundary.entry[0],
  nodes: {id: computed.workflow.nodes[id] for id in computed.extract_nodes},
  endings: {}
}

# For each exit transition, create a subflow ending
for exit in computed.boundary.exits:
  if exit.is_ending:
    # Propagate the parent ending
    ending_id = exit.target
    computed.subflow.endings[ending_id] = computed.workflow.endings[ending_id]
  else:
    # Create a synthetic success ending for the resume point
    ending_id = "resume_" + exit.target
    computed.subflow.endings[ending_id] = {
      type: "success",
      message: "Resume parent workflow at ${exit.target}"
    }
    # Rewire the exit node's transition to point to this ending
    rewire_transition(computed.subflow.nodes[exit.from_node], exit.target, ending_id)
```

Write the subflow file using Write tool.

#### Step 3A.4: Replace Extracted Nodes with Reference in Parent

Remove the extracted nodes from the parent workflow and insert a reference node:

```pseudocode
# Remove extracted nodes
for node_id in computed.extract_nodes:
  del computed.workflow.nodes[node_id]

# Insert reference node
reference_node_id = "ref_" + computed.subflow_name
computed.workflow.nodes[reference_node_id] = {
  type: "reference",
  doc: relative_path(computed.workflow_path, computed.subflow_path),
  description: "Delegate to ${computed.subflow_name} subflow",
  next_node: computed.boundary.exits[0].target  # Primary resume point
}
```

#### Step 3A.5: Wire Parent Transitions

Update all transitions in the parent that previously pointed to the subflow entry node to now point to the reference node:

```pseudocode
for node_id, node in computed.workflow.nodes:
  update_transition_targets(node, computed.boundary.entry[0], reference_node_id)

# If start_node was the entry node, update it
if computed.workflow.start_node == computed.boundary.entry[0]:
  computed.workflow.start_node = reference_node_id
```

Write the updated parent workflow using Write tool.

---

### Phase 3B: Inline Subflow

> **Detail:** See `patterns/refactoring-operations.md` for the complete inline procedure.

#### Step 3B.1: Find Reference Node to Inline

If `computed.suggested_nodes` contains reference nodes, present them. Otherwise, list all reference nodes:

```pseudocode
computed.reference_nodes = [
  {id: node_id, node: node}
  for node_id, node in computed.workflow.nodes
  if node.type == "reference"
]
```

If no reference nodes exist, report:

> No reference nodes found in this workflow. Inline operation requires a reference node pointing to a subflow.

Then return to Phase 2 for a different operation.

Present the reference nodes as an AskUserQuestion and store the selection in `computed.inline_target`.

#### Step 3B.2: Read the Referenced Subflow

```pseudocode
computed.inline_ref = computed.workflow.nodes[computed.inline_target]
computed.subflow_path = resolve_reference_path(computed.inline_ref)
computed.subflow_content = Read(computed.subflow_path)
computed.subflow = parse_yaml(computed.subflow_content)
```

If the subflow file does not exist or is not valid YAML, report error and stop.

#### Step 3B.3: Copy Subflow Nodes into Parent

Check for node ID collisions between the subflow and parent. If collisions exist, prefix subflow node IDs:

```pseudocode
collision_ids = set(computed.subflow.nodes.keys()) & set(computed.workflow.nodes.keys())
if collision_ids:
  prefix = computed.subflow.name.replace("-", "_") + "_"
  computed.subflow = prefix_node_ids(computed.subflow, prefix)
```

Copy nodes from the subflow into the parent workflow:

```pseudocode
for node_id, node in computed.subflow.nodes:
  computed.workflow.nodes[node_id] = node
```

#### Step 3B.4: Rewire Transitions

Replace the reference node in the parent with the subflow's entry:

```pseudocode
# All transitions pointing to the reference node now point to the subflow's start_node
for node_id, node in computed.workflow.nodes:
  update_transition_targets(node, computed.inline_target, computed.subflow.start_node)

# If parent start_node was the reference, update it
if computed.workflow.start_node == computed.inline_target:
  computed.workflow.start_node = computed.subflow.start_node

# Rewire subflow endings: each subflow ending that maps to a resume point
# should be replaced by the reference node's next_node
resume_target = computed.inline_ref.next_node
for ending_id in computed.subflow.endings:
  for node_id, node in computed.workflow.nodes:
    update_transition_targets(node, ending_id, resume_target)
```

#### Step 3B.5: Remove Reference Node and Cleanup

```pseudocode
del computed.workflow.nodes[computed.inline_target]
# Subflow endings that were inlined are not added to parent endings
```

Write the updated workflow using Write tool.

---

### Phase 3C: Split Workflow

> **Detail:** See `patterns/refactoring-operations.md` for the complete split procedure.

#### Step 3C.1: Choose Split Point

Present the workflow nodes and ask the user where to split:

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "Which node should be the boundary? Nodes before this point go to workflow A, this node and after go to workflow B.",
    "header": "Split At",
    "multiSelect": false,
    "options_from_state": "computed.node_list_ordered"
  }
}
```

Where `computed.node_list_ordered` lists nodes in BFS order from start_node. Store the split point in `computed.split_node`.

#### Step 3C.2: Partition Nodes

Perform BFS from `start_node`, collecting nodes until reaching `computed.split_node`:

```pseudocode
function partition_at(workflow, split_node):
  workflow_a_nodes = set()
  queue = [workflow.start_node]

  while queue:
    current = queue.pop(0)
    if current == split_node or current not in workflow.nodes:
      continue
    if current in workflow_a_nodes:
      continue
    workflow_a_nodes.add(current)
    for target in get_all_transition_targets(current, workflow.nodes[current]):
      if target not in workflow_a_nodes and not target.startswith("${"):
        queue.append(target)

  workflow_b_nodes = set(workflow.nodes.keys()) - workflow_a_nodes
  return workflow_a_nodes, workflow_b_nodes

computed.partition_a, computed.partition_b = partition_at(computed.workflow, computed.split_node)
```

#### Step 3C.3: Create Two Workflow Files

**Workflow A:** Contains nodes before the split point. Add an `invoke_skill` consequence at the boundary to hand off to Workflow B.

```pseudocode
computed.workflow_a = {
  name: computed.workflow.name + "-part-a",
  version: computed.workflow.version,
  start_node: computed.workflow.start_node,
  nodes: {id: computed.workflow.nodes[id] for id in computed.partition_a},
  endings: {
    handoff_to_b: {
      type: "success",
      message: "Handing off to ${computed.workflow.name}-part-b"
    }
  }
}

# Rewire transitions from A nodes that point to B nodes to point to handoff ending
for node_id in computed.partition_a:
  node = computed.workflow_a.nodes[node_id]
  for target in get_all_transition_targets(node_id, node):
    if target in computed.partition_b:
      update_transition_targets(node, target, "handoff_to_b")

# Add invoke_skill action to final node before handoff
# (Insert a new action node that invokes workflow B)
computed.workflow_a.nodes["invoke_part_b"] = {
  type: "action",
  description: "Invoke part B of the split workflow",
  actions: [
    {
      type: "invoke_skill",
      skill: computed.workflow.name + "-part-b",
      pass_state: true
    }
  ],
  on_success: "handoff_to_b",
  on_failure: "error_handoff"
}
computed.workflow_a.endings["error_handoff"] = {
  type: "error",
  message: "Failed to invoke part B"
}
```

**Workflow B:** Contains nodes from the split point onward. Preserves the original endings.

```pseudocode
computed.workflow_b = {
  name: computed.workflow.name + "-part-b",
  version: computed.workflow.version,
  start_node: computed.split_node,
  nodes: {id: computed.workflow.nodes[id] for id in computed.partition_b},
  endings: computed.workflow.endings  # Keep original endings
}
```

Ask the user for output paths and write both files using Write tool.

---

### Phase 3D: Rename Nodes

> **Detail:** See `patterns/refactoring-operations.md` for the complete rename procedure.

#### Step 3D.1: Collect Rename Mapping

Ask the user for the renaming they want to perform:

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "How would you like to rename nodes?",
    "header": "Rename",
    "multiSelect": false,
    "options": [
      {
        "id": "single",
        "label": "Rename a single node",
        "description": "Change one node ID and update all references"
      },
      {
        "id": "prefix",
        "label": "Add/change prefix",
        "description": "Add or replace a prefix on all node IDs (e.g., 'old_' -> 'new_')"
      },
      {
        "id": "batch",
        "label": "Batch rename",
        "description": "Provide multiple old -> new mappings"
      }
    ]
  }
}
```

For each rename mode, build `computed.rename_map` as a dictionary of `{old_name: new_name}`.

- **single**: Ask for the node to rename (from `computed.node_list`) and the new name.
- **prefix**: Ask for the old prefix (or empty for none) and the new prefix. Build mapping for all matching nodes.
- **batch**: Ask the user to provide mappings. Validate that no new name collides with existing non-renamed node IDs.

#### Step 3D.2: Apply Renames

For each entry in `computed.rename_map`, update:

1. The node key in `computed.workflow.nodes`
2. All `on_success`, `on_failure` references
3. All `branches.on_true`, `branches.on_false` references
4. All `on_response.*.next_node` references
5. All `next_node` references on reference nodes
6. The `start_node` field if it matches a renamed node

```pseudocode
function apply_renames(workflow, rename_map):
  # Rename node keys
  new_nodes = {}
  for node_id, node in workflow.nodes:
    new_id = rename_map.get(node_id, node_id)
    new_nodes[new_id] = node

  # Update all transition targets
  for node_id, node in new_nodes:
    update_all_targets(node, rename_map)

  # Update start_node
  workflow.start_node = rename_map.get(workflow.start_node, workflow.start_node)

  workflow.nodes = new_nodes
```

Write the updated workflow using Edit tool (to preserve file structure) or Write tool.

---

### Phase 3E: Cleanup Dead Code

> **Detail:** See `patterns/refactoring-operations.md` for the complete cleanup procedure.

#### Step 3E.1: Identify All Dead Code

Collect unreachable nodes, unused endings, and unused state variables:

```pseudocode
computed.dead_code = {
  orphan_nodes: computed.orphans or find_orphans(computed.workflow),
  unused_endings: computed.unused_endings or find_unused_endings(computed.workflow),
  unused_state: find_unused_state(computed.workflow)
}
```

Where `find_unused_state` checks `initial_state` fields that are never read or written:

```pseudocode
function find_unused_state(workflow):
  declared_vars = set(workflow.initial_state.keys()) if workflow.initial_state else set()
  used_vars = set()

  # Scan all string values in nodes for ${...} interpolation
  for ref in find_all_interpolations(workflow.nodes):
    base_var = ref.split(".")[0]
    used_vars.add(base_var)

  # Scan consequence fields that reference state
  for node_id, node in workflow.nodes:
    if node.type == "action":
      for action in node.actions:
        if "field" in action:
          used_vars.add(action.field.split(".")[0])
        if "store_as" in action:
          used_vars.add(action.store_as.split(".")[0])
        if "flag" in action:
          used_vars.add("flags")

  # Standard runtime vars are always considered "used"
  always_used = {"phase", "flags", "computed", "prompts", "output", "logging",
                 "_semantics", "_semantics_loaded"}
  used_vars.update(always_used)

  return declared_vars - used_vars
```

#### Step 3E.2: Present for Confirmation

Display what will be removed and ask for confirmation:

```
## Dead Code Detected

{if computed.dead_code.orphan_nodes}
### Unreachable Nodes ({len(computed.dead_code.orphan_nodes)})
{for node_id in computed.dead_code.orphan_nodes}
- `{node_id}` ({computed.workflow.nodes[node_id].type})
{/for}
{/if}

{if computed.dead_code.unused_endings}
### Unused Endings ({len(computed.dead_code.unused_endings)})
{for ending_id in computed.dead_code.unused_endings}
- `{ending_id}` ({computed.workflow.endings[ending_id].type})
{/for}
{/if}

{if computed.dead_code.unused_state}
### Potentially Unused State Variables ({len(computed.dead_code.unused_state)})
{for var in computed.dead_code.unused_state}
- `{var}`
{/for}
{/if}
```

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "Which dead code items should be removed?",
    "header": "Remove",
    "multiSelect": true,
    "options": [
      {
        "id": "orphans",
        "label": "Unreachable nodes",
        "description": "Remove nodes not reachable from start_node"
      },
      {
        "id": "endings",
        "label": "Unused endings",
        "description": "Remove endings not referenced by any node"
      },
      {
        "id": "state",
        "label": "Unused state variables",
        "description": "Remove initial_state fields that appear unused"
      },
      {
        "id": "all",
        "label": "All of the above",
        "description": "Remove all detected dead code"
      }
    ]
  }
}
```

#### Step 3E.3: Remove Dead Code

```pseudocode
if "orphans" in response or "all" in response:
  for node_id in computed.dead_code.orphan_nodes:
    del computed.workflow.nodes[node_id]

if "endings" in response or "all" in response:
  for ending_id in computed.dead_code.unused_endings:
    del computed.workflow.endings[ending_id]

if "state" in response or "all" in response:
  for var in computed.dead_code.unused_state:
    del computed.workflow.initial_state[var]
```

Write the updated workflow using Write tool.

---

## Phase 4: Validate

### Step 4.1: Run Validation on Modified Workflow

After executing the selected operation, run validation on the modified workflow. Reuse the validation logic from `bp-author-skill-validate`:

```pseudocode
# Schema validation: verify all nodes have required fields
computed.validation.schema_ok = validate_schema(computed.workflow)

# Graph validation: verify reachability, ending paths, no new orphans
computed.validation.graph_ok = validate_graph(computed.workflow)

# Transition validation: verify all targets reference valid nodes or endings
computed.validation.transitions_ok = validate_transitions(computed.workflow)

computed.validation.issues = collect_all_issues()
```

If any errors are found, display them immediately.

### Step 4.2: Show Diff of Changes

Present a summary of what changed:

```
## Refactoring Complete: {computed.selected_operation}

### Changes Summary

**Before:**
- Nodes: {computed.analysis.node_count}
- Endings: {computed.analysis.ending_count}

**After:**
- Nodes: {len(computed.workflow.nodes)}
- Endings: {len(computed.workflow.endings)}

### Files Modified
{list of files written or edited}

{if computed.validation.issues}
### Validation Issues
{for issue in computed.validation.issues}
- [{issue.severity}] {issue.message}
{/for}
{/if}
```

### Step 4.3: Final Action

```json
{
  "tool": "AskUserQuestion",
  "params": {
    "question": "What would you like to do with the changes?",
    "header": "Confirm",
    "multiSelect": false,
    "options": [
      {
        "id": "save",
        "label": "Save changes",
        "description": "Keep the refactored workflow"
      },
      {
        "id": "review",
        "label": "Review full diff",
        "description": "Show the complete before/after comparison"
      },
      {
        "id": "undo",
        "label": "Undo changes",
        "description": "Revert to the original workflow"
      },
      {
        "id": "done",
        "label": "Done",
        "description": "Changes are already saved, exit"
      }
    ]
  }
}
```

**Response handling:**

- `save` -- Write the final `computed.workflow` to `computed.workflow_path`. Confirm with a summary message.
- `review` -- Display the full YAML diff between the original workflow content and the modified version. Then re-present this AskUserQuestion.
- `undo` -- Restore the original workflow content from the backup taken at the start of Phase 3. Write the original content back to `computed.workflow_path`.
- `done` -- Display final summary and exit.

---

## Reference Documentation

- **Extract Subflow Procedure:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-refactor/patterns/extract-subflow-procedure.md`
- **Refactoring Operations:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-refactor/patterns/refactoring-operations.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Schema Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/patterns/schema-validation-rules.md`
- **Graph Validation Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/patterns/graph-validation-algorithm.md`

---

## Related Skills

- **Validate workflow:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/SKILL.md`
- **Analyze skill structure:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-analyze/SKILL.md`
- **Visualize workflow:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-visualize/SKILL.md`
- **Create new skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-create/SKILL.md`
- **Upgrade skills:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-upgrade/SKILL.md`
