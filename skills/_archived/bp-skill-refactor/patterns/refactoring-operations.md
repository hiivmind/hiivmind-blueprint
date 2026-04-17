> **Used by:** `SKILL.md` Phases 3B-3E
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

# Refactoring Operations

Detailed procedures for inline, split, merge, rename, and cleanup refactoring operations on workflow.yaml files.

---

## Operation 1: Inline Subflow

The inverse of extraction. Expands a `reference` node back into the parent workflow by copying the subflow's nodes directly into the parent and rewiring all transitions.

### When to Inline

- The referenced subflow is trivial (3 or fewer nodes)
- The subflow is only used by this single parent (no reuse benefit)
- Debugging is easier with all nodes visible in one file
- Preparing to further refactor the combined workflow

### Procedure

```
function inline_subflow(parent_workflow, reference_node_id):
  ref_node = parent_workflow.nodes[reference_node_id]

  # Step 1: Resolve and load the subflow
  subflow_path = resolve_reference_path(ref_node)
  subflow = parse_yaml(Read(subflow_path))

  # Step 2: Handle node ID collisions
  parent_ids = set(parent_workflow.nodes.keys())
  subflow_ids = set(subflow.nodes.keys())
  collisions = parent_ids & subflow_ids

  if collisions:
    # Prefix all subflow node IDs to avoid collision
    prefix = subflow.name.replace("-", "_") + "_"
    subflow = rename_all_nodes(subflow, lambda id: prefix + id)

  # Step 3: Map subflow endings to parent targets
  # The reference node's next_node is where the parent resumes
  resume_target = ref_node.next_node
  ending_to_target = {}

  for ending_id, ending in subflow.endings:
    if ending.type == "success":
      ending_to_target[ending_id] = resume_target
    elif ending.type == "error":
      # Check if parent has a matching error ending
      matching_error = find_matching_error_ending(parent_workflow, ending)
      if matching_error:
        ending_to_target[ending_id] = matching_error
      else:
        # Import the error ending into parent
        new_ending_id = subflow.name.replace("-", "_") + "_" + ending_id
        parent_workflow.endings[new_ending_id] = ending
        ending_to_target[ending_id] = new_ending_id

  # Step 4: Rewire subflow internal transitions
  # Replace any transition targeting a subflow ending with the mapped parent target
  for node_id, node in subflow.nodes:
    for target in get_all_transition_targets(node_id, node):
      if target in ending_to_target:
        update_transition_targets(node, target, ending_to_target[target])

  # Step 5: Copy subflow nodes into parent
  for node_id, node in subflow.nodes:
    parent_workflow.nodes[node_id] = node

  # Step 6: Rewire parent transitions
  # All transitions pointing to the reference node now point to the subflow's start_node
  subflow_entry = subflow.start_node
  for node_id, node in parent_workflow.nodes:
    if node_id == reference_node_id:
      continue
    update_transition_targets(node, reference_node_id, subflow_entry)

  # Update start_node if needed
  if parent_workflow.start_node == reference_node_id:
    parent_workflow.start_node = subflow_entry

  # Step 7: Remove the reference node
  del parent_workflow.nodes[reference_node_id]

  return parent_workflow
```

### State Mapping During Inline

When the subflow reads/writes state variables, the inline operation must preserve the same state paths:

```
# Since reference nodes share state with the parent, inlined nodes
# automatically use the same state namespace. No mapping is needed
# unless the subflow was using a context mapping:

if "context" in ref_node:
  # The reference node mapped parent state to subflow state
  # After inlining, replace subflow state references with parent equivalents
  for subflow_var, parent_expr in ref_node.context:
    for node_id, node in subflow.nodes:
      replace_state_references(node, subflow_var, parent_expr)
```

---

## Operation 2: Split Workflow

Divides a large workflow into two smaller workflows linked by an `invoke_skill` consequence. The first workflow hands off to the second at a user-chosen boundary node.

### When to Split

- Workflow exceeds 20 nodes
- Clear logical boundary between two phases (e.g., "setup" vs. "execution")
- Different error handling strategies for each half
- One half could be reused independently

