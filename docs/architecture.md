# Blueprint Skill Architecture

> **Version:** Post-v6.0.0 refactor (February 2026)
> **Scope:** hiivmind-blueprint + hiivmind-blueprint-lib

---

## Core Philosophy

A **skill** is a prose orchestrator. A **workflow** is a tool that a skill uses.

This is the single idea that governs the entire system. Skills are not "prose skills" or "workflow skills" or "hybrid skills" — they are skills, period. Each one is a `SKILL.md` file that guides Claude through a multi-phase procedure. Some phases are pure prose instructions. Others delegate to structured YAML workflow definitions. The skill decides.

### Why Prose Orchestration?

LLMs are good at following procedures described in natural language. They handle ambiguity, recover from unexpected states, and make judgment calls. Workflow YAML graphs are good at deterministic routing — when you have 8 conditional branches, you don't want the LLM improvising which path to take.

The architecture puts each where it excels:

| Concern | Best Expressed As |
|---------|-------------------|
| "Gather requirements from the user" | Prose |
| "Route through 12 validation checks" | Workflow |
| "Interpret results and suggest next steps" | Prose |
| "Branch on 5 mutually exclusive conditions" | Workflow |
| "Read files, analyze patterns, make judgments" | Prose |
| "Execute a strict FSM with defined transitions" | Workflow |

### The LLM-as-Execution-Engine

Workflows don't run on a traditional engine. The LLM reads the YAML, reads the type definitions (consequence types, precondition types, node types), and interprets the `effect` pseudocode directly. Each type definition includes an `effect` field that tells the LLM what to do:

```yaml
mutate_state:
  payload:
    kind: state_mutation
    effect: |
      if operation == "set":   state[field] = value
      if operation == "append": state[field].push(value)
```

The LLM is the engine. The YAML is the program. The type definitions are the instruction set.

---

## Skill Anatomy

Every skill lives in a directory under `skills/`:

```
skills/my-skill/
├── SKILL.md                    # The orchestrator (always present)
├── workflows/                  # Optional: structured workflow definitions
│   ├── validate.yaml          # One workflow per phase that needs it
│   └── transform.yaml
└── patterns/                   # Optional: heavy reference material
    └── *.md                   # Offloaded from SKILL.md to keep it focused
```

### SKILL.md Structure

```yaml
---
name: my-skill
description: >
  Trigger keywords and description for intent matching...
allowed-tools: Read, Write, Glob, AskUserQuestion
inputs:
  - name: target_path
    type: string
    required: true
    description: Path to the thing being processed
outputs:
  - name: result
    type: object
    description: What this skill produces
workflows:
  - workflows/validate.yaml
  - workflows/transform.yaml
---

# My Skill Title

[Overview — what this skill does]

## Phase 1: Gather
[Prose instructions — tool calls, user prompts, analysis]

## Phase 2: Validate
Execute `workflows/validate.yaml` following the execution guide.

## Phase 3: Transform
Execute `workflows/transform.yaml` following the execution guide.

## Phase 4: Report
[Prose instructions — display results, offer next steps]
```

The frontmatter declares the skill's interface. The body defines the procedure. Each phase is either prose or workflow-backed. The SKILL.md is always the authority on flow.

### Inputs and Outputs

Skills declare their interface in frontmatter:

- **`inputs:`** — What the skill accepts (prompted interactively if not provided)
- **`outputs:`** — What the skill produces (stored in `computed.*` namespace)
- **`workflows:`** — Which workflow files this skill delegates to

This makes skills composable. One skill's output can feed another skill's input. The `computed.analysis` handoff between `bp-skill-analyze` and `bp-workflow-extract` is the canonical example.

---

## Workflow Definitions

A workflow is a directed graph of typed nodes. It lives in `workflows/*.yaml` inside a skill directory.

### Building Blocks

The type system has three categories:

| Category | Count | Purpose |
|----------|-------|---------|
| **Node types** | 3 | Graph structure (action, conditional, user_prompt) |
| **Consequence types** | 22 | Operations that nodes execute |
| **Precondition types** | 9 | Conditions that nodes evaluate |

### Node Types

| Type | What It Does | Routes |
|------|-------------|--------|
| `action` | Executes a list of consequences | `on_success` / `on_failure` |
| `conditional` | Evaluates a precondition | `on_true` / `on_false` |
| `user_prompt` | Presents options to the user | Routes by selected `handler_id` |

Three node types. That's it. Every workflow graph is built from these three primitives.

### Type Definitions

Types are defined in the `hiivmind-blueprint-lib` catalog and deployed locally per repo in `.hiivmind/blueprint/definitions.yaml`. The slimmed-down format keeps only what the LLM needs at execution time:

```yaml
# .hiivmind/blueprint/definitions.yaml
consequences:
  mutate_state:
    description: "Modify workflow state"
    parameters:
      - name: operation
        type: string
        required: true
        enum: [set, append, clear, merge]
    payload:
      kind: state_mutation
      effect: |
        if operation == "set": state[field] = value
```

