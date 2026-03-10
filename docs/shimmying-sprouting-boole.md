# Refactor: Separate Skill Definitions from Workflow Definitions

## Context

The current blueprint authoring system conflates "defining a skill" with "building a workflow." Skills are classified as prose/workflow/hybrid/simple, but this taxonomy is artificial — all real skills are hybrids of prose orchestration and structured workflow execution. With the `reference` node removed in v5.0.0, workflows can no longer compose by calling other workflows, but a prose-based skill can have multiple phases each backed by distinct, self-contained workflow definitions.

**The core shift:** A skill is a prose orchestrator (SKILL.md) that optionally delegates specific phases to one or more workflow definitions. Workflows are tools that skills use, not a skill type.

**Design decisions (from user input):**
- Workflow files go in `workflows/` subdirectory within skill directory
- Skill inputs/outputs are defined in SKILL.md YAML frontmatter
- Classification replaces prose/workflow/hybrid/simple with coverage model: `none | partial | full`
- Single comprehensive PR (no phasing)

---

## New Skill Directory Layout

```
skills/my-skill/
├── SKILL.md                    # Prose orchestrator (always present)
├── workflows/                  # Optional: workflow definitions
│   ├── validate.yaml          # Self-contained workflow for one phase
│   └── transform.yaml         # Self-contained workflow for another phase
└── patterns/                   # Optional: supporting pattern files
    └── *.md
```

**Single-workflow skills** still use `workflows/workflow.yaml` (not a bare `workflow.yaml` at skill root — this is a breaking change from the old layout).

## New SKILL.md Frontmatter

```yaml
---
name: my-skill
description: >
  What this skill does...
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
inputs:
  - name: target_path
    type: string
    required: true
    description: Path to process
outputs:
  - name: result
    type: object
    description: Structured analysis result
workflows:                          # Optional: declared workflow files
  - workflows/validate.yaml
  - workflows/transform.yaml
---
```

## New SKILL.md Body Structure

```markdown
# My Skill

[Overview paragraph — what this skill does and when to use it]

## Execution

### Phase 1: Discover
[Prose instructions — tool calls, file reads, analysis]

### Phase 2: Validate
Execute `workflows/validate.yaml` following the execution guide.
[Pre/post workflow prose if needed]

### Phase 3: Transform
Execute `workflows/transform.yaml` following the execution guide.

### Phase 4: Report
[Prose instructions — display results, offer next steps]
```

Each phase is either prose or workflow-backed. The SKILL.md is always the authority on overall flow.

---

## Changes by File

### 1. Templates (`hiivmind-blueprint/templates/`)

#### `SKILL.md.template` — REWRITE
- **Current:** Thin workflow loader that detects one `workflow.yaml` and delegates entirely
- **New:** Hybrid skill template with:
  - `inputs:` and `outputs:` in frontmatter
  - Optional `workflows:` list in frontmatter
  - Body with phases (prose and/or workflow-backed)
  - Execution section that shows how to run prose phases AND how to delegate to workflows
  - Remove the "Step 2: Detect Workflow" / single-workflow-path assumption
  - Keep: Usage, Help, Runtime Flags, Intent Detection sections (conditional)

#### `workflow.yaml.template` — MINOR UPDATE
- Add header comment clarifying this is for individual workflow definitions within a skill
- Remove any skill-level language (this defines a workflow, not a skill)
- Remove `{{skill_id}}` → use `{{workflow_id}}` for the name field
- Keep all node templates unchanged

#### `gateway-command.md.template` — UPDATE
- Gateway is a special skill type. Update to match new frontmatter model
- Add `inputs:` (the request argument)
- Keep routing/dispatch protocol unchanged

#### `intent-mapping.yaml.template` — NO CHANGE
#### `output-config.yaml.template` — NO CHANGE
#### `help-display.md.template` — NO CHANGE

### 2. Patterns (`hiivmind-blueprint/patterns/`)

#### `authoring-guide.md` — MAJOR UPDATE
Split into two clear parts:

**Part 1: Authoring Skills**
- Skill structure (SKILL.md + optional workflows/ + patterns/)
- Defining inputs and outputs in frontmatter
- Designing phases (prose vs workflow-backed)
- When to extract a workflow (high conditional density, loops, FSM patterns)
- Multi-workflow composition via prose orchestration
- State handoff between prose phases and workflows

**Part 2: Authoring Workflows**
- Existing content: YAML structure, nodes, transitions, state, endings, interpolation
- Clarify workflows are self-contained units within a skill
- Remove any skill-level concerns from workflow docs

#### `execution-guide.md` — UPDATE
- Add new section: "Skill Execution Model"
  - Phase 1: Read SKILL.md, identify phases and workflow references
  - Phase 2: Execute phases sequentially (prose or workflow)
  - Phase 3: For workflow phases: load definitions.yaml, initialize, execute, complete
  - State handoff: how `computed.*` flows between prose and workflow phases
- Keep existing 3-phase workflow execution model (Init → Execute → Complete) but nest it within the skill-level model

