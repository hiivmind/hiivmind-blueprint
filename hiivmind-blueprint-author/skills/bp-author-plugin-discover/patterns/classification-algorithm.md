# Classification Algorithm

> **Used by:** `SKILL.md` Phase 2, Step 2.2
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

This document defines the full classification algorithm for determining whether a SKILL.md
file is prose-based, workflow-based, hybrid, or too simple for workflow conversion.

---

## Indicator Scoring

Each SKILL.md file is scored across two dimensions: **workflow affinity** and **prose density**.
The balance between these scores, combined with the presence or absence of a sibling
`workflow.yaml`, determines the classification.

### Workflow Indicators

Patterns that suggest the skill is already converted to workflow execution:

| Indicator | Regex / Detection | Weight | Rationale |
|-----------|-------------------|--------|-----------|
| `workflow.yaml` reference | `/workflow\.yaml/` | 2 | Direct reference to workflow file |
| "Execute this workflow" | `/Execute this workflow/i` | 2 | Thin-loader boilerplate phrase |
| "Execution Protocol" section | `/## Execution Protocol/` | 3 | Standard section in workflow-backed skills |
| "Initial State Schema" section | `/## Initial State Schema/` | 3 | Workflow state declaration block |
| `lib/workflow/` reference | `/lib\/workflow\//` | 1 | Reference to workflow library patterns |
| `hiivmind-blueprint-lib` reference | `/hiivmind-blueprint-lib/` | 1 | Reference to external type library |
| Workflow graph section | `/## Workflow Graph Overview/` | 2 | ASCII graph of node topology |

**Workflow score formula:**

```pseudocode
workflow_score =
    count("workflow.yaml") * 2
  + count("Execute this workflow") * 2
  + count("Execution Protocol") * 3
  + count("Initial State Schema") * 3
  + count("lib/workflow/") * 1
  + count("hiivmind-blueprint-lib") * 1
  + count("Workflow Graph Overview") * 2
```

### Prose Indicators

Patterns that suggest the skill contains procedural instructions meant for LLM execution:

| Indicator | Regex / Detection | Weight | Rationale |
|-----------|-------------------|--------|-----------|
| Phase/Step headings | `/^## (Phase\|Step) \d/m` | 2 | Numbered procedural phases |
| Conditional language | `/\b(if\|when\|otherwise\|based on\|depending on)\b/i` | 1 | Branching logic in prose |
| AskUserQuestion JSON blocks | `/"questions"\s*:\s*\[/` | 2 | Inline JSON for user interaction |
| AskUserQuestion text refs | `/AskUserQuestion\|ask user\|prompt user/i` | 1 | Prose references to user prompts |
| Pseudocode blocks | `/```pseudocode/` | 1 | Inline pseudocode procedures |
| Computed state references | `/computed\.\w+/` | 1 | State management in prose |
| Tool invocation prose | `/\b(Read|Write|Glob|Grep|Bash)\b.*file\|content/i` | 1 | Prose describing tool calls |

**Prose score formula:**

```pseudocode
prose_score =
    count_phase_headings * 2
  + count_conditionals * 1
  + count_ask_user_json * 2
  + count_ask_user_text * 1
  + count_pseudocode_blocks * 1
  + count_computed_refs * 1
  + count_tool_prose * 1
