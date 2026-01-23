# Workflow Generation Pattern

Generating complete workflow.yaml files from analyzed skill structures. This pattern assembles node mappings into valid, executable workflows.

---

## Overview

Workflow generation takes:
- **Analysis output** - Phases, actions, conditionals, state variables
- **Node mappings** - Node configurations for each element

And produces:
- **workflow.yaml** - Complete workflow specification
- **Thin SKILL.md** - Minimal loader that executes the workflow

---

## Generation Process

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: SCAFFOLD WORKFLOW                                       │
│  - Create name, version, description                             │
│  - Define initial_state from detected variables                  │
│  - Set up entry_preconditions                                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 2: BUILD NODE GRAPH                                        │
│  - Create nodes from mappings                                    │
│  - Connect nodes with transitions                                │
│  - Resolve forward references                                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 3: DEFINE ENDINGS                                          │
│  - Success ending(s)                                             │
│  - Error endings with recovery hints                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 4: VALIDATE GRAPH                                          │
│  - All transitions point to valid nodes                          │
│  - No unreachable nodes                                          │
│  - All paths lead to endings                                     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 5: OUTPUT FILES                                            │
│  - Generate workflow.yaml                                        │
│  - Generate thin SKILL.md                                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Scaffold Generation

### Workflow Header

```yaml
name: "{{skill_name}}"
version: "1.0.0"
description: >
  {{original_description}}
```

**Sources:**
- `name` - From skill directory name or frontmatter
- `version` - Start at 1.0.0 for new workflows
- `description` - From original SKILL.md frontmatter

### Entry Preconditions

Generate from:
1. Tools mentioned in `allowed-tools`
2. Files that must exist before starting
3. Prerequisites mentioned in prose

```yaml
entry_preconditions:
  - type: tool_available
    tool: git
  - type: config_exists
```

**Detection patterns:**
- "requires git" → `tool_available: git`
- "config must exist" → `config_exists`
- "run from corpus directory" → `config_exists`

### Initial State

Generate from detected state variables:

```yaml
initial_state:
  phase: "start"
  {{#each state_variables}}
  {{name}}: null
  {{/each}}
  flags:
    {{#each boolean_flags}}
    {{name}}: false
    {{/each}}
  computed: {}
```

**Boolean flags to generate:**
- One for each conditional that affects routing
- Common patterns: `config_found`, `is_first_source`, `valid_input`

---

## Node Graph Construction

### Ordering Nodes

Nodes should be ordered for readability:

1. **Start node** first
2. **Happy path** nodes in execution order
3. **Branch nodes** after their branching point
4. **Error nodes** at the end

### Connecting Transitions

```
FUNCTION connect_transitions(nodes, phases):
  FOR each node IN nodes:
    SWITCH node.type:
      CASE "action":
        # on_success: next node in sequence or next phase
        # on_failure: appropriate error node
        node.on_success = find_next_node(node, phases)
        node.on_failure = find_error_handler(node)

      CASE "conditional":
        # branches already defined by mapping
        # verify both targets exist
        validate_exists(node.branches.true)
        validate_exists(node.branches.false)

      CASE "user_prompt":
        # on_response handlers already defined
        # verify all next_node targets exist
        FOR each handler IN node.on_response:
          validate_exists(handler.next_node)

      CASE "validation_gate":
        # on_valid and on_invalid already defined
        validate_exists(node.on_valid)
        validate_exists(node.on_invalid)

      CASE "reference":
        # next_node already defined
        validate_exists(node.next_node)
```

### Phase Transitions

When one phase ends and another begins:

```yaml
# End of phase 1
phase1_complete:
  type: action
  actions:
    - type: set_state
      field: phase
      value: "phase2"
  on_success: phase2_start  # First node of phase 2
  on_failure: error_phase1
```

---

## Endings Generation

### Success Endings

Generate from successful completion paths:

```yaml
endings:
  success:
    type: success
    message: "{{success_message}}"
    summary:
      {{#each output_variables}}
      {{name}}: "${computed.{{name}}}"
      {{/each}}
```