### Procedure

```
function split_workflow(workflow, split_node_id):
  # Step 1: Partition nodes via BFS
  # Workflow A: nodes reachable from start_node without crossing split_node
  # Workflow B: split_node and everything reachable from it

  part_a_nodes = set()
  queue = [workflow.start_node]
  while queue:
    current = queue.pop(0)
    if current == split_node_id or current not in workflow.nodes:
      continue
    if current in part_a_nodes:
      continue
    part_a_nodes.add(current)
    for target in get_all_transition_targets(current, workflow.nodes[current]):
      if not target.startswith("${"):
        queue.append(target)

  part_b_nodes = set(workflow.nodes.keys()) - part_a_nodes

  # Step 2: Build Workflow A
  workflow_a = {
    name: workflow.name + "-part-a",
    version: workflow.version,
    description: workflow.description + " (Part A: setup)",
    start_node: workflow.start_node,
    initial_state: deep_copy(workflow.initial_state),
    nodes: {},
    endings: {}
  }

  for node_id in part_a_nodes:
    workflow_a.nodes[node_id] = deep_copy(workflow.nodes[node_id])

  # Add handoff node: invokes part B
  workflow_a.nodes["handoff_to_part_b"] = {
    type: "action",
    description: "Hand off to ${workflow.name}-part-b",
    actions: [
      {
        type: "invoke_skill",
        skill: workflow.name + "-part-b",
        pass_state: true
      }
    ],
    on_success: "handoff_success",
    on_failure: "handoff_error"
  }

  workflow_a.endings["handoff_success"] = {
    type: "success",
    message: "Handed off to part B successfully"
  }
  workflow_a.endings["handoff_error"] = {
    type: "error",
    message: "Failed to invoke part B"
  }

  # Rewire A's transitions that pointed to B nodes to point to handoff
  for node_id, node in workflow_a.nodes:
    for target in get_all_transition_targets(node_id, node):
      if target in part_b_nodes:
        update_transition_targets(node, target, "handoff_to_part_b")

  # Import any error endings from original that A nodes reference
  for node_id, node in workflow_a.nodes:
    for target in get_all_transition_targets(node_id, node):
      if target in workflow.endings and target not in workflow_a.endings:
        workflow_a.endings[target] = deep_copy(workflow.endings[target])

  # Step 3: Build Workflow B
  workflow_b = {
    name: workflow.name + "-part-b",
    version: workflow.version,
    description: workflow.description + " (Part B: execution)",
    start_node: split_node_id,
    initial_state: deep_copy(workflow.initial_state),
    nodes: {},
    endings: deep_copy(workflow.endings)  # B gets all original endings
  }

  for node_id in part_b_nodes:
    workflow_b.nodes[node_id] = deep_copy(workflow.nodes[node_id])

  # Remove endings from B that are only referenced by A
  b_targets = set()
  for node_id, node in workflow_b.nodes:
    b_targets.update(get_all_transition_targets(node_id, node))
  for ending_id in list(workflow_b.endings.keys()):
    if ending_id not in b_targets:
      del workflow_b.endings[ending_id]

  return workflow_a, workflow_b
```

### Output File Naming Convention

```
Original:  skills/my-skill/workflow.yaml
Split A:   skills/my-skill/workflow.yaml           (overwrite original)
Split B:   skills/my-skill-part-b/workflow.yaml    (new directory)
```

Or, if user prefers to keep original intact:

```
Split A:   skills/my-skill-part-a/workflow.yaml
Split B:   skills/my-skill-part-b/workflow.yaml
```

---

## Operation 3: Merge Workflows

Combines two separate workflows into a single workflow. The inverse of split. The first workflow's success ending is replaced by a transition to the second workflow's start node.

### When to Merge

- Two workflows that are always invoked sequentially
- Reducing `invoke_skill` overhead
- Consolidating closely related logic
- Simplifying the skill directory structure

### Procedure

