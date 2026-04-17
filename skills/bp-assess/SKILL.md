---
name: bp-assess
description: >
  This skill should be used when the user asks to "assess a skill", "assess my plugin",
  "analyze coverage", "check skill health", "evaluate plugin", "skill inventory",
  "coverage report", "what's the state of my plugin", "where does this skill sit",
  "spectrum position", "is this skill appropriately formalized". Triggers on
  "assess", "evaluate", "coverage", "health", "inventory", "spectrum", "fit analysis".
allowed-tools: Read, Glob, Grep, AskUserQuestion
inputs:
  - name: target_path
    type: string
    required: false
    description: Path to a skill directory, SKILL.md, or plugin root (prompted if not provided)
outputs:
  - name: assessment
    type: object
    description: Complete assessment including coverage position, complexity, fit analysis, and options
---

# Assess Skill & Plugin Coverage

Neutral assessment of where a skill or plugin sits on the coverage spectrum (prose / partial / full
workflow) and whether the current formalization level is an appropriate fit for the skill's
complexity. Reports position and presents OPTIONS — never prescribes movement toward more or less
formalization.

> **Phase Detection Algorithm:** `patterns/phase-detection-algorithm.md`
> **Complexity Scoring Algorithm:** `patterns/complexity-scoring-algorithm.md`
> **Quality Indicators:** `patterns/quality-indicators.md`
> **Analysis Output Schema:** `patterns/analysis-output-schema.md`
> **Classification Algorithm:** `patterns/classification-algorithm.md`
> **Health Scoring Algorithm:** `patterns/health-scoring-algorithm.md`
> **Cross-Skill Metrics:** `patterns/cross-skill-metrics.md`
> **Batch Execution Protocol:** `patterns/batch-execution-protocol.md`

---

## Overview

This skill performs neutral assessment at two scopes:

| Scope | What It Does |
|-------|--------------|
| **Single skill** | Locate skill, parse phases, classify coverage, score complexity, determine fit |
| **Plugin-wide** | Scan all skills, classify each, compute cross-skill metrics, produce health dashboard |

The key output is the **fit analysis** — mapping each skill's complexity against its current
formalization level to determine whether the current position on the spectrum is appropriate.

**Coverage spectrum positions:**

| Position | Meaning |
|----------|---------|
| `prose` | All phases are natural-language instructions — no workflow files |
| `partial` | Some phases delegate to workflows, others remain prose |
| `full` | All phases delegate to workflow definitions |

**Fit outcomes (NEUTRAL — no outcome is inherently better):**

| Fit | Meaning |
|-----|---------|
| `good-fit` | Complexity and formalization level are well-matched |
| `potential-mismatch` | Complexity and formalization level diverge — worth reviewing |
| `review-recommended` | Strong divergence — user should consider whether current level serves them |

---

## Phase 1: Mode Detection

Parse invocation arguments to determine assessment scope and behavior.

### Step 1.1: Parse Arguments

Inspect the invocation arguments for mode flags:

```pseudocode
PARSE_MODE(args):
  computed.mode = null
  computed.target_path = null
  computed.batch_op = null
  computed.discovery_only = false

  IF args contains "--skill <path>":
    computed.mode = "single"
    computed.target_path = extract_path(args, "--skill")

  ELIF args contains "--plugin":
    computed.mode = "plugin"
    computed.target_path = CLAUDE_PLUGIN_ROOT

  ELIF args contains "--batch <op>":
    computed.mode = "plugin"
    computed.batch_op = extract_value(args, "--batch")
    computed.target_path = CLAUDE_PLUGIN_ROOT

  ELIF args contains "--discovery-only":
    computed.mode = "plugin"
    computed.discovery_only = true
    computed.target_path = CLAUDE_PLUGIN_ROOT

  ELIF args is a bare path:
    # Determine if path points to a skill or plugin root
    IF path_contains_skill_md(args):
      computed.mode = "single"
      computed.target_path = args
    ELIF path_contains_skills_dir(args):
      computed.mode = "plugin"
      computed.target_path = args
    ELSE:
      computed.mode = null  # Will prompt

  ELSE:
    computed.mode = null  # Will prompt
```

