# Workflow Generation Pattern

Generate complete workflow.yaml files from analyzed skill structures.

---

## Generation Phases

1. **Scaffold** - Create header, entry_preconditions, initial_state
2. **Build nodes** - Map analysis elements to node configurations
3. **Connect transitions** - Wire on_success/on_failure/branches
4. **Define endings** - Success and error endpoints
5. **Validate graph** - Check reachability and paths to endings
6. **Output files** - Write workflow.yaml and thin SKILL.md

---

## Scaffold Generation

### Header

```yaml
name: "{{skill_name}}"
version: "1.0.0"
description: >
  {{original_description}}
```

### Entry Preconditions

Generate from analysis.prerequisites:
- "requires git" → `tool_available: git`
- "config must exist" → `config_exists`

### Initial State

```yaml
initial_state:
  phase: "start"
  {{#each state_variables}}
  {{name}}: null
  {{/each}}
  flags: {}
  computed: {}
```

---

## Node Graph Construction

### Node Ordering

1. Start node first
2. Happy path in execution order
3. Branch nodes after branching point
4. Error nodes at end

### Transition Connections

| Node Type | Connect Via |
|-----------|-------------|
| action | `on_success`, `on_failure` |
| conditional | `branches.on_true`, `branches.on_false` |
| user_prompt | `on_response.*.next_node` |
| validation_gate | `on_valid`, `on_invalid` |
| reference | `next_node` |

---

## Endings Generation

### Success

```yaml
success:
  type: success
  message: "{{skill_name}} completed successfully"
  summary:
    {{#each output_variables}}
    {{name}}: "${computed.{{name}}}"
    {{/each}}
```

### Error

```yaml
error_{{type}}:
  type: error
  message: "{{description}}"
  recovery: "{{recovery_skill}}"  # If recoverable
```

---

## Graph Validation

### Reachability

All nodes must be reachable from `start_node`. Algorithm:

1. Initialize visited = {start_node}
2. BFS through all transition targets
3. Orphan nodes = all_nodes - visited

### Path to Ending

All nodes must have a path to some ending. Reverse the graph and verify all nodes can reach an ending set.

### Transition Targets

Every `on_success`, `on_failure`, `branches.*`, `next_node`, and `on_response.*.next_node` must reference a valid node or ending.

---

## Common Errors

| Error | Fix |
|-------|-----|
| Orphan node detected | Add transition to reach it or remove |
| Dead end node | Add on_success/on_failure |
| Invalid target "X" | Add X to nodes/endings or fix reference |
| Missing required field | Check node type requirements |

---

## Output Templates

- **workflow.yaml:** `templates/workflow.yaml.template`
- **Thin SKILL.md:** `templates/skill-with-executor.md.template`

---

## Related Documentation

- **Skill Analysis:** `lib/blueprint/patterns/skill-analysis.md`
- **Node Mapping:** `lib/blueprint/patterns/node-mapping.md`
- **Workflow Schema:** `lib/workflow/engine.md`
