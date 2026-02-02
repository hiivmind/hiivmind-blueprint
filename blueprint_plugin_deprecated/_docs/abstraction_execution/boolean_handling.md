# Boolean Key Handling - IMPLEMENTED

**Status**: ✅ Completed
**Decision**: Option B (Semantic Key Names)
**Date**: 2026-01-28

## Problem Statement

When validating workflow.yaml files, we got errors like:
- `'true' is a required property`
- `Additional properties are not allowed ('False', 'True' were unexpected)`

**Root Cause**: YAML parses `true:` and `false:` as boolean literals (`True`/`False`), which get converted to capitalized strings `"True"`/`"False"` during validation. The schema expected lowercase `"true"`/`"false"`.

## Solution Implemented

Changed conditional node branch keys from `true`/`false` to `on_true`/`on_false`:

```yaml
# Before (required quoting to avoid YAML boolean parsing)
branches:
  "true": next_node_a
  "false": next_node_b

# After (no quoting needed - semantic key names)
branches:
  on_true: next_node_a
  on_false: next_node_b
```

### Schema Change (node-types.json)

```json
"branches": {
  "type": "object",
  "description": "Branch targets for true/false conditions",
  "required": ["on_true", "on_false"],
  "properties": {
    "on_true": {
      "$ref": "common.json#/$defs/node_reference",
      "description": "Node to transition to if condition is true"
    },
    "on_false": {
      "$ref": "common.json#/$defs/node_reference",
      "description": "Node to transition to if condition is false"
    }
  },
  "additionalProperties": false
}
```

## Files Modified

### hiivmind-blueprint-lib (schema + reference implementations)
- `schema/node-types.json` - Updated schema to require `on_true`/`on_false` keys
- `workflows/core/intent-detection.yaml` - Updated 3 conditional nodes
- `nodes/core/conditional.yaml` - Updated definition + 4 examples

### hiivmind-blueprint (documentation + templates)
- `CLAUDE.md` - Updated YAML Gotchas section
- `templates/workflow.yaml.template` - Updated template comments and generated code
- `lib/workflow/engine.md` - Updated specification and pseudocode
- `lib/workflow/legacy/validation-queries.md` - Updated jq queries
- `commands/hiivmind-blueprint/workflow.yaml` - Updated 2 conditional nodes

### NOT Updated (requires separate migration)
- `hiivmind-corpus/skills/*/workflow.yaml` - ~60+ conditional nodes
- `hiivmind-corpus/commands/hiivmind-corpus/workflow.yaml`

## Options Considered

### Option A: Accept Both Capitalizations (patternProperties) - REJECTED

```json
"patternProperties": {
  "^[Tt]rue$": { "$ref": "..." },
  "^[Ff]alse$": { "$ref": "..." }
}
```

**Rejected because**: Hacky regex pattern matching, allows inconsistent mixed capitalization.

### Option B: Use Semantic Key Names - SELECTED ✓

**Selected because**:
1. Avoids YAML boolean parsing entirely
2. More semantic and clearer intent (`on_true` vs `true`)
3. Consistent with `on_success`/`on_failure` naming in action nodes
4. No quoting needed - natural YAML authoring

### Option C: Keep Current, Enforce Quoted Keys - REJECTED

**Rejected because**: Unintuitive for YAML authors, easy to forget quotes.

## Verification

```bash
LIB_SCHEMA="file:///path/to/hiivmind-blueprint-lib/schema/"
SCHEMA_DIR="/path/to/hiivmind-blueprint-lib/schema"

# Validate schema is valid
check-jsonschema --check-metaschema "$SCHEMA_DIR/node-types.json"

# Validate updated workflow
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  /path/to/hiivmind-blueprint-lib/workflows/core/intent-detection.yaml
```

## Migration Notes

Existing workflows using `true:`/`false:` keys will fail schema validation until migrated. Search pattern:

```bash
grep -r "branches:" --include="workflow.yaml" -A 2 | grep -E "^\s+(true|false):"
```

Replace with:
- `true:` → `on_true:`
- `false:` → `on_false:`


Implementation complete. Here's a summary of the changes:

  Summary

  Changed conditional node branch keys from true/false to on_true/on_false to avoid YAML boolean parsing issues.

  Files Modified

  hiivmind-blueprint-lib (schema + reference implementations):
  - schema/node-types.json - Updated schema to require on_true/on_false keys
  - workflows/core/intent-detection.yaml - Updated 3 conditional nodes
  - nodes/core/conditional.yaml - Updated definition + 4 examples

  hiivmind-blueprint (documentation + templates):
  - CLAUDE.md - Updated YAML Gotchas section
  - templates/workflow.yaml.template - Updated template comments and generated code
  - lib/workflow/engine.md - Updated specification and pseudocode
  - lib/workflow/legacy/validation-queries.md - Updated jq queries
  - commands/hiivmind-blueprint/workflow.yaml - Updated 2 conditional nodes

  Schema Change

  // Before
  "branches": {
    "required": ["true", "false"],
    "properties": {
      "true": { "$ref": "common.json#/$defs/node_reference" },
      "false": { "$ref": "common.json#/$defs/node_reference" }
    }
  }

  // After
  "branches": {
    "required": ["on_true", "on_false"],
    "properties": {
      "on_true": { "$ref": "common.json#/$defs/node_reference" },
      "on_false": { "$ref": "common.json#/$defs/node_reference" }
    }
  }

  Workflow Syntax Change

  # Before (required quoting to avoid YAML boolean parsing)
  branches:
    "true": next_node_a
    "false": next_node_b

  # After (no quoting needed - semantic key names)
  branches:
    on_true: next_node_a
    on_false: next_node_b

  Note: Corpus workflows were not updated per your request. They will need to be updated separately to match the new schema.

✻ Churned for 4m 17s