### Step 1.2: Prompt if Needed

If mode was not determined from arguments, ask the user:

```json
{
  "questions": [{
    "question": "What would you like to assess?",
    "header": "Assessment Scope",
    "multiSelect": false,
    "options": [
      {
        "label": "A single skill",
        "description": "Assess one skill's coverage position, complexity, and fit"
      },
      {
        "label": "The entire plugin",
        "description": "Assess all skills — inventory, coverage distribution, and health"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_SCOPE(response):
  SWITCH response:
    CASE "A single skill":
      computed.mode = "single"
      # Follow up to get path (Step 1.3)
    CASE "The entire plugin":
      computed.mode = "plugin"
      computed.target_path = CLAUDE_PLUGIN_ROOT
```

### Step 1.3: Resolve Skill Path (Single-Skill Mode)

If `computed.mode == "single"` and `computed.target_path` is not set:

```json
{
  "questions": [{
    "question": "Which skill should I assess?",
    "header": "Target Skill",
    "multiSelect": false,
    "options": [
      {"label": "Provide path", "description": "I'll give you the skill directory or SKILL.md path"},
      {"label": "Search current plugin", "description": "Look for skills in this plugin's skills/ directory"}
    ]
  }]
}
```

If "Search current plugin" is selected:

```pseudocode
SEARCH_PLUGIN_SKILLS():
  candidates = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
  # Present as AskUserQuestion with each skill name as an option
  computed.target_path = selected_candidate_path
```

Store the resolved path in `computed.target_path` and the SKILL.md content in
`computed.skill_content`.

---

## Phase 2: Discover

Locate and parse skill files. The path diverges based on `computed.mode`.

### Step 2.1: Single-Skill Discovery

If `computed.mode == "single"`:

1. Resolve whether `computed.target_path` is a directory (containing SKILL.md) or a SKILL.md
   file directly
2. Read the SKILL.md content
3. Parse YAML frontmatter

```pseudocode
DISCOVER_SINGLE():
  IF is_directory(computed.target_path):
    computed.skill_path = computed.target_path + "/SKILL.md"
  ELSE:
    computed.skill_path = computed.target_path

  computed.skill_content = Read(computed.skill_path)
  computed.skill_dir = parent_directory(computed.skill_path)
  computed.skill_name = basename(computed.skill_dir)

  # Parse frontmatter
  frontmatter = content between first "---" and second "---"
  parsed = parse_yaml(frontmatter)

  computed.frontmatter = {
    name: parsed.name,
    description: parsed.description,
    allowed_tools: split(parsed["allowed-tools"], ", "),
    inputs_defined: "inputs" IN parsed AND len(parsed.inputs) > 0,
    outputs_defined: "outputs" IN parsed AND len(parsed.outputs) > 0,
    inputs: parsed.inputs OR [],
    outputs: parsed.outputs OR []
  }

  # Discover workflow files
  workflow_files = Glob(computed.skill_dir + "/workflows/*.yaml")
  legacy_workflow = file_exists(computed.skill_dir + "/workflow.yaml")

  computed.workflow_files = workflow_files
  computed.has_workflows_dir = len(workflow_files) > 0
  computed.has_legacy_workflow = legacy_workflow
```

### Step 2.2: Plugin-Wide Discovery

If `computed.mode == "plugin"`:

Scan for all SKILL.md files and parse each. Uses the same classification logic documented in
`patterns/classification-algorithm.md`.

