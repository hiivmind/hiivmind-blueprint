# Refactoring Operations

Reference procedures for the 5 refactoring operations available in bp-maintain.

## Extract Subflow

Move a group of nodes from a parent workflow into a separate subflow file.

See `extract-subflow-procedure.md` for the detailed step-by-step with boundary
analysis and YAML examples.

### Summary

1. Select nodes for extraction (multi-select, exclude start_node)
2. Identify extraction boundary (entry nodes, exit transitions, shared state)
3. Create subflow file with extracted nodes and synthetic endings
4. Remove extracted nodes from parent and rewire transitions
5. Write both files

### Constraints

- Subflow should have a single entry point
- Selected nodes must be reachable (not orphans)
- Exit transitions map to subflow endings

## Inline Subflow (Legacy)

Expand a `reference` node back into the parent workflow. Applies only to pre-v5.0.0
workflows.

### Procedure

1. Find all `reference` nodes in the workflow
2. Select which reference to inline
3. Read the referenced subflow file
4. Check for node ID collisions; prefix subflow node IDs if needed
5. Copy subflow nodes into parent
6. Rewire: transitions to reference node -> subflow's start_node
7. Rewire: subflow ending references -> reference node's next_node
8. Remove the reference node
9. Write the updated workflow

### Collision Handling

```pseudocode
collision_ids = set(subflow.nodes.keys()) & set(parent.nodes.keys())
if collision_ids:
    prefix = subflow.name.replace("-", "_") + "_"
    for node_id in subflow.nodes:
        new_id = prefix + node_id
        # Update node key and all internal references
```

## Split Workflow

Break one large workflow into two smaller ones at a user-chosen boundary.

### Procedure

1. Present nodes in BFS order from start_node
2. User selects split point node
3. BFS from start_node, collecting nodes before the split point (Workflow A)
4. Remaining nodes form Workflow B (starting at split point)
5. Workflow A gets a handoff ending and invoke_skill action
6. Workflow B preserves original endings
7. Write both workflow files

### Partitioning

```pseudocode
function partition_at(workflow, split_node):
    workflow_a = set()
    queue = [workflow.start_node]
    while queue:
        current = queue.pop(0)
        if current == split_node or current not in workflow.nodes:
            continue
        if current in workflow_a:
            continue
        workflow_a.add(current)
        for target in get_all_transition_targets(current, workflow.nodes[current]):
            if target not in workflow_a:
                queue.append(target)
    workflow_b = set(workflow.nodes.keys()) - workflow_a
    return workflow_a, workflow_b
```

## Rename Nodes

Rename node IDs and update all references throughout the workflow.

### Modes

- **Single**: Rename one node ID
- **Prefix**: Add or replace a prefix on all node IDs
- **Batch**: Provide multiple old -> new mappings

### Update Points

All of these must be updated when renaming:

1. Node key in `nodes` map
2. `on_success` and `on_failure` fields
3. `branches.on_true` and `branches.on_false` fields
4. `on_response.*.next_node` fields
5. `start_node` field
6. Any `${...}` interpolations referencing node IDs (rare)

### Procedure

```pseudocode
function apply_renames(workflow, rename_map):
    new_nodes = {}
    for node_id, node in workflow.nodes:
        new_id = rename_map.get(node_id, node_id)
        new_nodes[new_id] = node
    for node_id, node in new_nodes:
        update_all_targets(node, rename_map)
    workflow.start_node = rename_map.get(workflow.start_node, workflow.start_node)
    workflow.nodes = new_nodes
```

## Cleanup Dead Code

Remove unreachable nodes, unused endings, and unused state variables.

### Detection

- **Orphan nodes**: BFS from start_node; nodes not visited are orphans
- **Unused endings**: Collect all transition targets; endings not referenced are unused
- **Unused state**: Compare initial_state keys against all `${...}` references and
  mutate_state/set_flag/store_as fields; keys not referenced are unused

### Safety

- Always present findings for user confirmation before removing
- Standard runtime variables (`phase`, `flags`, `computed`, `prompts`, `output`,
  `logging`, `_semantics`, `_semantics_loaded`) are never flagged as unused
- Backup is created before any modifications
