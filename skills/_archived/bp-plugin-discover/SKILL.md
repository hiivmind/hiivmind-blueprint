---
name: bp-plugin-discover
description: >
  This skill should be used when the user asks to "find skills", "list skills",
  "show skill inventory", "what skills exist", "discover skills",
  "scan plugin for skills", "inventory skills", "show coverage",
  or needs to see the skill inventory and workflow coverage across a plugin.
  Triggers on "discover skills", "plugin discover", "list skills", "skill inventory",
  "scan plugin", "show skills", "coverage report".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Discover & Classify Plugin Skills

Scan a plugin for all SKILL.md files, classify each by workflow coverage level
(`none`, `partial`, `full`), check inputs/outputs completeness, and produce a
structured inventory for use by other skills.

> **Classification Algorithm:** `patterns/classification-algorithm.md`
> **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`

---

## Overview

This skill performs a full discovery pass over a plugin (or multiple locations) and produces
a typed inventory. The output feeds downstream skills such as `bp-skill-analyze`
(deep-dive on a single skill) and `bp-plugin-batch` (bulk operations).

**Coverage classifications produced:**

| Coverage | Meaning | Action |
|----------|---------|--------|
| `none` | All phases are prose — no `workflows/` directory or workflow files | Formalization candidates |
| `partial` | Some phases delegate to workflows, others remain prose | Review extraction candidates |
| `full` | All phases delegate to workflow files in `workflows/` | Already formalized |

**Additional flags:**

| Flag | Meaning |
|------|---------|
| `inputs_defined` | SKILL.md frontmatter has `inputs:` array |
| `outputs_defined` | SKILL.md frontmatter has `outputs:` array |
| `legacy_layout` | Has bare `workflow.yaml` sibling instead of `workflows/` subdirectory |

---

## Phase 1: Locate Skills

### Step 1.1: Determine Search Scope

Present the user with scope options. Use AskUserQuestion to capture the choice:

```json
{
  "questions": [{
    "question": "Where should I search for skills?",
    "header": "Search Scope",
    "multiSelect": false,
    "options": [
      {
        "label": "Current plugin",
        "description": "Scan skills/ in this plugin directory"
      },
      {
        "label": "User-level skills",
        "description": "Scan ~/.claude/skills/"
      },
      {
        "label": "Installed plugins",
        "description": "Scan ~/.claude/plugins/*/skills/"
      },
      {
        "label": "All locations",
        "description": "Scan current plugin, user skills, and installed plugins"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_SCOPE(response):
  SWITCH response:
    CASE "Current plugin":
      computed.search_scope = "plugin"
      computed.search_roots = [CLAUDE_PLUGIN_ROOT]
    CASE "User-level skills":
      computed.search_scope = "user"
      computed.search_roots = ["~/.claude/skills"]
    CASE "Installed plugins":
      computed.search_scope = "installed"
      computed.search_roots = ["~/.claude/plugins"]
    CASE "All locations":
      computed.search_scope = "all"
      computed.search_roots = [CLAUDE_PLUGIN_ROOT, "~/.claude/skills", "~/.claude/plugins"]
```

Store the selected scope in `computed.search_scope` and root paths in `computed.search_roots`.

### Step 1.2: Find All SKILL.md Files

For each search root, use Glob to locate SKILL.md files:

```pseudocode
FIND_SKILLS(search_roots):
  computed.skill_files = []

  FOR root IN search_roots:
    IF computed.search_scope == "plugin" OR computed.search_scope == "all":
      files = Glob(root + "/skills/*/SKILL.md")
      computed.skill_files += files

    IF computed.search_scope == "user" OR computed.search_scope == "all":
      files = Glob(root + "/*/SKILL.md")
      computed.skill_files += files

    IF computed.search_scope == "installed" OR computed.search_scope == "all":
      files = Glob(root + "/*/skills/*/SKILL.md")
      computed.skill_files += files

  # Deduplicate by absolute path
  computed.skill_files = deduplicate(computed.skill_files)

  # For each file, extract metadata
  FOR file IN computed.skill_files:
    file.directory = parent_directory(file.path)
    file.name = basename(file.directory)
    file.plugin = determine_plugin_name(file.path)
```

If `computed.skill_files` is empty, display a message:

> No SKILL.md files found in the selected scope. Verify the search path and try again.

Then offer to retry with a different scope or exit.

Store results in `computed.skill_files` as an array of objects with `path`, `directory`, `name`,
and `plugin` fields.

---

## Phase 2: Classify Skills

### Step 2.1: Check for Workflow Files

For each skill found, check for workflow files using the new directory layout:

```pseudocode
CHECK_WORKFLOWS():
  FOR skill IN computed.skill_files:
    # Check for workflows/ subdirectory (new layout)
    workflow_dir = skill.directory + "/workflows"
    workflow_files = Glob(workflow_dir + "/*.yaml")
    skill.workflow_files = workflow_files
    skill.has_workflows_dir = len(workflow_files) > 0

    # Check for legacy bare workflow.yaml sibling (old layout)
    legacy_path = skill.directory + "/workflow.yaml"
    skill.has_legacy_workflow = file_exists(legacy_path)
    IF skill.has_legacy_workflow:
      skill.legacy_workflow_path = legacy_path
```

### Step 2.2: Analyze SKILL.md Content and Classify

Read each SKILL.md and apply the coverage classification algorithm. The full algorithm
is documented in `patterns/classification-algorithm.md`.

For each skill, read the file content and determine coverage:

```pseudocode
CLASSIFY_ALL():
  FOR skill IN computed.skill_files:
    content = Read(skill.path)
    skill.line_count = count_lines(content)
    skill.frontmatter = extract_frontmatter(content)
    skill.coverage = classify_coverage(skill, content)
    skill.metrics = compute_metrics(content)
    skill.inputs_defined = "inputs" IN skill.frontmatter AND len(skill.frontmatter.inputs) > 0
    skill.outputs_defined = "outputs" IN skill.frontmatter AND len(skill.frontmatter.outputs) > 0
    skill.legacy_layout = skill.has_legacy_workflow AND NOT skill.has_workflows_dir
```

**Coverage classification function (summary — see `patterns/classification-algorithm.md` for full detail):**

```pseudocode
function classify_coverage(skill, content):
  # Count phases in the SKILL.md body
  phases = detect_phases(content)
  workflow_backed_phases = count_workflow_backed_phases(content, skill)
  total_phases = len(phases)

  IF total_phases == 0:
    return "none"

  IF workflow_backed_phases == 0:
    return "none"        # No phases delegate to workflows
  ELIF workflow_backed_phases == total_phases:
    return "full"        # All phases delegate to workflows
  ELSE:
    return "partial"     # Some phases are prose, some are workflow-backed
```

Store classification in `computed.skills[]` with the `coverage` field set.

### Step 2.3: Compute Phase Metrics

For each skill, compute per-phase metrics:

```pseudocode
function compute_metrics(content):
  metrics = {
    line_count:        count_lines(content),
    section_count:     count_matches(content, /^##+ /m),
    phase_count:       count_phases(content),
    workflow_phases:   count_workflow_backed_phases(content),
    prose_phases:      phase_count - workflow_phases,
    conditional_count: count_matches(content, /\b(if|when|otherwise|based on|depending on)\b/i),
    user_prompts:      count_matches(content, /"questions"\s*:\s*\[/) + count_matches(content, /AskUserQuestion/i),
    tool_refs:         count_unique_tools(content)
  }
  return metrics
```

**Complexity thresholds (for prose phases):**

| Metric | Low | Medium | High |
|--------|-----|--------|------|
| Line count | < 100 | 100-300 | > 300 |
| Phase count | 1-2 | 3-5 | 6+ |
| Conditionals | 0-2 | 3-6 | 7+ |
| User prompts | 0-1 | 2-3 | 4+ |

---

## Phase 3: Generate Inventory

### Step 3.1: Build Status Table

Construct a markdown summary table from `computed.skills[]`:

```
## Skill Discovery: {computed.plugin_name}

Scanned: {len(computed.skills)} skills
Location: {computed.search_scope}
Timestamp: {computed.discovery.timestamp}

| # | Skill | Coverage | Phases | Workflow Phases | I/O | Layout | Lines | Notes |
|---|-------|----------|--------|-----------------|-----|--------|-------|-------|
{for i, skill in enumerate(computed.skills)}
| {i+1} | {skill.name} | {skill.coverage} | {skill.metrics.phase_count} | {skill.metrics.workflow_phases} | {skill.inputs_defined}/{skill.outputs_defined} | {skill.legacy_layout ? "legacy" : "current"} | {skill.metrics.line_count} | {skill.notes} |
{/for}
```

Display this table to the user immediately.

### Step 3.2: Group by Coverage

After the summary table, present skills grouped by coverage level:

```
### Full Coverage ({count_full})

All phases delegate to workflow definitions:

{for skill in computed.skills where skill.coverage == "full"}
- **{skill.name}** — {skill.metrics.phase_count} phases, {len(skill.workflow_files)} workflow files
{/for}

### Partial Coverage ({count_partial})

Some phases are workflow-backed, others remain prose:

{for skill in computed.skills where skill.coverage == "partial"}
- **{skill.name}** — {skill.metrics.workflow_phases}/{skill.metrics.phase_count} phases formalized, {skill.metrics.prose_phases} prose phases remaining
{/for}

### No Coverage ({count_none})

All phases are prose — no workflow definitions:

{for skill in computed.skills where skill.coverage == "none"}
- **{skill.name}** — {skill.metrics.phase_count} phases, {skill.metrics.conditional_count} conditionals
{/for}
```

### Step 3.3: Generate Recommendations

Based on the inventory, produce actionable recommendations:

**Formalization Opportunities** — Prose phases with high extraction scores:

```pseudocode
FORMALIZATION_OPPORTUNITIES():
  candidates = []
  FOR skill IN computed.skills:
    IF skill.coverage IN ("none", "partial"):
      FOR phase IN skill.prose_phases:
        score = calculate_extraction_score(phase)
        IF score >= 3:
          candidates.append({skill: skill.name, phase: phase.title, score: score})
  return sorted(candidates, key=lambda c: c.score, reverse=True)
```

Display:
```
#### Formalization Opportunities
These prose phases are strong candidates for workflow extraction:

{for candidate in formalization_opportunities}
- **{candidate.skill}** → Phase: {candidate.phase} (extraction score: {candidate.score})
{/for}
```

**Completeness Gaps** — Skills missing inputs/outputs definitions:

```
#### Completeness Gaps
These skills are missing inputs/outputs in their frontmatter:

{for skill in computed.skills where not skill.inputs_defined or not skill.outputs_defined}
- **{skill.name}** — inputs: {skill.inputs_defined}, outputs: {skill.outputs_defined}
{/for}
```

**Legacy Layout** — Skills using old bare `workflow.yaml` instead of `workflows/` subdirectory:

```
#### Legacy Layout
These skills use the old layout (bare workflow.yaml) and should migrate to workflows/ subdirectory:

{for skill in computed.skills where skill.legacy_layout}
- **{skill.name}** — {skill.legacy_workflow_path}
{/for}
```

### Step 3.4: Store Discovery State

Persist the full inventory in `computed.discovery` for downstream skill consumption:

```pseudocode
STORE_DISCOVERY():
  computed.discovery = {
    timestamp:    current_iso_timestamp(),
    plugin_path:  computed.search_roots[0],
    search_scope: computed.search_scope,
    total_skills: len(computed.skills),
    skills:       computed.skills,
    summary: {
      none:    count(s for s in computed.skills if s.coverage == "none"),
      partial: count(s for s in computed.skills if s.coverage == "partial"),
      full:    count(s for s in computed.skills if s.coverage == "full")
    },
    completeness: {
      inputs_defined:  count(s for s in computed.skills if s.inputs_defined),
      outputs_defined: count(s for s in computed.skills if s.outputs_defined),
      legacy_layout:   count(s for s in computed.skills if s.legacy_layout)
    },
    recommendations: {
      formalization_opportunities: formalization_opportunities_list,
      completeness_gaps:           completeness_gaps_list,
      legacy_layout:               legacy_layout_list
    }
  }
```

---

## Phase 4: Offer Deep Dive

### Step 4.1: Next Action

After presenting the inventory, ask the user what they want to do next:

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {
        "label": "Analyze a specific skill",
        "description": "Run deep structural analysis on one skill from the inventory"
      },
      {
        "label": "Export discovery report",
        "description": "Save the full inventory to a YAML or Markdown file"
      },
      {
        "label": "Done",
        "description": "No further action needed"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_ACTION(response):
  SWITCH response:
    CASE "Analyze a specific skill":
      GOTO Step 4.2
    CASE "Export discovery report":
      GOTO Step 4.3
    CASE "Done":
      DISPLAY "Discovery complete. {computed.discovery.total_skills} skills inventoried."
      EXIT
```

### Step 4.2: Hand Off to Deep Analysis

If the user selects "Analyze a specific skill":

1. Present a follow-up AskUserQuestion listing skills that have prose phases
   (since fully-formalized skills may not need analysis):

   ```pseudocode
   BUILD_ANALYSIS_OPTIONS():
     analyzable = [s for s in computed.skills
                   if s.coverage in ("none", "partial")]
     options = [{ label: s.name, description: s.coverage + " / " + str(s.metrics.phase_count) + " phases" } for s in analyzable]
   ```

2. Once the user selects a skill, describe the handoff:

   > To perform deep analysis on **{selected_skill.name}**, invoke:
   >
   > ```
   > Skill(skill: "bp-skill-analyze", args: "{selected_skill.path}")
   > ```
   >
   > The skill-analyze skill will identify phases, compute extraction scores,
   > assess workflow quality, and produce a detailed analysis report.

3. Store the selected skill path in `computed.analysis_target` for downstream use.

### Step 4.3: Export Report

If the user selects "Export discovery report":

1. Ask for the output format and location:

   ```pseudocode
   default_path = computed.search_roots[0] + "/docs/skill-discovery-report"
   ```

2. Generate the report file:
   - **YAML format**: Serialize `computed.discovery` as a YAML document
   - **Markdown format**: Render the grouped inventory tables from Phase 3 as a standalone document

3. Display confirmation:

   > Discovery report saved to **{output_path}**.
   > Contains inventory of {computed.discovery.total_skills} skills with coverage classifications and metrics.

---

## Reference Documentation

- **Classification Algorithm:** `patterns/classification-algorithm.md` (local to this skill)
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`

---

## Related Skills

- Deep skill analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-analyze/SKILL.md`
- Plugin structure analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-analyze/SKILL.md`
- Batch operations: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-batch/SKILL.md`
- Workflow extraction: `${CLAUDE_PLUGIN_ROOT}/skills/bp-workflow-extract/SKILL.md`
