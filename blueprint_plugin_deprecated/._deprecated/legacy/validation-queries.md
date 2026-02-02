# Validation Queries

> **ARCHIVED:** This document is preserved for reference. Validation logic is being converted to:
> - **Validation workflow:** `skills/hiivmind-blueprint-validate/workflow.yaml`
> - **Validation consequence types:** `lib/consequences/definitions/extensions/validation.yaml`

---

yq query patterns for workflow.yaml validation. Used by `hiivmind-blueprint-validate`.

## Prerequisites

These queries require yq v4+ (mikefarah/yq).

```bash
# Verify installation
yq --version
# Expected: yq (https://github.com/mikefarah/yq/) version v4.x.x
```

---

## Schema Validation Queries

### Check Required Top-Level Fields

```bash
# All required fields present
yq 'has("name") and has("version") and has("start_node") and has("nodes") and has("endings")' workflow.yaml

# Individual field checks
yq 'has("name")' workflow.yaml
yq 'has("version")' workflow.yaml
yq 'has("description")' workflow.yaml
yq 'has("start_node")' workflow.yaml
yq 'has("nodes")' workflow.yaml
yq 'has("endings")' workflow.yaml
yq 'has("initial_state")' workflow.yaml
yq 'has("entry_preconditions")' workflow.yaml
```

### Check Nodes Non-Empty

```bash
# Nodes object has entries
yq '.nodes | length > 0' workflow.yaml

# Endings object has entries
yq '.endings | length > 0' workflow.yaml
```

---

## Node Type Validation

### List All Node Types

```bash
# Get unique node types
yq '[.nodes | to_entries | .[] | .value.type] | unique | .[]' workflow.yaml
```

### Find Invalid Node Types

```bash
# List types that aren't in the valid set
yq '[.nodes | to_entries | .[] | .value.type] | unique | .[] | select(. != "action" and . != "conditional" and . != "user_prompt" and . != "validation_gate" and . != "reference")' workflow.yaml
```

---

## Referential Integrity Queries

### Get All Valid Targets

```bash
# All node and ending names (valid transition targets)
yq '(.nodes | keys) + (.endings | keys) | .[]' workflow.yaml
```

### Check start_node Exists

```bash
# Returns true if start_node is in nodes
yq '.start_node as $start | .nodes | has($start)' workflow.yaml
```

### Find Invalid References

```bash
# References that aren't in nodes or endings
yq '
  (.nodes | keys) as $nodes |
  (.endings | keys) as $endings |
  ($nodes + $endings) as $valid |
  [.nodes | to_entries | .[] | [.value.on_success, .value.on_failure, .value.branches.on_true, .value.branches.on_false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null)] |
  unique |
  map(select(. as $ref | $valid | index($ref) | not)) |
  if length == 0 then empty else .[] end
' workflow.yaml
```

---

## User Prompt Validation Queries

### Check on_response Handlers

```bash
# Find user_prompt nodes where option IDs don't have handlers
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt") | {node: .key, options: [.value.prompt.options[].id], handlers: (.value.on_response | keys), missing: ([.value.prompt.options[].id] - (.value.on_response | keys))} | select(.missing | length > 0)' workflow.yaml
```

### Check Header Length

```bash
# Find prompts with header > 12 chars
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt" and (.value.prompt.header | length) > 12) | {node: .key, header: .value.prompt.header, length: (.value.prompt.header | length)}' workflow.yaml
```

---

## Graph Analysis Queries

### Find Potential Dead Ends

```bash
# Nodes without outgoing transitions (that aren't endings)
yq '
  (.endings | keys) as $endings |
  .nodes | to_entries | .[] |
  select(
    .value.on_success == null and
    .value.on_failure == null and
    .value.branches.on_true == null and
    .value.branches.on_false == null and
    .value.next_node == null and
    (.value.on_response == null or (.value.on_response | length) == 0)
  ) |
  .key
' workflow.yaml
```

### Detect Self-Loops

```bash
# Nodes that reference themselves
yq '.nodes | to_entries | .[] | select([.value.on_success, .value.on_failure, .value.branches.on_true, .value.branches.on_false, .value.next_node, (.value.on_response | .[]? | .next_node)] | any(. == .key)) | .key' workflow.yaml
```

---

## Type Validation Queries

> **See also:** `skills/hiivmind-blueprint-validate/SKILL.md` Phase 3.4 for the complete
> extensible type validation implementation with parameter checking.

### Extract All Precondition Types Used

```bash
# All precondition types in workflow
yq '[
  (.entry_preconditions[]?.type),
  (.nodes | to_entries | .[] | .value.condition?.type),
  (.nodes | to_entries | .[] | .value.validations[]?.type)
] | .[] | select(. != null) | unique' workflow.yaml
```

### Extract All Consequence Types Used

```bash
# All consequence types in workflow
yq '[
  (.nodes | to_entries | .[] | .value.actions[]?.type),
  (.nodes | to_entries | .[] | .value.on_response | .[]? | .consequence[]?.type)
] | .[] | select(. != null) | unique' workflow.yaml
```

### Extensible Type Validation

Type validation uses an extensible approach:
- **Known types**: Validates required parameters ARE present (error if missing)
- **Unknown types**: Allows them through with warnings (preserves extensibility)

See `skills/hiivmind-blueprint-validate/SKILL.md` Phase 3.4 for:
- Loading type definitions from `hiivmind-blueprint-lib`
- Extracting all precondition/consequence usages (including nested in composites)
- Validating required parameters are present
- Typo suggestions for unknown types

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - Workflow YAML structure
- **Preconditions:** `lib/preconditions/definitions/` - Precondition type definitions
- **Consequences:** `lib/consequences/definitions/` - Consequence type definitions
- **Validate Skill:** `skills/hiivmind-blueprint-validate/SKILL.md`
