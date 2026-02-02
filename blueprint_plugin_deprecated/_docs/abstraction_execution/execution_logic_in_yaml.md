# Migration Plan: Extract Execution Logic to YAML

## Goal

Make workflows self-describing by extracting execution logic from markdown docs to structured YAML in hiivmind-blueprint-lib. Thin loaders become minimal (just load workflow from source).

---

## Background

Node execution pseudocode is duplicated between `engine.md` and `blueprint-lib/nodes/core/*.yaml`. The unique content in engine.md (core loop, state management, dispatch algorithms) should be extracted to YAML files.

---

## Duplication Analysis: engine.md vs blueprint-lib

### Key Finding: Node Execution Pseudocode is DUPLICATED

The `hiivmind-blueprint-lib/nodes/core/*.yaml` files contain:
- `execution.effect` - The same pseudocode algorithms as engine.md
- `fields` - Schema definitions
- `examples` - Usage patterns

**Example - Conditional Node:**

**In engine.md (lines 711-782):**
```
FUNCTION execute_conditional_node(node, types, state):
    IF node.audit AND node.audit.enabled:
        audit_results = { passed: true, total: 0, ... }
        conditions = get_nested_conditions(node.condition)
        FOR index, condition IN enumerate(conditions):
            ...
```

**In nodes/core/conditional.yaml (lines 99-149):**
```yaml
execution:
  effect: |
    if node.audit.enabled:
      audit_results = {
        passed: true,
        total: 0,
        ...
      }
      conditions = get_nested_conditions(node.condition)
      for index, condition in enumerate(conditions):
        ...
```

**Same algorithm, different locations.**

### Duplication Matrix

| Content | engine.md | blueprint-lib Location | Status |
|---------|-----------|------------------------|--------|
| Action node execution | Lines 684-709 | `nodes/core/action.yaml` (execution.effect) | **DUPLICATE** |
| Conditional node execution | Lines 711-782 | `nodes/core/conditional.yaml` (execution.effect) | **DUPLICATE** |
| User prompt execution | Lines 784-849 | `nodes/core/user-prompt.yaml` (execution.effect) | **DUPLICATE** |
| Validation gate execution | Lines 851-880 | `nodes/core/validation-gate.yaml` (execution.effect) | **DUPLICATE** |
| Reference node execution | Lines 881-933 | `nodes/core/reference.yaml` (execution.effect) | **PARTIAL** - local only |
| Type loading protocol | type-loader.md | N/A | **UNIQUE** to lib/workflow |
| Workflow loading protocol | workflow-loader.md | N/A (reference.yaml only has local) | **UNIQUE** to lib/workflow |
| Logging config protocol | logging-config-loader.md | N/A | **UNIQUE** to lib/workflow |
| Core execution loop | Lines 548-580 | N/A | **UNIQUE** to engine.md |
| State structure | Lines 1139-1220 | N/A | **UNIQUE** to engine.md |
| Variable interpolation | Lines 1408-1428 | N/A | **UNIQUE** to engine.md |

### What's UNIQUE in engine.md (not in blueprint-lib)

1. **Core execution loop** - Phase 1/2/3 model
2. **State structure definition** - Full state schema
3. **Variable interpolation** - `${...}` resolution algorithm
4. **Consequence dispatch** - Type-based dispatch algorithm
5. **Precondition evaluation** - Evaluation algorithm
6. **Interface detection** - Claude Code vs Claude.ai
7. **Checkpoint operations** - Save/restore state
8. **Dynamic routing** - `${computed.target}` interpolation in routing

### What's UNIQUE in loader docs

1. **type-loader.md** - Remote type definition fetching protocol
2. **workflow-loader.md** - Remote workflow fetching protocol (extends reference.yaml)
3. **logging-config-loader.md** - 4-tier config resolution

---

## Architectural Decision: Distributed Content Model

### User's Vision (Clarified)

**Goal: Self-Describing Workflows**

