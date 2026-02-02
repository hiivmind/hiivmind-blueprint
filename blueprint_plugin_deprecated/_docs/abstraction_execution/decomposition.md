# Framework Decomposition: Hybrid Approach

## Goal

Simplify `lib/workflow/` by:
1. Archiving redundant docs (prose that duplicates YAML type definitions)
2. Merging overlapping execution docs into engine.md
3. Converting validation logic to a workflow with new consequence types
4. Maintaining backward compatibility via legacy/ archive

---

## Current State: lib/workflow/ Inventory

| File | Content Type | Lines |
|------|--------------|-------|
| `engine.md` | **Procedural** - Abstract executor pattern | ~770 |
| `type-loader.md` | **Procedural** - Type loading protocol | ~628 |
| `execution.md` | **Procedural** - Detailed execution semantics | ~665 |
| `schema.md` | **Reference** - YAML workflow schema | ~505 |
| `state.md` | **Reference** - Runtime state structure | ~560 |
| `preconditions.md` | **Reference** - Precondition catalog | ~687 |
| `validation-queries.md` | **Patterns** - yq validation queries | ~804 |
| `validation-report-format.md` | **Reference** - Report format spec | ~438 |
| `logging-schema.md` | **Reference** - Log structure definition | ~450 |
| `consequences/README.md` | **Reference** - Consequence catalog | ~357 |
| `consequences/core/*.md` | **Reference** - Core type docs | 4 files |
| `consequences/extensions/*.md` | **Reference** - Extension type docs | 4 files |

---

## Analysis: What's Required vs Redundant

### Essential Framework (Required by Engine)

| Document | Why Essential |
|----------|---------------|
| `engine.md` | Core execution pattern - LLM interprets this |
| `type-loader.md` | How to resolve external type definitions |
| `schema.md` | Authoritative YAML structure reference |
| `state.md` | State structure that engine maintains |

### Redundant (Duplicates Type Definitions)

| Document | Why Redundant |
|----------|---------------|
| `preconditions.md` | YAML definitions in `lib/preconditions/definitions/` are authoritative |
| `consequences/README.md` | YAML definitions in `lib/consequences/definitions/` are authoritative |
| `consequences/core/*.md` | Human-readable duplicates of YAML definitions |
| `consequences/extensions/*.md` | Human-readable duplicates of YAML definitions |

### Overlapping (Merge Candidate)

| Document | Overlap With |
|----------|--------------|
| `execution.md` | `engine.md` - Both describe execution semantics |

### Convertible to Types/Workflows

| Document | Can Become |
|----------|------------|
| `validation-queries.md` | `validate_workflow` consequence + workflow |
| `validation-report-format.md` | Part of validation workflow |
| `logging-schema.md` | Logging consequences already exist |

---

## Proposed Minimal Framework

### Tier 1: Core Engine (Required)

```
lib/workflow/
├── engine.md           # Abstract execution pattern
├── type-loader.md      # Type definition loading
├── schema.md           # Workflow YAML schema
└── state.md            # Runtime state structure
```

These 4 files are the **essential framework**. Everything else is either:
- Redundant (types now define themselves)
- Convertible to workflows/types
- Optional tooling

### Tier 2: Convertible to Workflows

```yaml
# validation-queries.md + validation-report-format.md → workflow

skills/hiivmind-blueprint-validate/
├── SKILL.md
└── workflow.yaml       # Uses: validate_schema, validate_references, etc.
```

The validation logic becomes a **self-contained workflow** using consequence types:
- `validate_schema` - JSON Schema validation
- `validate_references` - Check node transitions
- `validate_types` - Verify types exist
- `generate_report` - Format validation output

### Tier 3: Redundant (Mark as Legacy or Remove)

| Document | Action |
|----------|--------|
| `preconditions.md` | Redirect to `lib/preconditions/definitions/index.yaml` |
| `consequences/README.md` | Redirect to `lib/consequences/definitions/index.yaml` |
| `consequences/core/*.md` | Archive or delete (YAML is authoritative) |
| `consequences/extensions/*.md` | Archive or delete (YAML is authoritative) |
| `execution.md` | Merge unique content into `engine.md`, then deprecate |

### Tier 4: Optional (Not Required for Execution)

| Document | Status |
|----------|--------|
| `logging-schema.md` | Useful reference but logging consequences are self-describing |

---

## Key Insight: Self-Describing Types

The type definitions (YAML) are **self-describing** with:
- `payload.effect` - Pseudocode for execution
- `parameters` - Schema for inputs
- `examples` - Usage patterns
- `since` - Version tracking

This means prose documentation (preconditions.md, consequences/README.md) is **redundant**. The LLM reads the YAML definitions directly.

---

## Target Structure

After cleanup, `lib/workflow/` will have:

```
lib/workflow/
├── engine.md           # Single execution reference (merged from execution.md)
├── type-loader.md      # Type loading protocol
├── schema.md           # Workflow YAML schema
├── state.md            # Runtime state structure
└── legacy/             # Archived redundant docs
    ├── execution.md    # Redirect stub → engine.md
    ├── preconditions.md
    ├── validation-queries.md
    ├── validation-report-format.md
    ├── logging-schema.md
    └── consequences/
        ├── README.md
        ├── core/
        └── extensions/
```

---

## New Consequence Types for Validation

To fully convert `validation-queries.md` to a workflow, add these consequences:

| Type | Category | Purpose |
|------|----------|---------|
| `validate_yaml_schema` | core/validation | JSON Schema validation |
| `validate_node_references` | core/validation | Check all transitions exist |
| `validate_type_existence` | core/validation | Verify types in registry |
| `check_graph_connectivity` | core/validation | Reachable from start_node |
| `detect_dead_ends` | core/validation | Find nodes with no exit |
| `format_validation_report` | core/interaction | Generate report output |

And preconditions:

| Type | Category | Purpose |
|------|----------|---------|
| `schema_valid` | core/validation | Schema check passed |
| `references_valid` | core/validation | All transitions valid |
| `types_exist` | core/validation | All types defined |
| `graph_connected` | core/validation | No orphan nodes |

---

## Thin Loader Dependencies (Answer to Original Question)

**Q: Does the thin loader imply only engine.md and type-loader.md are needed?**

**A: Yes, with caveats.**

For **skill execution**, the minimal dependencies are:

```
SKILL.md (thin loader)
    ↓ reads
workflow.yaml
    ↓ references
engine.md (execution pattern)
    ↓ uses
type-loader.md (resolves types)
    ↓ loads
bundle.yaml (type definitions - external or embedded)
```

The **schema.md** and **state.md** are needed by:
- The engine.md (it references them for state structure and schema details)
- Workflow authors (for understanding the YAML format)

So the **true minimal set** for execution is:
1. `engine.md` (references schema.md, state.md internally)
2. `type-loader.md`
3. External types (or lib/types/bundle.yaml)

The **schema.md** and **state.md** could even be merged into engine.md if desired, making it a single authoritative document.

---

---

## Implementation Plan

### Phase 1: Create Legacy Directory & Archive Redundant Docs

**Files to move to `lib/workflow/legacy/`:**

| Source | Destination | Reason |
|--------|-------------|--------|
| `preconditions.md` | `legacy/preconditions.md` | YAML definitions authoritative |
| `consequences/README.md` | `legacy/consequences/README.md` | YAML definitions authoritative |
| `consequences/core/*.md` | `legacy/consequences/core/` | YAML definitions authoritative |
| `consequences/extensions/*.md` | `legacy/consequences/extensions/` | YAML definitions authoritative |
| `validation-queries.md` | `legacy/validation-queries.md` | Will become workflow |
| `validation-report-format.md` | `legacy/validation-report-format.md` | Will become workflow |
| `logging-schema.md` | `legacy/logging-schema.md` | Logging types self-describe |

**Add deprecation header to each archived file:**
```markdown
> **ARCHIVED:** This document is preserved for reference. The authoritative sources are:
> - Type definitions: `lib/consequences/definitions/` and `lib/preconditions/definitions/`
> - Execution: `lib/workflow/engine.md`
```

### Phase 2: Merge execution.md into engine.md

**Unique content in execution.md to merge:**
- Detailed trace mode example (line ~586-617) - add to engine.md Debugging section
- SKILL.md Template section (line ~482-575) - already covered by templates/

**After merge:** Replace execution.md with redirect stub:
```markdown
# Workflow Execution

> **Moved:** This document has been consolidated into `engine.md`.
> See `lib/workflow/engine.md` for complete execution semantics.
```

### Phase 3: Add Validation Consequence Types

**Create:** `lib/consequences/definitions/extensions/validation.yaml`

```yaml
consequences:
  - type: validate_yaml_schema
    description:
      brief: Validate workflow against JSON Schema
    parameters:
      - name: workflow_path
        type: string
        required: true
      - name: schema_path
        type: string
        required: true
      - name: store_as
        type: string
        required: true
    payload:
      kind: tool_call
      tool: Bash
      effect: "yq validate ${workflow_path} ${schema_path}"

  - type: validate_node_references
    description:
      brief: Check all node transitions point to valid targets
    # ... (full definition)

  - type: format_validation_report
    description:
      brief: Generate formatted validation output
    # ... (full definition)
```

**Add corresponding preconditions to:** `lib/preconditions/definitions/extensions/validation.yaml`

### Phase 4: Update Thin Loader Template

**Edit:** `templates/skill-with-executor.md.template`

Remove type-loader.md from Resources table (it's internal to engine.md):

```markdown
## Resources

| Resource | Path |
|----------|------|
| **Workflow** | `${CLAUDE_PLUGIN_ROOT}/skills/{{skill_directory}}/workflow.yaml` |
| **Engine** | `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md` |
```

### Phase 5: Update CLAUDE.md Architecture

Update the architecture diagram to reflect new structure.

---

## Files to Modify/Create

| Action | File |
|--------|------|
| CREATE | `lib/workflow/legacy/` directory |
| MOVE | 10+ files to legacy/ |
| EDIT | `lib/workflow/engine.md` - add trace mode section |
| EDIT | `lib/workflow/execution.md` - replace with redirect |
| CREATE | `lib/consequences/definitions/extensions/validation.yaml` |
| CREATE | `lib/preconditions/definitions/extensions/validation.yaml` |
| EDIT | `lib/types/bundle.yaml` - add validation types |
| EDIT | `templates/skill-with-executor.md.template` |
| EDIT | `CLAUDE.md` - update architecture diagram |

---

## Verification

1. **Archive integrity** - All legacy files accessible with deprecation headers
2. **Engine completeness** - Verify engine.md has all execution semantics
3. **Type self-documentation** - Read a consequence YAML definition, verify it's sufficient without prose docs
4. **Thin loader test** - Execute a workflow referencing only engine.md