**Message sources:**
- Look for "success", "complete", "done" in prose
- Default: "{{skill_name}} completed successfully"

### Error Endings

Generate from:
1. Explicit error mentions in prose
2. Failure paths from conditionals
3. on_failure targets from action nodes

```yaml
  error_no_config:
    type: error
    message: "No config.yaml found"
    recovery: "hiivmind-corpus-init"
    details: "This skill requires a corpus directory"

  error_clone_failed:
    type: error
    message: "Failed to clone repository"
    details: "Check the URL and your network connection"

  cancelled:
    type: error
    message: "Operation cancelled by user"
```

**Recovery detection:**
- If prose mentions "run X first" → `recovery: X`
- If prose mentions prerequisite skill → `recovery: that_skill`

---

## Graph Validation

### Reachability Check

```
FUNCTION validate_reachability(workflow):
  reachable = set()
  queue = [workflow.start_node]

  WHILE queue is not empty:
    node_name = queue.pop()
    IF node_name IN reachable:
      CONTINUE
    reachable.add(node_name)

    # Add all transitions
    node = workflow.nodes[node_name] OR workflow.endings[node_name]
    IF node is ending:
      CONTINUE

    transitions = get_all_transitions(node)
    FOR each target IN transitions:
      queue.append(target)

  # Check for unreachable nodes
  all_nodes = set(workflow.nodes.keys())
  unreachable = all_nodes - reachable
  IF unreachable:
    WARN "Unreachable nodes: {unreachable}"
```

### Path to Ending Check

```
FUNCTION validate_paths_to_ending(workflow):
  # Reverse the graph
  reverse_graph = build_reverse_graph(workflow)

  # Find all nodes that can reach an ending
  can_reach_ending = set()
  FOR each ending IN workflow.endings:
    can_reach_ending.add(ending)
    add_predecessors(reverse_graph, ending, can_reach_ending)

  # Check all nodes can reach an ending
  FOR each node IN workflow.nodes:
    IF node NOT IN can_reach_ending:
      ERROR "Node {node} has no path to any ending"
```

### Transition Target Validation

```
FUNCTION validate_transitions(workflow):
  valid_targets = set(workflow.nodes.keys()) | set(workflow.endings.keys())

  FOR each node_name, node IN workflow.nodes:
    transitions = get_all_transitions(node)
    FOR each target IN transitions:
      IF target NOT IN valid_targets:
        ERROR "Node {node_name} references unknown target {target}"
```

---

## Output Generation

### workflow.yaml Template

```yaml
# Generated by hiivmind-blueprint
# Source: {{original_skill_path}}
# Generated: {{timestamp}}

name: "{{skill_name}}"
version: "1.0.0"
description: >
  {{description}}

entry_preconditions:
{{#each entry_preconditions}}
  - type: {{type}}
    {{#each params}}
    {{key}}: {{value}}
    {{/each}}
{{/each}}

initial_state:
  phase: "start"
{{#each initial_fields}}
  {{name}}: {{default_value}}
{{/each}}
  flags:
{{#each flags}}
    {{name}}: false
{{/each}}
  computed: {}

start_node: {{start_node}}

nodes:
{{#each nodes}}
  {{id}}:
    type: {{type}}
    {{#if description}}
    description: "{{description}}"
    {{/if}}
    {{#render_node_body this}}
    {{/render_node_body}}

{{/each}}

endings:
{{#each endings}}
  {{id}}:
    type: {{type}}
    message: "{{message}}"
    {{#if recovery}}
    recovery: "{{recovery}}"
    {{/if}}
    {{#if details}}
    details: "{{details}}"
    {{/if}}
    {{#if summary}}
    summary:
      {{#each summary}}
      {{key}}: "{{value}}"
      {{/each}}
    {{/if}}

{{/each}}
```

### Thin SKILL.md Template

```markdown
---
name: {{skill_name}}
description: >
  {{description}}
allowed-tools: Read, Glob, Grep, Write, Edit, AskUserQuestion, Bash, WebFetch
---

# {{title}}

Execute this workflow inline. State persists in conversation context.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/{{skill_dir}}/workflow.yaml`

