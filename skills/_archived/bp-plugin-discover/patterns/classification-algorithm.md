# Classification Algorithm

> **Used by:** `SKILL.md` Phase 2, Step 2.2
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`

This document defines the full classification algorithm for determining a skill's
workflow coverage level: `none`, `partial`, or `full`.

---

## Coverage Model

Every skill is classified by how much of its execution is backed by workflow definitions:

| Coverage | Meaning | Criteria |
|----------|---------|----------|
| `none` | All phases are prose instructions | No `workflows/` directory, no workflow files referenced |
| `partial` | Some phases delegate to workflows | At least one phase references a workflow file, but not all |
| `full` | All phases delegate to workflows | Every phase in the skill references a workflow file |

---

## Phase Detection

Before classifying coverage, we must identify all phases in a SKILL.md.

### Phase Heading Patterns

Phases are identified by numbered headings in the body (after frontmatter):

```pseudocode
function detect_phases(content):
  phases = []

  # Match numbered phase headings: ## Phase N: Title, ### Phase N: Title
  phase_headings = find_all_matches(content, /^##+ Phase (\d+)[:\s]+(.+)$/m)

  FOR match IN phase_headings:
    phase = {
      number:    int(match.group(1)),
      title:     match.group(2).strip(),
      line:      match.line_number,
      content:   get_section_content(content, match.line_number)
    }
    phases.append(phase)

  return phases
```

### Workflow-Backed Phase Detection

A phase is workflow-backed if its content delegates to a workflow file:

```pseudocode
function is_workflow_backed(phase_content):
  # Pattern 1: Explicit workflow execution instruction
  IF matches(phase_content, /Execute\s+`workflows\/[\w-]+\.yaml`/):
    return true

  # Pattern 2: Workflow file reference in the phase
  IF matches(phase_content, /workflows\/[\w-]+\.yaml/):
    return true

  # Pattern 3: "Follow the execution guide" delegation
  IF matches(phase_content, /execution-guide\.md/) AND matches(phase_content, /workflows\//):
    return true

  return false

function count_workflow_backed_phases(content, skill):
  phases = detect_phases(content)
  count = 0
  FOR phase IN phases:
    IF is_workflow_backed(phase.content):
      count += 1
  return count
```

---

## Coverage Classification Algorithm

### Full Decision Tree

```pseudocode
function classify_coverage(skill, content):
  phases = detect_phases(content)
  total_phases = len(phases)

  # ---- Edge case: no phases detected ----
  IF total_phases == 0:
    line_count = count_lines(content)
    IF line_count < 30:
      return "none"    # Very simple skill, no formal phases
    ELSE:
      # Has content but no numbered phases — treat as single implicit prose phase
      return "none"

  # ---- Count workflow-backed phases ----
  workflow_phases = 0
  FOR phase IN phases:
    IF is_workflow_backed(phase.content):
      workflow_phases += 1

  # ---- Also check for workflows/ directory ----
  has_workflows_dir = skill.has_workflows_dir
  has_legacy_workflow = skill.has_legacy_workflow

  # ---- Classification ----
  IF workflow_phases == 0 AND NOT has_workflows_dir AND NOT has_legacy_workflow:
    return "none"

  IF workflow_phases == total_phases:
    return "full"

  IF workflow_phases > 0:
    return "partial"

  # Has workflow files but no phases reference them — still partial
  IF has_workflows_dir OR has_legacy_workflow:
    return "partial"

  return "none"
```

---

## Additional Flags

Beyond coverage, the algorithm detects these supplementary flags:

### Inputs/Outputs Completeness

```pseudocode
function check_io_completeness(frontmatter):
  inputs_defined = "inputs" IN frontmatter AND is_array(frontmatter.inputs) AND len(frontmatter.inputs) > 0
  outputs_defined = "outputs" IN frontmatter AND is_array(frontmatter.outputs) AND len(frontmatter.outputs) > 0
  return { inputs_defined, outputs_defined }
```

### Legacy Layout Detection

```pseudocode
function check_legacy_layout(skill):
  # Legacy: has bare workflow.yaml sibling but no workflows/ subdirectory
  IF skill.has_legacy_workflow AND NOT skill.has_workflows_dir:
    return true
  return false
```

### Frontmatter Workflows Declaration

```pseudocode
function check_workflows_declared(frontmatter, skill):
  # Check that frontmatter workflows: list matches actual files
  IF "workflows" IN frontmatter:
    declared = set(frontmatter.workflows)
    actual = set(relative_paths(skill.workflow_files))
    missing = declared - actual
    extra = actual - declared
    return { declared, actual, missing, extra, consistent: len(missing) == 0 AND len(extra) == 0 }
  return { declared: set(), actual: set(relative_paths(skill.workflow_files)), consistent: true }
```

---

## Threshold Reference

Summary of key thresholds used in the algorithm:

| Check | Threshold | Result |
|-------|-----------|--------|
| `total_phases == 0 AND line_count < 30` | Very short file | `none` |
| `workflow_phases == 0 AND no workflow files` | No workflow backing | `none` |
| `workflow_phases == total_phases` | All phases have workflows | `full` |
| `0 < workflow_phases < total_phases` | Some phases have workflows | `partial` |
| `has_legacy_workflow AND NOT has_workflows_dir` | Old layout detected | flag: `legacy_layout` |

---

## Edge Cases

### Empty SKILL.md

A SKILL.md that contains only YAML frontmatter (or is entirely empty) is classified
as `none` with 0 phases. Detection:

```pseudocode
if line_count < 10:
  return "none"
```

### Frontmatter-Only File

Some skills have frontmatter + a one-line description but no phases:

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

This classifies as `none` (0 phases, no workflows).

### Legacy Workflow Layout

A skill may use the old layout with a bare `workflow.yaml` sibling instead of
the `workflows/` subdirectory. This is still detected and counted:

```pseudocode
IF skill.has_legacy_workflow:
  # Check if SKILL.md content references it
  IF matches(content, /workflow\.yaml/):
    # Count as workflow-backed for coverage purposes
    # But flag legacy_layout = true for migration recommendation
```

### Skills with workflows/ but No Phase References

A skill may have workflow files in `workflows/` but the SKILL.md body does not
reference them in any phase. This classifies as `partial` (the files exist, but
the skill orchestration hasn't been updated to delegate to them).

---

## Classification Examples

### Example: Full Coverage

```markdown
---
name: repo-audit
workflows:
  - workflows/scan.yaml
  - workflows/report.yaml
inputs:
  - name: target
    type: string
    required: true
outputs:
  - name: report
    type: object
---

# Repo Audit

## Phase 1: Scan
Execute `workflows/scan.yaml` following the execution guide.

## Phase 2: Report
Execute `workflows/report.yaml` following the execution guide.
```

**Result:** `full` (2/2 phases workflow-backed)

### Example: Partial Coverage

```markdown
---
name: data-pipeline-setup
workflows:
  - workflows/validate.yaml
inputs:
  - name: config_path
    type: string
    required: true
---

# Data Pipeline Setup

## Phase 1: Gather
[Prose instructions for collecting user input]

## Phase 2: Validate
Execute `workflows/validate.yaml` following the execution guide.

## Phase 3: Report
[Prose instructions for displaying results]
```

**Result:** `partial` (1/3 phases workflow-backed)

### Example: No Coverage

```markdown
---
name: my-prose-skill
allowed-tools: Read, Glob, AskUserQuestion
---

# Analyze Data

## Phase 1: Locate Files
...if no files found, ask user...

## Phase 2: Parse Content
...when file is JSON, use jq... otherwise, treat as text...

## Phase 3: Generate Report
...depending on the output format selected...
```

**Result:** `none` (0/3 phases workflow-backed, no workflow files)

### Example: Legacy Layout

```markdown
---
name: my-converted-skill
---

# My Skill

Execute this workflow deterministically.

## Execution Protocol
See execution guide.
```

With a sibling `workflow.yaml` file (but no `workflows/` directory).

**Result:** `partial` (legacy workflow detected), **flag:** `legacy_layout = true`

---

## Using Classification Results

The classification drives downstream behavior:

| Coverage | Downstream Skill | Action |
|----------|-----------------|--------|
| `none` | `bp-skill-analyze` | Identify extraction candidates, then `bp-workflow-extract` |
| `partial` | `bp-skill-analyze` | Assess remaining prose phases for extraction |
| `full` | `bp-skill-validate` | Validate all workflow files |
| Any + `legacy_layout` | `bp-skill-refactor` | Migrate to `workflows/` subdirectory layout |
| Any + missing I/O | `bp-skill-refactor` | Add inputs/outputs to frontmatter |

---

## Related Documentation

- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
