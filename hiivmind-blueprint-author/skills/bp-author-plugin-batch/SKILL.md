---
name: bp-author-plugin-batch
description: >
  This skill should be used when the user asks to "batch validate", "upgrade all skills",
  "validate all workflows", "batch operation", "apply to all skills", "bulk convert",
  or needs to run an operation across all skills in a plugin. Triggers on "batch",
  "validate all", "upgrade all", "bulk", "apply to all", "all skills", "batch operation".
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion
---

# Batch Plugin Operations

Apply a selected operation (validate, upgrade, analyze, visualize, or migrate) across all
skills in a plugin. Discovers skills via the `bp-author-plugin-discover` classification logic,
lets the user filter and select an error-handling mode, then executes the operation on each
skill with progress tracking and produces an aggregated report.

> **Batch Execution Protocol:** `patterns/batch-execution-protocol.md`
> **Classification Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/patterns/classification-algorithm.md`

---

## Overview

This skill orchestrates bulk operations across an entire plugin. Rather than invoking
individual skills one at a time, the user can batch-apply any of the following operations:

| Operation | What It Does | Applicable To |
|-----------|-------------|---------------|
| Validate | Run schema/graph/type/state checks on each workflow.yaml | `workflow`, `hybrid` |
| Upgrade | Detect version, apply schema migrations to each workflow.yaml | `workflow`, `hybrid` |
| Analyze | Compute quality metrics and complexity scores on each skill | `prose`, `hybrid` |
| Visualize | Generate Mermaid diagrams for each workflow.yaml | `workflow`, `hybrid` |
| Migrate | Convert prose skills to workflow format (analyze then migrate) | `prose` |

**Downstream skills invoked per-item:**

| Operation | Per-Skill Skill |
|-----------|----------------|
| Validate | `bp-author-skill-validate` |
| Upgrade | `bp-author-skill-upgrade` |
| Analyze | `bp-author-skill-analyze` / `bp-author-prose-analyze` |
| Visualize | `bp-author-visualize` |
| Migrate | `bp-author-prose-analyze` then `bp-author-prose-migrate` |

---

## Phase 1: Discover

Scan the plugin for all SKILL.md files and classify each one. This reuses the same logic
as `bp-author-plugin-discover`.

### Step 1.1: Get Skill Inventory

Locate all SKILL.md files across `skills/` and `skills-prose/` directories:

```pseudocode
DISCOVER_SKILLS():
  skill_files = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
  skill_files += Glob("${CLAUDE_PLUGIN_ROOT}/skills-prose/*/SKILL.md")

  computed.inventory = []

  FOR file IN skill_files:
    directory = parent_directory(file.path)
    name = basename(directory)
    content = Read(file.path)

    has_workflow = file_exists(directory + "/workflow.yaml")
    classification = classify_skill(content, has_workflow)
    # Classification uses the algorithm from:
    # ${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/patterns/classification-algorithm.md

    computed.inventory.append({
      name: name,
      path: file.path,
      directory: directory,
      classification: classification,
      has_workflow: has_workflow,
      line_count: count_lines(content)
    })
```

### Step 1.2: Display Summary Counts

Present a grouped summary so the user can see what they are working with:

```
## Plugin Skill Inventory

