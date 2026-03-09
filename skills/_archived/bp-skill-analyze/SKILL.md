---
name: bp-skill-analyze
description: >
  This skill should be used when the user asks to "analyze a skill", "examine skill structure",
  "skill metrics", "assess skill quality", "skill complexity", "review skill",
  "check skill coverage", "what does this skill do", or needs to understand an existing
  skill's structure, coverage, and quality. Triggers on "analyze skill", "skill analysis",
  "skill quality", "skill metrics", "examine skill", "review skill", "coverage report".
allowed-tools: Read, Glob, Grep, AskUserQuestion
inputs:
  - name: skill_path
    type: string
    required: false
    description: Path to the skill directory or SKILL.md (prompted if not provided)
outputs:
  - name: analysis
    type: object
    description: Complete analysis including coverage, phases, complexity, quality, and recommendations
---

# Analyze Skill Structure & Quality

Unified analysis for any skill — examines the SKILL.md orchestrator, identifies phases
(prose and workflow-backed), classifies coverage, assesses per-phase complexity, evaluates
workflow quality, and identifies workflow extraction candidates.

> **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
> **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`

---

## Overview

This skill produces a comprehensive analysis containing:

| Category | What It Measures |
|----------|-----------------|
| Phase identification | Major execution stages — prose and workflow-backed |
| Coverage classification | `none` / `partial` / `full` — how much is formalized |
| Per-phase complexity | Conditionals, tool variety, user interactions, state variables per phase |
| Workflow quality | Node metrics, error handling, naming, anti-patterns (for workflow phases) |
| Extraction candidates | Prose phases that would benefit from workflow formalization |
| Inputs/outputs completeness | Whether frontmatter declares inputs and outputs |
| Recommendations | Prioritized improvements across all dimensions |

The output `computed.analysis` follows the schema defined in
`${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`.

---

## Phase 1: Locate Skill

### Step 1.1: Determine Target Skill

If user provided a path in the invocation arguments:
1. Resolve whether it's a directory (containing SKILL.md) or a SKILL.md file directly
2. Read the SKILL.md content
3. Store in `computed.skill_content` and `computed.skill_path`

If no path was provided:

```json
{
  "questions": [{
    "question": "Which skill would you like me to analyze?",
    "header": "Target",
    "multiSelect": false,
    "options": [
      {"label": "Provide path", "description": "I'll give you the skill directory or SKILL.md path"},
      {"label": "Search current plugin", "description": "Look for skills in this repo"},
      {"label": "Search installed plugins", "description": "Find installed Claude Code skills"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_TARGET(response):
  SWITCH response:
    CASE "Provide path":
      # Ask for path via follow-up prompt
      computed.skill_path = resolve_skill_path(user_provided_path)

    CASE "Search current plugin":
      candidates = Glob("skills/*/SKILL.md")
      # Present candidates as selection
      computed.skill_path = selected_candidate

    CASE "Search installed plugins":
      candidates = Glob("~/.claude/skills/*/SKILL.md")
      candidates += Glob(".claude-plugin/skills/*/SKILL.md")
      computed.skill_path = selected_candidate
```

### Step 1.2: Parse Frontmatter

Extract from the SKILL.md YAML frontmatter:

```pseudocode
PARSE_FRONTMATTER():
  frontmatter = content between first "---" and second "---"
  parsed = parse_yaml(frontmatter)

  computed.frontmatter = {
    name: parsed.name,
    description: parsed.description,
    allowed_tools: split(parsed["allowed-tools"], ", "),
    inputs_defined: "inputs" IN parsed AND len(parsed.inputs) > 0,
    outputs_defined: "outputs" IN parsed AND len(parsed.outputs) > 0,
    inputs: parsed.inputs OR [],
    outputs: parsed.outputs OR [],
    workflows_declared: parsed.workflows OR []
  }

  computed.skill_name = parsed.name
```

If frontmatter is missing or malformed, warn but continue using filename as fallback.

### Step 1.3: Discover Workflow Files

Check for workflow files in the skill's `workflows/` subdirectory and verify they match
the frontmatter declarations:

```pseudocode
DISCOVER_WORKFLOWS():
  skill_dir = parent_directory(computed.skill_path)

  # Check for workflows/ subdirectory
  workflow_files = Glob(skill_dir + "/workflows/*.yaml")

  # Also check for legacy layout (bare workflow.yaml at skill root)
  legacy_workflow = Glob(skill_dir + "/workflow.yaml")

  computed.workflow_files = []

  FOR wf_path IN workflow_files:
    content = Read(wf_path)
    computed.workflow_files.append({
      path: wf_path,
      filename: basename(wf_path),
      content: content,
      name: extract_field(content, "name"),
      layout: "modern"    # workflows/ subdirectory
    })

  FOR wf_path IN legacy_workflow:
    content = Read(wf_path)
    computed.workflow_files.append({
      path: wf_path,
      filename: basename(wf_path),
      content: content,
      name: extract_field(content, "name"),
      layout: "legacy"    # bare workflow.yaml at skill root
    })

  # Check declared vs actual
  declared = set(computed.frontmatter.workflows_declared)
  actual = set(wf.path for wf in computed.workflow_files)

  computed.workflow_consistency = {
    declared_count: len(declared),
    actual_count: len(actual),
    missing: declared - actual,      # Declared but not on disk
    undeclared: actual - declared     # On disk but not in frontmatter
  }
```

---

## Phase 2: Phase Identification

### Step 2.1: Identify Phases

Scan the SKILL.md body (after frontmatter) for phase boundaries:

| Pattern | Example | Confidence |
|---------|---------|------------|
| Numbered heading | `## Phase 1: Initialize` | High |
| Phase/Stage keyword | `### Phase: Validation` | High |
| Sequential numbering | `1. First...`, `2. Then...` | Medium |
| Temporal markers | `First`, `Next`, `Finally` | Medium |

```pseudocode
IDENTIFY_PHASES():
  computed.phases = []
  body = content_after_frontmatter(computed.skill_content)

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
    # Treat entire body as single phase
    computed.phases = [{
      id: "main",
      title: "Main",
      prose_location: "lines 1-{total}",
      confidence: "low"
    }]
```

### Step 2.2: Classify Phase Types

For each phase, determine whether it's prose-driven or workflow-backed:

```pseudocode
CLASSIFY_PHASES():
  FOR phase IN computed.phases:
    phase_content = get_lines(body, phase.prose_location)

    # Check for workflow delegation markers
    workflow_refs = find_patterns(phase_content, [
      /Execute\s+`?workflows\/[^`]+\.yaml`?/,
      /Run\s+`?workflows\/[^`]+\.yaml`?/,
      /workflow\.yaml/,
      /execution guide.*Init.*Execute.*Complete/
    ])

    IF len(workflow_refs) > 0:
      phase.type = "workflow"
      phase.workflow_file = extract_workflow_filename(workflow_refs[0])
      # Find matching workflow in computed.workflow_files
      match = find(computed.workflow_files, wf => wf.filename == phase.workflow_file)
      IF match:
        phase.workflow_data = match
    ELSE:
      phase.type = "prose"
```

### Step 2.3: Classify Coverage

```pseudocode
CLASSIFY_COVERAGE():
  prose_count = count(p for p in computed.phases if p.type == "prose")
  workflow_count = count(p for p in computed.phases if p.type == "workflow")

  IF workflow_count == 0:
    computed.coverage = "none"
  ELIF prose_count == 0:
    computed.coverage = "full"
  ELSE:
    computed.coverage = "partial"
```

---

## Phase 3: Per-Phase Analysis

### Step 3.1: Analyze Prose Phases

For each prose phase, extract structural information:

```pseudocode
ANALYZE_PROSE_PHASE(phase):
  content = get_lines(body, phase.prose_location)

  # Count conditionals
  phase.conditionals = count_patterns(content, [
    /If\s+.*then/i, /When\s+/i, /Based on/i,
    /Depending on/i, /Unless/i, /Either.*or/i
  ])

  # Count tool references
  phase.tool_calls = 0
  phase.tools_used = set()
  FOR tool, patterns IN TOOL_PATTERNS:
    hits = count_patterns(content, patterns)
    IF hits > 0:
      phase.tool_calls += hits
      phase.tools_used.add(tool)

  # Count user interactions
  phase.user_interactions = count_patterns(content, [
    /AskUserQuestion/i, /ask.*user/i, /prompt.*user/i,
    /get.*input/i, /confirm.*with.*user/i
  ])

  # Count state variables
  phase.state_variables = count_unique_patterns(content, [
    /computed\.\w+/, /\$\{[^}]+\}/, /state\.\w+/
  ])

  # Lines of prose
  phase.prose_lines = count_non_empty_lines(content)

  # Assess complexity
  phase.complexity = assess_prose_complexity(phase)

  # Calculate extraction score
  phase.extraction_score = calculate_extraction_score(phase)
  phase.extraction_recommendation = recommend_extraction(phase.extraction_score)
```

**Extraction scoring (from skill-analysis.md pattern):**

```pseudocode
function calculate_extraction_score(phase):
  score = 0
  IF phase.conditionals >= 5: score += 3
  ELIF phase.conditionals >= 3: score += 2
  # FSM-like state transitions
  IF has_fsm_pattern(phase): score += 3
  # Loop with break condition
  IF has_loop_pattern(phase): score += 2
  # Multiple user prompts with branching
  IF phase.user_interactions >= 2: score += 2
  # Validation gate pattern (multiple assertions)
  IF has_validation_pattern(phase): score += 2
  # Linear tool call sequence only
  IF phase.conditionals == 0 AND phase.tool_calls > 0: score += 1
  RETURN score

function recommend_extraction(score):
  IF score <= 2: RETURN "leave_as_prose"
  IF score <= 4: RETURN "consider_extraction"
  RETURN "strong_candidate"
```

**Prose complexity assessment:**

```pseudocode
function assess_prose_complexity(phase):
  factors = {
    conditionals: classify(phase.conditionals, [1, 4]),      # 0-1=low, 2-4=med, 5+=high
    tool_variety: classify(len(phase.tools_used), [2, 4]),
    user_interactions: classify(phase.user_interactions, [1, 3]),
    state_variables: classify(phase.state_variables, [3, 7]),
    prose_lines: classify(phase.prose_lines, [30, 80])
  }
  avg = mean(factors.values)
  IF avg < 1.5: RETURN "low"
  IF avg <= 2.5: RETURN "medium"
  RETURN "high"
```

### Step 3.2: Analyze Workflow Phases

For each workflow-backed phase, extract metrics from the workflow YAML:

```pseudocode
ANALYZE_WORKFLOW_PHASE(phase):
  wf = phase.workflow_data
  IF wf IS NULL:
    phase.complexity = "unknown"
    phase.warnings = ["Workflow file not found"]
    RETURN

  content = wf.content

  # Node counts
  phase.node_count = count_nodes(content)
  phase.node_types = count_nodes_by_type(content)

  # Branch depth (DFS through graph)
  phase.branch_depth = compute_branch_depth(content)

  # Cyclomatic complexity
  edges = count_edges(content)
  nodes_plus_endings = phase.node_count + count_endings(content)
  phase.cyclomatic_complexity = edges - nodes_plus_endings + 2

  # Quality metrics
  phase.description_coverage = check_description_coverage(content)
  phase.error_handling_coverage = check_error_handling(content)
  phase.naming_consistency = check_naming(content)

  # Anti-patterns
  phase.anti_patterns = detect_anti_patterns(content)

  # Complexity classification
  phase.complexity = assess_workflow_complexity(phase)
```

**Workflow complexity assessment:**

```pseudocode
function assess_workflow_complexity(phase):
  IF phase.node_count <= 5 AND phase.branch_depth <= 1: RETURN "low"
  IF phase.node_count <= 12 AND phase.branch_depth <= 2: RETURN "medium"
  RETURN "high"
```

---

## Phase 4: Aggregate Analysis

### Step 4.1: Compute Aggregate Complexity

```pseudocode
AGGREGATE_COMPLEXITY():
  complexity_values = { "low": 1, "medium": 2, "high": 3, "unknown": 2 }
  scores = [complexity_values[p.complexity] for p in computed.phases]
  avg = mean(scores)

  IF avg < 1.5: computed.aggregate_complexity = "low"
  ELIF avg <= 2.5: computed.aggregate_complexity = "medium"
  ELSE: computed.aggregate_complexity = "high"
```

### Step 4.2: Check Inputs/Outputs Completeness

```pseudocode
CHECK_IO_COMPLETENESS():
  computed.io_completeness = {
    inputs_defined: computed.frontmatter.inputs_defined,
    outputs_defined: computed.frontmatter.outputs_defined,
    input_count: len(computed.frontmatter.inputs),
    output_count: len(computed.frontmatter.outputs)
  }

  # Check if state variables suggest missing inputs
  all_state_refs = collect_state_references(computed.phases)
  possible_inputs = [ref for ref in all_state_refs if looks_like_input(ref)]
  computed.io_completeness.suggested_inputs = possible_inputs
```

### Step 4.3: Generate Recommendations

```pseudocode
GENERATE_RECOMMENDATIONS():
  computed.recommendations = []

  # Inputs/outputs
  IF NOT computed.frontmatter.inputs_defined:
    computed.recommendations.append({
      type: "add_inputs",
      priority: "medium",
      message: "Skill is missing inputs definition in frontmatter"
    })

  IF NOT computed.frontmatter.outputs_defined:
    computed.recommendations.append({
      type: "add_outputs",
      priority: "medium",
      message: "Skill is missing outputs definition in frontmatter"
    })

  # Workflow consistency
  IF len(computed.workflow_consistency.missing) > 0:
    computed.recommendations.append({
      type: "fix_missing_workflows",
      priority: "high",
      message: "Declared workflows not found on disk: " + join(computed.workflow_consistency.missing)
    })

  IF len(computed.workflow_consistency.undeclared) > 0:
    computed.recommendations.append({
      type: "declare_workflows",
      priority: "low",
      message: "Workflow files on disk not declared in frontmatter: " + join(computed.workflow_consistency.undeclared)
    })

  # Legacy layout
  legacy_workflows = [wf for wf in computed.workflow_files if wf.layout == "legacy"]
  IF len(legacy_workflows) > 0:
    computed.recommendations.append({
      type: "migrate_layout",
      priority: "medium",
      message: "Migrate from legacy layout (bare workflow.yaml) to workflows/ subdirectory"
    })

  # Extraction candidates
  FOR phase IN computed.phases:
    IF phase.type == "prose" AND phase.extraction_recommendation == "strong_candidate":
      computed.recommendations.append({
        type: "extract_workflow",
        priority: "medium",
        phase: phase.id,
        message: "Phase '" + phase.title + "' has extraction score "
          + str(phase.extraction_score) + " — strong candidate for workflow extraction"
      })
    ELIF phase.type == "prose" AND phase.extraction_recommendation == "consider_extraction":
      computed.recommendations.append({
        type: "extract_workflow",
        priority: "low",
        phase: phase.id,
        message: "Phase '" + phase.title + "' has extraction score "
          + str(phase.extraction_score) + " — consider extracting to workflow"
      })

  # Workflow quality issues
  FOR phase IN computed.phases:
    IF phase.type == "workflow" AND phase.workflow_data:
      IF phase.error_handling_coverage < 70:
        computed.recommendations.append({
          type: "improve_error_handling",
          priority: "high",
          phase: phase.id,
          message: "Workflow '" + phase.workflow_file + "' has low error handling coverage"
        })
      IF len(phase.anti_patterns) > 0:
        computed.recommendations.append({
          type: "fix_anti_patterns",
          priority: "medium",
          phase: phase.id,
          message: str(len(phase.anti_patterns)) + " anti-patterns in '" + phase.workflow_file + "'"
        })
```

---

## Phase 5: Generate Report

### Step 5.1: Assemble Analysis Output

Build the complete analysis structure matching the schema in `skill-analysis.md`:

```pseudocode
ASSEMBLE_ANALYSIS():
  computed.analysis = {
    skill_name: computed.skill_name,
    skill_path: computed.skill_path,

    frontmatter: computed.frontmatter,
    coverage: computed.coverage,

    phases: [
      {
        id: phase.id,
        title: phase.title,
        type: phase.type,
        prose_location: phase.prose_location,
        complexity: phase.complexity,
        # Prose phase fields:
        conditionals: phase.conditionals,
        tool_calls: phase.tool_calls,
        user_interactions: phase.user_interactions,
        extraction_score: phase.extraction_score,
        extraction_recommendation: phase.extraction_recommendation,
        # Workflow phase fields:
        workflow_file: phase.workflow_file,
        node_count: phase.node_count
      }
      FOR phase IN computed.phases
    ],

    aggregate_complexity: computed.aggregate_complexity,

    io_completeness: computed.io_completeness,
    workflow_consistency: computed.workflow_consistency,
    recommendations: computed.recommendations
  }
```

### Step 5.2: Display Human-Readable Report

```
## Skill Analysis: {computed.skill_name}

**Path:** {computed.skill_path}
**Coverage:** {computed.coverage}
**Aggregate Complexity:** {computed.aggregate_complexity}

---

### Frontmatter

| Field | Status |
|-------|--------|
| Inputs defined | {yes/no} ({count}) |
| Outputs defined | {yes/no} ({count}) |
| Workflows declared | {count} |
| Allowed tools | {list} |

### Phases ({count})

| # | Phase | Type | Complexity | Key Metrics |
|---|-------|------|------------|-------------|
{for phase in computed.phases}
| {phase.number} | {phase.title} | {phase.type} | {phase.complexity} | {metrics_summary} |
{/for}

### Extraction Candidates

{if any prose phases have extraction_score >= 3}
| Phase | Score | Recommendation | Signals |
|-------|-------|----------------|---------|
{for phase where extraction_score >= 3}
| {phase.title} | {phase.extraction_score} | {phase.extraction_recommendation} | {signals} |
{/for}
{else}
No prose phases meet the extraction threshold (score >= 3).
{/if}

### Workflow Quality (workflow-backed phases only)

{if any workflow phases}
| Workflow | Nodes | Branch Depth | CC | Descriptions | Error Handling | Anti-Patterns |
|----------|-------|--------------|----|-------------|----------------|---------------|
{for phase where type == "workflow"}
| {phase.workflow_file} | {phase.node_count} | {phase.branch_depth} | {phase.cyclomatic_complexity} | {phase.description_coverage}% | {phase.error_handling_coverage}% | {len(phase.anti_patterns)} |
{/for}
{else}
No workflow-backed phases to analyze.
{/if}

### Recommendations ({count})

{for i, rec in enumerate(computed.recommendations)}
{i+1}. **[{rec.priority}]** {rec.message}
{/for}
```

### Step 5.3: Offer Next Actions

```json
{
  "questions": [{
    "question": "Analysis complete. What would you like to do next?",
    "header": "Next",
    "multiSelect": false,
    "options": [
      {"label": "Extract workflow", "description": "Extract a prose phase into a workflow file"},
      {"label": "Validate workflows", "description": "Run full validation on existing workflow files"},
      {"label": "Save analysis", "description": "Save the analysis YAML to a file"},
      {"label": "Analyze another", "description": "Run analysis on a different skill"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_ACTION(response):
  SWITCH response:
    CASE "Extract workflow":
      extraction_candidates = [p for p in computed.phases
        if p.type == "prose" AND p.extraction_score >= 3]
      IF len(extraction_candidates) > 0:
        DISPLAY "Extraction candidates:"
        FOR c IN extraction_candidates:
          DISPLAY "  - " + c.title + " (score: " + str(c.extraction_score) + ")"
        DISPLAY ""
        DISPLAY "To extract, invoke:"
        DISPLAY "  Skill(skill: 'bp-workflow-extract', args: '{computed.skill_path}')"
      ELSE:
        DISPLAY "No prose phases meet the extraction threshold."

    CASE "Validate workflows":
      DISPLAY "To validate, invoke:"
      DISPLAY "  Skill(skill: 'bp-skill-validate', args: '{computed.skill_path}')"

    CASE "Save analysis":
      analysis_path = parent_directory(computed.skill_path) + "/analysis.yaml"
      Write(analysis_path, yaml_format(computed.analysis))
      DISPLAY "Analysis saved to " + analysis_path

    CASE "Analyze another":
      # Clear state and restart
      GOTO Phase 1, Step 1.1
```

---

## Reference Documentation

- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

---

## Related Skills

- Workflow extraction from prose phases: `${CLAUDE_PLUGIN_ROOT}/skills/bp-workflow-extract/SKILL.md`
- Skill validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/SKILL.md`
- Skill refactoring: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-refactor/SKILL.md`
- Plugin-level analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-analyze/SKILL.md`
- Workflow visualization: `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