```pseudocode
DISCOVER_PLUGIN():
  skill_files = Glob(computed.target_path + "/skills/*/SKILL.md")

  IF len(skill_files) == 0:
    DISPLAY "No SKILL.md files found in " + computed.target_path + "/skills/"
    DISPLAY "Verify the path and try again."
    EXIT

  computed.skills = []

  FOR file IN skill_files:
    directory = parent_directory(file.path)
    name = basename(directory)
    content = Read(file.path)

    # Parse frontmatter
    frontmatter = extract_frontmatter(content)

    # Check for workflow files
    workflow_files = Glob(directory + "/workflows/*.yaml")
    has_workflows_dir = len(workflow_files) > 0
    has_legacy_workflow = file_exists(directory + "/workflow.yaml")

    computed.skills.append({
      name: name,
      path: file.path,
      directory: directory,
      content: content,
      frontmatter: frontmatter,
      workflow_files: workflow_files,
      has_workflows_dir: has_workflows_dir,
      has_legacy_workflow: has_legacy_workflow,
      inputs_defined: "inputs" IN frontmatter AND len(frontmatter.inputs) > 0,
      outputs_defined: "outputs" IN frontmatter AND len(frontmatter.outputs) > 0,
      legacy_layout: has_legacy_workflow AND NOT has_workflows_dir,
      line_count: count_lines(content)
    })

  computed.discovery = {
    timestamp: current_iso_timestamp(),
    plugin_path: computed.target_path,
    total_skills: len(computed.skills)
  }
```

If `computed.discovery_only == true`, skip to Phase 5 (Report) after discovery completes —
display the inventory table and exit.

---

## Phase 3: Classify

Analyze structure and classify coverage. Path diverges based on scope.

### Step 3.1: Single-Skill Classification

If `computed.mode == "single"`:

**Identify phases** using the algorithm in `patterns/phase-detection-algorithm.md`:

```pseudocode
CLASSIFY_SINGLE():
  body = content_after_frontmatter(computed.skill_content)

  # Detect phases
  computed.phases = []
  FOR line_num, line IN enumerate(body_lines):
    confidence = detect_phase_marker(line)
    IF confidence:
      phase = {
        id: slugify(extracted_title),
        title: extracted_title,
        prose_location: "lines {start}-{end}",
        confidence: confidence
      }
      computed.phases.append(phase)

  IF len(computed.phases) == 0:
    computed.phases = [{
      id: "main",
      title: "Main",
      prose_location: "lines 1-{total}",
      confidence: "low"
    }]

  # Classify each phase as prose or workflow-backed
  FOR phase IN computed.phases:
    phase_content = get_lines(body, phase.prose_location)
    workflow_refs = find_patterns(phase_content, [
      /Execute\s+`?workflows\/[^`]+\.yaml`?/,
      /Run\s+`?workflows\/[^`]+\.yaml`?/,
      /workflow\.yaml/
    ])
    IF len(workflow_refs) > 0:
      phase.type = "workflow"
      phase.workflow_file = extract_workflow_filename(workflow_refs[0])
    ELSE:
      phase.type = "prose"

  # Classify coverage
  prose_count = count(p for p in computed.phases if p.type == "prose")
  workflow_count = count(p for p in computed.phases if p.type == "workflow")

  IF workflow_count == 0:
    computed.coverage = "prose"
  ELIF prose_count == 0:
    computed.coverage = "full"
  ELSE:
    computed.coverage = "partial"
```

**Per-phase complexity** using `patterns/complexity-scoring-algorithm.md`:

```pseudocode
ANALYZE_PHASE_COMPLEXITY():
  FOR phase IN computed.phases:
    IF phase.type == "prose":
      content = get_lines(body, phase.prose_location)

      phase.conditionals = count_patterns(content, [
        /If\s+.*then/i, /When\s+/i, /Based on/i,
        /Depending on/i, /Unless/i, /Either.*or/i
      ])
      phase.tool_calls = count_tool_references(content)
      phase.tools_used = extract_unique_tools(content)
      phase.user_interactions = count_patterns(content, [
        /AskUserQuestion/i, /ask.*user/i, /prompt.*user/i
      ])
      phase.state_variables = count_unique_patterns(content, [
        /computed\.\w+/, /\$\{[^}]+\}/
      ])
      phase.prose_lines = count_non_empty_lines(content)

      # Complexity classification
      factors = {
        conditionals: classify(phase.conditionals, [1, 4]),
        tool_variety: classify(len(phase.tools_used), [2, 4]),
        user_interactions: classify(phase.user_interactions, [1, 3]),
        state_variables: classify(phase.state_variables, [3, 7]),
        prose_lines: classify(phase.prose_lines, [30, 80])
      }
      avg = mean(factors.values)
      IF avg < 1.5: phase.complexity = "low"
      ELIF avg <= 2.5: phase.complexity = "medium"
      ELSE: phase.complexity = "high"

    ELIF phase.type == "workflow" AND phase.workflow_data:
      phase.node_count = count_nodes(phase.workflow_data.content)
      phase.branch_depth = compute_branch_depth(phase.workflow_data.content)
      IF phase.node_count <= 5 AND phase.branch_depth <= 1:
        phase.complexity = "low"
      ELIF phase.node_count <= 12 AND phase.branch_depth <= 2:
        phase.complexity = "medium"
      ELSE:
        phase.complexity = "high"

  # Aggregate complexity
  complexity_values = { "low": 1, "medium": 2, "high": 3, "unknown": 2 }
  scores = [complexity_values[p.complexity] for p in computed.phases]
  avg = mean(scores)
  IF avg < 1.5: computed.aggregate_complexity = "low"
  ELIF avg <= 2.5: computed.aggregate_complexity = "medium"
  ELSE: computed.aggregate_complexity = "high"
```

### Step 3.2: Plugin-Wide Classification

If `computed.mode == "plugin"`:

Classify each skill and compute cross-skill metrics. Uses algorithms from
`patterns/classification-algorithm.md`, `patterns/health-scoring-algorithm.md`, and
`patterns/cross-skill-metrics.md`.

```pseudocode
CLASSIFY_PLUGIN():
  FOR skill IN computed.skills:
    # Detect phases
    body = content_after_frontmatter(skill.content)
    phases = detect_phases(body)
    workflow_backed = count_workflow_backed_phases(body, skill)
    total_phases = len(phases)

    IF total_phases == 0 OR workflow_backed == 0:
      skill.coverage = "prose"
    ELIF workflow_backed == total_phases:
      skill.coverage = "full"
    ELSE:
      skill.coverage = "partial"

    skill.phase_count = total_phases
    skill.workflow_phases = workflow_backed
    skill.prose_phases = total_phases - workflow_backed

    # Per-skill metrics
    skill.metrics = {
      line_count: skill.line_count,
      section_count: count_matches(skill.content, /^##+ /m),
      phase_count: total_phases,
      workflow_phases: workflow_backed,
      prose_phases: total_phases - workflow_backed,
      conditional_count: count_matches(skill.content, /\b(if|when|otherwise|based on|depending on)\b/i),
      user_prompts: count_matches(skill.content, /"questions"\s*:\s*\[/) + count_matches(skill.content, /AskUserQuestion/i),
      tool_refs: count_unique_tools(skill.content)
    }

    # Per-skill complexity
    IF skill.metrics.line_count > 300 AND skill.metrics.conditional_count > 6:
      skill.complexity = "high"
    ELIF skill.metrics.line_count > 100 OR skill.metrics.conditional_count > 2:
      skill.complexity = "medium"
    ELSE:
      skill.complexity = "low"

  # Summary counts
  computed.discovery.summary = {
    prose: count(s for s in computed.skills if s.coverage == "prose"),
    partial: count(s for s in computed.skills if s.coverage == "partial"),
    full: count(s for s in computed.skills if s.coverage == "full")
  }

  # Cross-skill metrics (see patterns/cross-skill-metrics.md)
  computed.cross_skill = {
    total_skills: len(computed.skills),
    total_line_count: sum(s.line_count for s in computed.skills),
    avg_line_count: mean(s.line_count for s in computed.skills),
    total_phases: sum(s.phase_count for s in computed.skills),
    coverage_distribution: computed.discovery.summary,
    complexity_distribution: {
      low: count(s for s in computed.skills if s.complexity == "low"),
      medium: count(s for s in computed.skills if s.complexity == "medium"),
      high: count(s for s in computed.skills if s.complexity == "high")
    },
    completeness: {
      inputs_defined: count(s for s in computed.skills if s.inputs_defined),
      outputs_defined: count(s for s in computed.skills if s.outputs_defined),
      legacy_layout: count(s for s in computed.skills if s.legacy_layout)
    }
  }
```

