# Workflow Generation Pattern

Generate complete workflow.yaml files from analyzed skill structures.

> **Related Patterns:**
> - Prompt Modes: `lib/patterns/prompt-modes.md`
> - Node Mapping: `lib/patterns/node-mapping.md`

---

## Generation Phases

1. **Scaffold** - Create header, entry_preconditions, initial_state
2. **Build nodes** - Map analysis elements to node configurations
3. **Connect transitions** - Wire on_success/on_failure/branches
4. **Define endings** - Success and error endpoints
5. **Validate graph** - Check reachability and paths to endings
6. **Output files** - Write workflow.yaml and SKILL.md

---

## Scaffold Generation

### Header

```yaml
name: "{{skill_name}}"
version: "1.0.0"
description: >
  {{original_description}}

definitions:
  source: "{computed.lib_ref}"
```

### Entry Preconditions

Generate from analysis.prerequisites:
- "requires git" → `tool_check: { tool: git, capability: available }`
- "config must exist" → `path_check: { path: data/config.yaml, check: is_file }`

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

### Multi-Modal Prompt Configuration

If workflow has user_prompt nodes, configure prompt modes:

```yaml
initial_state:
  prompts:
    interface: "auto"  # auto-detect or explicit
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.7
```

### Logging Auto-Features

When logging is enabled, the engine auto-injects `log_node` and `log_entry` consequences:

```yaml
initial_state:
  logging:
    enabled: true
    level: "info"
    auto:
      node_tracking: true  # Auto-call log_node after each node
    output:
      format: "yaml"
      location: ".logs/"
    retention:
      strategy: "count"
      count: 10
```

**With `logging.auto` enabled:**
- No explicit `log_node` consequences needed per node
- `log_entry` available for manual event/warning/error logging

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
| conditional (audit) | `branches.on_true`, `branches.on_false` + `audit.output` |
| user_prompt | `on_response.*.next_node` |
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

## Remote Workflow References

Use reference nodes to delegate to shared workflows:

```yaml
detect_intent:
  type: reference
  workflow: {computed.lib_ref}:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
  next_node: "${computed.dynamic_target}"
```

**Format:** `owner/repo@version:workflow-name`

**Key characteristics:**
- State is shared with parent workflow
- Sub-workflow can read and modify parent state
- `next_node` supports dynamic interpolation

---

## Conditional Audit Mode

For validation scenarios, use audit mode to collect all errors:

```yaml
validate_prerequisites:
  type: conditional
  condition:
    type: composite
    operator: all
    conditions:
      - type: tool_check
        tool: git
        capability: available
      - type: path_check
        path: "data/config.yaml"
        check: is_file
  audit:
    enabled: true
    output: computed.validation_errors
    messages:
      tool_check: "Git is required"
      path_check: "Configuration file missing"
  branches:
    on_true: proceed
    on_false: show_errors
```

**Audit mode:**
- Evaluates ALL conditions (no short-circuit)
- Collects results with custom error messages
- Replaces deprecated `validation_gate` node type

---

## Type Quick Reference

### Consequences (consolidated)

| Old Types | New Type | Operation Parameter |
|-----------|----------|-------------------|
| `read_file`, `write_file`, `create_directory`, `delete_file` | `local_file_ops` | read, write, mkdir, delete |
| `clone_repo`, `git_pull`, `git_fetch`, `get_sha` | `git_ops_local` | clone, pull, fetch, get-sha |
| `web_fetch`, `cache_web_content` | `web_ops` | fetch, cache |
| `run_script`, `run_python`, `run_bash` | `run_command` | interpreter: auto/bash/python/node |
| `set_state`, `append_state`, `clear_state`, `merge_state` | `mutate_state` | set, append, clear, merge |
| `display_message`, `display_table` | `display` | format: text/table/json/markdown |

### Preconditions (consolidated)

