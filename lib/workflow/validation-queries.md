# Validation Queries

yq query patterns for workflow.yaml validation. Used by `hiivmind-blueprint-validate`.

---

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

### Get Workflow Metadata

```bash
# Extract key fields for report header
yq '{name: .name, version: .version, start_node: .start_node}' workflow.yaml

# Get node count
yq '.nodes | length' workflow.yaml

# Get ending count
yq '.endings | length' workflow.yaml
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

### Nodes Missing Type Field

```bash
# Find nodes without a type field
yq '.nodes | to_entries | .[] | select(.value.type == null) | .key' workflow.yaml
```

---

## Node Type-Specific Required Fields

### Action Nodes

```bash
# Find action nodes missing required fields
yq '.nodes | to_entries | .[] | select(.value.type == "action") | select(.value.actions == null or .value.on_success == null or .value.on_failure == null) | {node: .key, missing: ([(if .value.actions == null then "actions" else empty end), (if .value.on_success == null then "on_success" else empty end), (if .value.on_failure == null then "on_failure" else empty end)])}' workflow.yaml
```

### Conditional Nodes

```bash
# Find conditional nodes missing required fields
yq '.nodes | to_entries | .[] | select(.value.type == "conditional") | select(.value.condition == null or .value.branches == null or .value.branches.true == null or .value.branches.false == null) | {node: .key, missing: ([(if .value.condition == null then "condition" else empty end), (if .value.branches.true == null then "branches.true" else empty end), (if .value.branches.false == null then "branches.false" else empty end)])}' workflow.yaml
```

### User Prompt Nodes

```bash
# Find user_prompt nodes missing required fields
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt") | select(.value.prompt == null or .value.prompt.question == null or .value.prompt.header == null or .value.prompt.options == null or .value.on_response == null) | {node: .key, missing: ([(if .value.prompt.question == null then "prompt.question" else empty end), (if .value.prompt.header == null then "prompt.header" else empty end), (if .value.prompt.options == null then "prompt.options" else empty end), (if .value.on_response == null then "on_response" else empty end)])}' workflow.yaml
```

### Validation Gate Nodes

```bash
# Find validation_gate nodes missing required fields
yq '.nodes | to_entries | .[] | select(.value.type == "validation_gate") | select(.value.validations == null or .value.on_valid == null or .value.on_invalid == null) | {node: .key, missing: ([(if .value.validations == null then "validations" else empty end), (if .value.on_valid == null then "on_valid" else empty end), (if .value.on_invalid == null then "on_invalid" else empty end)])}' workflow.yaml
```

### Reference Nodes

```bash
# Find reference nodes missing required fields
yq '.nodes | to_entries | .[] | select(.value.type == "reference") | select(.value.doc == null or .value.next_node == null) | {node: .key, missing: ([(if .value.doc == null then "doc" else empty end), (if .value.next_node == null then "next_node" else empty end)])}' workflow.yaml
```

---

## Referential Integrity Queries

### Get All Valid Targets

```bash
# All node and ending names (valid transition targets)
yq '(.nodes | keys) + (.endings | keys) | .[]' workflow.yaml

# As JSON array for scripting
yq -o=json '(.nodes | keys) + (.endings | keys)' workflow.yaml
```

### Check start_node Exists

```bash
# Returns true if start_node is in nodes
yq '.start_node as $start | .nodes | has($start)' workflow.yaml

# Get start_node value
yq '.start_node' workflow.yaml
```

### Find All Transition References

```bash
# List all transitions with source and destination
yq '.nodes | to_entries | .[] | {node: .key, type: .value.type, on_success: .value.on_success, on_failure: .value.on_failure, branches_true: .value.branches.true, branches_false: .value.branches.false, next_node: .value.next_node, on_response: (.value.on_response | keys // [])}' workflow.yaml
```

### Find All Destination Nodes

```bash
# Collect all referenced destinations
yq '[.nodes | to_entries | .[] | [.value.on_success, .value.on_failure, .value.branches.true, .value.branches.false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null)] | unique | .[]' workflow.yaml
```

### Find Invalid References

```bash
# References that aren't in nodes or endings
yq '
  (.nodes | keys) as $nodes |
  (.endings | keys) as $endings |
  ($nodes + $endings) as $valid |
  [.nodes | to_entries | .[] | [.value.on_success, .value.on_failure, .value.branches.true, .value.branches.false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null)] |
  unique |
  map(select(. as $ref | $valid | index($ref) | not)) |
  if length == 0 then empty else .[] end
