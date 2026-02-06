---
name: bp-author-plugin-discover
description: >
  This skill should be used when the user asks to "find skills", "list skills to convert",
  "show conversion status", "what skills need workflow", "discover prose skills",
  "scan plugin for skills", "inventory skills", or needs to see which skills in a plugin
  are prose-based vs. workflow-based. Triggers on "discover skills", "plugin discover",
  "list skills", "conversion status", "show skills", "skill inventory", "scan plugin".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Discover & Classify Plugin Skills

Scan a plugin for all SKILL.md files, classify each as prose-based, workflow-based, hybrid,
or too simple, and produce a structured inventory for use by other skills.

> **Classification Algorithm:** `patterns/classification-algorithm.md`
> **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

---

## Overview

This skill performs a full discovery pass over a plugin (or multiple locations) and produces
a typed inventory. The output feeds downstream skills such as `bp-author-prose-analyze`
(deep-dive on a single skill) and `bp-author-plugin-batch` (bulk conversion).

**Classifications produced:**

| Status | Meaning | Action |
|--------|---------|--------|
| `prose` | Traditional SKILL.md with procedural instructions, no workflow.yaml | Ready to convert |
| `workflow` | Already has a sibling workflow.yaml and thin-loader SKILL.md | Already converted |
| `hybrid` | Has workflow.yaml but SKILL.md still contains heavy prose logic | Needs review |
| `simple` | Minimal SKILL.md with few sections and low conditional density | May not benefit from workflow |

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
        "description": "Scan skills/ and skills-prose/ in this plugin directory"
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

For each search root, use Glob to locate SKILL.md files. The glob patterns differ by scope:

```pseudocode
FIND_SKILLS(search_roots):
  computed.skill_files = []

  FOR root IN search_roots:
    IF computed.search_scope == "plugin" OR computed.search_scope == "all":
      # Current plugin: check skills/ and skills-prose/ directories
      files = Glob(root + "/skills/*/SKILL.md")
      files += Glob(root + "/skills-prose/*/SKILL.md")
      computed.skill_files += files

    IF computed.search_scope == "user" OR computed.search_scope == "all":
      # User-level skills
      files = Glob(root + "/*/SKILL.md")
      computed.skill_files += files

    IF computed.search_scope == "installed" OR computed.search_scope == "all":
      # Installed plugins: nested one level deeper
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

### Step 2.1: Check for Workflow Sibling

For each skill found, check whether a `workflow.yaml` file exists as a sibling:

```pseudocode
CHECK_WORKFLOW_SIBLINGS():
  FOR skill IN computed.skill_files:
    workflow_path = skill.directory + "/workflow.yaml"
    skill.has_workflow = file_exists(workflow_path)
    IF skill.has_workflow:
      skill.workflow_path = workflow_path
```

### Step 2.2: Analyze SKILL.md Content

Read each SKILL.md and apply the classification algorithm. The full algorithm with scoring
weights and edge cases is documented in `patterns/classification-algorithm.md`.

For each skill, read the file content and count indicators:

```pseudocode
CLASSIFY_ALL():
  FOR skill IN computed.skill_files:
    content = Read(skill.path)
    skill.line_count = count_lines(content)
    skill.classification = classify_skill(skill, content)
    skill.metrics = compute_metrics(content)