```
function merge_workflows(primary, secondary):
  # Step 1: Handle node ID collisions
  primary_ids = set(primary.nodes.keys())
  secondary_ids = set(secondary.nodes.keys())
  collisions = primary_ids & secondary_ids

  if collisions:
    # Prefix secondary node IDs with namespace
    prefix = secondary.name.replace("-", "_") + "_"
    secondary = rename_all_nodes(secondary, lambda id: prefix + id)

  # Step 2: Copy secondary nodes into primary
  for node_id, node in secondary.nodes:
    primary.nodes[node_id] = node

  # Step 3: Rewire primary's success ending
  # Find the success ending in primary that should link to secondary
  link_ending = find_handoff_ending(primary)  # Usually "success" or "handoff_success"

  if link_ending:
    # Find all transitions pointing to this ending and redirect to secondary start
    for node_id, node in primary.nodes:
      update_transition_targets(node, link_ending, secondary.start_node)
    # Remove the now-unused ending
    del primary.endings[link_ending]

  # Step 4: Import secondary endings
  for ending_id, ending in secondary.endings:
    # Prefix if collision with primary endings
    final_id = ending_id
    if ending_id in primary.endings:
      final_id = secondary.name.replace("-", "_") + "_" + ending_id
      # Update any secondary node transitions pointing to this ending
      for node_id, node in primary.nodes:
        if node_id in secondary.nodes:
          update_transition_targets(node, ending_id, final_id)
    primary.endings[final_id] = ending

  # Step 5: Merge initial_state
  if secondary.initial_state:
    for key, value in secondary.initial_state:
      if key not in primary.initial_state:
        primary.initial_state[key] = value
      # else: primary value takes precedence

  primary.name = primary.name.replace("-part-a", "")  # Clean up split artifacts
  return primary
```

### Collision Resolution Strategy

When merging, node ID collisions are resolved by prefixing the secondary workflow's nodes:

| Primary Node | Secondary Node | Resolution |
|-------------|----------------|------------|
| `validate_input` | `validate_input` | `secondary_name_validate_input` |
| `process_data` | `process_data` | `secondary_name_process_data` |
| `check_exists` | (no collision) | `check_exists` (unchanged) |

---

## Operation 4: Rename Nodes

Renames node IDs throughout the workflow, updating all references in transitions, branches, on_response handlers, and the start_node field.

### When to Rename

- Node IDs are unclear or inconsistent with naming conventions
- Preparing for merge (pre-emptive namespace prefixing)
- Fixing typos in node names
- Aligning with updated naming standards

### Naming Conventions Reference

| Purpose | Pattern | Example |
|---------|---------|---------|
| Read/Load | `read_*`, `load_*` | `read_config` |
| Check/Validate | `check_*`, `validate_*` | `check_exists` |
| Ask user | `ask_*`, `select_*` | `ask_source_type` |
| Execute | `execute_*`, `run_*` | `execute_clone` |
| Error | `error_*` | `error_no_config` |
| Route/Dispatch | `route_*` | `route_by_type` |

### Procedure

```
function rename_nodes(workflow, rename_map):
  # rename_map: {old_id: new_id, ...}

  # Step 1: Validate rename map
  issues = []
  new_ids = set(rename_map.values())
  existing_ids = set(workflow.nodes.keys()) - set(rename_map.keys())

  # Check for collisions with non-renamed nodes
  collisions = new_ids & existing_ids
  if collisions:
    issues.append("New names collide with existing nodes: ${collisions}")

  # Check for duplicate new names
  if len(new_ids) < len(rename_map):
    issues.append("Duplicate target names in rename map")

  # Check that all old names exist
  for old_id in rename_map:
    if old_id not in workflow.nodes:
      issues.append("Node '${old_id}' not found in workflow")

  if issues:
    return issues

  # Step 2: Rebuild nodes map with new keys
  new_nodes = {}
  for node_id, node in workflow.nodes:
    new_id = rename_map.get(node_id, node_id)
    new_nodes[new_id] = node
  workflow.nodes = new_nodes

  # Step 3: Update all transition targets
  for node_id, node in workflow.nodes:
    if node.type == "action":
      node.on_success = rename_map.get(node.on_success, node.on_success)
      node.on_failure = rename_map.get(node.on_failure, node.on_failure)

    elif node.type == "conditional":
      node.branches.on_true = rename_map.get(node.branches.on_true, node.branches.on_true)
      node.branches.on_false = rename_map.get(node.branches.on_false, node.branches.on_false)

    elif node.type == "user_prompt":
      for handler_id, handler in node.on_response:
        handler.next_node = rename_map.get(handler.next_node, handler.next_node)

    elif node.type == "reference":
      node.next_node = rename_map.get(node.next_node, node.next_node)

  # Step 4: Update start_node
  workflow.start_node = rename_map.get(workflow.start_node, workflow.start_node)

  return workflow
```