' workflow.yaml
```

### Find Invalid References with Context

```bash
# Get invalid references with the node that references them
yq '
  (.nodes | keys) as $nodes |
  (.endings | keys) as $endings |
  ($nodes + $endings) as $valid |
  .nodes | to_entries | .[] |
  {
    node: .key,
    invalid_on_success: (if .value.on_success != null and ($valid | index(.value.on_success) | not) then .value.on_success else null end),
    invalid_on_failure: (if .value.on_failure != null and ($valid | index(.value.on_failure) | not) then .value.on_failure else null end),
    invalid_branches_true: (if .value.branches.true != null and ($valid | index(.value.branches.true) | not) then .value.branches.true else null end),
    invalid_branches_false: (if .value.branches.false != null and ($valid | index(.value.branches.false) | not) then .value.branches.false else null end),
    invalid_next_node: (if .value.next_node != null and ($valid | index(.value.next_node) | not) then .value.next_node else null end)
  } |
  select(.invalid_on_success != null or .invalid_on_failure != null or .invalid_branches_true != null or .invalid_branches_false != null or .invalid_next_node != null)
' workflow.yaml
```

---

## User Prompt Validation Queries

### Check on_response Handlers

```bash
# Find user_prompt nodes where option IDs don't have handlers
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt") | {node: .key, options: [.value.prompt.options[].id], handlers: (.value.on_response | keys), missing: ([.value.prompt.options[].id] - (.value.on_response | keys))} | select(.missing | length > 0)' workflow.yaml
```

### Check for Duplicate Option IDs

```bash
# Find prompts with duplicate option IDs
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt") | {node: .key, duplicates: ([.value.prompt.options[].id] | group_by(.) | .[] | select(length > 1) | .[0])} | select(.duplicates != null)' workflow.yaml
```

### Check Header Length

```bash
# Find prompts with header > 12 chars
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt" and (.value.prompt.header | length) > 12) | {node: .key, header: .value.prompt.header, length: (.value.prompt.header | length)}' workflow.yaml
```

### Check Option Count

```bash
# Find prompts with <2 or >4 options
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt" and ((.value.prompt.options | length) < 2 or (.value.prompt.options | length) > 4)) | {node: .key, option_count: (.value.prompt.options | length)}' workflow.yaml
```

### List All Prompts with Stats

```bash
# Summary of all user_prompt nodes
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt") | {node: .key, header: .value.prompt.header, header_length: (.value.prompt.header | length), option_count: (.value.prompt.options | length)}' workflow.yaml
```

---

## Graph Analysis Queries

### Build Adjacency List

```bash
# Node to destinations mapping
yq '.nodes | to_entries | .[] | {node: .key, destinations: ([.value.on_success, .value.on_failure, .value.branches.true, .value.branches.false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null)) | unique}' workflow.yaml
```

### Find Reachable Nodes

To find orphan nodes, we need to trace from start_node. This is a multi-step process best done in bash/python, but we can get the direct descendants:

```bash
# Get start_node and its direct descendants
yq '.start_node as $start | .nodes[$start] | [.on_success, .on_failure, .branches.true, .branches.false, .next_node, (.on_response | .[]? | .next_node)] | .[] | select(. != null) | unique' workflow.yaml
```

### Find Potential Dead Ends

```bash
# Nodes without outgoing transitions (that aren't endings)
yq '
  (.endings | keys) as $endings |
  .nodes | to_entries | .[] |
  select(
    .value.on_success == null and
    .value.on_failure == null and
    .value.branches.true == null and
    .value.branches.false == null and
    .value.next_node == null and
    (.value.on_response == null or (.value.on_response | length) == 0)
  ) |
  .key