Thin loaders should contain ONLY:
- Instructions for loading workflow YAML from remote repo

Everything else is in the workflow YAML and its referenced definitions:
- Execution semantics
- Node type handling
- Type resolution
- State management

**Thin Loader Pattern (MINIMAL):**

```markdown
---
name: my-skill
description: ...
---

# My Skill

> **Workflow:** `hiivmind/hiivmind-blueprint-lib@v2.0.0:workflows/my-skill`
> **Definitions:** `hiivmind/hiivmind-blueprint-lib@v2.0.0`

## Load and Execute

1. Fetch workflow from source
2. Fetch execution semantics from definitions
3. Execute workflow (workflow is self-describing)

No reference to hiivmind-blueprint docs needed.
```

**Workflow YAML Pattern (SELF-DESCRIBING):**

```yaml
workflow:
  id: my-skill
  version: "1.0"
  definitions:
    source: hiivmind/hiivmind-blueprint-lib@v2.0.0
    # This source provides:
    # - execution/traversal.yaml (how to run workflows)
    # - execution/state.yaml (state management)
    # - nodes/core/*.yaml (node type execution)
    # - consequences/core/*.yaml (consequence types)
    # - preconditions/core/*.yaml (precondition types)

  entry_node: start
  nodes:
    # ... workflow definition ...
```

The `definitions.source` bundle provides ALL execution semantics. No external doc references.

### Proposed Structure

```
hiivmind-blueprint-lib/
├── nodes/core/*.yaml           # Node type execution (EXISTS)
│   - action.yaml
│   - conditional.yaml
│   - user-prompt.yaml
│   - reference.yaml (add remote workflow handling)
│   - validation-gate.yaml
│
├── execution/                  # NEW: Core infrastructure
│   ├── traversal.yaml          # Core loop: LOOP → node → dispatch → route
│   ├── state.yaml              # State structure and interpolation
│   ├── consequence-dispatch.yaml  # Type-based consequence execution
│   ├── precondition-dispatch.yaml # Precondition evaluation
│   └── logging.yaml            # Logging resolution and auto-injection
│
├── resolution/                 # NEW: External file resolution
│   ├── type-loader.yaml        # From type-loader.md
│   └── workflow-loader.yaml    # From workflow-loader.md
│
├── consequences/               # EXISTS: Type definitions
├── preconditions/              # EXISTS: Type definitions
├── workflows/                  # EXISTS: Reusable workflows
└── schema/                     # EXISTS: JSON schemas
```

### Content Migration Plan