```

---

## Decision Algorithm

### Full Decision Tree

```pseudocode
function classify_skill(skill):
  content = Read(skill.path)

  # ---- Gather raw counts ----
  workflow_refs      = count_matches(content, /workflow\.yaml/)
  execute_workflow   = count_matches(content, /Execute this workflow/i)
  execution_protocol = count_matches(content, /## Execution Protocol/)
  initial_state      = count_matches(content, /## Initial State Schema/)
  lib_workflow       = count_matches(content, /lib\/workflow\//)
  blueprint_lib      = count_matches(content, /hiivmind-blueprint-lib/)
  graph_section      = count_matches(content, /## Workflow Graph Overview/)

  phase_headings     = count_matches(content, /^## (Phase|Step) \d/m)
  conditionals       = count_matches(content, /\b(if|when|otherwise|based on|depending on)\b/i)
  ask_user_json      = count_matches(content, /"questions"\s*:\s*\[/)
  ask_user_text      = count_matches(content, /AskUserQuestion|ask user|prompt user/i)
  pseudocode_blocks  = count_matches(content, /```pseudocode/)
  computed_refs      = count_matches(content, /computed\.\w+/)
  line_count         = count_lines(content)

  # ---- Compute aggregate scores ----
  workflow_score = (
      workflow_refs * 2
    + execute_workflow * 2
    + execution_protocol * 3
    + initial_state * 3
    + lib_workflow * 1
    + blueprint_lib * 1
    + graph_section * 2
  )

  prose_score = (
      phase_headings * 2
    + conditionals * 1
    + ask_user_json * 2
    + ask_user_text * 1
    + pseudocode_blocks * 1
    + computed_refs * 1
  )

  # ---- Apply decision tree ----

  # Edge case: empty or frontmatter-only file
  if line_count < 10:
    return "simple"

  # Branch 1: Has sibling workflow.yaml
  if skill.has_workflow:
    if workflow_score > 6 AND phase_headings < 3:
      return "workflow"    # Properly converted thin loader
    elif workflow_score > 6 AND phase_headings >= 3:
      return "hybrid"      # Workflow exists but prose remains heavy
    elif workflow_score <= 6 AND prose_score > 8:
      return "hybrid"      # Workflow present but prose dominates
    else:
      return "workflow"    # Default: trust the workflow.yaml presence

  # Branch 2: No sibling workflow.yaml
  else:
    if prose_score >= 8:
      return "prose"       # Strong procedural content, ready to convert
    elif phase_headings > 3 OR conditionals > 5:
      return "prose"       # Enough structure to warrant workflow
    elif phase_headings <= 2 AND conditionals <= 2 AND line_count < 80:
      return "simple"      # Too small to benefit from conversion
    elif ask_user_json >= 1 OR pseudocode_blocks >= 2:
      return "prose"       # Has structured interaction, worth converting
    else:
      return "prose"       # Default: assume convertible unless proven simple
```

---

## Threshold Reference

Summary of numeric thresholds used in the decision tree:

| Check | Threshold | Branch |
|-------|-----------|--------|
| `line_count < 10` | 10 lines | -> `simple` (edge case) |
| `workflow_score > 6` | score 7+ | -> `workflow` (with `has_workflow`) |
| `phase_headings < 3` | 0-2 phases | thin loader (with high workflow_score) |
| `phase_headings >= 3` | 3+ phases | hybrid (with high workflow_score) |
| `prose_score > 8` | score 9+ | -> `hybrid` (when `has_workflow` but low workflow_score) |
| `prose_score >= 8` | score 8+ | -> `prose` (no workflow) |
| `phase_headings > 3` | 4+ phases | -> `prose` (secondary check) |
| `conditionals > 5` | 6+ conditionals | -> `prose` (secondary check) |
| `line_count < 80` | under 80 lines | -> `simple` (with low phases/conditionals) |

---

## Edge Cases

### Empty SKILL.md

A SKILL.md that contains only YAML frontmatter (or is entirely empty) should be classified
as `simple`. Detection:

```pseudocode
if line_count < 10:
  # File has frontmatter and possibly a title, but no procedural content
  return "simple"
```

### Frontmatter-Only File

Some skills have frontmatter + a one-line description but no phases or steps:

```yaml
---
name: my-skill
description: >
  Does something simple.
allowed-tools: Read
---

# My Skill

Read the file and display it.
```

This classifies as `simple` because `phase_headings == 0`, `conditionals == 0`, and
`line_count < 80`.

### Mixed Patterns (Hybrid)

A skill may have been partially converted: workflow.yaml exists, the SKILL.md references it,
but the SKILL.md also retains extensive procedural prose from before conversion. Example
signals:

- `## Execution Protocol` section exists (workflow indicator)
- But also `## Phase 1:`, `## Phase 2:`, `## Phase 3:` (prose indicator)
- `workflow_score > 6` AND `phase_headings >= 3`
- Classification: `hybrid` -- needs review to strip residual prose

### Skills with Only Pseudocode

A skill may have no `## Phase N` headings but contain multiple pseudocode blocks with
conditional logic. The `pseudocode_blocks >= 2` check catches these:

```pseudocode
if ask_user_json >= 1 OR pseudocode_blocks >= 2:
  return "prose"  # Structured enough to convert
```

---

## Classification Examples

### Example: Workflow Skill (Thin Loader)

```markdown
---
name: my-converted-skill
description: >
  Does something via workflow.
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# My Skill

Execute this workflow deterministically. State persists in conversation context.

## Prerequisites
...

## Initial State Schema
...

## Execution Protocol
See engine_entrypoint.md for full protocol.

## Workflow Graph Overview
...

## Reference Documentation
- hiivmind-blueprint-lib
```

**Scores:** `workflow_score = 2+2+3+3+2 = 12`, `phase_headings = 0`, `has_workflow = true`
**Result:** `workflow` (score > 6, phases < 3)

### Example: Prose Skill (Ready to Convert)

```markdown
---
name: my-prose-skill
description: >
  Analyzes and processes data files.
allowed-tools: Read, Glob, AskUserQuestion
---

# Analyze Data

## Phase 1: Locate Files
...if no files found, ask user...

## Phase 2: Parse Content
...when file is JSON, use jq... otherwise, treat as text...

## Phase 3: Generate Report
...depending on the output format selected...

## Phase 4: Export
...if user chose markdown, write .md... based on the analysis results...
```

**Scores:** `workflow_score = 0`, `phase_headings = 4`, `conditionals = 5+`
**Result:** `prose` (no workflow, phase_headings > 3)

### Example: Hybrid Skill

```markdown
---
name: my-hybrid-skill
...
---

# My Skill

Execute this workflow deterministically.

## Initial State Schema
state:
  ...

## Phase 1: Validate Input
...if config missing, ask user...

## Phase 2: Process Data
...when format is JSON...otherwise...

## Phase 3: Generate Output
...depending on user selection...

## Execution Protocol
See engine_entrypoint.md.

## Workflow Graph Overview
...
```

**Scores:** `workflow_score = 2+3+3+2 = 10`, `phase_headings = 3`, `has_workflow = true`
**Result:** `hybrid` (workflow_score > 6 but phase_headings >= 3)

### Example: Simple Skill

```markdown
---
name: my-simple-skill
description: >
  Displays version info.
allowed-tools: Read
---

# Version Info

Read the VERSION file and display the contents.
```

**Scores:** `workflow_score = 0`, `phase_headings = 0`, `conditionals = 0`, `line_count ~12`
**Result:** `simple` (no workflow, phases <= 2, conditionals <= 2, lines < 80)

---

## Using Classification Results

The classification drives downstream behavior:

| Classification | Downstream Skill | Action |
|----------------|-----------------|--------|
| `prose` | `bp-author-prose-analyze` | Full structural analysis, then `bp-author-prose-migrate` |
| `workflow` | None needed | Already converted; optionally run `bp-author-skill-validate` |
| `hybrid` | `bp-author-skill-refactor` | Strip residual prose, validate workflow completeness |
| `simple` | None needed | Flag as "skip" in batch operations |

---

## Related Documentation

- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