' workflow.yaml
```

### Detect Self-Loops

```bash
# Nodes that reference themselves
yq '.nodes | to_entries | .[] | select([.value.on_success, .value.on_failure, .value.branches.true, .value.branches.false, .value.next_node, (.value.on_response | .[]? | .next_node)] | any(. == .key)) | .key' workflow.yaml
```

### Find Single-Option User Prompts

```bash
# User prompts with only 1 option (potential railroad)
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt" and (.value.prompt.options | length) == 1) | .key' workflow.yaml
```

---

## Type Validation Queries

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

### Known Precondition Types (for comparison)

```bash
# Define as shell array
KNOWN_PRECONDITIONS=(
  "config_exists" "index_exists" "index_is_placeholder" "file_exists" "directory_exists"
  "source_exists" "source_cloned" "source_has_updates"
  "tool_available" "python_module_available"
  "flag_set" "flag_not_set" "state_equals" "state_not_null" "state_is_null"
  "count_equals" "count_above" "count_below"
  "fetch_succeeded" "fetch_returned_content"
  "all_of" "any_of" "none_of" "evaluate_expression"
)
```

### Known Consequence Types (for comparison)

```bash
# Define as shell array
KNOWN_CONSEQUENCES=(
  # Core: workflow.md
  "set_flag" "set_state" "append_state" "clear_state" "merge_state"
  "evaluate" "compute"
  "display_message" "display_table"
  "invoke_pattern" "create_checkpoint" "rollback_checkpoint" "spawn_agent"
  "set_timestamp" "compute_hash" "invoke_skill"
  # Core: intent-detection.md
  "evaluate_keywords" "parse_intent_flags" "match_3vl_rules" "dynamic_route"
  # Core: logging.md
  "init_log" "log_node" "log_event" "log_warning" "log_error"
  "log_session_snapshot" "finalize_log" "write_log"
  "apply_log_retention" "output_ci_summary"
  # Extensions: file-system.md
  "read_config" "read_file" "write_file" "create_directory" "delete_file"
  "write_config_entry"
  # Extensions: git.md
  "clone_repo" "get_sha" "git_pull" "git_fetch"
  # Extensions: web.md
  "web_fetch" "cache_web_content"
  # Domain-specific
  "add_source" "update_source" "discover_installed_corpora"
)
```

---

## State/Variable Validation Queries

### Find All Variable References

```bash
# Extract ${...} patterns from strings
yq '.. | strings | select(test("\\$\\{")) | capture("\\$\\{(?<var>[^}]+)\\}") | .var' workflow.yaml
```

### Find All Flags Set via set_flag

```bash
yq '[.nodes | to_entries | .[] | .value.actions[]? | select(.type == "set_flag") | .flag] | unique | .[]' workflow.yaml
```

### Find All Flags Checked via flag_set

```bash
yq '[
  (.entry_preconditions[]? | select(.type == "flag_set") | .flag),
  (.nodes | to_entries | .[] | .value.condition? | select(.type == "flag_set") | .flag),
  (.nodes | to_entries | .[] | .value.validations[]? | select(.type == "flag_set") | .flag)
] | .[] | select(. != null) | unique' workflow.yaml
```

### Find All store_as Targets

```bash
yq '[.nodes | to_entries | .[] | .value.actions[]? | .store_as | select(. != null)] | unique | .[]' workflow.yaml
```

### Find Initial State Fields

```bash
yq '.initial_state | keys | .[]' workflow.yaml

# Including nested fields
yq '.initial_state | .. | path | join(".")' workflow.yaml
```

---

## Ending Validation Queries

### Check Ending Types

```bash
# Find invalid ending types
yq '[.endings | to_entries | .[] | .value.type] | unique | .[] | select(. != "success" and . != "error")' workflow.yaml
```

### Check for Success Ending

```bash
# Count success endings
yq '[.endings | to_entries | .[] | select(.value.type == "success")] | length' workflow.yaml
```

### Find Variable References in Ending Messages

```bash
yq '.endings | to_entries | .[] | {ending: .key, message: .value.message, vars: ([.value.message | capture("\\$\\{(?<var>[^}]+)\\}"; "g") | .var] // [])}' workflow.yaml
```

### List All Endings

```bash
yq '.endings | to_entries | .[] | {name: .key, type: .value.type, message: .value.message, recovery: .value.recovery}' workflow.yaml
```

---

## Intent Mapping Validation Queries

Use these on `intent-mapping.yaml` if it exists.

### List All Defined Flags

```bash
yq '.intent_flags | keys | .[]' intent-mapping.yaml
```

### List All Rules and Their Conditions

```bash
yq '.intent_rules[] | {name: .name, conditions: (.conditions | keys), action: .action}' intent-mapping.yaml
```

### Find Flags Referenced in Rules

```bash
yq '[.intent_rules[].conditions | keys | .[]] | unique | .[]' intent-mapping.yaml
```

### Find Flags Referenced But Not Defined

```bash
yq '
  (.intent_flags | keys) as $defined |
  [.intent_rules[].conditions | keys | .[]] | unique |
  map(select(. as $ref | $defined | index($ref) | not)) |
  if length == 0 then empty else .[] end