#### `node-mapping.md` — UPDATE
- Remove `reference` node mentions (line references to deprecated node still present)
- Add section: "Multi-Workflow Composition Patterns"
  - Pattern: skill-level prose orchestrating multiple workflows
  - When to split into separate workflows vs one large workflow
  - State handoff conventions between workflows

#### `skill-analysis.md` — REWRITE
- Remove focus on prose→workflow migration
- New focus: analyzing any skill's structure
  - Phase identification (prose and workflow-backed)
  - Coverage classification (none/partial/full)
  - Phase-level complexity assessment
  - Workflow extraction candidates (high-conditional prose phases)

### 3. References (`hiivmind-blueprint/references/`)

#### `node-features.md` — MINOR UPDATE
- Remove or clean up `reference` node documentation (already marked as removed in v6.0.0)

#### `consequences-catalog.md` — NO CHANGE
#### `preconditions-catalog.md` — NO CHANGE
#### `display-config-examples.md` — NO CHANGE
#### `prompts-config-examples.md` — NO CHANGE

### 4. Skills (`hiivmind-blueprint/skills/`)

#### `VERIFICATION.md` — UPDATE
- Update check #7: "NO `workflow.yaml` files" → update for new `workflows/` subdirectory convention
- Add check: SKILL.md frontmatter includes `inputs:` and `outputs:` arrays
- Add check: Any declared `workflows:` in frontmatter have corresponding files
- Remove prose/workflow/hybrid classification references

#### `bp-skill-create/SKILL.md` — MAJOR REFACTOR
- **Current:** Creates one SKILL.md + one workflow.yaml with fixed structure
- **New:**
  - Phase 1: Gather skill name, description, inputs/outputs
  - Phase 2: Design phases — ask user how many phases, which are workflow-backed
  - Phase 3: Generate SKILL.md with new frontmatter (inputs, outputs, workflows list)
  - Phase 4: Generate workflow files in `workflows/` for each workflow-backed phase
  - Phase 5: Create infrastructure (plugin.json, etc.)
  - Phase 6: Validate and report
- Update `patterns/scaffold-checklist.md` for new placeholders
- References removed: `engine-entrypoint.md.template`, `config.yaml.template` (deleted in v6.0.0)

#### `bp-prose-analyze/` → RENAME to `bp-skill-analyze/` (absorb old `bp-skill-analyze`)
- **Current bp-prose-analyze:** Analyzes prose SKILL.md for migration readiness
- **Current bp-skill-analyze:** Analyzes workflow quality metrics
- **New bp-skill-analyze:** Unified analysis for any skill
  - Phase identification across prose and workflow phases
  - Coverage classification (none/partial/full)
  - Per-phase complexity assessment
  - Workflow extraction candidates (high-conditional prose phases)
  - Quality metrics for existing workflows
  - Inputs/outputs completeness check
- Delete old `bp-skill-analyze/` and `bp-prose-analyze/` directories
- Create new `bp-skill-analyze/` with merged functionality

#### `bp-prose-migrate/` → RENAME to `bp-workflow-extract/`
- **Current:** Converts entire prose skill into single workflow.yaml + thin SKILL.md
- **New:**
  - Takes a specific phase (or set of phases) from a skill
  - Generates individual workflow file(s) in `workflows/`
  - Updates SKILL.md to reference new workflow(s) and add workflow execution instructions
  - Does NOT replace the entire SKILL.md — preserves prose phases
  - State handoff: input parameters wired from skill state, output stored back
- Rename the skill directory and all references

#### `bp-plugin-discover/SKILL.md` — REFACTOR
- **Current:** Classifies as prose/workflow/hybrid/simple
- **New:**
  - Inventory all skills with:
    - Phase count
    - Workflow count
    - Coverage level (none/partial/full)
    - Inputs/outputs defined (yes/no)
  - Recommendations based on coverage gaps, not conversion readiness
  - Remove quick wins / priority conversions framing
  - Replace with: "Formalization opportunities" (phases that would benefit from workflow extraction)
- Update `patterns/classification-algorithm.md` for coverage-based classification

#### `bp-skill-validate/SKILL.md` — EXTEND
- Add skill-level validation:
  - Frontmatter completeness (inputs, outputs defined)
  - Declared workflows exist on disk
  - Workflow files validate individually
  - Phase consistency (workflow references in body match frontmatter)
- Keep existing workflow validation dimensions (schema, graph, types, state)

#### `bp-skill-refactor/SKILL.md` — UPDATE
- Add new refactoring operations:
  - Extract workflow from prose phase
  - Merge small workflows
  - Add missing inputs/outputs to frontmatter
  - Migrate from old layout (bare `workflow.yaml`) to new (`workflows/` subdirectory)

#### `bp-plugin-analyze/SKILL.md` — UPDATE
- Replace prose/workflow/hybrid metrics with coverage metrics
- Add inputs/outputs completeness across plugin
- Add phase structure analysis

