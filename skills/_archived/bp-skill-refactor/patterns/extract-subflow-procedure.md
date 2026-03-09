> **Used by:** `SKILL.md` Phase 3A
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

# Extract Subflow Procedure

Complete step-by-step procedure for extracting a group of nodes from a parent workflow into a separate subflow file, replacing them with a reference node.

---

## Overview

Extraction is the most common refactoring operation. It reduces complexity in a parent workflow by moving a cohesive group of nodes into a standalone subflow. The parent workflow retains a single `reference` node that delegates to the subflow.

**Prerequisites:**
- The selected nodes must form a contiguous subgraph (reachable from a single entry point)
- The subgraph should have a clear entry node and well-defined exit transitions
- Shared state must be explicitly identified for the interface contract

---

## Step 1: Validate Selection

Before extraction, verify the selected nodes form a valid subgraph:

```
function validate_selection(selected_nodes, workflow):
  selected_set = set(selected_nodes)
  issues = []

  # Check 1: At least one node selected
  if len(selected_nodes) == 0:
    issues.append("No nodes selected for extraction")
    return issues

  # Check 2: Don't extract start_node alone (it would break the parent)
  if workflow.start_node in selected_set and len(selected_set) == 1:
    issues.append("Cannot extract only the start_node. Select additional nodes or choose a different operation.")

  # Check 3: Verify contiguity - all selected nodes reachable from entry
  entry_candidates = find_entry_nodes(selected_nodes, workflow)
  if len(entry_candidates) > 1:
    issues.append("Selection has multiple entry points: ${entry_candidates}. A subflow should have a single entry. Consider selecting a contiguous group.")

  # Check 4: No circular dependency with parent
  # (exit transitions should not point back into selected nodes from outside)
  for node_id in selected_nodes:
    node = workflow.nodes[node_id]
    for target in get_all_transition_targets(node_id, node):
      if target in selected_set:
        continue  # Internal transition, fine
      # Check if any non-selected node transitioning to this target
      # also transitions back into the selection
      # (This creates a back-edge that complicates extraction)

  return issues
```

---

## Step 2: Identify Extraction Boundary

The boundary defines the interface between parent and subflow:

```
function identify_boundary(selected_nodes, workflow):
  selected_set = set(selected_nodes)

  # --- Entry nodes ---
  # Nodes in the selection that receive transitions from outside
  entry_nodes = []
  for node_id in selected_nodes:
    has_external_incoming = false
    for other_id, other_node in workflow.nodes:
      if other_id in selected_set:
        continue
      targets = get_all_transition_targets(other_id, other_node)
      if node_id in targets:
        has_external_incoming = true
        break
    # Also check if this is the start_node
    if node_id == workflow.start_node:
      has_external_incoming = true
    if has_external_incoming:
      entry_nodes.append(node_id)

  # --- Exit transitions ---
  # Transitions from selected nodes to nodes outside the selection
  exit_transitions = []
  for node_id in selected_nodes:
    node = workflow.nodes[node_id]
    for target in get_all_transition_targets(node_id, node):
      if target.startswith("${"):
        exit_transitions.append({
          from_node: node_id,
          target: target,
          is_dynamic: true,
          is_ending: false
        })
      elif target not in selected_set:
        exit_transitions.append({
          from_node: node_id,
          target: target,
          is_dynamic: false,
          is_ending: target in workflow.endings
        })

  # --- State interface ---
  input_state = collect_state_reads(selected_nodes, workflow.nodes) \
                & collect_state_writes(non_selected_nodes, workflow.nodes)
  output_state = collect_state_writes(selected_nodes, workflow.nodes) \
                 & collect_state_reads(non_selected_nodes, workflow.nodes)

  return {
    entry_nodes: entry_nodes,
    exit_transitions: exit_transitions,
    input_state: input_state,
    output_state: output_state
  }
```

---

## Step 3: Create Subflow Interface

Define the input/output state mapping that forms the contract between parent and subflow:

```
computed.subflow_interface = {
  inputs: [
    {name: var, source: "parent.${var}"}
    for var in computed.boundary.input_state
  ],
  outputs: [
    {name: var, target: "parent.${var}"}
    for var in computed.boundary.output_state
  ]
}
```

This mapping is documented as comments in the subflow file for clarity.

---

## Step 4: Build Subflow Workflow

Construct the new subflow workflow.yaml:

```
function build_subflow(name, selected_nodes, boundary, parent_workflow):
  subflow = {
    name: name,
    version: parent_workflow.version or "1.0.0",
    description: "Subflow extracted from ${parent_workflow.name}",
    # Document the interface contract
    # input_state: boundary.input_state (read from parent)
    # output_state: boundary.output_state (written back to parent)
    start_node: boundary.entry_nodes[0],
    nodes: {},
    endings: {}
  }

  # Copy selected nodes
  for node_id in selected_nodes:
    subflow.nodes[node_id] = deep_copy(parent_workflow.nodes[node_id])

  # Handle exit transitions
  for exit in boundary.exit_transitions:
    if exit.is_dynamic:
      # Dynamic targets (${...}) pass through unchanged
      continue
    elif exit.is_ending:
      # Propagate the parent ending directly
      subflow.endings[exit.target] = deep_copy(parent_workflow.endings[exit.target])
    else:
      # Create a synthetic ending for the resume point
      ending_id = "resume_" + exit.target
      subflow.endings[ending_id] = {
        type: "success",
        message: "Resume parent workflow at '${exit.target}'"
      }
      # Rewire the exit node's transition
      rewire_target(subflow.nodes[exit.from_node], exit.target, ending_id)

  return subflow
```

---

## Step 5: Replace Nodes with Reference in Parent