Catalog metadata (category, since, replaces, related) is stripped at deployment time.

### Execution Model

Workflow execution follows three phases:

1. **Initialize** — Parse definitions, validate types, initialize state, check entry preconditions
2. **Execute** — Main loop: dispatch current node by type, follow transitions, repeat until ending
3. **Complete** — Display ending message and summary

State flows through execution via namespaces:

| Namespace | Purpose |
|-----------|---------|
| `flags.*` | Boolean routing flags |
| `computed.*` | Results from consequences and inter-phase data |
| `user_responses.*` | User selections from prompt nodes |
| `checkpoints.*` | State snapshots for rollback |

---

## Coverage Model

Skills are classified by how much of their execution is formalized into workflows:

| Coverage | Meaning |
|----------|---------|
| **`none`** | All phases are prose. No `workflows/` directory. |
| **`partial`** | Some phases delegate to workflows, others remain prose. |
| **`full`** | All substantive phases delegate to workflow files. |

This replaces the old `prose/workflow/hybrid/simple` taxonomy, which was artificial — it implied skills had to be one thing or another. The coverage model acknowledges that formalization is a spectrum, and skills naturally evolve from `none` → `partial` → `full` as high-complexity prose phases get extracted into workflows.

### When to Extract a Workflow

Not every prose phase benefits from formalization. The extraction scoring system identifies candidates:

| Signal | Score | Rationale |
|--------|-------|-----------|
| 5+ conditional branches | +3 | Deterministic routing prevents LLM drift |
| FSM-like state transitions | +3 | Node graph maps naturally |
| Loop with explicit break condition | +2 | Graph enforces termination |
| Multiple user prompts with branching | +2 | Response handlers route deterministically |
| Validation gate (multiple assertions) | +2 | Audit mode evaluates ALL conditions |
| Linear tool call sequence | +1 | Simple action chain, low benefit |

**Thresholds:** 0-2 = leave as prose, 3-4 = consider extraction, 5+ = strong candidate.

A "gathering" phase that reads files and asks the user questions? Leave it as prose. A "validation" phase with 12 independent checks that all need to run? Extract it — the workflow graph guarantees every check executes.

---

## The Skill Catalog

Fifteen skills form the blueprint authoring toolkit. They fall into four groups.

### Creation Skills

| Skill | Purpose |
|-------|---------|
| **bp-skill-create** | Scaffold a new skill from templates — gathers name, description, inputs/outputs, designs phases, generates SKILL.md + workflow files |
| **bp-gateway-create** | Create a gateway command with 3VL intent routing |
| **bp-intent-create** | Create an intent-mapping.yaml with flag definitions and rules |

### Analysis Skills

| Skill | Purpose |
|-------|---------|
| **bp-skill-analyze** | Deep analysis of any skill — phase identification, coverage classification, per-phase complexity, extraction candidates, quality metrics |
| **bp-plugin-discover** | Scan a plugin for all skills, classify by coverage level, check inputs/outputs completeness, produce inventory |
| **bp-plugin-analyze** | Plugin-wide health analysis — cross-skill metrics, dependency maps, intent coverage, version consistency, scored recommendations |

### Transformation Skills

| Skill | Purpose |
|-------|---------|
| **bp-workflow-extract** | Extract specific prose phases into workflow definitions — generates `workflows/*.yaml` and updates SKILL.md |
| **bp-skill-refactor** | Restructure existing workflows — extract subflows, inline, split, merge, rename nodes, cleanup dead code |
| **bp-skill-upgrade** | Migrate workflow.yaml from older schema versions to latest |
| **bp-plugin-batch** | Apply any operation (validate, upgrade, analyze, visualize, extract) across all skills in a plugin |

### Validation Skills

| Skill | Purpose |
|-------|---------|
| **bp-skill-validate** | Validate a workflow.yaml across 4 dimensions: schema, graph, types, state |
| **bp-gateway-validate** | Validate gateway command structure and routing |
| **bp-intent-validate** | Validate 3VL rule logic and coverage |
| **bp-visualize** | Generate Mermaid diagrams from workflow files |

### Skill Pipeline

The skills compose into natural workflows:

```
bp-plugin-discover          "What skills exist? What's their coverage?"
        │
        ▼
bp-skill-analyze            "Pick one. What are its phases? What's complex?"
        │
        ▼
bp-workflow-extract         "Extract that high-complexity phase into a workflow."
        │
        ▼
bp-skill-validate           "Verify the generated workflow is correct."
        │
        ▼
bp-visualize                "Show me the workflow graph."
```

For new skills:

```
bp-skill-create             "Scaffold the skill with N phases, M workflow-backed."
        │
        ▼
bp-skill-validate           "Verify the generated workflows."
```

For bulk operations:

```
bp-plugin-discover          "Inventory everything."
        │
        ▼
bp-plugin-batch             "Validate/analyze/extract across all skills."
        │
        ▼
bp-plugin-analyze           "How healthy is the plugin overall?"
```

---

## Key Design Decisions

### Skills Are Always Prose Orchestrators

