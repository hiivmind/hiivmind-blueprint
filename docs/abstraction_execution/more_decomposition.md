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
| `engine.md` | Core execution pattern - LLM interprets this (will include schema + state) |
| `type-loader.md` | How to resolve external type definitions |

**Merged into engine.md:**

| Document | Content Merged |
|----------|----------------|
| `schema.md` | Authoritative YAML structure reference → engine.md "Workflow Schema" section |
| `state.md` | State structure that engine maintains → engine.md "State Management" section |
| `execution.md` | Detailed execution semantics → engine.md execution sections |

### Redundant (Duplicates Type Definitions)

| Document | Why Redundant |
|----------|---------------|
| `preconditions.md` | YAML definitions in `lib/preconditions/definitions/` are authoritative |
| `consequences/README.md` | YAML definitions in `lib/consequences/definitions/` are authoritative |
| `consequences/core/*.md` | Human-readable duplicates of YAML definitions |
| `consequences/extensions/*.md` | Human-readable duplicates of YAML definitions |

### Overlapping (Merge into engine.md)

| Document | Content | Merge Target |
|----------|---------|--------------|
| `execution.md` | Detailed execution semantics | engine.md execution sections |
| `schema.md` | YAML workflow structure | engine.md "Workflow Schema" section |
| `state.md` | Runtime state structure | engine.md "State Management" section |

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
├── engine.md           # Single comprehensive execution reference
└── type-loader.md      # Type definition loading
```

These 2 files are the **essential framework**. Everything else is either:
- Merged into engine.md (schema.md, state.md, execution.md)
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

### Tier 4: Extract & Archive

| Document | Action |
|----------|--------|
| `logging-schema.md` | Extract JSON Schema to `lib/schema/logging-schema.json`, then archive prose to `legacy/` |

The log structure will be formally defined in JSON Schema and referenced by logging consequences.

---

## Key Insight: Self-Describing Types

The type definitions (YAML) are **self-describing** with:
- `payload.effect` - Pseudocode for execution
- `parameters` - Schema for inputs
- `examples` - Usage patterns
- `since` - Version tracking

This means prose documentation (preconditions.md, consequences/README.md) is **redundant**. The LLM reads the YAML definitions directly.

---

## Node Types → hiivmind-blueprint-types

Node types should also be externalized to hiivmind-blueprint-types for consistency.

**Current structure:**
```
hiivmind-blueprint-types/
├── consequences/definitions/
├── preconditions/definitions/
└── bundle.yaml
```

**Proposed structure:**
```
hiivmind-blueprint-types/
├── consequences/definitions/
├── preconditions/definitions/
├── nodes/definitions/              # NEW
│   ├── index.yaml                  # Registry of node types
│   └── core/
│       ├── action.yaml             # action node type
│       ├── conditional.yaml        # conditional node type
│       ├── user-prompt.yaml        # user_prompt node type
│       ├── validation-gate.yaml    # validation_gate node type
│       └── reference.yaml          # reference node type
└── bundle.yaml                     # Updated to include node types
```

**Node type definition format:**
```yaml
# nodes/definitions/core/action.yaml
nodes:
  - type: action
    description:
      brief: Executes operations and routes based on success/failure
      detail: |
        An action node executes a sequence of consequences. All actions
        must succeed for on_success routing; any failure triggers on_failure.
    since: "1.0.0"
    fields:
      - name: type
        type: string
        required: true
        value: "action"
      - name: description
        type: string
        required: false
        description: Human-readable purpose
      - name: actions
        type: array
        items: consequence
        required: true
        description: Array of consequence objects to execute
      - name: on_success
        type: node_reference
        required: true
        description: Node or ending to route to on success
      - name: on_failure
        type: node_reference
        required: true
        description: Node or ending to route to on failure
    execution:
      effect: |
        for action in node.actions:
          result = dispatch_consequence(action, state)
          if result.failed:
            return route_to(node.on_failure)
        return route_to(node.on_success)
    examples:
      - name: Basic action chain
        yaml: |
          my_action:
            type: action
            actions:
              - type: read_file
                path: "config.yaml"
                store_as: config
              - type: set_flag
                flag: config_loaded
                value: true
            on_success: next_step
            on_failure: error_handler
