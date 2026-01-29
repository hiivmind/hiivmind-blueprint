# Schema Consolidation

All JSON Schema files have been consolidated into `hiivmind-blueprint-lib` as the single source of truth.

## Schema Location

**Repository:** [hiivmind/hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib)

**Path:** `schema/`

## Available Schemas

| Schema | Purpose |
|--------|---------|
| `common.json` | Shared definitions (semver, identifiers, parameters) |
| `workflow.json` | Main workflow.yaml validation |
| `workflow-definitions.json` | Definitions block validation |
| `node-types.json` | Node type definitions (action, conditional, etc.) |
| `consequence-definition.json` | Consequence type catalog validation |
| `precondition-definition.json` | Precondition type catalog validation |
| `intent-mapping.json` | 3VL intent-mapping.yaml validation |
| `logging.json` | Workflow execution log format |
| `logging-config.json` | Plugin logging.yaml configuration |

## Validation Commands

For local development, use `--base-uri` to resolve relative `$ref` paths:

```bash
# Validate a workflow file
check-jsonschema \
  --base-uri "file:///path/to/hiivmind-blueprint-lib/schema/" \
  --schemafile /path/to/hiivmind-blueprint-lib/schema/workflow.json \
  path/to/workflow.yaml

# Validate consequence definitions
check-jsonschema \
  --base-uri "file:///path/to/hiivmind-blueprint-lib/schema/" \
  --schemafile /path/to/hiivmind-blueprint-lib/schema/consequence-definition.json \
  consequences/core/*.yaml

# Validate precondition definitions
check-jsonschema \
  --base-uri "file:///path/to/hiivmind-blueprint-lib/schema/" \
  --schemafile /path/to/hiivmind-blueprint-lib/schema/precondition-definition.json \
  preconditions/core/*.yaml
```

## Schema $id Convention

All schemas use raw GitHub URLs for their `$id`:

```
https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/main/schema/{name}.json
```

This enables:
- Direct fetchability for validators
- Version pinning via branch/tag in URL path (main, v2.0.0, etc.)
- No additional hosting infrastructure needed

## $ref Composition

Schemas use `$ref` to compose shared definitions:

- `common.json#/$defs/semver` - Semantic version pattern
- `common.json#/$defs/identifier` - Lowercase identifiers
- `common.json#/$defs/parameter` - Parameter definition structure
- `node-types.json#/$defs/node` - Polymorphic node definition
- `node-types.json#/$defs/consequence` - Consequence stub
- `node-types.json#/$defs/precondition` - Precondition stub
