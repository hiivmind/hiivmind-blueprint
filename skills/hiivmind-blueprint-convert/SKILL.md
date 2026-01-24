---
name: hiivmind-blueprint-convert
description: >
  This skill should be used when the user asks to "convert skill to workflow", "generate workflow.yaml",
  "transform skill to YAML", "create workflow from analysis", "convert analysis to nodes",
  or needs to create a deterministic workflow from an analyzed skill. Triggers on "convert skill",
  "blueprint convert", "hiivmind-blueprint convert", "make workflow", "skill to yaml",
  or after running hiivmind-blueprint-analyze.
allowed-tools: Read, Write, AskUserQuestion
---

# Convert Skill to Workflow

Transform an analyzed skill structure into a deterministic workflow.yaml file.

> **Pattern Documentation:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/node-mapping.md`

---

## Overview

This skill takes analysis output (from `hiivmind-blueprint-analyze`) and produces:
- Complete workflow.yaml with all nodes
- Proper node transitions
- Entry preconditions
- Endings (success and error)
- Initial state configuration

---

## Prerequisites

Before running this skill:
1. Run `hiivmind-blueprint-analyze` on the target skill
2. Have the analysis output available in state

If no analysis is available, this skill will invoke the analyze skill first.

---

## Phase 1: Validate Analysis

### Step 1.1: Check for Analysis

If `computed.analysis` exists in state:
1. Validate it has required fields:
   - `skill_name`
   - `phases` (array)
   - `complexity`
2. Proceed to Phase 2

If no analysis available:
1. **Ask user** for next step:
   ```json
   {
     "questions": [{
       "question": "No skill analysis found. What would you like to do?",
       "header": "Analysis",
       "multiSelect": false,
       "options": [
         {"label": "Analyze first", "description": "Run analysis on a skill, then convert"},
         {"label": "Provide analysis file", "description": "Load analysis from a YAML file"},
         {"label": "Cancel", "description": "Exit without converting"}
       ]
     }]
   }
   ```
2. Based on response:
   - **Analyze first**: Invoke `hiivmind-blueprint-analyze`, then continue
   - **Provide analysis file**: Read the file, parse YAML, continue
   - **Cancel**: Exit with message

### Step 1.2: Review Analysis

Display key metrics to user:

```
## Converting: {skill_name}

**Complexity:** {complexity}
**Phases:** {phase_count}
**Estimated nodes:** {estimated_nodes}

{if warnings}
**Warnings:**
{warnings}
{/if}

Proceed with conversion?
```

---

## Phase 2: Build Workflow Scaffold

### Step 2.1: Create Workflow Header

From analysis, generate:

```yaml
name: "{analysis.skill_name}"
version: "1.0.0"
description: >
  {analysis.frontmatter.description}
```

### Step 2.2: Generate Entry Preconditions

Based on detected prerequisites in the skill:

**Detection rules:**
| Prose Pattern | Precondition |
|---------------|--------------|
| "requires git" | `tool_available: git` |
| "config must exist" | `config_exists` |
| "file X must exist" | `file_exists: X` |
| "run from directory with Y" | `file_exists: Y` |

If no prerequisites detected:
```yaml
entry_preconditions: []
```

### Step 2.3: Generate Initial State

From analysis.state_variables:

```yaml
initial_state:
  phase: "start"
  {for each state_variable}
  {variable.name}: null  # or default value
  {/for}
  flags:
    {for each boolean condition detected}
    {condition_name}: false
    {/for}
  computed: {}
```

### Step 2.4: Configure Logging

Based on `analysis.conversion_recommendations.logging_recommendation`:

**If "enable":**
Auto-add default logging configuration to initial_state:

```yaml
initial_state:
  logging:
    enabled: true
    level: "info"
    auto:
      init: true
      node_tracking: true
      finalize: true
      write: true
    output:
      format: "yaml"
      location: ".logs/"
    retention:
      strategy: "count"
      count: 10
