# Plan: Fix Intent Detection Workflow Schemas

## Scope

Focus **only** on intent detection within hiivmind-blueprint and hiivmind-blueprint-lib:
- `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib/workflows/core/intent-detection.yaml`
- Related schemas in hiivmind-blueprint-lib

Ignore corpus-specific business logic from the source workflow.

---

## Problem Statement

1. **Deploy-time self-containment**: Workflows need pseudocode embedded or properly referenced to execute without hiivmind-blueprint source.

2. **Schema compliance**: The `intent-detection.yaml` uses fields not defined in schemas.

---

## Current State of intent-detection.yaml

The workflow uses these types (all defined ✓):

| Consequence | Defined | Has Pseudocode |
|-------------|---------|----------------|
| `parse_intent_flags` | ✓ core/intent | ✓ payload.effect |
| `match_3vl_rules` | ✓ core/intent | ✓ payload.effect |
| `set_state` | ✓ core/state | ✓ payload.effect |
| `dynamic_route` | ✓ core/intent | ✓ payload.effect |

| Precondition | Defined | Notes |
|--------------|---------|-------|
| `evaluate_expression` | ✓ core/expression | Used in conditionals |

### Schema Violations in intent-detection.yaml

| Line | Issue | Current | Schema Expects |
|------|-------|---------|----------------|
| 125-132 | `options_from_state` | Dynamic options from state | Static `options` array |
| 129-132 | `option_mapping` | Transform state to options | Not defined |
| 134-146 | `on_response.selected/other` | Generic handlers | Specific option IDs |
| 166-173 | `endings` section | Workflow terminal states | Not in workflow schema |

---

## Proposed Architecture: Hybrid Model

### Principle

**Reusable consequences** reference predefined types with pseudocode in bundle:
```yaml
- type: parse_intent_flags       # Defined in bundle
  input: "${arguments}"
  flag_definitions: "${intent_flags}"
  store_as: computed.intent_flags
```

**Inline actions** embed pseudocode directly for non-reusable logic:
```yaml
- type: inline
  description: "Custom extraction logic"
  pseudocode: |
    result = custom_transform(input)
    return result
  store_as: computed.result
```

### user_prompt Schema Extension

Add support for dynamic options:

```yaml
# nodes/core/user-prompt.yaml - additions
prompt:
  # Static options (existing)
  options:
    type: array
    required_unless: options_from_state

  # Dynamic options (NEW)
  options_from_state:
    type: string
    description: State path containing array of items
    required_unless: options

  option_mapping:
    type: object
    required_with: options_from_state
    properties:
      id: { type: string, description: "Expression for option ID" }
      label: { type: string, description: "Expression for display label" }
      description: { type: string, description: "Expression for description" }

on_response:
  # Specific option handlers (existing)
  {option_id}: { consequence: array, next_node: string }

  # Generic handlers (NEW)
  selected:
    type: object
    description: Handler when user selects any dynamic option
  other:
    type: object
    description: Handler when user enters custom text
```

### endings Schema (NEW)

```yaml
# Workflow-level schema addition
endings:
  type: object
  description: Terminal states for the workflow
  additionalProperties:
    properties:
      type: { enum: [success, failure, cancelled] }
      message: { type: string }
      summary: { type: object }
```

---

## Implementation Plan

### Step 1: Extend user_prompt node schema
**File**: `hiivmind-blueprint-lib/nodes/core/user-prompt.yaml`

Add:
- `options_from_state` field with execution pseudocode
- `option_mapping` field
- `selected` and `other` response handlers
- Pseudocode in `execution.effect` for dynamic option building

### Step 2: Add endings to workflow schema
**File**: `hiivmind-blueprint-lib/bundle.yaml` (workflows section)

Add `endings` to the workflow definition schema.

### Step 3: Add inline consequence type
**File**: `hiivmind-blueprint-lib/consequences/core/control.yaml` or new file

Define the `inline` consequence type for embedded pseudocode.

### Step 4: Update bundle.yaml summaries
**File**: `hiivmind-blueprint-lib/bundle.yaml`

Update the `nodes.types.user_prompt` summary to include new fields.

### Step 5: Validate intent-detection.yaml
**File**: `hiivmind-blueprint-lib/workflows/core/intent-detection.yaml`

Verify workflow now complies with extended schemas.

---

## Files to Modify

| File | Changes |
|------|---------|
| `hiivmind-blueprint-lib/nodes/core/user-prompt.yaml` | Add dynamic options, generic handlers, execution pseudocode |
| `hiivmind-blueprint-lib/bundle.yaml` | Add endings schema, update user_prompt summary, add inline type |
| `hiivmind-blueprint-lib/consequences/core/control.yaml` | Add `inline` consequence type |
| `hiivmind-blueprint-lib/workflows/core/intent-detection.yaml` | Verify compliance (may need minor adjustments) |

---

## Verification

1. **Schema check**: `intent-detection.yaml` uses only defined types/fields
2. **Pseudocode completeness**: Every action node has execution semantics available
3. **Deploy test**: Load only `bundle.yaml` + `intent-detection.yaml`, verify all execution paths have pseudocode


● All validations pass. Here's a summary of changes made:

  Files Modified

  hiivmind-blueprint-lib

  1. nodes/core/user-prompt.yaml
    - Added options_from_state field (alternative to static options)
    - Added option_mapping field (transforms state items to options)
    - Added selected and other reserved response handler keys
    - Extended execution pseudocode to handle dynamic options
    - Added example showing disambiguation usage
  2. consequences/core/control.yaml
    - Added inline consequence type for embedded pseudocode
  3. bundle.yaml
    - Added inline to core/control types (now 44 consequences total)
    - Added workflow_schema.endings section with execution pseudocode
    - Updated user_prompt node summary with new fields
    - Fixed branch keys to use quoted "true"/"false" strings
  4. workflows/core/intent-detection.yaml
    - Fixed branch keys to use quoted "true"/"false" strings

  hiivmind-blueprint

  5. lib/schema/workflow-schema.json
    - Updated prompt definition to use oneOf (either options OR options_from_state + option_mapping)
    - Added option_mapping object definition
    - Added "failure" and "cancelled" to ending type enum

  Verification

  - intent-detection.yaml validates against workflow-schema.json ✓
  - workflow-schema.json is a valid JSON Schema ✓

✻ Baked for 2m 15s