' intent-mapping.yaml
```

### Check 3VL Values Are Valid

```bash
# Find invalid 3VL values (not T, F, or U)
yq '[.intent_rules[].conditions | to_entries | .[].value] | unique | .[] | select(. != "T" and . != "F" and . != "U")' intent-mapping.yaml
```

### List All Rule Actions

```bash
yq '[.intent_rules[].action] | unique | .[]' intent-mapping.yaml
```

### Compare Rule Actions to Workflow Nodes

```bash
# Run this after getting workflow nodes
# Get all actions from intent-mapping
yq '[.intent_rules[].action] | unique | .[]' intent-mapping.yaml

# Compare against nodes in workflow (run separately)
yq '(.nodes | keys) + (.endings | keys) | .[]' workflow.yaml
```

---

## Logging Validation Queries

Queries for validating logging configuration and usage consistency.

### L1: Check init_log Exists When Config Present

```bash
# Check if logging config enabled but no init_log consequence
yq '
  (.initial_state.logging.enabled == true) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "init_log")] | length == 0)
' workflow.yaml
```

### L2: Check finalize_log Exists When init_log Used

```bash
# Find workflows with init_log but no finalize_log
yq '
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "init_log")] | length > 0) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "finalize_log")] | length == 0)
' workflow.yaml
```

### L3: Check Order - init Before finalize

```bash
# Get node order and verify init_log appears before finalize_log
# (Basic check - assumes node execution follows graph from start_node)
yq '
  .nodes | to_entries |
  map(select(.value.actions[]?.type == "init_log" or .value.actions[]?.type == "finalize_log")) |
  .[0].value.actions[]?.type == "init_log"
' workflow.yaml
```

### L4: Check write_log Has finalize_log

```bash
# Find write_log without finalize_log
yq '
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "write_log")] | length > 0) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "finalize_log")] | length == 0)
' workflow.yaml
```

### L5: Check Level Consistency

```bash
# Find workflows where config.level is error/warn but uses log_event (requires info level)
yq '
  (.initial_state.logging.level == "error" or .initial_state.logging.level == "warn") and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "log_event")] | length > 0)
' workflow.yaml

# Find workflows where config.level is error but uses log_warning (requires warn level)
yq '
  (.initial_state.logging.level == "error") and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "log_warning")] | length > 0)
' workflow.yaml
```

### L6: Check Retention Has write_log

```bash
# Find apply_log_retention without write_log
yq '
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "apply_log_retention")] | length > 0) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "write_log")] | length == 0)
' workflow.yaml
```

### L7: List All Logging Consequences

```bash
# Audit all logging consequences in workflow
yq '[.nodes | to_entries | .[] |
  {node: .key, logging: [.value.actions[]? | select(.type | test("^(init_log|log_node|log_event|log_warning|log_error|log_session_snapshot|finalize_log|write_log|apply_log_retention|output_ci_summary)$"))]}
] | map(select(.logging | length > 0))' workflow.yaml
```

### Logging Validation Summary

| # | Query | Purpose | Severity |
|---|-------|---------|----------|
| L1 | Config without init_log | Enabled logging but no initialization | Warning |
| L2 | init_log without finalize_log | Incomplete logging lifecycle | Error |
| L3 | Order check | init_log should precede finalize_log | Error |
| L4 | write_log without finalize | Writing unfinalized log | Error |
| L5 | Level mismatch | Config level doesn't permit used consequences | Warning |
| L6 | Retention without write | Can't clean logs that weren't written | Warning |
| L7 | List all logging | Audit helper | Info |

---

## Composite Validation Script

Example bash script combining multiple queries:

```bash
#!/bin/bash
# validate-workflow.sh - Quick validation checks

WORKFLOW="${1:-workflow.yaml}"

echo "=== Schema Validation ==="
echo -n "Required fields: "
yq 'has("name") and has("version") and has("start_node") and has("nodes") and has("endings")' "$WORKFLOW"

echo -n "Node count: "
yq '.nodes | length' "$WORKFLOW"