```
function update_parent(parent_workflow, selected_nodes, boundary, subflow_path, subflow_name):
  # Remove extracted nodes
  for node_id in selected_nodes:
    del parent_workflow.nodes[node_id]

  # Create reference node
  ref_id = "ref_" + subflow_name
  parent_workflow.nodes[ref_id] = {
    type: "reference",
    doc: relative_path_from(parent_workflow_path, subflow_path),
    description: "Delegate to ${subflow_name} subflow",
    next_node: determine_resume_node(boundary)
  }

  # Rewire incoming transitions
  entry_id = boundary.entry_nodes[0]
  for node_id, node in parent_workflow.nodes:
    update_transition_targets(node, entry_id, ref_id)

  # Update start_node if needed
  if parent_workflow.start_node == entry_id:
    parent_workflow.start_node = ref_id

  return parent_workflow

function determine_resume_node(boundary):
  # Find the most common non-ending exit target
  non_ending_exits = [e for e in boundary.exit_transitions if not e.is_ending and not e.is_dynamic]
  if non_ending_exits:
    return non_ending_exits[0].target
  # If all exits go to endings, use the first ending
  ending_exits = [e for e in boundary.exit_transitions if e.is_ending]
  if ending_exits:
    return ending_exits[0].target
  # Fallback
  return boundary.exit_transitions[0].target if boundary.exit_transitions else "success"
```

---

## Step 6: Validate Both Workflows

After extraction, validate both the parent and the subflow independently:

```
parent_issues = validate_workflow(parent_workflow)
subflow_issues = validate_workflow(subflow)

if parent_issues or subflow_issues:
  display "Validation issues after extraction:"
  if parent_issues:
    display "Parent workflow:"
    for issue in parent_issues:
      display "  - [${issue.severity}] ${issue.message}"
  if subflow_issues:
    display "Subflow '${subflow_name}':"
    for issue in subflow_issues:
      display "  - [${issue.severity}] ${issue.message}"
```

---

## Before/After Example

### Before: Parent workflow with god node

```yaml
name: my-skill
version: "1.0.0"
start_node: validate_input

nodes:
  validate_input:
    type: conditional
    condition:
      type: path_check
      path: "${computed.config_path}"
      check: is_file
    branches:
      on_true: process_data
      on_false: error_no_config

  process_data:
    type: action
    description: "Process the data through multiple stages"
    actions:
      - type: local_file_ops
        operation: read
        path: "${computed.config_path}"
        store_as: computed.config
      - type: compute
        expression: "parse_sections(computed.config)"
        store_as: computed.sections
      - type: local_file_ops
        operation: read
        path: "${computed.data_path}"
        store_as: computed.raw_data
      - type: compute
        expression: "transform(computed.raw_data, computed.sections)"
        store_as: computed.transformed
      - type: local_file_ops
        operation: write
        path: "${computed.output_path}"
        content: "${computed.transformed}"
      - type: compute_hash
        input: "${computed.transformed}"
        store_as: computed.output_hash
    on_success: generate_report
    on_failure: error_processing

  generate_report:
    type: action
    description: "Generate summary report"
    actions:
      - type: display
        format: table
        data: "${computed.sections}"
    on_success: success
    on_failure: error_report

endings:
  success:
    type: success
    message: "Processing complete"
  error_no_config:
    type: error
    message: "Configuration file not found"
  error_processing:
    type: error
    message: "Data processing failed"
  error_report:
    type: error
    message: "Report generation failed"
```

### After: Parent workflow with reference node

```yaml
name: my-skill
version: "1.0.0"
start_node: validate_input

nodes:
  validate_input:
    type: conditional
    condition:
      type: path_check
      path: "${computed.config_path}"
      check: is_file
    branches:
      on_true: ref_data_processing
      on_false: error_no_config

  ref_data_processing:
    type: reference
    doc: "subflows/data-processing.yaml"
    description: "Delegate to data-processing subflow"
    next_node: generate_report

  generate_report:
    type: action
    description: "Generate summary report"
    actions:
      - type: display
        format: table
        data: "${computed.sections}"
    on_success: success
    on_failure: error_report

endings:
  success:
    type: success
    message: "Processing complete"
  error_no_config:
    type: error
    message: "Configuration file not found"
  error_report:
    type: error
    message: "Report generation failed"
```

### After: Extracted subflow

```yaml
name: data-processing
version: "1.0.0"
description: "Subflow extracted from my-skill"
# Interface:
#   input_state: computed.config_path, computed.data_path, computed.output_path
#   output_state: computed.config, computed.sections, computed.transformed, computed.output_hash
start_node: process_data

nodes:
  process_data:
    type: action
    description: "Process the data through multiple stages"
    actions:
      - type: local_file_ops
        operation: read
        path: "${computed.config_path}"
        store_as: computed.config
      - type: compute
        expression: "parse_sections(computed.config)"
        store_as: computed.sections
      - type: local_file_ops
        operation: read
        path: "${computed.data_path}"
        store_as: computed.raw_data
      - type: compute
        expression: "transform(computed.raw_data, computed.sections)"
        store_as: computed.transformed
      - type: local_file_ops
        operation: write
        path: "${computed.output_path}"
        content: "${computed.transformed}"
      - type: compute_hash
        input: "${computed.transformed}"
        store_as: computed.output_hash
    on_success: resume_generate_report
    on_failure: error_processing

endings:
  resume_generate_report:
    type: success
    message: "Resume parent workflow at 'generate_report'"
  error_processing:
    type: error
    message: "Data processing failed"
```

---

## Related Documentation

- **Refactoring Operations:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-refactor/patterns/refactoring-operations.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Schema Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/patterns/schema-validation-rules.md`
