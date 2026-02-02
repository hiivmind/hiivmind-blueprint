# Plan: Extensible Type Validation for Workflows

## Problem Statement

The `workflow.json` schema uses `additionalProperties: true` for preconditions/consequences to allow forward-compatibility with new types. But this means:
- Known types with missing required params pass schema validation
- No parameter validation at all

We need **extensible validation** that:
- **Known types**: Validates required parameters ARE present (error if missing)
- **Unknown types**: Allows them through (warns, doesn't block) - preserving extensibility

## Design Philosophy

| Type Status | Behavior |
|-------------|----------|
| Known type, all params present | ✅ Pass |
| Known type, missing required param | ❌ Error |
| Unknown type | ⚠️ Warning (not error) - allows extension |
| Known type, extra params | ✅ Pass (forward-compatible) |

## Implementation

### Enhance Phase 3.4 in `hiivmind-blueprint-validate/SKILL.md`

Add detailed implementation for parameter validation.

### Step 1: Load Type Definitions

```bash
# Build type lookup from definition files
SCHEMA_DIR="${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib"

# Extract precondition types and their required parameters
yq eval-all '
  [.preconditions[] | {
    "type": .type,
    "required_params": [.parameters[] | select(.required == true) | .name]
  }]
' "$SCHEMA_DIR"/preconditions/**/*.yaml > /tmp/precondition_types.json

# Extract consequence types and their required parameters
yq eval-all '
  [.consequences[] | {
    "type": .type,
    "required_params": [.parameters[] | select(.required == true) | .name]
  }]
' "$SCHEMA_DIR"/consequences/**/*.yaml > /tmp/consequence_types.json
```

### Step 2: Extract Used Types from Workflow

```bash
# Get all precondition types used in workflow
yq '
  [
    # Entry preconditions
    .entry_preconditions[]?.type,
    # Conditional node conditions (including nested in all_of, any_of, etc.)
    .. | select(has("type") and (parent | type) != "object" or (parent | has("type"))) | .type
  ] | unique | .[]
' workflow.yaml

# Get all consequence types used
yq '
  [.nodes | .. | select(type == "!!map" and has("type") and (parent | has("actions"))) | .type] | unique | .[]
' workflow.yaml
```

### Step 3: Validate Types Exist

```bash
# Check each used precondition type exists in definitions
for type in $(yq '...' workflow.yaml); do
  if ! yq ".[] | select(.type == \"$type\")" /tmp/precondition_types.json | grep -q .; then
    echo "ERROR: Unknown precondition type: $type"
  fi
done
```

### Step 4: Validate Required Parameters Present

```bash
# For each precondition usage, check required params
# This requires correlating usage location with type definition

# Example: For file_exists, check 'path' parameter is present
yq '
  .nodes | to_entries | .[] |
  select(.value.condition.type == "file_exists") |
  select(.value.condition | has("path") | not) |
  "ERROR: \(.key): file_exists missing required param: path"
' workflow.yaml
```

### New Checks to Add

| # | Check | Query Pattern | Severity |
|---|-------|---------------|----------|
| 27a | Unknown precondition type | Type not in definitions | **Warning** (allows extension) |
| 27b | Unknown consequence type | Type not in definitions | **Warning** (allows extension) |
| 27c | Missing required precondition param | Known type, param missing | **Error** |
| 27d | Missing required consequence param | Known type, param missing | **Error** |
| 27e | Nested precondition params | Check params in all_of/any_of/xor_of/not | **Error** |
| 27f | Typo suggestions | Unknown type similar to known type | **Info** |

### Pseudocode for Extensible Validation

```python
# Load definitions
precond_defs = load_all_preconditions()  # {type: {required_params: [...]}}
conseq_defs = load_all_consequences()

# Validate preconditions
for precond in extract_all_preconditions(workflow):
    if precond.type not in precond_defs:
        # WARN not error - allows custom/extension types
        warn(f"Unknown precondition type: {precond.type} (may be custom extension)")
        continue  # Can't validate params for unknown type

    # For KNOWN types, require all params
    required = precond_defs[precond.type].required_params
    for param in required:
        if param not in precond:
            error(f"{precond.type} missing required param: {param}")

# Validate consequences (in action nodes)
for action_node in workflow.nodes.values():
    if action_node.type != 'action':
        continue
    for conseq in action_node.actions:
        if conseq.type not in conseq_defs:
            # WARN not error - allows custom/extension types
            warn(f"Unknown consequence type: {conseq.type} (may be custom extension)")
            continue

        # For KNOWN types, require all params
        required = conseq_defs[conseq.type].required_params
        for param in required:
            if param not in conseq:
                error(f"{conseq.type} missing required param: {param}")
```

### Handling Nested Preconditions

Preconditions can be nested in composites:

```yaml
condition:
  type: all_of
  conditions:
    - type: file_exists
      path: "config.yaml"
    - type: flag_set
      flag: initialized
```

Need to recursively extract preconditions:

```bash
# Recursive extraction using yq
yq '
  .. | select(type == "!!map" and has("type")) |
  select(.type | test("^(all_of|any_of|xor_of|not)$") | not) |
  {type: .type, params: (. | keys | map(select(. != "type")))}
' workflow.yaml
```

## Files to Modify

| File | Changes |
|------|---------|
| `skills/hiivmind-blueprint-validate/SKILL.md` | Add detailed Phase 3.4 implementation with yq patterns |

## Verification

1. Run enhanced validation against existing workflows
2. Test with intentionally broken workflow (wrong type, missing param)
3. Verify error messages are clear and actionable

## Example Error Output

```
══════════════════════════════════════
  Blueprint Workflow Validation Report
══════════════════════════════════════

Errors (1)
──────────
✗ [Type] clone_repo missing required param: url (line 78)
  Required params: url, path
  Found: path

Warnings (2)
────────────
⚠ [Type] Unknown precondition type: my_custom_check (line 45)
  May be a custom extension - cannot validate parameters

⚠ [Type] Unknown precondition type: filexists (line 52)
  Did you mean: file_exists?
```

This approach:
- **Errors** on known types with missing params (blocks if found)
- **Warns** on unknown types (allows extensibility, suggests typo fixes)


The implementation is complete. Let me provide a summary of what was implemented:

  Summary

  I've implemented extensible type validation for workflows in hiivmind-blueprint-validate/SKILL.md. The key changes are:

  Phase 3.4: Type Validation (Enhanced)

  New Checks Added:
  ┌───────┬──────────────────────────────────────────┬────────────────────────────┐
  │ Check │               Description                │          Severity          │
  ├───────┼──────────────────────────────────────────┼────────────────────────────┤
  │ 27a   │ Unknown precondition type                │ Warning (allows extension) │
  ├───────┼──────────────────────────────────────────┼────────────────────────────┤
  │ 27b   │ Unknown consequence type                 │ Warning (allows extension) │
  ├───────┼──────────────────────────────────────────┼────────────────────────────┤
  │ 27c   │ Missing required precondition param      │ Error                      │
  ├───────┼──────────────────────────────────────────┼────────────────────────────┤
  │ 27d   │ Missing required consequence param       │ Error                      │
  ├───────┼──────────────────────────────────────────┼────────────────────────────┤
  │ 27e   │ Nested precondition params in composites │ Error                      │
  ├───────┼──────────────────────────────────────────┼────────────────────────────┤
  │ 27f   │ Typo suggestions for unknown types       │ Info                       │
  └───────┴──────────────────────────────────────────┴────────────────────────────┘
  Design Philosophy:
  - Known types with missing required params → Error
  - Unknown types → Warning (preserves extensibility for custom types)
  - Known types with extra params → Pass (forward-compatible)

  Implementation Steps:
  1. Step 3.4.1: Load type definitions from hiivmind-blueprint-lib using yq eval-all
  2. Step 3.4.2: Extract all precondition usages (entry, conditional nodes, validation gates, nested in composites)
  3. Step 3.4.3: Extract all consequence usages (action nodes, user_prompt on_response)
  4. Step 3.4.4: Validate precondition types and parameters with typo suggestions
  5. Step 3.4.5: Validate consequence types and parameters with typo suggestions
  6. Step 3.4.6: Special handling for composite preconditions (all_of, any_of, xor_of, none_of)

  Also Updated:
  - lib/workflow/legacy/validation-queries.md - Added cross-reference to the new extensible validation implementation

✻ Baked for 6m 4s