| Old Types | New Type | Parameter |
|-----------|----------|-----------|
| `flag_set`, `flag_not_set`, `state_equals`, `state_not_null`, `state_is_null` | `state_check` | operator: true/false/equals/not_null/null |
| `file_exists`, `directory_exists`, `config_exists`, `index_exists` | `path_check` | check: exists/is_file/is_directory/contains_text |
| `tool_available`, `tool_version_gte` | `tool_check` | capability: available/version_gte |
| `source_exists`, `source_cloned`, `source_has_updates` | `source_check` | aspect: exists/cloned/has_updates |
| `all_of`, `any_of`, `none_of`, `xor_of` | `composite` | operator: all/any/none/xor |
| `fetch_succeeded`, `fetch_returned_content` | `fetch_check` | aspect: succeeded/has_content |
| `count_equals`, `count_above`, `count_below` | `evaluate_expression` | len(field) == N, len(field) > N, etc. |

---

## Progressive Loading Strategy

Execution semantics from hiivmind-blueprint-lib should be loaded progressively, not all at once.

### Why Progressive Loading?

| Problem | Solution |
|---------|----------|
| Files are 2000+ lines | Fetch entrypoints first (small payloads) |
| Skimmable prose gets pattern-matched | Verification checkpoints with specific values |
| Full files discourage reading | On-demand detail fetching |
| No validation of actual reading | Expected values that can't be guessed |

### The 3-Phase Loading Model

```
Phase 1: Entrypoint Fetch (before execution)
    ↓
    Fetch bootstrap phases, traversal phases, type threshold
    Store in state._semantics.*
    VERIFY expected values match
    ↓
Phase 2: Execute with Entrypoints as Guide
    ↓
    Follow _semantics.traversal.phases: ["initialize", "execute", "complete"]
    Use _semantics.type_loading.hybrid_threshold: 30
    ↓
Phase 3: On-Demand Detail Fetch (during execution)
    ↓
    First time dispatching a conditional? Fetch conditional.yaml
    First time loading a reference? Fetch workflow-loader.yaml
    First time executing consequence type X? Fetch consequences/X.yaml
```

### State Tracking for Semantics

Add these fields to `initial_state` to track what's been loaded:

```yaml
initial_state:
  _semantics_loaded:
    execution_loader: false
    engine_execution: false
    type_loader: false
    workflow_loader: false
  _semantics:
    bootstrap: null
    traversal: null
    type_loading: null
    output_defaults: null
```

### Verification Checkpoint Values

These specific values create a forcing function for actual reading:

| Field | Expected | Why Specific |
|-------|----------|--------------|
| `_semantics.traversal.phases` | `["initialize", "execute", "complete"]` | 3-phase model, not guessable |
| `_semantics.bootstrap.required_sections` | 4 items | Specific count from file |
| `_semantics.type_loading.hybrid_threshold` | `30` | Specific number from file |
| `_semantics.bootstrap.phases` | ends with "execute" | 5-phase bootstrap sequence |

If these values are wrong, the fetch was skipped or returned incorrect data.

### Pre-Composed yq Queries

See `resolution/entrypoints.yaml` in hiivmind-blueprint-lib for ready-to-use queries:

```bash
# Bootstrap entrypoints
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/resolution/execution-loader.yaml \
  --jq '.content' | base64 -d | yq '{
    "phases": [.resolution.execution_loader.bootstrap.fetch_order.phases[].id],
    "required_sections": [.resolution.execution_loader.section_registry.sections | to_entries[] | select(.value.required == true) | .key]
  }'
```

### Templates Using Progressive Loading

Both templates now include progressive loading:
- `templates/gateway-command.md.template` - Phase 2 entrypoint fetch block
- `templates/SKILL.md.template` - Phase 1 entrypoint fetch with verification

---

## Output Templates

- **workflow.yaml:** `templates/workflow.yaml.template`
- **SKILL.md:** `templates/SKILL.md.template`

---

## Related Documentation

- **Skill Analysis:** `lib/blueprint/patterns/skill-analysis.md`
- **Node Mapping:** `lib/blueprint/patterns/node-mapping.md`
- **Prompt Modes:** `lib/patterns/prompt-modes.md`
- **Workflow Schema:** `lib/workflow/engine.md`
- **Type References:**
  - `references/consequences-catalog.md`
  - `references/preconditions-catalog.md`
  - `references/node-features.md`
  - `references/prompt-modes.md`