echo -n "Ending count: "
yq '.endings | length' "$WORKFLOW"

echo ""
echo "=== Invalid Node Types ==="
yq '[.nodes | to_entries | .[] | .value.type] | unique | .[] | select(. != "action" and . != "conditional" and . != "user_prompt" and . != "validation_gate" and . != "reference")' "$WORKFLOW"

echo ""
echo "=== Invalid References ==="
yq '
  (.nodes | keys) as $nodes |
  (.endings | keys) as $endings |
  ($nodes + $endings) as $valid |
  [.nodes | to_entries | .[] | [.value.on_success, .value.on_failure, .value.branches.true, .value.branches.false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null)] |
  unique |
  map(select(. as $ref | $valid | index($ref) | not)) |
  if length == 0 then "None" else .[] end
' "$WORKFLOW"

echo ""
echo "=== User Prompt Issues ==="
echo "Headers > 12 chars:"
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt" and (.value.prompt.header | length) > 12) | {node: .key, header: .value.prompt.header}' "$WORKFLOW"

echo "Missing handlers:"
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt") | {node: .key, missing: ([.value.prompt.options[].id] - (.value.on_response | keys))} | select(.missing | length > 0)' "$WORKFLOW"

echo ""
echo "=== Success Endings ==="
yq '[.endings | to_entries | .[] | select(.value.type == "success") | .key] | if length == 0 then "WARNING: No success ending!" else .[] end' "$WORKFLOW"
```

---

## Two-Tier Validation Architecture

The workflow system uses a two-tier validation approach for both preconditions and consequences:

### Tier 1: Structural Validation (JSON Schema)

The `lib/schema/workflow-schema.json` validates **workflow structure**:
- Required top-level fields (`name`, `version`, `start_node`, `nodes`, `endings`)
- Node types (`action`, `conditional`, `user_prompt`, `validation_gate`, `reference`)
- Node-type-specific required fields
- Transition references
- **Precondition has a `type` field** (but NOT which types exist)
- **Consequence has a `type` field** (but NOT which types exist)

```bash
# Validate structure with JSON Schema (requires jsonschema or ajv)
python3 -c "
import json, jsonschema
with open('lib/schema/workflow-schema.json') as f:
    schema = json.load(f)
import yaml
with open('workflow.yaml') as f:
    workflow = yaml.safe_load(f)
jsonschema.validate(workflow, schema)
print('Schema validation passed')
"
```

### Tier 2: Type Validation (Runtime)

Both preconditions and consequences use modular YAML definitions as the authoritative source.

#### Precondition Type Validation

The `lib/preconditions/definitions/index.yaml` is the **authoritative source** for precondition types:

```bash
# Check if a precondition type is valid
TYPE="file_exists"
yq ".type_lookup | has(\"$TYPE\")" lib/preconditions/definitions/index.yaml

# Get definition file for a type
yq ".type_lookup.$TYPE" lib/preconditions/definitions/index.yaml

# List all known precondition types
yq '.type_lookup | keys | .[]' lib/preconditions/definitions/index.yaml

# Count types
yq '.stats.total_types' lib/preconditions/definitions/index.yaml
```

#### Consequence Type Validation

The `lib/consequences/definitions/index.yaml` is the **authoritative source** for consequence types:

```bash
# Check if a consequence type is valid
TYPE="clone_repo"
yq ".type_lookup | has(\"$TYPE\")" lib/consequences/definitions/index.yaml

# Get definition file for a type
yq ".type_lookup.$TYPE" lib/consequences/definitions/index.yaml

# List all known consequence types
yq '.type_lookup | keys | .[]' lib/consequences/definitions/index.yaml

# Count types
yq '.stats.total_types' lib/consequences/definitions/index.yaml
```

### Runtime Precondition Validation

For each precondition used in a workflow, validate against definitions:

```bash
# Extract all precondition types used in workflow
USED_PRECONDITIONS=$(yq '[
  (.entry_preconditions[]?.type),
  (.nodes | to_entries | .[] | .value.condition?.type),
  (.nodes | to_entries | .[] | .value.validations[]?.type)
] | .[] | select(. != null) | unique' workflow.yaml)

# Check each against known types
KNOWN_PRECONDITIONS=$(yq '.type_lookup | keys | .[]' lib/preconditions/definitions/index.yaml)