| Current Location | New Location | Content |
|------------------|--------------|---------|
| engine.md:684-933 (Node execution) | Already in nodes/core/*.yaml | REMOVE from engine.md |
| engine.md:548-580 (Core loop) | execution/traversal.yaml | MOVE |
| engine.md:1139-1510 (State) | execution/state.yaml | MOVE |
| engine.md:936-1056 (Consequence dispatch) | execution/consequence-dispatch.yaml | MOVE |
| engine.md:1059-1131 (Precondition eval) | execution/precondition-dispatch.yaml | MOVE |
| logging-config-loader.md | execution/logging.yaml | MOVE |
| type-loader.md | resolution/type-loader.yaml | MOVE |
| workflow-loader.md | resolution/workflow-loader.yaml | MOVE |

---

## Full Migration Plan

### Phase 1: Create New YAML Files in blueprint-lib

#### 1.1 execution/ directory

**File: execution/traversal.yaml**
Content from engine.md lines 548-623:
- `FUNCTION initialize()`
- `FUNCTION execute()` (main loop)
- `FUNCTION complete()`

**File: execution/state.yaml**
Content from engine.md lines 1134-1576:
- State structure definition
- Field reference
- Variable interpolation (`resolve_path`, `interpolate`)
- Dynamic routing (`resolve_routing_target`)
- Checkpoint operations

**File: execution/consequence-dispatch.yaml**
Content from engine.md lines 936-1056:
- `FUNCTION execute_consequence()`
- Kind handlers: state_mutation, computation, tool_call, composite, side_effect

**File: execution/precondition-dispatch.yaml**
Content from engine.md lines 1059-1131:
- `FUNCTION evaluate_precondition()`
- Type-specific handlers

**File: execution/logging.yaml**
Content from logging-config-loader.md:
- 4-tier hierarchy
- `FUNCTION load_logging_config()`
- `FUNCTION extract_logging_from_runtime()`
- Deep merge, validation, sub-workflow inheritance

#### 1.2 resolution/ directory

**File: resolution/type-loader.yaml**
Content from type-loader.md:
- `FUNCTION load_types()`
- `FUNCTION parse_source()`
- `FUNCTION build_registry()`
- Extension loading

**File: resolution/workflow-loader.yaml**
Content from workflow-loader.md:
- `FUNCTION load_workflow()`
- `FUNCTION parse_workflow_reference()`
- Index format, dependency validation

#### 1.3 Update nodes/core/reference.yaml

Add remote workflow support (currently only local `doc:` references):
- Add `workflow:` field for remote references
- Add execution effect for remote loading

#### 1.4 YAML Format Examples

Based on the existing `nodes/core/*.yaml` pattern, the execution files will follow this structure:

**Example: execution/traversal.yaml**

```yaml
# Workflow Execution Traversal
# Core loop for executing workflow nodes

schema_version: "1.0"
category: execution

execution:
  traversal:
    description:
      brief: Core workflow execution loop
      detail: |
        Executes workflows following a 3-phase model:
        Phase 1: Initialize - Load workflow, types, state
        Phase 2: Execute - Loop through nodes until ending
        Phase 3: Complete - Finalize log, write output
      notes:
        - Single entry point per workflow
        - Node dispatch based on node.type
        - State is shared and mutable

    phases:
      - id: initialize
        effect: |
          FUNCTION initialize(workflow_path, plugin_root, runtime_flags):
              workflow = parse_yaml(read_file(workflow_path))
              types = load_types(workflow.definitions)
              logging_config = load_logging_config(workflow, plugin_root, runtime_flags)

              validate_schema(workflow)
              validate_types_exist(workflow, types)

              state = {
                  workflow_name: workflow.name,
                  current_node: workflow.entry_node,
                  flags: merge(workflow.initial_state.flags, {}),
                  computed: {},
                  user_responses: {},
                  logging: logging_config,
                  node_history: []
              }

              IF logging_config.auto.init:
                  execute_consequence({ type: "init_log", ... }, types, state)

              RETURN { workflow, types, state }

      - id: execute
        effect: |
          FUNCTION execute(workflow, types, state):
              LOOP:
                  node = workflow.nodes[state.current_node]

                  IF state.current_node IN workflow.endings:
                      ending = workflow.endings[state.current_node]
                      RETURN { status: "complete", ending: ending }

                  result = dispatch_node(node, types, state)
                  state.node_history.append({ node_id: state.current_node, outcome: result.outcome })
                  state.current_node = result.next_node

    dispatch:
      effect: |
        FUNCTION dispatch_node(node, types, state):
            SWITCH node.type:
                CASE "action": RETURN execute_action_node(node, types, state)
                CASE "conditional": RETURN execute_conditional_node(node, types, state)
                CASE "user_prompt": RETURN execute_user_prompt_node(node, types, state)
                CASE "reference": RETURN execute_reference_node(node, types, state)
                DEFAULT: THROW "Unknown node type: {node.type}"

    since: "1.0.0"
```

**Example: execution/state.yaml**

```yaml
# Workflow State Management
schema_version: "1.0"
category: execution

execution:
  state:
    description:
      brief: Runtime state structure and variable interpolation

    structure:
      fields:
        - name: workflow_name
          type: string
        - name: current_node
          type: string
        - name: flags
          type: object
          description: Boolean flags (set_flag modifies these)
        - name: computed
          type: object
          description: Store_as results go here
        - name: user_responses
          type: object
          description: Responses from user_prompt nodes

    interpolation:
      effect: |
        FUNCTION interpolate(template, state):
            FOR each match IN template.match_all(/\$\{([^}]+)\}/):
                path = match.group(1)
                value = resolve_path(state, path)
                template = template.replace(match.full, value)
            RETURN template

        FUNCTION resolve_path(state, path):
            parts = path.split(".")
            current = state
            FOR each part IN parts:
                IF current is null: RETURN null
                current = current[part]
            RETURN current

    dynamic_routing:
      effect: |
        FUNCTION resolve_routing_target(target, state):
            IF target.starts_with("${") AND target.ends_with("}"):
                path = target[2:-1]
                RETURN resolve_path(state, path)
            RETURN target

    since: "1.0.0"
```

**Example: resolution/type-loader.yaml**

```yaml
# Type Definition Loader
schema_version: "1.0"
category: resolution

resolution:
  type_loader:
    description:
      brief: Load type definitions from remote GitHub repositories
      notes:
        - Uses raw.githubusercontent.com for fetching
        - Supports version pinning (@v2.0.0)

    source_format:
      pattern: "{owner}/{repo}@{version}"
      examples:
        - "hiivmind/hiivmind-blueprint-lib@v2.0.0"

    loading:
      effect: |
        FUNCTION load_types(definitions_block):
            source = definitions_block.source
            parts = parse_source(source)
            base_url = "https://raw.githubusercontent.com/{parts.owner}/{parts.repo}/{parts.version}/"

            consequences_index = fetch(base_url + "consequences/index.yaml")
            preconditions_index = fetch(base_url + "preconditions/index.yaml")

            registry = build_registry(consequences_index, preconditions_index)

            IF definitions_block.extensions:
                FOR each ext IN definitions_block.extensions:
                    ext_registry = load_types({ source: ext })
                    registry = merge_registry(registry, ext_registry)

            RETURN registry

        FUNCTION parse_source(source):
            match = source.match(/^([^\/]+)\/([^@]+)@(.+)$/)
            RETURN { owner: match[1], repo: match[2], version: match[3] }

    since: "1.0.0"
```

This format:
- Follows the `nodes/core/*.yaml` pattern with `description`, `effect`, `since`
- Uses structured YAML with `effect: |` for pseudocode blocks
- Self-documenting with notes and examples
- Groups related algorithms under semantic keys

### Phase 2: Update lib/workflow Docs to Reference YAML

The lib/workflow docs remain as user-facing reference, but now reference the YAML files as the source of truth for execution logic.

| File | Change |
|------|--------|
| `lib/workflow/engine.md` | KEEP - Update to reference `execution/*.yaml` for algorithms |
| `lib/workflow/type-loader.md` | KEEP - Update to reference `resolution/type-loader.yaml` |
| `lib/workflow/workflow-loader.md` | KEEP - Update to reference `resolution/workflow-loader.yaml` |
| `lib/workflow/logging-config-loader.md` | KEEP - Update to reference `execution/logging.yaml` |

**Example update pattern for engine.md:**

```markdown
## Execution Model

The core execution loop is defined in the authoritative YAML:

> **Source:** `hiivmind/hiivmind-blueprint-lib@v2.0.0:execution/traversal.yaml`

For a concise overview of the algorithm, see the `phases` and `dispatch` sections
in that file.
```

This keeps the docs as helpful user-facing reference while pointing to YAML as the source of truth.

### Phase 3: Update Thin Loaders to Minimal Pattern

The goal is to make thin loaders reference ONLY the remote workflow source, not local docs.

**Pattern for all thin loaders:**

```markdown
---
name: skill-name
description: ...
---

# Skill Name

> **Workflow:** `hiivmind/hiivmind-blueprint-lib@v2.0.0:workflows/skill-name`

## Load and Execute

Load workflow from source. The workflow's `definitions.source` provides all execution semantics.
```

**Files to convert to minimal thin loaders:**

| File | Current State | Change |
|------|---------------|--------|
| `commands/hiivmind-blueprint.md` | Has 30-line embedded algorithm + doc refs | Convert to minimal loader |
| `skills/hiivmind-blueprint-gateway/SKILL.md` | References lib/workflow/engine.md | Convert to minimal loader |
| `skills/hiivmind-blueprint-convert/SKILL.md` | References lib/workflow/engine.md | Convert to minimal loader |
| `skills/hiivmind-blueprint-generate/SKILL.md` | References + copies engine.md | Convert to minimal loader |
| `skills/hiivmind-blueprint-validate/SKILL.md` | References lib/workflow/engine.md | Convert to minimal loader |
| `skills/hiivmind-blueprint-upgrade/SKILL.md` | References + copies engine.md | Convert to minimal loader |
| `skills/hiivmind-blueprint-analyze/SKILL.md` | References lib/workflow/engine.md | Convert to minimal loader |
| `skills/hiivmind-blueprint-init/SKILL.md` | Copies lib/workflow/ files | Convert to minimal loader |
| `templates/gateway-command.md.template` | Has doc references | Update template |
| `templates/thin-loader.md.template` | May have doc refs | Update template |

**CLAUDE.md and docs/ updates:**

These are user-facing documentation, not LLM execution instructions:
- `CLAUDE.md` - Update to describe the new architecture (workflow-centric, not doc-centric)
- `lib/blueprint/patterns/*.md` - Update to reference blueprint-lib YAML instead of deleted docs
- `docs/*.md` - User guides can reference blueprint-lib YAML for technical details

### Phase 4: Create User-Facing Docs (Optional)

If user-facing documentation is still needed:

**docs/workflow-engine-overview.md**
- High-level explanation of workflow execution
- Links to blueprint-lib YAML files for details

### Phase 5: Verification

1. All references point to valid locations
2. Workflow execution still works (thin loaders reference correct files)
3. No broken links in documentation

---

## Files Summary

### To Create in blueprint-lib (7 files)

| File | Content Source | Lines (approx) |
|------|----------------|----------------|
| `execution/traversal.yaml` | engine.md | ~100 |
| `execution/state.yaml` | engine.md | ~450 |
| `execution/consequence-dispatch.yaml` | engine.md | ~130 |
| `execution/precondition-dispatch.yaml` | engine.md | ~80 |
| `execution/logging.yaml` | logging-config-loader.md | ~470 |
| `resolution/type-loader.yaml` | type-loader.md | ~340 |
| `resolution/workflow-loader.yaml` | workflow-loader.md | ~350 |

### To Update in hiivmind-blueprint (4 files)

Update docs to reference new YAML as source of truth:
- `lib/workflow/engine.md` → Reference `execution/*.yaml`
- `lib/workflow/type-loader.md` → Reference `resolution/type-loader.yaml`
- `lib/workflow/workflow-loader.md` → Reference `resolution/workflow-loader.yaml`
- `lib/workflow/logging-config-loader.md` → Reference `execution/logging.yaml`

### To Update Thin Loaders (10 files)

Thin loaders become minimal - just reference the workflow source:
- `commands/hiivmind-blueprint.md`
- `skills/hiivmind-blueprint-*.md` (8 skills)
- `templates/*.template` (2 templates)

### Other Updates

- `CLAUDE.md` - Architecture description
- `lib/blueprint/patterns/*.md` - Technical references

---

## Execution Order

1. **Create execution/ and resolution/ in blueprint-lib** (7 new YAML files)
2. **Update lib/workflow/ docs** to reference new YAML files (4 files)
3. **Update thin loaders to minimal pattern** (10 files)
4. **Update CLAUDE.md and patterns** (documentation)
5. **Verify** - Workflows still execute correctly