```

**Benefits:**
1. **Versioned node types**: Node type definitions can evolve independently
2. **Extensible**: Custom node types can be added as extensions
3. **Self-describing**: LLM reads node type definitions directly
4. **Consistent**: Same pattern as consequences and preconditions

---

## Target Structure

After cleanup, `lib/workflow/` will have:

```
lib/workflow/
├── engine.md           # Single comprehensive reference (merged from execution.md, schema.md, state.md)
├── type-loader.md      # Type loading protocol
└── legacy/             # Archived redundant docs
    ├── execution.md    # Redirect stub → engine.md
    ├── schema.md       # Redirect stub → engine.md
    ├── state.md        # Redirect stub → engine.md
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

**A: Yes.**

For **skill execution**, the minimal dependencies are:

```
SKILL.md (thin loader)
    ↓ reads
workflow.yaml
    ↓ references
engine.md (execution pattern + schema + state)
    ↓ uses
type-loader.md (resolves types)
    ↓ loads
bundle.yaml (type definitions - external or embedded)
```

The **true minimal set** for execution is:
1. `engine.md` (comprehensive: execution + schema + state)
2. `type-loader.md`
3. External types (or lib/types/bundle.yaml)

By merging schema.md and state.md into engine.md, we create a single authoritative document that contains everything needed to execute workflows.

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
| `logging-schema.md` | `legacy/logging-schema.md` | Extract JSON Schema first, then archive |

**Add deprecation header to each archived file:**
```markdown
> **ARCHIVED:** This document is preserved for reference. The authoritative sources are:
> - Type definitions: `lib/consequences/definitions/` and `lib/preconditions/definitions/`
> - Execution: `lib/workflow/engine.md`
```

### Phase 2: Merge execution.md, schema.md, and state.md into engine.md

**Documents to merge into engine.md:**

| Document | Content to Merge | Location in engine.md |
|----------|------------------|----------------------|
| `execution.md` | Trace mode example (line ~586-617) | Debugging section |
| `schema.md` | YAML workflow structure (node types, fields) | New "Workflow Schema" section |
| `state.md` | Runtime state structure (phases, flags, computed) | New "State Management" section |

**Already covered (skip):**
- execution.md SKILL.md Template section → covered by templates/

**After merge:** Replace each file with redirect stub:
```markdown
# [Original Title]

> **ARCHIVED:** This document has been consolidated into `engine.md`.
> See `lib/workflow/engine.md` for the complete reference.
```

**engine.md new structure:**
```
1. Overview
2. Architecture
3. Type Loading (references type-loader.md)
   - How to load node types, consequences, preconditions from external definitions
   - Bundle resolution
4. Node Dispatch
   - How to process each node type (references external node type definitions)
   - Variable interpolation
5. State Management
   - Runtime state structure (phases, flags, computed)
   - State isolation for nested skills
6. Execution Model
   - Three-phase execution (initialize → loop → completion)
   - Consequence dispatch
7. Error Handling
8. Debugging (includes execution.md trace mode)
```

**Key change:** engine.md will reference external type definitions rather than embedding the full schema. The LLM reads:
1. engine.md (how to execute)
2. Node type YAML definitions (what each node type is)
3. Consequence/precondition YAML definitions (what each type does)

### Phase 3: Extract Logging JSON Schema

**Create:** `lib/schema/logging-schema.json`