---

## Phase 4: Fit Analysis

**This is the key phase.** For each assessed skill, map its complexity against its current
formalization level to determine whether the position on the spectrum is appropriate.

**CRITICAL: This phase is NEUTRAL. No formalization level is inherently better. A high-complexity
prose skill may be perfectly appropriate if the author prefers prose orchestration. A low-complexity
fully-formalized skill may also be fine if the author wants workflow guarantees.**

### Step 4.1: Compute Fit (Single-Skill)

If `computed.mode == "single"`:

```pseudocode
COMPUTE_FIT_SINGLE():
  computed.fit = determine_fit(computed.coverage, computed.aggregate_complexity)

  computed.fit_analysis = {
    coverage_position: computed.coverage,
    aggregate_complexity: computed.aggregate_complexity,
    fit: computed.fit,
    rationale: computed.fit_rationale,
    options: computed.fit_options
  }
```

### Step 4.2: Compute Fit (Plugin-Wide)

If `computed.mode == "plugin"`:

```pseudocode
COMPUTE_FIT_PLUGIN():
  FOR skill IN computed.skills:
    skill.fit = determine_fit(skill.coverage, skill.complexity)
    skill.fit_rationale = get_rationale(skill.coverage, skill.complexity, skill.fit)
    skill.fit_options = get_options(skill.coverage, skill.complexity, skill.fit)
```

### Step 4.3: Fit Determination Algorithm

The fit algorithm is the same regardless of scope:

```pseudocode
function determine_fit(coverage, complexity):
  # ---- GOOD FIT cases ----
  # Low complexity + prose = perfectly fine as prose
  IF complexity == "low" AND coverage == "prose":
    return "good-fit"

  # Medium complexity + partial = reasonable middle ground
  IF complexity == "medium" AND coverage == "partial":
    return "good-fit"

  # High complexity + full = well-suited to workflow formalization
  IF complexity == "high" AND coverage == "full":
    return "good-fit"

  # Low complexity + full = author chose formalization, that's valid
  IF complexity == "low" AND coverage == "full":
    return "good-fit"

  # Medium complexity + prose = common and usually fine
  IF complexity == "medium" AND coverage == "prose":
    return "good-fit"

  # ---- POTENTIAL MISMATCH cases ----
  # High complexity + prose = may benefit from formalization, but author may prefer prose
  IF complexity == "high" AND coverage == "prose":
    return "potential-mismatch"

  # High complexity + partial = some formalized, some not — may want consistency
  IF complexity == "high" AND coverage == "partial":
    return "potential-mismatch"

  # ---- DEFAULT ----
  # Any remaining combinations
  return "good-fit"


function get_rationale(coverage, complexity, fit):
  SWITCH fit:
    CASE "good-fit":
      return "The skill's complexity ({complexity}) aligns with its current coverage " +
             "level ({coverage}). No action needed unless you have a specific reason to change."

    CASE "potential-mismatch":
      IF complexity == "high" AND coverage == "prose":
        return "This skill has high complexity ({conditionals} conditionals, " +
               "{phases} phases) but relies entirely on prose orchestration. " +
               "This works but may be harder to maintain as complexity grows."
      IF complexity == "high" AND coverage == "partial":
        return "This skill has high complexity with mixed coverage — some phases " +
               "are workflow-backed and some are prose. Consider whether the split " +
               "is intentional or an artifact of incremental development."

    CASE "review-recommended":
      return "Significant divergence between complexity and formalization level. " +
             "Review whether the current approach still serves your needs."


function get_options(coverage, complexity, fit):
  options = []

  # Always offer "no action" as a valid choice
  options.append({
    action: "no-change",
    description: "Keep the current approach — no changes needed"
  })

  IF coverage == "prose" AND complexity IN ("medium", "high"):
    options.append({
      action: "enhance",
      description: "Add structure (pseudocode blocks, decision tables) while staying prose",
      journey_skill: "bp-enhance"
    })
    options.append({
      action: "extract",
      description: "Extract high-complexity phases into workflow definitions",
      journey_skill: "bp-extract"
    })

  IF coverage == "partial":
    options.append({
      action: "enhance",
      description: "Improve the prose phases with better structure",
      journey_skill: "bp-enhance"
    })
    options.append({
      action: "extract",
      description: "Extract remaining prose phases into workflows for consistency",
      journey_skill: "bp-extract"
    })

  IF coverage == "full":
    options.append({
      action: "maintain",
      description: "Run validation and health checks on existing workflows",
      journey_skill: "bp-maintain"
    })

  return options
```