```

**Classification function (summary -- see `patterns/classification-algorithm.md` for full detail):**

```pseudocode
function classify_skill(skill, content):
  # Count workflow indicators
  workflow_refs = count_matches(content, /workflow\.yaml|Execute this workflow|Execution Protocol/)
  lib_workflow_refs = count_matches(content, /lib\/workflow\/|hiivmind-blueprint-lib/)
  initial_state_schema = count_matches(content, /## Initial State Schema/)

  # Count prose indicators
  prose_sections = count_matches(content, /^## (Phase|Step) \d/m)
  conditional_count = count_matches(content, /\b(if|when|otherwise|based on|depending on)\b/i)
  ask_user_json = count_matches(content, /"questions"\s*:\s*\[/)
  user_prompt_refs = count_matches(content, /AskUserQuestion|ask user|prompt user/i)

  # Compute aggregate scores
  workflow_score = workflow_refs * 2 + lib_workflow_refs + initial_state_schema * 3
  prose_score = prose_sections * 2 + conditional_count + ask_user_json * 2 + user_prompt_refs

  if skill.has_workflow:
    if workflow_score > 6 AND prose_sections < 3:
      return "workflow"    # Thin loader, already fully converted
    else:
      return "hybrid"      # Has workflow but retains heavy prose
  else:
    if prose_sections > 3 OR conditional_count > 5:
      return "prose"       # Substantial procedural content, ready to convert
    elif prose_sections <= 2 AND conditional_count <= 2 AND skill.line_count < 80:
      return "simple"      # Too small/simple to benefit from workflow
    else:
      return "prose"       # Default: treat as convertible
```

Store classification in `computed.skills[]` with the `classification` field set.

### Step 2.3: Estimate Complexity for Prose Skills

For each skill classified as `prose` or `hybrid`, compute complexity metrics:

```pseudocode
function compute_metrics(content):
  metrics = {
    line_count:       count_lines(content),
    section_count:    count_matches(content, /^##+ /m),
    phase_count:      count_matches(content, /^## (Phase|Step) \d/m),
    conditional_count: count_matches(content, /\b(if|when|otherwise|based on|depending on)\b/i),
    user_prompts:     count_matches(content, /"questions"\s*:\s*\[/) + count_matches(content, /AskUserQuestion/i),
    tool_refs:        count_unique_tools(content)
  }
  return metrics
```

**Complexity thresholds:**

| Metric | Low | Medium | High |
|--------|-----|--------|------|
| Line count | < 100 | 100-300 | > 300 |
| Section count | 1-3 | 4-8 | 9+ |
| Phase count | 1-2 | 3-5 | 6+ |
| Conditionals | 0-2 | 3-6 | 7+ |
| User prompts | 0-1 | 2-3 | 4+ |
| Tool variety | 1-2 | 3-4 | 5+ |

**Aggregate complexity:**

```pseudocode
function compute_complexity(metrics):
  scores = []
  scores.append( LOW if metrics.line_count < 100 else MEDIUM if metrics.line_count <= 300 else HIGH )
  scores.append( LOW if metrics.section_count <= 3 else MEDIUM if metrics.section_count <= 8 else HIGH )
  scores.append( LOW if metrics.conditional_count <= 2 else MEDIUM if metrics.conditional_count <= 6 else HIGH )
  scores.append( LOW if metrics.user_prompts <= 1 else MEDIUM if metrics.user_prompts <= 3 else HIGH )

  # Map LOW=1, MEDIUM=2, HIGH=3
  avg = average(numeric_values(scores))
  if avg < 1.5:
    return "low"
  elif avg < 2.5:
    return "medium"
  else:
    return "high"
```

Store the complexity rating in `computed.skills[].complexity` and the raw metrics
in `computed.skills[].metrics`.

---

## Phase 3: Generate Inventory

### Step 3.1: Build Status Table

Construct a markdown summary table from `computed.skills[]`:

```
## Skill Discovery: {computed.plugin_name}

Scanned: {len(computed.skills)} skills
Location: {computed.search_scope}
Timestamp: {computed.discovery.timestamp}

| # | Skill | Status | Complexity | Lines | Sections | Conditionals | Notes |
|---|-------|--------|------------|-------|----------|--------------|-------|
{for i, skill in enumerate(computed.skills)}
| {i+1} | {skill.name} | {skill.classification} | {skill.complexity or "n/a"} | {skill.metrics.line_count} | {skill.metrics.section_count} | {skill.metrics.conditional_count} | {skill.notes} |
{/for}
```

Display this table to the user immediately so they can see the full picture.

### Step 3.2: Group by Status

After the summary table, present skills grouped by classification:

```
### Ready to Convert ({count_prose})

Skills with prose-based procedures that can be converted to workflow.yaml:

{for skill in computed.skills where skill.classification == "prose"}
- **{skill.name}** -- {skill.complexity} complexity, ~{skill.metrics.section_count} phases, {skill.metrics.conditional_count} conditionals
{/for}

### Already Converted ({count_workflow})

Skills that already have a workflow.yaml sibling:

{for skill in computed.skills where skill.classification == "workflow"}
- **{skill.name}** -- workflow.yaml present at {skill.workflow_path}
{/for}

### Needs Review ({count_hybrid})

Skills with workflow.yaml but significant remaining prose logic:

{for skill in computed.skills where skill.classification == "hybrid"}
- **{skill.name}** -- hybrid: workflow exists but SKILL.md contains {skill.metrics.section_count} prose sections
{/for}

### Too Simple ({count_simple})

Skills that may not benefit from workflow conversion:

{for skill in computed.skills where skill.classification == "simple"}
- **{skill.name}** -- {skill.metrics.line_count} lines, {skill.metrics.section_count} sections
{/for}
```

### Step 3.3: Generate Recommendations

Based on the inventory, produce actionable recommendations in three tiers:

**Quick Wins** -- Medium-complexity prose skills that will convert cleanly:

```pseudocode
QUICK_WINS():
  candidates = [s for s in computed.skills
                 if s.classification == "prose"
                 AND s.complexity == "medium"
                 AND s.metrics.conditional_count <= 5]
  # Sort by section count ascending (fewer sections = easier)
  return sorted(candidates, key=lambda s: s.metrics.section_count)
```

Display:
```
#### Quick Wins
These medium-complexity skills are strong candidates for straightforward conversion:

{for skill in quick_wins}
- **{skill.name}** -- {skill.metrics.section_count} sections, {skill.metrics.conditional_count} conditionals
{/for}
```

**Priority Conversions** -- High-conditional-density skills that benefit most from deterministic workflow:

```pseudocode
PRIORITY_CONVERSIONS():
  candidates = [s for s in computed.skills
                 if s.classification == "prose"
                 AND (s.metrics.conditional_count > 5 OR s.metrics.user_prompts >= 3)]
  return sorted(candidates, key=lambda s: s.metrics.conditional_count, reverse=True)
```

Display:
```
#### Priority Conversions
These skills have many conditionals or user prompts and benefit most from workflow structure:

{for skill in priority_conversions}
- **{skill.name}** -- {skill.metrics.conditional_count} conditionals, {skill.metrics.user_prompts} user prompts
{/for}
```

**Skip for Now** -- Simple skills or already-converted skills that need no action:

```
#### Skip for Now
These skills are either too simple to benefit from workflow or already converted:

{for skill in computed.skills where skill.classification in ("simple", "workflow")}
- **{skill.name}** ({skill.classification})
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
    skills:       computed.skills,    # Full array with classification, metrics, complexity
    summary: {
      prose:    count(s for s in computed.skills if s.classification == "prose"),
      workflow: count(s for s in computed.skills if s.classification == "workflow"),
      hybrid:   count(s for s in computed.skills if s.classification == "hybrid"),
      simple:   count(s for s in computed.skills if s.classification == "simple")
    },
    recommendations: {
      quick_wins:           quick_wins_list,
      priority_conversions: priority_conversions_list,
      skip:                 skip_list
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
      # Display final summary line and exit
      DISPLAY "Discovery complete. {computed.discovery.total_skills} skills inventoried."
      EXIT
```

### Step 4.2: Hand Off to Deep Analysis

If the user selects "Analyze a specific skill":

1. Present a follow-up AskUserQuestion listing only the `prose` and `hybrid` skills
   (since `workflow` and `simple` skills do not need analysis):

   ```pseudocode
   BUILD_ANALYSIS_OPTIONS():
     analyzable = [s for s in computed.skills
                   if s.classification in ("prose", "hybrid")]
     options = [{ label: s.name, description: s.classification + " / " + s.complexity } for s in analyzable]
   ```

2. Once the user selects a skill, describe the handoff:

   > To perform deep analysis on **{selected_skill.name}**, invoke:
   >
   > ```
   > Skill(skill: "bp-author-prose-analyze", args: "{selected_skill.path}")
   > ```
   >
   > The prose-analyze skill will read the full SKILL.md, extract phases, conditionals,
   > state variables, and user interactions, and produce a detailed analysis report.

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
   > Contains inventory of {computed.discovery.total_skills} skills with classifications and metrics.

---

## Reference Documentation

- **Classification Algorithm:** `patterns/classification-algorithm.md` (local to this skill)
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`

---

## Related Skills

- Deep skill analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`
- Plugin structure analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-analyze/SKILL.md`
- Batch conversion: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-batch/SKILL.md`
- Single skill migration: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-migrate/SKILL.md`