#### `bp-plugin-batch/SKILL.md` — UPDATE
- Update batch operations for new model:
  - Batch add inputs/outputs to skills missing them
  - Batch migrate layout (old `workflow.yaml` → `workflows/workflow.yaml`)
  - Batch coverage report

#### `bp-visualize/SKILL.md` — MINOR UPDATE
- Handle multiple workflow files per skill
- Generate composite diagram showing skill phases + per-workflow graphs

#### Intent/Gateway skills — MINOR UPDATES
- `bp-intent-create/`, `bp-intent-validate/`, `bp-gateway-create/`, `bp-gateway-validate/`
- Update references to new SKILL.md template structure
- Update any references to old skill classifications

### 5. Blueprint-lib (`hiivmind-blueprint-lib/`)

#### `README.md` — UPDATE
- Clarify that types define workflow building blocks, not skills
- Add section explaining skills vs workflows

#### No schema changes needed
- Workflow schemas unchanged (workflows are still the same YAML structure)
- Skill frontmatter is a Claude Code convention, not a blueprint-lib schema
- The `schema/resolution/definitions.json` is unchanged (definitions.yaml still works the same way)

---

## Implementation Order

Within the single PR, implement in dependency order:

1. **Templates** — Foundation everything else depends on
   - `SKILL.md.template` (rewrite)
   - `workflow.yaml.template` (minor)
   - `gateway-command.md.template` (update)

2. **Patterns & References** — Guides that skills reference
   - `authoring-guide.md` (major update)
   - `execution-guide.md` (update)
   - `node-mapping.md` (update)
   - `skill-analysis.md` (rewrite)
   - `node-features.md` (minor)

3. **Core authoring skills** — Primary user-facing skills
   - `bp-skill-create` (major refactor)
   - New `bp-skill-analyze` (merge of bp-prose-analyze + bp-skill-analyze)
   - New `bp-workflow-extract` (rename from bp-prose-migrate)

4. **Supporting skills** — Skills that depend on core skills
   - `bp-plugin-discover` (refactor classification)
   - `bp-skill-validate` (extend)
   - `bp-skill-refactor` (update)
   - `bp-plugin-analyze` (update)
   - `bp-plugin-batch` (update)
   - `bp-visualize` (minor)
   - Intent/gateway skills (minor)

5. **Verification & docs**
   - `VERIFICATION.md` (update)
   - Blueprint-lib `README.md` (update)

---

## Key Files to Modify

### hiivmind-blueprint (primary)
| File | Change Type |
|------|-------------|
| `templates/SKILL.md.template` | Rewrite |
| `templates/workflow.yaml.template` | Minor update |
| `templates/gateway-command.md.template` | Update |
| `patterns/authoring-guide.md` | Major update |
| `patterns/execution-guide.md` | Update |
| `patterns/node-mapping.md` | Update |
| `patterns/skill-analysis.md` | Rewrite |
| `references/node-features.md` | Minor update |
| `skills/VERIFICATION.md` | Update |
| `skills/bp-skill-create/SKILL.md` | Major refactor |
| `skills/bp-skill-create/patterns/scaffold-checklist.md` | Update |
| `skills/bp-prose-analyze/` | Delete (merged into bp-skill-analyze) |
| `skills/bp-skill-analyze/` | Rewrite (absorbs bp-prose-analyze) |
| `skills/bp-prose-migrate/` | Delete (renamed to bp-workflow-extract) |
| `skills/bp-workflow-extract/` | New (from bp-prose-migrate refactor) |
| `skills/bp-plugin-discover/SKILL.md` | Refactor |
| `skills/bp-plugin-discover/patterns/classification-algorithm.md` | Rewrite |
| `skills/bp-skill-validate/SKILL.md` | Extend |
| `skills/bp-skill-refactor/SKILL.md` | Update |
| `skills/bp-plugin-analyze/SKILL.md` | Update |
| `skills/bp-plugin-batch/SKILL.md` | Update |
| `skills/bp-visualize/SKILL.md` | Minor update |
| `skills/bp-intent-create/SKILL.md` | Minor update |
| `skills/bp-intent-validate/SKILL.md` | Minor update |
| `skills/bp-gateway-create/SKILL.md` | Minor update |
| `skills/bp-gateway-validate/SKILL.md` | Minor update |

### hiivmind-blueprint-lib (secondary)
| File | Change Type |
|------|-------------|
| `README.md` | Update |

---

## Verification

1. **Template validation:** Generated SKILL.md from new template has valid frontmatter with inputs/outputs
2. **Authoring guide review:** Both "Authoring Skills" and "Authoring Workflows" sections are self-contained
3. **Skill consistency:** All 15 skills' SKILL.md files reference new templates and patterns correctly
4. **Cross-references:** No broken `${CLAUDE_PLUGIN_ROOT}` references after renames
5. **VERIFICATION.md:** Run checks against updated skills to confirm compliance
6. **Coverage classification:** `bp-plugin-discover` correctly reports none/partial/full for test skills
7. **End-to-end:** `bp-skill-create` generates a valid hybrid skill with workflows/ subdirectory
