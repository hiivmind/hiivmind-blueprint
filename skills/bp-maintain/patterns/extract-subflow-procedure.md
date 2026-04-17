# Extract Subflow Procedure

Detailed step-by-step procedure for extracting a group of nodes from a parent workflow
into a separate subflow file.

## Step 1: Select Nodes

Present a multi-select list of all nodes except `start_node`. Each option shows:
- Node ID
- Node type
- Description (if available)
- Action count (for action nodes)

## Step 2: Identify Extraction Boundary

Analyze the selected nodes to determine the interface between parent and subflow.

### Entry Nodes

Selected nodes that have incoming transitions from outside the selection:

```pseudocode
function find_entry_nodes(selected, all_nodes):
    selected_set = set(selected)
    entries = []
    for node_id in selected:
        for other_id, other_node in all_nodes:
            if other_id not in selected_set:
                targets = get_all_transition_targets(other_id, other_node)
                if node_id in targets:
                    entries.append(node_id)
                    break
    return entries
```

**Constraint:** A subflow should have exactly one entry point. If multiple entries are
detected, warn the user and suggest selecting a contiguous group.

### Exit Transitions

Transitions from selected nodes to nodes outside the selection:

```pseudocode
function find_exit_transitions(selected, all_nodes, endings):
    selected_set = set(selected)
    exits = []
    for node_id in selected:
        node = all_nodes[node_id]
        for target in get_all_transition_targets(node_id, node):
            if target not in selected_set and not target.startswith("${"):
                exits.append({
                    from_node: node_id,
                    target: target,
                    is_ending: target in endings
                })
    return exits
```

### Shared State

Variables read by inside nodes but written by outside nodes (input state), and
variables written by inside nodes but read by outside nodes (output state):

```pseudocode
inside_reads = collect_state_reads(selected, all_nodes)
inside_writes = collect_state_writes(selected, all_nodes)
outside_reads = collect_state_reads(non_selected, all_nodes)
outside_writes = collect_state_writes(non_selected, all_nodes)

input_state = inside_reads & outside_writes
output_state = inside_writes & outside_reads
```

## Step 3: Create Subflow File

Build the subflow workflow structure:

```yaml
name: <subflow_name>
version: <parent_version>
description: "Subflow extracted from <parent_name>"
start_node: <entry_node>
nodes:
  <extracted nodes...>
endings:
  <mapped from exit transitions...>
```

### Ending Mapping

For each exit transition:

- If target is an ending in the parent -> copy that ending to the subflow
- If target is a node in the parent -> create a synthetic `resume_<target>` ending

```pseudocode
for exit in boundary.exits:
    if exit.is_ending:
        subflow.endings[exit.target] = parent.endings[exit.target]
    else:
        ending_id = "resume_" + exit.target
        subflow.endings[ending_id] = {
            type: "success",
            message: "Resume parent workflow at " + exit.target
        }
        rewire_transition(subflow.nodes[exit.from_node], exit.target, ending_id)
```

## Step 4: Update Parent Workflow

Remove extracted nodes and rewire transitions:

```pseudocode
# Remove extracted nodes
for node_id in selected:
    del parent.nodes[node_id]

# Rewire transitions pointing to the entry node
resume_target = boundary.exits[0].target
for node_id, node in parent.nodes:
    update_transition_targets(node, boundary.entry[0], resume_target)

# Update start_node if needed
if parent.start_node == boundary.entry[0]:
    parent.start_node = resume_target
```

## Step 5: Write Files

1. Create the `subflows/` directory if it does not exist
2. Write the subflow file
3. Write the updated parent workflow

## Example

### Before (parent workflow)

```yaml
name: deploy-service
start_node: check_env
nodes:
  check_env:
    type: conditional
    condition: { type: path_check, path: ".env" }
    branches:
      on_true: build_image
      on_false: setup_env
  setup_env:
    type: action
    actions:
      - { type: local_file_ops, operation: write, path: ".env" }
    on_success: build_image
    on_failure: error_exit
  build_image:
    type: action
    actions:
      - { type: run_command, command: "docker build" }
    on_success: push_image
    on_failure: error_exit
  push_image:
    type: action
    actions:
      - { type: run_command, command: "docker push" }
    on_success: deploy_done
    on_failure: error_exit
endings:
  deploy_done: { type: success }
  error_exit: { type: error }
```

### After extracting [build_image, push_image]

**Subflow (subflows/docker-pipeline.yaml):**

```yaml
name: docker-pipeline
start_node: build_image
nodes:
  build_image:
    type: action
    actions:
      - { type: run_command, command: "docker build" }
    on_success: push_image
    on_failure: error_exit
  push_image:
    type: action
    actions:
      - { type: run_command, command: "docker push" }
    on_success: deploy_done
    on_failure: error_exit
endings:
  deploy_done: { type: success, message: "Resume parent workflow at deploy_done" }
  error_exit: { type: error }
```

**Updated parent:**

```yaml
name: deploy-service
start_node: check_env
nodes:
  check_env:
    type: conditional
    condition: { type: path_check, path: ".env" }
    branches:
      on_true: deploy_done
      on_false: setup_env
  setup_env:
    type: action
    actions:
      - { type: local_file_ops, operation: write, path: ".env" }
    on_success: deploy_done
    on_failure: error_exit
endings:
  deploy_done: { type: success }
  error_exit: { type: error }
```
