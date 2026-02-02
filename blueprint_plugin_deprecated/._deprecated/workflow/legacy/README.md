# Legacy Documentation Archive

> **ARCHIVED:** These documents are preserved for reference. The authoritative sources are now:
> - **Type definitions:** `lib/consequences/definitions/` and `lib/preconditions/definitions/`
> - **Execution engine:** `lib/workflow/engine.md` (comprehensive reference)
> - **Type loader:** `lib/workflow/type-loader.md`

## Why These Files Are Archived

The hiivmind-blueprint framework has evolved to use **self-describing YAML type definitions**. These definitions include:
- Execution semantics (`payload.effect`)
- Parameters with types and constraints
- Examples for multi-shot prompting
- Version tracking (`since`)

This means prose documentation that merely duplicates YAML definitions is **redundant**. The LLM reads YAML definitions directly.

## What's Here

### Merged into engine.md

| File | Original Purpose | New Location |
|------|------------------|--------------|
| `execution.md` | Detailed execution semantics | `lib/workflow/engine.md` |
| `schema.md` | YAML workflow structure | `lib/workflow/engine.md` "Workflow Schema" section |
| `state.md` | Runtime state structure | `lib/workflow/engine.md` "State Management" section |

### Redundant Documentation

| File | Original Purpose | Authoritative Source |
|------|------------------|---------------------|
| `preconditions.md` | Precondition catalog | `lib/preconditions/definitions/index.yaml` |
| `consequences/README.md` | Consequence taxonomy | `lib/consequences/definitions/index.yaml` |
| `consequences/core/*.md` | Core consequence docs | `lib/consequences/definitions/core/*.yaml` |
| `consequences/extensions/*.md` | Extension consequence docs | `lib/consequences/definitions/extensions/*.yaml` |

### Convertible to Workflows

| File | Status |
|------|--------|
| `validation-queries.md` | Will become validation workflow |
| `validation-report-format.md` | Part of validation workflow |

### Extracted to Schema

| File | Extracted To |
|------|--------------|
| `logging-schema.md` | `lib/schema/logging-schema.json` |

## Using This Archive

These files remain accessible for:
- Historical reference
- Understanding design rationale
- Migration guidance

For current documentation, see:
- `lib/workflow/engine.md` - Complete execution reference
- `lib/workflow/type-loader.md` - Type loading protocol
- `lib/consequences/definitions/` - YAML consequence definitions
- `lib/preconditions/definitions/` - YAML precondition definitions
