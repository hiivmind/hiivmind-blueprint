# Schema Consolidation Plan

## Goal

Consolidate all JSON Schema files into `hiivmind-blueprint-lib/schema/` as the single source of truth, using `$ref` composition for modular validation.

## Current State

### hiivmind-blueprint (6 schemas scattered)
| File | Purpose | Location |
|------|---------|----------|
| workflow-schema.json | Main workflow validation (v2.1) | lib/schema/ |
| intent-mapping-schema.json | 3VL intent routing | lib/schema/ |
| logging-schema.json | Execution log format | lib/schema/ |
| logging-config-schema.json | Plugin logging config (v1.3) | lib/schema/ |
| consequence-definition.json | Type catalog (v1.1) | lib/consequences/schema/ |
| precondition-definition.json | Type catalog (v1.0) | lib/preconditions/schema/ |

### hiivmind-blueprint-lib (3 schemas)
| File | Purpose | Location |
|------|---------|----------|
| workflow-definitions.json | Validates `definitions` block only | schema/ |
| consequence-definition.json | DUPLICATE | consequences/schema/ |
| precondition-definition.json | DUPLICATE | preconditions/schema/ |

## Target Structure

```
hiivmind-blueprint-lib/schema/
├── common.json                    # NEW: Shared definitions (semver, identifiers, parameters)
├── workflow.json                  # Main workflow schema (from blueprint)
├── workflow-definitions.json      # Keep existing
├── node-types.json                # NEW: Extract from workflow.json for reuse
├── consequence-definition.json    # Move from consequences/schema/
├── precondition-definition.json   # Move from preconditions/schema/
├── logging.json                   # Move from blueprint
├── logging-config.json            # Move from blueprint
└── intent-mapping.json            # Move from blueprint
```

## Schema $id Convention

All schemas use raw GitHub URLs:
```
https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/{name}.json
```

This provides:
- Direct fetchability for validators
- Version via branch/tag in URL path (main, v2.0.0, etc.)
- No additional hosting infrastructure needed

For version-pinned validation:
```
https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/schema/workflow.json
```

## $ref Composition Design

### common.json (NEW)
Shared definitions used by multiple schemas:
- `semver`: `^\d+\.\d+\.\d+$`
- `semver_short`: `^\d+\.\d+$`
- `identifier`: `^[a-z][a-z0-9_]*$`
- `node_reference`: string (node or ending ID)
- `parameter`: shared parameter object structure

### workflow.json
Refactor to use `$ref`:
```json
{
  "$id": "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/workflow.json",
  "properties": {
    "version": { "$ref": "common.json#/$defs/semver" },
    "definitions": { "$ref": "workflow-definitions.json" },
    "nodes": { "additionalProperties": { "$ref": "node-types.json#/$defs/node" } }
  }
}
```

Note: Relative `$ref` paths work because check-jsonschema resolves them relative to the schema file location.

### node-types.json (NEW)
Extract node type definitions from workflow.json:
- `action_node`, `conditional_node`, `user_prompt_node`, `validation_gate_node`, `reference_node`
- Reusable by other tools validating individual nodes

### Precondition/Consequence Stubs
Keep current "structure-only" validation pattern:
```json
"precondition": {
  "type": "object",
  "required": ["type"],
  "properties": { "type": { "$ref": "common.json#/$defs/identifier" } },
  "additionalProperties": true
}
```
Runtime validates type exists in loaded definitions.

## Implementation Steps

### Phase 1: Create common.json
1. Create `hiivmind-blueprint-lib/schema/common.json`
2. Define shared `$defs`: semver, identifier, parameter
3. Validate with `check-jsonschema --check-metaschema`

### Phase 2: Move Type Definition Schemas
1. Move `consequences/schema/consequence-definition.json` → `schema/consequence-definition.json`
2. Move `preconditions/schema/precondition-definition.json` → `schema/precondition-definition.json`
3. Update `$id` URIs
4. Add `$ref` to `common.json#/$defs/parameter`
5. Delete old locations

### Phase 3: Create node-types.json
1. Extract node type `$defs` from workflow-schema.json
2. Create `schema/node-types.json`
3. Define the 5 node types with polymorphic if/then

### Phase 4: Migrate workflow.json
1. Copy `workflow-schema.json` from blueprint → lib as `schema/workflow.json`
2. Replace inline `$defs` with `$ref` to:
   - `common.json#/$defs/semver`
   - `workflow-definitions.json`
   - `node-types.json#/$defs/node`
3. Update `$id`
4. Test with `check-jsonschema`

### Phase 5: Move Remaining Schemas
1. Move from blueprint to lib:
   - `intent-mapping-schema.json` → `schema/intent-mapping.json`
   - `logging-schema.json` → `schema/logging.json`
   - `logging-config-schema.json` → `schema/logging-config.json`
