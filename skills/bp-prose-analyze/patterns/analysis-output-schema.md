> **Used by:** `SKILL.md` Phase 4, Step 4.1
> **Contract between:** bp-prose-analyze → bp-prose-migrate

# Analysis Output Schema

Complete field reference for the analysis YAML produced by `bp-prose-analyze` and consumed by `bp-prose-migrate`. This document is the handoff contract between the two skills.

---

## Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `skill_path` | string | **required** | Absolute path to the analyzed SKILL.md file |
| `skill_name` | string | **required** | Skill identifier extracted from frontmatter `name` field |

---

## `frontmatter` Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `frontmatter.name` | string | **required** | Skill name from YAML frontmatter |
| `frontmatter.description` | string | **required** | Trigger description from YAML frontmatter |
| `frontmatter.allowed_tools` | string[] | **required** | List of allowed tool names (e.g., `["Read", "Write"]`) |

---

## Complexity Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `complexity` | enum | **required** | One of: `"low"`, `"medium"`, `"high"` |
| `complexity_score` | float | **required** | Weighted score from 1.00 to 3.00 |

---

## `metrics` Object

All metrics fields are **required** integers.

| Field | Type | Description |
|-------|------|-------------|
| `metrics.phase_count` | integer | Number of detected phases |
| `metrics.conditional_count` | integer | Number of detected conditionals |
| `metrics.branching_depth` | integer | Maximum nesting depth of conditionals |
| `metrics.tool_variety` | integer | Count of distinct tools referenced |
| `metrics.user_interactions` | integer | Count of AskUserQuestion-type actions |
| `metrics.state_variables` | integer | Count of detected state variables |

---

## `phases` Array

Each entry in the `phases` array describes one detected phase. Array is **required** and must contain at least one entry.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `phases[].id` | string | **required** | Slugified phase identifier (e.g., `"validate_input"`) |
| `phases[].title` | string | **required** | Original phase title from prose (e.g., `"Validate Input"`) |
| `phases[].prose_location` | string | **required** | Line range in source (e.g., `"lines 15-28"`) |
| `phases[].confidence` | enum | **required** | Detection confidence: `"high"`, `"medium"`, `"low"` |
| `phases[].content_lines` | integer[] | optional | Array of line numbers belonging to this phase |
| `phases[].sub_steps` | object[] | optional | Nested sub-step definitions (same schema as phase) |
| `phases[].actions` | object[] | optional | Actions detected within this phase (see Actions below) |
| `phases[].conditionals` | object[] | optional | Conditionals detected within this phase (see Conditionals below) |

### `phases[].actions[]` Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tool` | string | **required** | Tool name (e.g., `"Read"`, `"Write"`, `"AskUserQuestion"`) |
| `description` | string | **required** | Human-readable description of the action |
| `line` | integer | **required** | Line number in source SKILL.md |
| `conditional` | boolean | **required** | Whether this action is inside a conditional branch |
| `condition` | string | optional | Condition text if `conditional` is `true`; `null` otherwise |

### `phases[].conditionals[]` Object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `location` | string | **required** | Line reference (e.g., `"line 20"`) |
| `type` | enum | **required** | One of: `"if-then"`, `"if-else"`, `"conditional"`, `"switch"`, `"negated-if"` |
| `condition_text` | string | **required** | The condition being evaluated (e.g., `"file exists"`) |
| `branches` | object[] | **required** | Array of branch descriptions |
| `branches[].description` | string | **required** | What happens in this branch |
| `affects_phases` | string[] | optional | Phase IDs affected by this conditional's outcome |

---

## `state_variables` Array

Each entry describes a detected state variable. Array is **required** (may be empty).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `state_variables[].name` | string | **required** | Variable name (e.g., `"config"`, `"user_choice"`) |
| `state_variables[].source` | enum | **required** | One of: `"user_input"`, `"file_read"`, `"computed"`, `"external"` |
| `state_variables[].defined_in` | string | **required** | Phase ID where variable is first assigned |
| `state_variables[].used_in` | string[] | **required** | Phase IDs where variable is referenced |
| `state_variables[].description` | string | optional | Human-readable description of what this variable holds |

---

## `user_interactions` Array

Each entry describes a point where user input is required. Array is **required** (may be empty).

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `user_interactions[].phase` | string | **required** | Phase ID containing this interaction |
| `user_interactions[].type` | enum | **required** | One of: `"selection"`, `"confirmation"`, `"free_text"`, `"multi_select"` |
| `user_interactions[].question` | string | **required** | The question or prompt text |
| `user_interactions[].line` | integer | **required** | Line number in source SKILL.md |
| `user_interactions[].options` | string[] | optional | Available options for selection/confirmation types |

---

## `logging_patterns` Object