Extract the log structure from `logging-schema.md` into a formal JSON Schema:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://hiivmind.dev/schemas/logging-schema.json",
  "title": "Workflow Execution Log",
  "type": "object",
  "properties": {
    "metadata": {
      "type": "object",
      "properties": {
        "workflow_name": { "type": "string" },
        "workflow_version": { "type": "string" },
        "skill_name": { "type": ["string", "null"] },
        "plugin_name": { "type": ["string", "null"] },
        "execution_path": { "type": "string" },
        "session": { "$ref": "#/$defs/session" }
      },
      "required": ["workflow_name", "workflow_version", "execution_path"]
    },
    "execution": { "$ref": "#/$defs/execution" },
    "node_history": { "type": "array", "items": { "$ref": "#/$defs/nodeEntry" } },
    "events": { "type": "array", "items": { "$ref": "#/$defs/event" } },
    "warnings": { "type": "array", "items": { "$ref": "#/$defs/warning" } },
    "errors": { "type": "array", "items": { "$ref": "#/$defs/error" } },
    "summary": { "type": ["string", "null"] }
  },
  "$defs": {
    // ... definitions for session, execution, nodeEntry, event, warning, error
  }
}
```

This schema can be referenced by logging consequences for validation.

### Phase 4: Create Node Type Definitions in hiivmind-blueprint-types

**Repository:** `/home/nathanielramm/git/hiivmind/hiivmind-blueprint-types`

**Files to create:**

| File | Content |
|------|---------|
| `nodes/definitions/index.yaml` | Registry of 5 node types |
| `nodes/definitions/core/action.yaml` | action node definition |
| `nodes/definitions/core/conditional.yaml` | conditional node definition |
| `nodes/definitions/core/user-prompt.yaml` | user_prompt node definition |
| `nodes/definitions/core/validation-gate.yaml` | validation_gate node definition |
| `nodes/definitions/core/reference.yaml` | reference node definition |

**Update existing files:**

| File | Change |
|------|--------|
| `bundle.yaml` | Add node type definitions |
| `package.yaml` | Update stats, add nodes section |

**Node type definition follows consequence pattern:**
- `type` - Node type identifier
- `description.brief` + `description.detail` - Documentation
- `fields` - Required and optional fields with types
- `execution.effect` - Pseudocode for engine execution
- `examples` - Usage examples

### Phase 5: Add Validation Consequence Types

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

### Phase 6: Update Thin Loader Template

**Edit:** `templates/skill-with-executor.md.template`

Remove type-loader.md from Resources table (it's internal to engine.md):

```markdown
## Resources

| Resource | Path |
|----------|------|
| **Workflow** | `${CLAUDE_PLUGIN_ROOT}/skills/{{skill_directory}}/workflow.yaml` |
| **Engine** | `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md` |
```

### Phase 7: Update CLAUDE.md Architecture

Update the architecture diagram to reflect new structure.

---

## Files to Modify/Create

### In hiivmind-blueprint (this repo)

| Action | File |
|--------|------|
| CREATE | `lib/workflow/legacy/` directory |
| MOVE | 13 files to legacy/ (see Phase 1 + schema.md, state.md, execution.md) |
| CREATE | `lib/schema/logging-schema.json` - extracted from logging-schema.md |
| EDIT | `lib/workflow/engine.md` - merge schema.md, state.md, execution.md content |
| EDIT | `lib/workflow/execution.md` - replace with redirect stub |
| EDIT | `lib/workflow/schema.md` - replace with redirect stub |
| EDIT | `lib/workflow/state.md` - replace with redirect stub |
| CREATE | `lib/consequences/definitions/extensions/validation.yaml` |
| CREATE | `lib/preconditions/definitions/extensions/validation.yaml` |
| EDIT | `lib/types/bundle.yaml` - add validation types + node types |
| EDIT | `templates/skill-with-executor.md.template` - reference only engine.md |
| EDIT | `CLAUDE.md` - update architecture diagram |

### In hiivmind-blueprint-types (separate repo)

| Action | File |
|--------|------|
| CREATE | `nodes/definitions/index.yaml` |
| CREATE | `nodes/definitions/core/action.yaml` |
| CREATE | `nodes/definitions/core/conditional.yaml` |
| CREATE | `nodes/definitions/core/user-prompt.yaml` |
| CREATE | `nodes/definitions/core/validation-gate.yaml` |
| CREATE | `nodes/definitions/core/reference.yaml` |
| EDIT | `bundle.yaml` - add node type definitions |
| EDIT | `package.yaml` - update stats, add nodes section |

---

## Verification

1. **Archive integrity** - All legacy files accessible with deprecation headers
2. **Engine completeness** - Verify engine.md contains:
   - Execution semantics from execution.md
   - References to external node type definitions
   - References to external consequence/precondition definitions
3. **Type self-documentation** - Read each YAML type definition:
   - Consequence: Can execute without prose docs? ✓
   - Precondition: Can evaluate without prose docs? ✓
   - Node type: Can dispatch without schema.md/state.md? ✓
4. **Thin loader test** - Execute a workflow referencing only engine.md
5. **No broken references** - Search for links to schema.md/state.md/execution.md, verify redirects work
6. **Node types in bundle** - Verify bundle.yaml includes all 5 node types from hiivmind-blueprint-types
7. **Cross-repo consistency** - Verify hiivmind-blueprint-types bundle.yaml matches lib/types/bundle.yaml