for type in $USED_PRECONDITIONS; do
  if echo "$KNOWN_PRECONDITIONS" | grep -qx "$type"; then
    echo "✓ $type"
  else
    echo "✗ $type (unknown precondition type)"
  fi
done
```

### Runtime Consequence Validation

For each consequence used in a workflow, validate against definitions:

```bash
# Extract all consequence types used in workflow
USED_CONSEQUENCES=$(yq '[
  (.nodes | to_entries | .[] | .value.actions[]?.type),
  (.nodes | to_entries | .[] | .value.on_response | .[]? | .consequence[]?.type)
] | .[] | select(. != null) | unique' workflow.yaml)

# Check each against known types
KNOWN_CONSEQUENCES=$(yq '.type_lookup | keys | .[]' lib/consequences/definitions/index.yaml)

for type in $USED_CONSEQUENCES; do
  if echo "$KNOWN_CONSEQUENCES" | grep -qx "$type"; then
    echo "✓ $type"
  else
    echo "✗ $type (unknown consequence type)"
  fi
done
```

### Combined Runtime Validation

Validate both preconditions and consequences in one pass:

```bash
#!/bin/bash
# validate-types.sh - Runtime type validation

WORKFLOW="${1:-workflow.yaml}"
EXIT_CODE=0

echo "=== Precondition Type Validation ==="
USED_PRECONDITIONS=$(yq '[
  (.entry_preconditions[]?.type),
  (.nodes | to_entries | .[] | .value.condition?.type),
  (.nodes | to_entries | .[] | .value.validations[]?.type)
] | .[] | select(. != null)' "$WORKFLOW" | sort -u)

KNOWN_PRECONDITIONS=$(yq '.type_lookup | keys | .[]' lib/preconditions/definitions/index.yaml)

for type in $USED_PRECONDITIONS; do
  if echo "$KNOWN_PRECONDITIONS" | grep -qx "$type"; then
    echo "✓ $type"
  else
    echo "✗ $type (unknown precondition type)"
    EXIT_CODE=1
  fi
done

echo ""
echo "=== Consequence Type Validation ==="
USED_CONSEQUENCES=$(yq '[
  (.nodes | to_entries | .[] | .value.actions[]?.type),
  (.nodes | to_entries | .[] | .value.on_response | .[]? | .consequence[]?.type)
] | .[] | select(. != null)' "$WORKFLOW" | sort -u)

KNOWN_CONSEQUENCES=$(yq '.type_lookup | keys | .[]' lib/consequences/definitions/index.yaml)

for type in $USED_CONSEQUENCES; do
  if echo "$KNOWN_CONSEQUENCES" | grep -qx "$type"; then
    echo "✓ $type"
  else
    echo "✗ $type (unknown consequence type)"
    EXIT_CODE=1
  fi
done

exit $EXIT_CODE
```

### Benefits of Two-Tier Approach

| Aspect | Tier 1 (Schema) | Tier 2 (Definitions) |
|--------|----------------|---------------------|
| **Validates** | Workflow structure | Precondition and consequence types |
| **Source** | `workflow-schema.json` | `preconditions/definitions/`, `consequences/definitions/` |
| **When** | Parse time | Runtime |
| **Extensible** | No (fixed node types) | Yes (add YAML files) |
| **IDE support** | JSON Schema autocomplete | Separate tooling |

### Adding New Precondition Types

1. Add definition to `lib/preconditions/definitions/extensions/` or `core/`
2. Update `lib/preconditions/definitions/index.yaml` with type lookup
3. Workflows using new type will pass schema validation immediately
4. Runtime validation checks type exists in index

### Adding New Consequence Types

1. Add definition to `lib/consequences/definitions/extensions/` or `core/`
2. Update `lib/consequences/definitions/index.yaml` with type lookup
3. Workflows using new type will pass schema validation immediately
4. Runtime validation checks type exists in index

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - Workflow YAML structure
- **Preconditions:** `lib/preconditions/definitions/` - Precondition type definitions
- **Precondition Docs:** `lib/workflow/preconditions.md` - Precondition usage guide
- **Consequences:** `lib/consequences/definitions/` - Consequence type definitions
- **Capability Detection:** `lib/consequences/capabilities/` - Tool availability checks
- **Validate Skill:** `skills/hiivmind-blueprint-validate/SKILL.md`