```

**If "optional":**
**Ask user:**
```json
{
  "questions": [{
    "question": "Would you like to enable workflow logging?",
    "header": "Logging",
    "multiSelect": false,
    "options": [
      {"label": "Yes (Recommended)", "description": "Enable auto-logging with default settings"},
      {"label": "Manual", "description": "I'll configure logging myself"},
      {"label": "No", "description": "Skip logging for this workflow"}
    ]
  }]
}
```

Based on response:
- **Yes**: Add default logging config as above
- **Manual**: Add minimal `logging.enabled: false` placeholder
- **No**: Omit logging section entirely

**If "skip":**
No logging configuration added.

**When logging.auto.node_tracking is enabled:**
The framework will automatically inject `log_node` consequences after each node execution. No explicit logging consequences needed in the workflow.

---

## Phase 3: Map Nodes

### Step 3.1: Process Each Phase

For each phase in analysis.phases:

1. **Determine phase structure:**
   - Linear (no conditionals): Single action node
   - Has conditionals: Multiple nodes

2. **Map actions to consequences:**

   | Tool | Consequence Type | Parameters |
   |------|------------------|------------|
   | Read file | `read_file` | path, store_as |
   | Read config | `read_config` | store_as |
   | Write file | `write_file` | path, content |
   | Bash command | `run_command` | command, store_as |
   | Git clone | `clone_repo` | url, dest, branch |
   | Fetch URL | `web_fetch` | url, store_as |
   | Set variable | `set_state` | field, value |
   | Set flag | `set_flag` | flag, value |

3. **Create action nodes:**

   ```yaml
   {phase_id}:
     type: action
     description: "{phase.title}"
     actions:
       {for each action in phase.actions}
       - type: {consequence_type}
         {action parameters}
       {/for}
     on_success: {next_node}
     on_failure: {error_node}
   ```

### Step 3.2: Process Conditionals

For each conditional in analysis:

1. **If-else (2 branches):**
   ```yaml
   {conditional_id}:
     type: conditional
     description: "{condition_text}"
     condition:
       type: {precondition_type}
       {condition parameters}
     branches:
       true: {true_branch_node}
       false: {false_branch_node}
   ```

2. **Switch (3+ branches):**
   - Create multiple conditional nodes OR
   - Create user_prompt node for user selection

### Step 3.3: Process User Interactions

For each user interaction in analysis:

```yaml
{interaction_id}:
  type: user_prompt
  prompt:
    question: "{interaction.question}"
    header: "{short_header}"
    options:
      {for each option}
      - id: {option_id}
        label: "{option_label}"
        description: "{option_description}"
      {/for}
  on_response:
    {for each option}
    {option_id}:
      consequence:
        - type: set_state
          field: user_selection
          value: {option_id}
      next_node: {next_node_for_option}
    {/for}
```

### Step 3.4: Connect Node Transitions

Determine transition targets:

1. **Sequential phases:** on_success → next phase start
2. **Branching phases:** Connect branches to correct nodes
3. **Error handling:** Route failures to error endings

Build transition graph and verify:
- All on_success/on_failure targets exist
- All branches.true/false targets exist
- All on_response.next_node targets exist

---

## Phase 4: Generate Endings

### Step 4.1: Success Ending

```yaml
success:
  type: success
  message: "{skill_name} completed successfully"
  summary:
    {for each important output variable}
    {variable}: "${computed.{variable}}"
    {/for}
```

### Step 4.2: Error Endings

For each failure path detected:

```yaml
error_{error_type}:
  type: error
  message: "{error description}"
  {if recoverable}
  recovery: "{recovery_skill}"
  details: "{how to fix}"
  {/if}
```

Common error endings to generate:
- `error_file_not_found`
- `error_validation_failed`
- `error_user_cancelled`
- `error_operation_failed`

---

## Phase 5: Validate Workflow

### Step 5.1: Structural Validation

Verify:
- `start_node` exists in `nodes`
- All transition targets exist (nodes or endings)
- No orphan nodes (unreachable from start)
- All paths lead to an ending

### Step 5.2: Report Validation Results

If validation passes:
```
Workflow generated successfully.
- {node_count} nodes
- {ending_count} endings
- All paths validated
```

If validation fails:
```
Workflow validation failed:
{for each error}
- {error description}
{/for}

Please review and fix the issues.
```

---

## Phase 6: Output Workflow

### Step 6.1: Store Workflow

Store generated workflow in:
```yaml
computed:
  workflow:
    name: "..."
    version: "1.0.0"
    description: "..."
    entry_preconditions: [...]
    initial_state: {...}
    start_node: "..."
    nodes: {...}
    endings: {...}
```

### Step 6.2: Display Preview

Show the user a preview of key workflow elements:

```
## Workflow Generated: {name}

### Nodes ({count})
{for each node}
- **{node_id}** ({type}): {description}
{/for}

### Flow
{simplified flow diagram}

### Endings
{for each ending}
- **{ending_id}** ({type}): {message}
{/for}
```

### Step 6.3: Next Steps

Inform user of next steps:

```
Workflow is ready for generation.

**Next steps:**
1. Run `/hiivmind-blueprint generate` to create files
2. Or review the workflow first with `show workflow`

The workflow will create:
- `workflow.yaml` - The deterministic workflow
- `SKILL.md` - Thin loader (replaces original)
```

---

## Output Format

The generated workflow follows the schema at:
`${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`

---

## Reference Documentation

- **Node Mapping:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/node-mapping.md`
- **Workflow Generation:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/workflow-generation.md`
- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`
- **Preconditions:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/preconditions.md`
- **Consequences:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/consequences.md`

---

## Related Skills

- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