---

## Phase 5: Report

Display findings to the user. Format depends on scope.

### Step 5.1: Single-Skill Report

If `computed.mode == "single"`:

```
## Assessment: {computed.skill_name}

**Path:** {computed.skill_path}
**Coverage Position:** {computed.coverage}
**Aggregate Complexity:** {computed.aggregate_complexity}
**Fit:** {computed.fit}

---

### Frontmatter

| Field | Status |
|-------|--------|
| Inputs defined | {yes/no} ({count}) |
| Outputs defined | {yes/no} ({count}) |
| Allowed tools | {list} |

### Phases ({count})

| # | Phase | Type | Complexity | Key Metrics |
|---|-------|------|------------|-------------|
{for i, phase in enumerate(computed.phases)}
| {i+1} | {phase.title} | {phase.type} | {phase.complexity} | {metrics_summary} |
{/for}

### Coverage Position

This skill sits at **{computed.coverage}** on the coverage spectrum:

```
[prose] ----{marker}---- [partial] ------------ [full]
```

### Fit Analysis

**Fit:** {computed.fit}

{computed.fit_rationale}

### Options

These are neutral options — all are valid choices:

{for option in computed.fit_options}
- **{option.action}**: {option.description}
  {if option.journey_skill}→ Use `{option.journey_skill}` to proceed{/if}
{/for}
```

### Step 5.2: Plugin-Wide Report

If `computed.mode == "plugin"`:

```
## Plugin Assessment: {basename(computed.target_path)}

**Path:** {computed.target_path}
**Skills found:** {computed.discovery.total_skills}
**Timestamp:** {computed.discovery.timestamp}

---

### Inventory

| # | Skill | Coverage | Phases | Complexity | Fit | I/O | Lines |
|---|-------|----------|--------|------------|-----|-----|-------|
{for i, skill in enumerate(computed.skills)}
| {i+1} | {skill.name} | {skill.coverage} | {skill.phase_count} | {skill.complexity} | {skill.fit} | {skill.inputs_defined}/{skill.outputs_defined} | {skill.line_count} |
{/for}

### Coverage Distribution

| Position | Count | Skills |
|----------|-------|--------|
| prose | {count_prose} | {comma_separated_names} |
| partial | {count_partial} | {comma_separated_names} |
| full | {count_full} | {comma_separated_names} |

### Fit Summary

| Fit | Count | Skills |
|-----|-------|--------|
| good-fit | {count} | {names} |
| potential-mismatch | {count} | {names} |
| review-recommended | {count} | {names} |

### Cross-Skill Metrics

| Metric | Value |
|--------|-------|
| Total skills | {computed.cross_skill.total_skills} |
| Total lines | {computed.cross_skill.total_line_count} |
| Avg lines/skill | {computed.cross_skill.avg_line_count} |
| Total phases | {computed.cross_skill.total_phases} |
| Inputs defined | {computed.cross_skill.completeness.inputs_defined}/{total} |
| Outputs defined | {computed.cross_skill.completeness.outputs_defined}/{total} |
| Legacy layout | {computed.cross_skill.completeness.legacy_layout} |

### Health Dashboard

Health score computed per `patterns/health-scoring-algorithm.md`:

| Category | Score | Weight | Weighted |
|----------|-------|--------|----------|
| Coverage balance | {score}/100 | 20% | {weighted} |
| Completeness | {score}/100 | 20% | {weighted} |
| Complexity distribution | {score}/100 | 15% | {weighted} |
| Fit alignment | {score}/100 | 25% | {weighted} |
| Consistency | {score}/100 | 20% | {weighted} |
| **Overall** | | | **{total}/100** |

### Skills with Potential Mismatches

{if any skills have fit != "good-fit"}
These skills have divergent complexity vs formalization — review whether the current level
serves your needs:

{for skill in computed.skills where skill.fit != "good-fit"}
- **{skill.name}** ({skill.coverage} / {skill.complexity}) — {skill.fit_rationale}
{/for}
{else}
All skills show good fit between complexity and formalization level.
{/if}
```