### Batch Rename with Prefix

A common operation is adding or changing a prefix on all nodes:

```
function build_prefix_rename_map(workflow, old_prefix, new_prefix):
  rename_map = {}
  for node_id in workflow.nodes:
    if old_prefix == "":
      # Adding a new prefix
      rename_map[node_id] = new_prefix + node_id
    elif node_id.startswith(old_prefix):
      # Replacing an existing prefix
      rename_map[node_id] = new_prefix + node_id[len(old_prefix):]
    # else: node doesn't match old prefix, skip
  return rename_map
```

---

## Operation 5: Cleanup Dead Code

Removes unreachable nodes, unused endings, and unused state variables from the workflow.

### When to Cleanup

- After other refactoring operations that may leave orphaned elements
- Before validation to reduce noise
- When workflow has grown organically and accumulated unused elements
- Before publishing or sharing a workflow

### Orphan Detection Algorithm

Uses BFS from `start_node` to find all reachable nodes. Any node not visited is an orphan.

```
function find_orphan_nodes(workflow):
  visited = set()
  queue = [workflow.start_node]

  while queue:
    current = queue.pop(0)
    if current in visited:
      continue
    if current not in workflow.nodes:
      continue  # Ending or dynamic target
    visited.add(current)

    node = workflow.nodes[current]
    for target in get_all_transition_targets(current, node):
      if not target.startswith("${") and target not in visited:
        queue.append(target)

  orphans = set(workflow.nodes.keys()) - visited
  return orphans
```

### Unused Ending Detection

An ending is unused if no node transition references it:

```
function find_unused_endings(workflow):
  referenced_endings = set()

  for node_id, node in workflow.nodes:
    for target in get_all_transition_targets(node_id, node):
      if target in workflow.endings:
        referenced_endings.add(target)

  unused = set(workflow.endings.keys()) - referenced_endings
  return unused
```

### Unused State Detection

State variables declared in `initial_state` that are never referenced anywhere in the workflow:

```
function find_unused_state(workflow):
  if not workflow.initial_state:
    return set()

  declared = set(workflow.initial_state.keys())

  # Collect all state references from the workflow
  referenced = set()
  all_text = serialize_to_string(workflow.nodes) + serialize_to_string(workflow.endings)

  for var in declared:
    # Check for direct references: ${var}, ${var.sub}, state.var, computed.var
    if var in all_text:
      referenced.add(var)

  # Always-used standard fields
  standard_fields = {"phase", "flags", "computed", "prompts", "output",
                     "logging", "_semantics", "_semantics_loaded"}
  referenced.update(standard_fields & declared)

  unused = declared - referenced
  return unused
```

### Cleanup Procedure

```
function cleanup_dead_code(workflow, remove_orphans, remove_endings, remove_state):
  removed = {nodes: [], endings: [], state: []}

  if remove_orphans:
    orphans = find_orphan_nodes(workflow)
    for node_id in orphans:
      del workflow.nodes[node_id]
      removed.nodes.append(node_id)

  if remove_endings:
    unused = find_unused_endings(workflow)
    for ending_id in unused:
      del workflow.endings[ending_id]
      removed.endings.append(ending_id)

  if remove_state:
    unused_vars = find_unused_state(workflow)
    for var in unused_vars:
      del workflow.initial_state[var]
      removed.state.append(var)

  return workflow, removed
```