Describes detected logging intent. Object is **required**.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `logging_patterns.intent_present` | boolean | **required** | Whether any logging indicators were found |
| `logging_patterns.indicators` | object[] | **required** | Array of detected indicators (may be empty) |
| `logging_patterns.indicators[].pattern` | string | **required** | The matched pattern text (e.g., `"audit trail"`) |
| `logging_patterns.indicators[].location` | string | **required** | Line reference (e.g., `"line 45"` or `"line 45 in validate_input"`) |
| `logging_patterns.indicators[].confidence` | enum | **required** | One of: `"high"`, `"medium"` |

---

## `conversion_recommendations` Object

Migration guidance produced by the complexity assessment. Object is **required**.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `conversion_recommendations.approach` | enum | **required** | One of: `"simple_linear"`, `"standard_workflow"`, `"complex_with_subflows"` |
| `conversion_recommendations.estimated_nodes` | integer | **required** | Estimated workflow node count |
| `conversion_recommendations.logging_recommendation` | enum | **required** | One of: `"enable"`, `"optional"`, `"skip"` |
| `conversion_recommendations.logging_indicators_count` | integer | **required** | Number of logging indicators detected |
| `conversion_recommendations.notes` | string[] | **required** | Observations about the skill structure (may be empty) |
| `conversion_recommendations.warnings` | string[] | **required** | Issues that may complicate conversion (may be empty) |

---

## Complete Example

```yaml
analysis:
  skill_path: "/home/user/plugins/my-plugin/skills/my-skill/SKILL.md"
  skill_name: "my-skill"

  frontmatter:
    name: "my-skill"
    description: "Trigger description for the skill"
    allowed_tools:
      - Read
      - Write
      - Glob
      - AskUserQuestion

  complexity: "medium"
  complexity_score: 1.85

  metrics:
    phase_count: 3
    conditional_count: 2
    branching_depth: 1
    tool_variety: 4
    user_interactions: 1
    state_variables: 4

  phases:
    - id: "locate_target"
      title: "Locate Target"
      prose_location: "lines 12-35"
      confidence: "high"
      actions:
        - tool: Glob
          description: "Find matching files"
          line: 15
          conditional: false
          condition: null
        - tool: AskUserQuestion
          description: "Ask user to select target"
          line: 22
          conditional: true
          condition: "if multiple files found"
      conditionals:
        - location: "line 20"
          type: "if-else"
          condition_text: "multiple files found"
          branches:
            - description: "present selection list"
            - description: "use single match"

    - id: "process"
      title: "Process"
      prose_location: "lines 37-68"
      confidence: "high"
      actions:
        - tool: Read
          description: "Read target file"
          line: 39
          conditional: false
          condition: null
        - tool: Write
          description: "Write processed output"
          line: 60
          conditional: false
          condition: null
      conditionals:
        - location: "line 45"
          type: "if-then"
          condition_text: "file contains legacy format"
          branches:
            - description: "transform to new format"

    - id: "report"
      title: "Report"
      prose_location: "lines 70-85"
      confidence: "high"
      actions: []
      conditionals: []

  state_variables:
    - name: "target_path"
      source: "user_input"
      defined_in: "locate_target"
      used_in: ["locate_target", "process"]
      description: "Path to the selected target file"
    - name: "file_content"
      source: "file_read"
      defined_in: "process"
      used_in: ["process", "report"]
      description: "Content of the target file"
    - name: "processed_output"
      source: "computed"
      defined_in: "process"
      used_in: ["process"]
      description: "Transformed output ready for writing"
    - name: "file_list"
      source: "computed"
      defined_in: "locate_target"
      used_in: ["locate_target"]
      description: "List of matching files from Glob"

  user_interactions:
    - phase: "locate_target"
      type: "selection"
      question: "Which file would you like to process?"
      line: 22
      options: ["file_a.md", "file_b.md"]

  logging_patterns:
    intent_present: false
    indicators: []

  conversion_recommendations:
    approach: "standard_workflow"
    estimated_nodes: 13
    logging_recommendation: "skip"
    logging_indicators_count: 0
    notes:
      - "Three phases map directly to workflow phases"
      - "Two conditionals require conditional nodes"
      - "Single user interaction can be a user_prompt node"
    warnings: []
```

---

## Consumer Notes for bp-prose-migrate

When consuming this schema, `bp-prose-migrate` should:

1. **Validate required fields** - All fields marked required must be present. Fail early with a descriptive error if any are missing.
2. **Use `phases[].actions` for node generation** - Each action maps to one or more workflow nodes.
3. **Use `phases[].conditionals` for routing** - Each conditional maps to a conditional node with transition branches.
4. **Use `state_variables` for state schema** - Each variable maps to an `initial_state` or `computed` field in the workflow.
5. **Use `conversion_recommendations.approach`** to select the generation strategy (linear, standard, or subflow-based).
6. **Respect `logging_recommendation`** - If `"enable"`, include logging configuration. If `"optional"`, ask the user. If `"skip"`, omit logging.