### Step 5.3: Batch Mode Continuation

If `computed.batch_op` is set, after displaying the plugin-wide report, continue to batch
execution using the protocol in `patterns/batch-execution-protocol.md`:

```pseudocode
BATCH_CONTINUATION():
  IF computed.batch_op IS NOT null:
    DISPLAY "Proceeding to batch operation: " + computed.batch_op
    # Filter skills to those applicable to the batch operation
    # Execute batch with progress tracking per batch-execution-protocol.md
    # Display aggregated batch results
```

---

## Phase 6: Offer Next Actions

Present journey-oriented next steps based on the assessment findings.

### Step 6.1: Next Actions (Single-Skill)

If `computed.mode == "single"`:

```json
{
  "questions": [{
    "question": "Assessment complete. What would you like to do?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {"label": "No changes needed", "description": "The current approach is fine"},
      {"label": "Enhance this skill", "description": "Improve structure while keeping prose (bp-enhance)"},
      {"label": "Extract to workflows", "description": "Formalize high-complexity phases (bp-extract)"},
      {"label": "Assess another skill", "description": "Run assessment on a different skill"},
      {"label": "Assess the full plugin", "description": "Switch to plugin-wide assessment"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_SINGLE(response):
  SWITCH response:
    CASE "No changes needed":
      DISPLAY "Assessment complete. No further action."
      EXIT

    CASE "Enhance this skill":
      DISPLAY "To enhance this skill, invoke:"
      DISPLAY "  bp-enhance --skill " + computed.skill_path
      DISPLAY ""
      DISPLAY "bp-enhance will help add structure (pseudocode, decision tables,"
      DISPLAY "pattern references) while keeping the prose orchestration approach."

    CASE "Extract to workflows":
      DISPLAY "To extract workflow definitions, invoke:"
      DISPLAY "  bp-extract --skill " + computed.skill_path
      DISPLAY ""
      DISPLAY "bp-extract will identify phases suitable for workflow extraction"
      DISPLAY "and generate workflow YAML files."

    CASE "Assess another skill":
      # Reset state and restart
      GOTO Phase 1, Step 1.3

    CASE "Assess the full plugin":
      computed.mode = "plugin"
      computed.target_path = CLAUDE_PLUGIN_ROOT
      GOTO Phase 2, Step 2.2
```

### Step 6.2: Next Actions (Plugin-Wide)

If `computed.mode == "plugin"`:

```json
{
  "questions": [{
    "question": "Plugin assessment complete. What would you like to do?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {"label": "Assess a specific skill", "description": "Deep-dive into one skill from the inventory"},
      {"label": "Enhance skills", "description": "Improve prose skills with better structure (bp-enhance)"},
      {"label": "Extract workflows", "description": "Formalize high-complexity prose phases (bp-extract)"},
      {"label": "Run maintenance", "description": "Validate and health-check existing workflows (bp-maintain)"},
      {"label": "Export report", "description": "Save the assessment to a file"},
      {"label": "Done", "description": "No further action needed"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_PLUGIN(response):
  SWITCH response:
    CASE "Assess a specific skill":
      # Present skills as selection options
      options = [{ label: s.name, description: s.coverage + " / " + s.complexity }
                 for s in computed.skills]
      # After selection:
      computed.mode = "single"
      computed.target_path = selected_skill.path
      GOTO Phase 2, Step 2.1

    CASE "Enhance skills":
      candidates = [s for s in computed.skills if s.coverage == "prose"]
      IF len(candidates) > 0:
        DISPLAY "Prose skills that could be enhanced:"
        FOR c IN candidates:
          DISPLAY "  - " + c.name + " (" + c.complexity + " complexity)"
        DISPLAY ""
        DISPLAY "Invoke bp-enhance on a specific skill to proceed."
      ELSE:
        DISPLAY "No prose-only skills found in this plugin."

    CASE "Extract workflows":
      candidates = [s for s in computed.skills
                    if s.coverage IN ("prose", "partial") AND s.complexity IN ("medium", "high")]
      IF len(candidates) > 0:
        DISPLAY "Skills where extraction may be worth considering:"
        FOR c IN candidates:
          DISPLAY "  - " + c.name + " (" + c.coverage + " / " + c.complexity + ")"
        DISPLAY ""
        DISPLAY "Invoke bp-extract on a specific skill to proceed."
      ELSE:
        DISPLAY "No skills currently flagged for extraction consideration."

    CASE "Run maintenance":
      candidates = [s for s in computed.skills if s.coverage IN ("partial", "full")]
      IF len(candidates) > 0:
        DISPLAY "Skills with workflows that can be maintained:"
        FOR c IN candidates:
          DISPLAY "  - " + c.name + " (" + c.coverage + ")"
        DISPLAY ""
        DISPLAY "Invoke bp-maintain to run validation and health checks."
      ELSE:
        DISPLAY "No workflow-backed skills found."

    CASE "Export report":
      default_path = computed.target_path + "/docs/assessment-report.md"
      report_content = assemble_report(computed)
      Write(default_path, report_content)
      DISPLAY "Assessment report saved to " + default_path

    CASE "Done":
      DISPLAY "Assessment complete. " + str(computed.discovery.total_skills) + " skills inventoried."
      EXIT
```

---

## State Flow

```
Phase 1          Phase 2           Phase 3              Phase 4          Phase 5        Phase 6
────────────────────────────────────────────────────────────────────────────────────────────────
computed.mode -> computed.skills  -> computed.coverage -> computed.fit -> Report      -> Handoff
computed         computed           computed.phases      computed         (displayed)    (bp-enhance,
.target_path     .frontmatter       computed.aggregate   .fit_analysis                   bp-extract,
computed         computed             _complexity        computed                        bp-maintain,
.batch_op        .discovery         computed.cross_skill .fit_options                    bp-build)
computed         computed
.discovery_only  .skill_content
```

---

## Reference Documentation

- **Phase Detection Algorithm:** `patterns/phase-detection-algorithm.md` (local)
- **Complexity Scoring Algorithm:** `patterns/complexity-scoring-algorithm.md` (local)
- **Quality Indicators:** `patterns/quality-indicators.md` (local)
- **Analysis Output Schema:** `patterns/analysis-output-schema.md` (local)
- **Classification Algorithm:** `patterns/classification-algorithm.md` (local)
- **Health Scoring Algorithm:** `patterns/health-scoring-algorithm.md` (local)
- **Cross-Skill Metrics:** `patterns/cross-skill-metrics.md` (local)
- **Batch Execution Protocol:** `patterns/batch-execution-protocol.md` (local)
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

---

## Related Skills

- **Enhance skill structure:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-enhance/SKILL.md`
- **Extract to workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-extract/SKILL.md`
- **Maintain workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/SKILL.md`
- **Build new skills:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
- **Visualize workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