Even a "fully formalized" skill (coverage = `full`) still has a SKILL.md that orchestrates the workflow execution. The SKILL.md reads the definitions file, loads the workflow, follows the execution guide, and handles the result. There is no "thin loader" pattern where SKILL.md is just a wrapper. The prose orchestrator IS the skill.

### Workflows Are Self-Contained

Each workflow file in `workflows/` is a complete, independent execution graph. Workflows don't call other workflows (the `reference` node was removed in v5.0.0). If a skill needs multiple workflows, the SKILL.md orchestrates them in sequence, passing state through the `computed.*` namespace.

### Local Definitions Only

Type definitions are deployed locally in `.hiivmind/blueprint/definitions.yaml`. No remote loading, no version resolution at runtime. Authors copy the types they need from the blueprint-lib catalog at authoring time. This means:

- Zero runtime dependencies
- Workflows are fully self-contained with their definitions file
- Version upgrades are explicit (run `bp-skill-upgrade`)

### Three Node Types, No More

The entire workflow graph language is built from `action`, `conditional`, and `user_prompt`. This constraint is intentional — it forces clarity. If you can't express your logic with these three primitives, it belongs in prose.

### Coverage Is a Spectrum

Skills aren't born fully formalized. A typical lifecycle:

1. **Create** as `none` — all prose, proving out the procedure
2. **Identify** high-complexity phases via `bp-skill-analyze`
3. **Extract** those phases to workflows → `partial`
4. **Optionally** extract remaining phases → `full`

Most skills stabilize at `partial`. The gathering and reporting phases work better as prose. The validation and transformation phases work better as workflows.

---

## State and Data Flow

### Within a Skill

State flows between phases via the `computed.*` namespace:

```
Phase 1 (prose)    →  computed.gathered_data    →  Phase 2 (workflow)
Phase 2 (workflow) →  computed.validation_result →  Phase 3 (prose)
Phase 3 (prose)    →  computed.final_report     →  [output to user]
```

### Between Skills

Skills compose via the `computed.*` namespace and declared inputs/outputs:

```
bp-skill-analyze   →  computed.analysis         →  bp-workflow-extract
bp-plugin-discover →  computed.inventory        →  bp-plugin-batch
```

The analysis output schema (`bp-skill-analyze/patterns/analysis-output-schema.md`) is the formal contract between analyze and extract.

### Within a Workflow

Workflow state includes:

- `state.current_node` — Where execution is
- `state.computed.*` — Results from consequence execution
- `state.flags.*` — Boolean routing flags
- `state.user_responses.*` — User prompt selections
- `state.checkpoints.*` — Snapshots for rollback

Variable interpolation uses `${...}` syntax: `${computed.file_path}`, `${flags.config_found}`.

---

## Verification

The `VERIFICATION.md` checklist enforces structural consistency across all 15 skills with 14 checks:

| # | Check | What It Catches |
|---|-------|----------------|
| 1 | Valid YAML frontmatter | Missing name, description, or allowed-tools |
| 2 | Phase structure (>=4 phases) | Skills that are too thin |
| 3 | AskUserQuestion JSON examples | Informal prompts instead of proper tool calls |
| 4 | Pseudocode blocks | Wrong language tags on algorithmic logic |
| 5 | `computed.*` references | Missing state management between phases |
| 6 | Pattern file references resolve | Broken references to supporting material |
| 7 | Workflows in `workflows/` subdirectory | Legacy bare `workflow.yaml` at skill root |
| 8 | No dogfooding sections | Old thin-loader template patterns leaking in |
| 9 | `lib/patterns/` uses CLAUDE_PLUGIN_ROOT | Broken relative path references |
| 10 | `templates/` uses CLAUDE_PLUGIN_ROOT | Same for template references |
| 11 | Handoff documentation | analyze ↔ extract contract documented in both directions |
| 12 | Frontmatter completeness | Missing inputs/outputs declarations |
| 13 | Declared workflows exist | Frontmatter lists a workflow file that doesn't exist on disk |
| 14 | End-to-end quality read (manual) | Prose quality, flow logic, cross-references |

---

## Relationship to blueprint-lib

`hiivmind-blueprint-lib` is the type definition catalog. It provides the building blocks that workflows use, not the skills themselves.

| Concept | Defined In | Used By |
|---------|-----------|---------|
| Consequence types (22) | blueprint-lib `consequences/*.yaml` | Workflow `action` nodes |
| Precondition types (9) | blueprint-lib `preconditions/*.yaml` | Workflow `conditional` nodes |
| Node types (3) | blueprint-lib `nodes/workflow_nodes.yaml` | All workflow nodes |
| Skill structure | blueprint `templates/SKILL.md.template` | Every skill |
| Execution semantics | blueprint `patterns/execution-guide.md` | Workflow phases |
| Authoring conventions | blueprint `patterns/authoring-guide.md` | Skill + workflow authoring |

The blueprint-lib catalog is the "what exists." The blueprint patterns are the "how to use it." The skills are the "do it for me."