2. Update `$id` URIs

### Phase 6: Update blueprint References
1. Delete `lib/schema/*.json` from blueprint
2. Create `lib/schema/README.md` pointing to lib
3. Update CLAUDE.md validation commands
4. Update any skills referencing old paths

## Files to Modify

### hiivmind-blueprint-lib (create/modify)
- `schema/common.json` (CREATE)
- `schema/node-types.json` (CREATE)
- `schema/workflow.json` (CREATE - migrated from blueprint)
- `schema/workflow-definitions.json` (MODIFY - add $ref to common.json)
- `schema/consequence-definition.json` (MOVE from consequences/schema/)
- `schema/precondition-definition.json` (MOVE from preconditions/schema/)
- `schema/logging.json` (CREATE - migrated from blueprint)
- `schema/logging-config.json` (CREATE - migrated from blueprint)
- `schema/intent-mapping.json` (CREATE - migrated from blueprint)

### hiivmind-blueprint (delete/update)
- `lib/schema/workflow-schema.json` (DELETE)
- `lib/schema/intent-mapping-schema.json` (DELETE)
- `lib/schema/logging-schema.json` (DELETE)
- `lib/schema/logging-config-schema.json` (DELETE)
- `lib/consequences/schema/consequence-definition.json` (DELETE)
- `lib/preconditions/schema/precondition-definition.json` (DELETE)
- `lib/schema/README.md` (CREATE - pointer to lib)
- `CLAUDE.md` (UPDATE - validation command paths)

## Verification

After each phase:
```bash
# Validate schema is valid JSON Schema
check-jsonschema --check-metaschema schema/*.json

# Validate existing YAML files still pass
check-jsonschema --schemafile schema/workflow.json \
  ../hiivmind-blueprint/commands/hiivmind-blueprint/workflow.yaml

check-jsonschema --schemafile schema/consequence-definition.json \
  consequences/core/*.yaml

check-jsonschema --schemafile schema/precondition-definition.json \
  preconditions/core/*.yaml
```

## check-jsonschema $ref Support

Confirmed: `check-jsonschema` resolves `$ref` automatically:
- Local relative refs: `"$ref": "common.json#/$defs/semver"` works
- Remote refs: Will fetch and cache from URLs
- The schema file location is used as base URI for resolution

## Open Questions Resolved

| Question | Answer |
|----------|--------|
| Which schemas go where? | All to lib - they're all reusable patterns |
| How to reference components? | `$ref` to relative files within lib/schema/ |
| What $id URIs? | Raw GitHub URLs: `https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/{name}.json` |
| Handle "any type valid"? | Keep stub pattern with `additionalProperties: true` |
| Separate node-types schema? | Yes - enables reuse and cleaner composition |


All tasks completed. Here's a summary of what was implemented:

  Schema Consolidation Complete

  Created in hiivmind-blueprint-lib/schema/
  ┌──────────────────────────────┬──────────────────────────────────────────────────────────┬─────────────────────────────────────────────────────────┐
  │            Schema            │                         Purpose                          │                      Uses $ref to                       │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ common.json                  │ Shared definitions (semver, identifier, parameter, etc.) │ -                                                       │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ workflow.json                │ Main workflow.yaml validation                            │ common.json, node-types.json, workflow-definitions.json │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ workflow-definitions.json    │ Definitions block                                        │ common.json                                             │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ node-types.json              │ Node type definitions (action, conditional, etc.)        │ common.json                                             │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ consequence-definition.json  │ Consequence YAML files                                   │ common.json                                             │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ precondition-definition.json │ Precondition YAML files                                  │ common.json                                             │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ intent-mapping.json          │ 3VL intent-mapping.yaml                                  │ common.json                                             │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ logging.json                 │ Workflow execution logs                                  │ common.json                                             │
  ├──────────────────────────────┼──────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┤
  │ logging-config.json          │ Plugin logging.yaml                                      │ -                                                       │
  └──────────────────────────────┴──────────────────────────────────────────────────────────┴─────────────────────────────────────────────────────────┘
  Removed from hiivmind-blueprint

  - lib/schema/workflow-schema.json
  - lib/schema/intent-mapping-schema.json
  - lib/schema/logging-schema.json
  - lib/schema/logging-config-schema.json
  - lib/consequences/schema/ directory
  - lib/preconditions/schema/ directory

  Updated

  - lib/schema/README.md - Created pointer to lib schemas
  - CLAUDE.md - Updated architecture diagram and validation commands

  Validation

  All schemas pass --check-metaschema validation. For local validation with $ref resolution, use:

  check-jsonschema \
    --base-uri "file:///path/to/hiivmind-blueprint-lib/schema/" \
    --schemafile /path/to/hiivmind-blueprint-lib/schema/workflow.json \
    path/to/workflow.yaml

✻ Cooked for 8m 26s