### Safety Checks

Before removing dead code, apply these safety checks:

1. **Never remove the last ending.** A workflow must have at least one ending.
   ```
   if len(workflow.endings) - len(unused_endings) < 1:
     warn("Cannot remove all endings. Keeping at least one.")
     unused_endings = unused_endings[:-1]  # Keep the last one
   ```

2. **Dynamic targets may reference seemingly orphaned nodes.** If any node uses `${...}` interpolation in transitions, warn that orphan detection may have false positives.
   ```
   has_dynamic = any(
     target.startswith("${")
     for node_id, node in workflow.nodes
     for target in get_all_transition_targets(node_id, node)
   )
   if has_dynamic:
     warn("Workflow uses dynamic targets (${...}). Some 'orphan' nodes may be reachable at runtime via dynamic routing.")
   ```

3. **State variables used in dynamic expressions.** A variable like `computed.route_target` may not appear in a simple text search but is used at runtime.
   ```
   for var in unused_vars:
     if var == "computed":
       warn("'computed' is a runtime namespace. Skipping removal.")
       unused_vars.remove(var)
   ```

---

## Helper Functions

These helper functions are used across multiple operations:

### get_all_transition_targets

Extracts all outgoing transition target IDs from a node:

```
function get_all_transition_targets(node_id, node):
  targets = []
  if node.type == "action":
    if "on_success" in node: targets.append(node.on_success)
    if "on_failure" in node: targets.append(node.on_failure)
  elif node.type == "conditional":
    if "branches" in node:
      if "on_true" in node.branches: targets.append(node.branches.on_true)
      if "on_false" in node.branches: targets.append(node.branches.on_false)
  elif node.type == "user_prompt":
    if "on_response" in node:
      for handler_id, handler in node.on_response:
        if "next_node" in handler: targets.append(handler.next_node)
  elif node.type == "reference":
    if "next_node" in node: targets.append(node.next_node)
  return targets
```

### update_transition_targets

Replaces a specific target with a new target in all transition fields of a node:

```
function update_transition_targets(node, old_target, new_target):
  if node.type == "action":
    if node.on_success == old_target: node.on_success = new_target
    if node.on_failure == old_target: node.on_failure = new_target
  elif node.type == "conditional":
    if node.branches.on_true == old_target: node.branches.on_true = new_target
    if node.branches.on_false == old_target: node.branches.on_false = new_target
  elif node.type == "user_prompt":
    for handler_id, handler in node.on_response:
      if handler.next_node == old_target: handler.next_node = new_target
  elif node.type == "reference":
    if node.next_node == old_target: node.next_node = new_target
```

### collect_state_reads / collect_state_writes

Collect state variable names read or written by a set of nodes:

```
function collect_state_reads(node_ids, all_nodes):
  reads = set()
  for node_id in node_ids:
    node = all_nodes[node_id]
    # Find all ${...} interpolations
    for ref in find_all_interpolations(node):
      reads.add(ref.split(".")[0])
  return reads

function collect_state_writes(node_ids, all_nodes):
  writes = set()
  for node_id in node_ids:
    node = all_nodes[node_id]
    if node.type == "action":
      for action in node.actions:
        if "store_as" in action:
          writes.add(action.store_as.split(".")[0])
        if "field" in action:
          writes.add(action.field.split(".")[0])
        if "flag" in action:
          writes.add("flags")
  return writes
```

### rename_all_nodes

Renames all node IDs in a workflow using a transform function:

```
function rename_all_nodes(workflow, transform_fn):
  # Build rename map
  rename_map = {node_id: transform_fn(node_id) for node_id in workflow.nodes}
  # Apply using the standard rename procedure
  return rename_nodes(workflow, rename_map)
```

---

## Related Documentation

- **Extract Subflow Procedure:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-refactor/patterns/extract-subflow-procedure.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Graph Validation Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/patterns/graph-validation-algorithm.md`