| Classification | Count | Skills |
|----------------|-------|--------|
| workflow | {count_workflow} | {comma_separated_names} |
| prose | {count_prose} | {comma_separated_names} |
| hybrid | {count_hybrid} | {comma_separated_names} |
| simple | {count_simple} | {comma_separated_names} |
| **Total** | **{total}** | |
```

Store the grouped counts in `computed.summary`:

```pseudocode
computed.summary = {
  workflow: [s for s in computed.inventory if s.classification == "workflow"],
  prose:    [s for s in computed.inventory if s.classification == "prose"],
  hybrid:   [s for s in computed.inventory if s.classification == "hybrid"],
  simple:   [s for s in computed.inventory if s.classification == "simple"]
}
```

---

## Phase 2: Select Operation

### Step 2.1: Choose Operation

Present the user with available operations via AskUserQuestion:

```json
{
  "questions": [{
    "question": "Which operation should I apply to the skills?",
    "header": "Operation",
    "multiSelect": false,
    "options": [
      {"label": "Validate (Recommended)", "description": "Run workflow validation on each skill"},
      {"label": "Upgrade", "description": "Upgrade each workflow to latest schema version"},
      {"label": "Analyze", "description": "Run quality analysis on each workflow"},
      {"label": "Visualize", "description": "Generate Mermaid diagrams for each workflow"},
      {"label": "Migrate", "description": "Convert prose skills to workflow format"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_OPERATION(response):
  SWITCH response:
    CASE "Validate (Recommended)":
      computed.selected_operation = "validate"
      computed.applicable_classifications = ["workflow", "hybrid"]
    CASE "Upgrade":
      computed.selected_operation = "upgrade"
      computed.applicable_classifications = ["workflow", "hybrid"]
    CASE "Analyze":
      computed.selected_operation = "analyze"
      computed.applicable_classifications = ["prose", "hybrid"]
    CASE "Visualize":
      computed.selected_operation = "visualize"
      computed.applicable_classifications = ["workflow", "hybrid"]
    CASE "Migrate":
      computed.selected_operation = "migrate"
      computed.applicable_classifications = ["prose"]
```

Store the selection in `computed.selected_operation` and the applicable classifications
in `computed.applicable_classifications`.

### Step 2.2: Choose Error Handling Mode

Ask the user how errors should be handled during batch execution:

```json
{
  "questions": [{
    "question": "How should errors be handled during batch execution?",
    "header": "Errors",
    "multiSelect": false,
    "options": [
      {"label": "Continue on error (Recommended)", "description": "Skip failed skills, report at end"},
      {"label": "Stop on first error", "description": "Halt batch if any skill fails"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_ERROR_MODE(response):
  SWITCH response:
    CASE "Continue on error (Recommended)":
      computed.error_mode = "continue"
    CASE "Stop on first error":
      computed.error_mode = "stop_on_first"
```

Store the selection in `computed.error_mode`.

---

## Phase 3: Filter

### Step 3.1: Choose Filter Strategy

Present the user with filtering options:

```json
{
  "questions": [{
    "question": "Which skills should be included?",
    "header": "Filter",
    "multiSelect": false,
    "options": [
      {"label": "All skills", "description": "Apply to every skill in the plugin"},
      {"label": "By classification", "description": "Only workflow / only prose / only hybrid"},
      {"label": "Select specific", "description": "Choose individual skills"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_FILTER(response):
  SWITCH response:
    CASE "All skills":
      computed.filtered_skills = computed.inventory
      GOTO Step 3.4
    CASE "By classification":
      GOTO Step 3.2
    CASE "Select specific":
      GOTO Step 3.3
```

### Step 3.2: Filter by Classification

If the user selected "By classification", present the classification options. Only show
classifications that are applicable to the selected operation:

```pseudocode
BUILD_CLASSIFICATION_OPTIONS():
  options = []
  FOR classification IN computed.applicable_classifications:
    count = len(computed.summary[classification])
    IF count > 0:
      options.append({
        label: classification,
        description: "{count} skill(s) with this classification"
      })
```

Present via AskUserQuestion with `multiSelect: true` so the user can select multiple
classifications:

```json
{
  "questions": [{
    "question": "Which classifications should be included?",
    "header": "Classifications",
    "multiSelect": true,
    "options": [
      {"label": "workflow", "description": "N skill(s) with this classification"},
      {"label": "prose", "description": "N skill(s) with this classification"},
      {"label": "hybrid", "description": "N skill(s) with this classification"}
    ]
  }]
}
```

Apply the filter:

```pseudocode
APPLY_CLASSIFICATION_FILTER(selected_classifications):
  computed.filtered_skills = [
    s for s in computed.inventory
    if s.classification in selected_classifications
  ]
```

### Step 3.3: Select Specific Skills

If the user selected "Select specific", present the full skill list with multiSelect enabled:

```pseudocode
BUILD_SKILL_OPTIONS():
  options = []
  FOR skill IN computed.inventory:
    options.append({
      label: skill.name,
      description: "{skill.classification} | {skill.line_count} lines | {skill.directory}"
    })
```

Present via AskUserQuestion:

```json
{
  "questions": [{
    "question": "Select the skills to include in this batch operation:",
    "header": "Skills",
    "multiSelect": true,
    "options": [
      {"label": "skill-name-1", "description": "workflow | 120 lines | /path/to/skill"},
      {"label": "skill-name-2", "description": "prose | 340 lines | /path/to/skill"}
    ]
  }]
}
```

Apply the filter:

```pseudocode
APPLY_SPECIFIC_FILTER(selected_names):
  computed.filtered_skills = [
    s for s in computed.inventory
    if s.name in selected_names
  ]
```

### Step 3.4: Confirm Filtered List

Display the filtered count and list, then confirm before proceeding:

```
## Batch Scope

**Operation:** {computed.selected_operation}
**Error mode:** {computed.error_mode}
**Skills included:** {len(computed.filtered_skills)} of {len(computed.inventory)}

| # | Skill | Classification |
|---|-------|----------------|
{for i, skill in enumerate(computed.filtered_skills)}
| {i+1} | {skill.name} | {skill.classification} |
{/for}
```

If `len(computed.filtered_skills) == 0`:

> No skills match the selected filter and operation combination. The **{computed.selected_operation}**
> operation applies to skills classified as **{computed.applicable_classifications}**, but no skills
> in the inventory have those classifications.

Then offer to return to Phase 2 to select a different operation, or Phase 3 to select a
different filter.

> **Detail:** See `patterns/batch-execution-protocol.md` for progress display format and
> error accumulation strategy.

---

## Phase 4: Execute Batch

### Step 4.1: Initialize Batch Tracking

Set up the tracking structure before starting the loop:

```pseudocode
INIT_BATCH():
  computed.batch = {
    total: len(computed.filtered_skills),
    completed: 0,
    passed: 0,
    failed: 0,
    skipped: 0,
    results: []
  }
```

### Step 4.2: Loop with Progress Tracking

Iterate through `computed.filtered_skills`, executing the selected operation on each skill.
Display progress after each iteration.

```pseudocode
EXECUTE_BATCH():
  FOR i, skill IN enumerate(computed.filtered_skills):

    # ---- Display progress ----
    progress_pct = ((i) / computed.batch.total) * 100
    DISPLAY "### [{i+1}/{computed.batch.total}] ({progress_pct:.0f}%) Processing: {skill.name}"

    # ---- Check applicability ----
    IF skill.classification NOT IN computed.applicable_classifications:
      computed.batch.results.append({
        skill: skill.name,
        status: "skip",
        details: "Classification '{skill.classification}' not applicable to '{computed.selected_operation}'"
      })
      computed.batch.skipped += 1
      computed.batch.completed += 1
      CONTINUE

    # ---- Execute operation ----
    TRY:
      result = execute_operation(computed.selected_operation, skill)

      computed.batch.results.append({
        skill: skill.name,
        status: "pass" IF result.success ELSE "fail",
        details: result.summary,
        issues: result.issues IF NOT result.success ELSE null
      })

      IF result.success:
        computed.batch.passed += 1
      ELSE:
        computed.batch.failed += 1

    CATCH error:
      computed.batch.results.append({
        skill: skill.name,
        status: "error",
        details: str(error)
      })
      computed.batch.failed += 1

      IF computed.error_mode == "stop_on_first":
        DISPLAY "Stopping batch: error encountered on '{skill.name}'"
        DISPLAY "Error: {str(error)}"
        BREAK

    computed.batch.completed += 1

    # ---- Progress summary line ----
    DISPLAY "  Result: {computed.batch.results[-1].status} | Running: {computed.batch.passed} passed, {computed.batch.failed} failed, {computed.batch.skipped} skipped"
```

### Step 4.3: Operation Execution Details

The `execute_operation` function dispatches to the appropriate per-skill logic based on
the selected operation. For each operation, the skill runs the operation inline (not by
invoking another skill, since batch mode requires collecting structured results).

**Validate:**

```pseudocode
function execute_operation("validate", skill):
  workflow_path = skill.directory + "/workflow.yaml"
  IF NOT file_exists(workflow_path):
    return { success: false, summary: "No workflow.yaml found", issues: ["Missing workflow.yaml"] }

  content = Read(workflow_path)

  # Run all four validation dimensions
  schema_issues = validate_schema(content)
  graph_issues = validate_graph(content)
  type_issues = validate_types(content)
  state_issues = validate_state(content)

  all_issues = schema_issues + graph_issues + type_issues + state_issues
  error_count = count(i for i in all_issues if i.severity == "error")
  warning_count = count(i for i in all_issues if i.severity == "warning")

  success = (error_count == 0)
  summary = "{error_count} error(s), {warning_count} warning(s)"

  return { success: success, summary: summary, issues: all_issues }
```

For the full validation procedure, refer to:
`${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/SKILL.md`

**Upgrade:**

```pseudocode
function execute_operation("upgrade", skill):
  workflow_path = skill.directory + "/workflow.yaml"
  IF NOT file_exists(workflow_path):
    return { success: false, summary: "No workflow.yaml found", issues: ["Missing workflow.yaml"] }

  content = Read(workflow_path)
  current_version = detect_version(content)
  target_version = "2.4"

  IF current_version == target_version:
    return { success: true, summary: "Already at v{target_version}" }

  # Apply migrations (create backup, apply each step, verify)
  changes = apply_migrations(content, current_version, target_version)
  success = len(changes.errors) == 0
  summary = "Upgraded {current_version} -> {target_version}, {len(changes.applied)} change(s)"

  return { success: success, summary: summary, issues: changes.errors }
```

For the full upgrade procedure, refer to:
`${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-upgrade/SKILL.md`

**Analyze:**

```pseudocode
function execute_operation("analyze", skill):
  content = Read(skill.path)

  # Extract phases, conditionals, actions, state variables, complexity
  phases = detect_phases(content)
  conditionals = extract_conditionals(content)
  actions = identify_actions(content)
  state_vars = detect_state_variables(content)
  complexity = compute_complexity(phases, conditionals, actions, state_vars)

  summary = "{complexity} complexity, {len(phases)} phases, {len(conditionals)} conditionals"
  return { success: true, summary: summary }
```

For the full analysis procedure, refer to:
`${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`

**Visualize:**

```pseudocode
function execute_operation("visualize", skill):
  workflow_path = skill.directory + "/workflow.yaml"
  IF NOT file_exists(workflow_path):
    return { success: false, summary: "No workflow.yaml found", issues: ["Missing workflow.yaml"] }

  content = Read(workflow_path)

  # Generate Mermaid diagram from workflow graph
  mermaid = generate_mermaid(content)
  output_path = skill.directory + "/workflow-diagram.md"
  Write(output_path, mermaid)

  summary = "Diagram written to {output_path}"
  return { success: true, summary: summary }
```

**Migrate:**

```pseudocode
function execute_operation("migrate", skill):
  # Step 1: Run prose-analyze to extract structure
  content = Read(skill.path)
  analysis = run_prose_analysis(content)

  # Step 2: Run prose-migrate using the analysis output
  migration_result = run_prose_migration(analysis, skill.directory)

  success = migration_result.workflow_generated
  summary = "Generated workflow.yaml with {migration_result.node_count} nodes" IF success
            ELSE "Migration failed: {migration_result.error}"

  return { success: success, summary: summary, issues: migration_result.errors }
```

For the full migration procedure, refer to:
- `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`
- `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-migrate/SKILL.md`

---

## Phase 5: Aggregate Report

### Step 5.1: Per-Skill Results Table

Display detailed results for every skill processed:

```
## Batch Results

| # | Skill | Status | Details |
|---|-------|--------|---------|
{for i, result in enumerate(computed.batch.results)}
| {i+1} | {result.skill} | {result.status} | {result.details} |
{/for}
```

Use status indicators:
- `pass` -- Operation succeeded with no errors
- `fail` -- Operation completed but found errors or produced invalid output
- `skip` -- Skill was not applicable to the selected operation
- `error` -- Operation threw an unexpected error

### Step 5.2: Summary Statistics

Display aggregate counts and success rate:

```
## Summary

**Operation:** {computed.selected_operation}
**Error Mode:** {computed.error_mode}
**Total:** {computed.batch.total} | **Passed:** {computed.batch.passed} | **Failed:** {computed.batch.failed} | **Skipped:** {computed.batch.skipped}
**Success Rate:** {(computed.batch.passed / (computed.batch.total - computed.batch.skipped)) * 100:.1f}%
```

If `computed.batch.total - computed.batch.skipped == 0`, display "N/A" for success rate
instead of dividing by zero.

### Step 5.3: Issues Requiring Attention

If any skills failed or errored, list them with details so the user can follow up:

```pseudocode
DISPLAY_ISSUES():
  failed_results = [r for r in computed.batch.results if r.status in ("fail", "error")]

  IF len(failed_results) == 0:
    DISPLAY "All applicable skills passed. No issues to report."
    RETURN

  DISPLAY "### Issues Requiring Attention"
  DISPLAY ""

  FOR result IN failed_results:
    DISPLAY "#### {result.skill} [{result.status}]"
    DISPLAY ""
    DISPLAY result.details
    IF result.issues:
      FOR issue IN result.issues:
        DISPLAY "- [{issue.severity}] {issue.message}"
    DISPLAY ""
```

### Step 5.4: Next Action

After presenting the report, ask the user what they want to do:

```json
{
  "questions": [{
    "question": "Batch operation complete. What would you like to do?",
    "header": "Next",
    "multiSelect": false,
    "options": [
      {"label": "Re-run failed", "description": "Re-execute the operation on skills that failed"},
      {"label": "Export report", "description": "Save the batch results to a markdown file"},
      {"label": "Fix issues", "description": "Address reported issues one skill at a time"},
      {"label": "Done", "description": "Batch operation finished"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT(response):
  SWITCH response:
    CASE "Re-run failed":
      # Rebuild filtered_skills to include only failed/errored results
      computed.filtered_skills = [
        s for s in computed.inventory
        if s.name in [r.skill for r in computed.batch.results if r.status in ("fail", "error")]
      ]
      # Reset batch counters
      computed.batch.completed = 0
      computed.batch.passed = 0
      computed.batch.failed = 0
      computed.batch.skipped = 0
      computed.batch.results = []
      computed.batch.total = len(computed.filtered_skills)
      # Re-execute Phase 4
      GOTO Phase 4, Step 4.1

    CASE "Export report":
      # Write the full report to a file
      default_path = "${CLAUDE_PLUGIN_ROOT}/docs/batch-report-{timestamp}.md"
      report_content = assemble_report(computed.batch)
      Write(default_path, report_content)
      DISPLAY "Report saved to {default_path}"
      # Re-prompt with remaining options
      GOTO Step 5.4

    CASE "Fix issues":
      # Present the list of failed skills and let the user pick one
      failed_skills = [r.skill for r in computed.batch.results if r.status in ("fail", "error")]
      # For each selected skill, describe the handoff:
      #   - Validate failures -> invoke bp-author-skill-validate on the specific skill
      #   - Upgrade failures -> invoke bp-author-skill-upgrade on the specific skill
      #   - Analyze failures -> invoke bp-author-prose-analyze on the specific skill
      #   - Migrate failures -> invoke bp-author-prose-analyze then bp-author-prose-migrate
      DISPLAY "Select a failed skill to address. The appropriate skill will be invoked:"
      FOR skill_name IN failed_skills:
        skill = lookup(computed.inventory, skill_name)
        DISPLAY "- **{skill_name}**: invoke bp-author-{computed.selected_operation} on {skill.path}"

    CASE "Done":
      DISPLAY "Batch operation complete. {computed.batch.passed} of {computed.batch.total} skills passed."
      EXIT
```

---

## State Flow

```
Phase 1                Phase 2                   Phase 3                Phase 4              Phase 5
─────────────────────────────────────────────────────────────────────────────────────────────────────
computed.inventory  -> computed.selected_op    -> computed.filtered   -> computed.batch    -> Report
computed.summary       computed.applicable_cls    _skills               .total               (assembled)
                       computed.error_mode                              .completed
                                                                        .passed
                                                                        .failed
                                                                        .skipped
                                                                        .results[]
```

---

## Reference Documentation

- **Batch Execution Protocol:** `patterns/batch-execution-protocol.md` (local to this skill)
- **Classification Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/patterns/classification-algorithm.md`
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`

---

## Related Skills

- **Discover skills:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/SKILL.md`
- **Validate workflow:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/SKILL.md`
- **Upgrade workflow:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-upgrade/SKILL.md`
- **Analyze prose skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`
- **Migrate prose skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-migrate/SKILL.md`
- **Analyze workflow skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-analyze/SKILL.md`
- **Visualize workflow:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-visualize/SKILL.md`