## Execution Instructions

### Phase 1: Initialize

1. **Load workflow.yaml** from this skill directory
2. **Check entry preconditions** (see `lib/workflow/preconditions.md`):
   - Evaluate each precondition in `entry_preconditions`
   - If ANY fails: display error, STOP
3. **Initialize state** from `initial_state`

### Phase 2: Execute Loop

```
REPEAT for each node:

1. Get node: workflow.nodes[current_node]

2. If current_node is an ending:
   - Display ending.message
   - If error with recovery: suggest recovery skill
   - STOP

3. Execute by node.type:
   - ACTION: Execute actions, route on_success/on_failure
   - CONDITIONAL: Evaluate condition, route branches.true/false
   - USER_PROMPT: Present question, apply consequence, route next_node
   - VALIDATION_GATE: Check validations, route on_valid/on_invalid
   - REFERENCE: Execute doc section, route next_node

4. Append to history

UNTIL ending reached
```

## Reference

- **Workflow Schema:** `lib/workflow/schema.md`
- **Preconditions:** `lib/workflow/preconditions.md`
- **Consequences:** `lib/workflow/consequences.md`
- **State Model:** `lib/workflow/state.md`
```

---

## Generation Examples

### Simple Linear Workflow

**Input Analysis:**
```yaml
phases:
  - id: read_config
    actions: [read_file]
  - id: process_data
    actions: [transform, write]
```

**Generated Workflow:**
```yaml
start_node: read_config

nodes:
  read_config:
    type: action
    actions:
      - type: read_config
        store_as: config
    on_success: process_data
    on_failure: error_no_config

  process_data:
    type: action
    actions:
      - type: compute
        expression: "transform(config)"
        store_as: computed.result
      - type: write_file
        path: "output.yaml"
        content: "${computed.result}"
    on_success: success
    on_failure: error_processing

endings:
  success:
    type: success
    message: "Processing complete"
  error_no_config:
    type: error
    message: "Config not found"
  error_processing:
    type: error
    message: "Processing failed"
```

### Branching Workflow

**Input Analysis:**
```yaml
phases:
  - id: check_type
    conditionals: [type check]
  - id: handle_git
    condition: "type == git"
  - id: handle_local
    condition: "type == local"
```

**Generated Workflow:**
```yaml
start_node: check_type

nodes:
  check_type:
    type: conditional
    condition:
      type: state_equals
      field: source_type
      value: "git"
    branches:
      true: handle_git
      false: check_local

  check_local:
    type: conditional
    condition:
      type: state_equals
      field: source_type
      value: "local"
    branches:
      true: handle_local
      false: error_unknown_type

  handle_git:
    type: action
    actions:
      - type: clone_repo
        url: "${source_url}"
    on_success: success
    on_failure: error_clone

  handle_local:
    type: action
    actions:
      - type: copy_files
        from: "${source_path}"
    on_success: success
    on_failure: error_copy
```

---

## Optimization Passes

### Merge Sequential Actions

If multiple single-action nodes are adjacent:

```yaml
# Before
node1:
  actions: [action1]
  on_success: node2
node2:
  actions: [action2]
  on_success: node3

# After
merged_node:
  actions: [action1, action2]
  on_success: node3
```

### Inline Trivial Conditionals

If a conditional only routes between two adjacent nodes:

```yaml
# Before
check_flag:
  type: conditional
  condition: flag_set: some_flag
  branches:
    true: do_thing
    false: skip_thing
skip_thing:
  on_success: next_node
do_thing:
  on_success: next_node

# Consider inlining the flag check into the action node
```

---

## Related Documentation

- **Skill Analysis:** `lib/blueprint/patterns/skill-analysis.md`
- **Node Mapping:** `lib/blueprint/patterns/node-mapping.md`
- **Workflow Schema:** `lib/workflow/schema.md`
- **Thin Loader Template:** `templates/thin-loader.md.template`
