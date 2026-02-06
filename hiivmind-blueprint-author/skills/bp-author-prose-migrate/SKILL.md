---
name: bp-author-prose-migrate
description: >
  This skill should be used when the user asks to "convert skill to workflow", "migrate skill",
  "generate workflow.yaml from skill", "transform prose to workflow", "create workflow from analysis",
  "convert analysis to nodes", or needs to create a deterministic workflow from an analyzed skill.
  Triggers on "migrate", "convert skill", "prose to workflow", "generate workflow", "skill to yaml",
  or after running bp-author-prose-analyze.
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
---

# Migrate Prose Skill to Workflow

Transform an analyzed skill structure into a complete workflow.yaml and thin SKILL.md.

> **Node Generation Procedure:** `patterns/node-generation-procedure.md` (local to this skill)
> **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
> **Consequence Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
> **Precondition Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
> **Prompt Modes:** `${CLAUDE_PLUGIN_ROOT}/references/prompt-modes.md`

---

## Overview

This is the core transformation skill in the prose-to-workflow pipeline. It takes the structured
analysis output from `bp-author-prose-analyze` and produces two files:

1. **workflow.yaml** -- Complete deterministic workflow with nodes, transitions, and endings
2. **SKILL.md** -- Thin loader that boots the workflow engine and executes the workflow

**Pipeline position:**

```
bp-author-plugin-discover       (inventory)
        |
bp-author-prose-analyze         (deep analysis)
        |
bp-author-prose-migrate  <---   THIS SKILL (transformation)
        |
test / iterate                  (manual verification)
```

**Key state handoff:** This skill expects `computed.analysis` to be populated by
`bp-author-prose-analyze`. If that state is missing, the skill will offer to run
analysis first or load an analysis file.

---

## Phase 1: Validate Analysis

### Step 1.1: Check Analysis Exists

Verify that `computed.analysis` exists and contains the required fields. The analysis
object is produced by `bp-author-prose-analyze` and must include:

- `skill_name` -- string, the name from SKILL.md frontmatter
- `phases` -- array of phase objects with title, actions, conditionals
- `complexity` -- string: "low", "medium", or "high"
- `state_variables` -- array of detected state variable descriptors
- `user_interactions` -- array of detected user interaction points
- `conversion_recommendations` -- object with logging_recommendation, prompt_mode hints

```pseudocode
VALIDATE_ANALYSIS():
  IF computed.analysis IS NOT DEFINED:
    GOTO ASK_USER_MISSING_ANALYSIS

  required_fields = ["skill_name", "phases", "complexity"]
  missing = [f for f in required_fields if f NOT IN computed.analysis]

  IF len(missing) > 0:
    DISPLAY "Analysis exists but is missing fields: {', '.join(missing)}"
    GOTO ASK_USER_MISSING_ANALYSIS

  IF len(computed.analysis.phases) == 0:
    DISPLAY "Analysis has no phases. The source skill may be too simple for workflow conversion."
    GOTO ASK_USER_MISSING_ANALYSIS

  GOTO Step 1.2
```

If analysis is missing or incomplete, present the user with recovery options:

```json
{
  "questions": [{
    "question": "No valid skill analysis found in state. What would you like to do?",
    "header": "Analysis",
    "multiSelect": false,
    "options": [
      {
        "label": "Analyze first",
        "description": "Run bp-author-prose-analyze on a skill, then return here to migrate"
      },
      {
        "label": "Load from file",
        "description": "Load a previously saved analysis from a YAML file"
      },
      {
        "label": "Cancel",
        "description": "Exit without migrating"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_MISSING_ANALYSIS(response):
  SWITCH response:
    CASE "Analyze first":
      DISPLAY "Invoke bp-author-prose-analyze first, then re-invoke this skill."
      DISPLAY ""
      DISPLAY "  Skill(skill: \"bp-author-prose-analyze\", args: \"<path-to-skill>\")"
      DISPLAY ""
      DISPLAY "The analysis output will be stored in computed.analysis for this skill to consume."
      EXIT
    CASE "Load from file":
      # Ask for file path
      DISPLAY "Provide the path to the analysis YAML file."
      file_path = user_input
      content = Read(file_path)
      computed.analysis = parse_yaml(content)
      # Re-validate after loading
      GOTO Step 1.1
    CASE "Cancel":
      DISPLAY "Migration cancelled."
      EXIT
```

### Step 1.2: Display Analysis Summary

Present key metrics from the analysis so the user can confirm before proceeding:

```
## Migration Target: {computed.analysis.skill_name}

**Complexity:** {computed.analysis.complexity}
**Phases:** {len(computed.analysis.phases)}
**Estimated nodes:** {computed.analysis.estimated_nodes}
**State variables:** {len(computed.analysis.state_variables)}
**User interactions:** {len(computed.analysis.user_interactions)}

{if computed.analysis.warnings}
**Warnings:**
{for warning in computed.analysis.warnings}
- {warning}
{/for}
{/if}

Proceeding with workflow generation...
```

Store `computed.skill_name = computed.analysis.skill_name` for convenient access
in later phases.

---

## Phase 2: Build Workflow Scaffold

### Step 2.1: Generate Header

Construct the workflow header from the analysis metadata:

```pseudocode
BUILD_HEADER():
  computed.workflow = {}
  computed.workflow.name = computed.analysis.skill_name
  computed.workflow.version = "1.0.0"
  computed.workflow.description = computed.analysis.frontmatter.description
    OR computed.analysis.skill_name + " workflow"
```

The header becomes the top section of the generated workflow.yaml:

```yaml
name: "{computed.workflow.name}"
version: "1.0.0"
description: >
  {computed.workflow.description}

definitions:
  source: {lib_ref from BLUEPRINT_LIB_VERSION.yaml}
```

### Step 2.2: Generate Entry Preconditions

Map detected prerequisites from the analysis to precondition types. The full
precondition type selection guide is in `patterns/node-generation-procedure.md`.

**Detection rules -- common prose patterns to precondition types:**

| Prose Pattern | Precondition Type | Parameters |
|---------------|-------------------|------------|
| "requires git" | tool_check | tool: git, capability: available |
| "requires jq" | tool_check | tool: jq, capability: available |
| "config must exist" | path_check | path: data/config.yaml, check: is_file |
| "file X must exist" | path_check | path: X, check: exists |
| "if flag is set" | state_check | operator: true |
| "if field equals X" | state_check | operator: equals, value: X |
| "run from plugin root" | path_check | path: .claude-plugin/plugin.json, check: is_file |

```pseudocode
BUILD_ENTRY_PRECONDITIONS():
  computed.workflow.entry_preconditions = []

  IF computed.analysis.prerequisites IS DEFINED:
    FOR prereq IN computed.analysis.prerequisites:
      precondition = map_prerequisite_to_precondition(prereq)
      computed.workflow.entry_preconditions.append(precondition)

  # Always include tool prerequisites if analysis mentions jq/yq
  IF computed.analysis.tool_dependencies:
    FOR tool IN computed.analysis.tool_dependencies:
      IF tool NOT already_in(computed.workflow.entry_preconditions):
        computed.workflow.entry_preconditions.append({
          type: "tool_check",
          tool: tool.name,
          capability: "available"
        })

  IF len(computed.workflow.entry_preconditions) == 0:
    # No prerequisites detected
    computed.workflow.entry_preconditions = []
```

### Step 2.3: Generate Initial State

Transform the analysis state variables into an initial_state YAML block:

```pseudocode
BUILD_INITIAL_STATE():
  computed.workflow.initial_state = {
    phase: "start",
    flags: {},
    computed: {}
  }

  # Map each detected state variable
  FOR var IN computed.analysis.state_variables:
    SWITCH var.type:
      CASE "string":
        computed.workflow.initial_state[var.name] = var.default OR null
      CASE "boolean":
        computed.workflow.initial_state.flags[var.name] = var.default OR false
      CASE "array":
        computed.workflow.initial_state[var.name] = var.default OR []
      CASE "object":
        computed.workflow.initial_state[var.name] = var.default OR {}
      DEFAULT:
        computed.workflow.initial_state[var.name] = null

  # Add output configuration (required for v2.4+ schema)
  computed.workflow.initial_state.output = {
    level: "normal",
    display_enabled: true,
    batch_enabled: true,
    batch_threshold: 3,
    use_icons: true,
    log_enabled: true,       # May be overridden in Step 2.4
    log_format: "yaml",
    log_location: ".logs/",
    ci_mode: false
  }

  # Add prompts configuration (required for v2.4+ schema)
  computed.workflow.initial_state.prompts = {
    interface: "auto",
    modes: {
      claude_code: "interactive",
      web: "forms",
      api: "structured",
      agent: "autonomous"
    },
    tabular: {
      match_strategy: "prefix",
      other_handler: "prompt"
    },
    autonomous: {
      strategy: "best_match",
      confidence_threshold: 0.7
    }
  }
```

### Step 2.4: Configure Logging

Based on `computed.analysis.conversion_recommendations.logging_recommendation`:

**If "enable":** Auto-add default logging configuration. Set
`computed.workflow.initial_state.output.log_enabled = true` (already the default
from Step 2.3).

**If "optional":** Ask the user:

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

**Response handling:**

```pseudocode
HANDLE_LOGGING(response):
  SWITCH response:
    CASE "Yes (Recommended)":
      # Keep defaults from Step 2.3 (log_enabled: true)
      # No changes needed
    CASE "Manual":
      # Set log_enabled to false as a placeholder for user to configure
      computed.workflow.initial_state.output.log_enabled = false
    CASE "No":
      # Disable logging entirely
      computed.workflow.initial_state.output.log_enabled = false
```

**If "skip":** Set `computed.workflow.initial_state.output.log_enabled = false`.

Store the complete scaffold in `computed.workflow.scaffold` as a checkpoint.

---

## Phase 3: Map Nodes

This is the core transformation phase. Each analysis phase becomes one or more
workflow nodes. The full consequence type and precondition type selection guides
are in `patterns/node-generation-procedure.md`.

### Step 3.1: Process Each Phase

Iterate through `computed.analysis.phases` and determine the node structure for
each phase:

```pseudocode
MAP_PHASES():
  computed.workflow.nodes = {}
  node_order = []  # Track insertion order for transition wiring

  FOR phase IN computed.analysis.phases:
    IF phase.conditionals.length == 0:
      # Linear phase -> single action node
      node = create_action_node(phase)
      computed.workflow.nodes[node.id] = node
      node_order.append(node.id)
    ELSE:
      # Branching phase -> conditional + branch nodes
      FOR conditional IN phase.conditionals:
        cond_node = create_conditional_node(conditional)
        computed.workflow.nodes[cond_node.id] = cond_node
        node_order.append(cond_node.id)

        FOR branch IN conditional.branches:
          branch_node = create_action_node(branch)
          computed.workflow.nodes[branch_node.id] = branch_node
          node_order.append(branch_node.id)

    # If phase has user interactions, create user_prompt nodes
    FOR interaction IN phase.user_interactions:
      prompt_node = create_user_prompt_node(interaction)
      computed.workflow.nodes[prompt_node.id] = prompt_node
      node_order.append(prompt_node.id)

  computed.workflow.start_node = node_order[0]
  computed.workflow.node_order = node_order
```

**Action node creation:**

```pseudocode
function create_action_node(phase_or_branch):
  node_id = slugify(phase_or_branch.title)  # e.g., "validate_inputs"

  actions = []
  FOR action IN phase_or_branch.actions:
    consequence = map_action_to_consequence(action)
    actions.append(consequence)

  RETURN {
    id: node_id,
    type: "action",
    description: phase_or_branch.title,
    actions: actions,
    on_success: null,   # Wired in Step 3.4
    on_failure: null     # Wired in Step 3.4
  }
```

**Consequence mapping** uses the table in `patterns/node-generation-procedure.md`. Summary
of the most common mappings:

| Action Description | Consequence Type | Operation |
|--------------------|------------------|-----------|
| Read a file | local_file_ops | read |
| Write a file | local_file_ops | write |
| Create directory | local_file_ops | mkdir |
| Run a shell command | run_command | interpreter: auto |
| Store a value | mutate_state | set |
| Append to list | mutate_state | append |
| Display output | display | format: text |
| Log an event | log_entry | level: info |

### Step 3.2: Process Conditionals

Map conditional structures from the analysis to conditional nodes:

**If-else (2 branches):** Map directly to a `conditional` node:

```yaml
# Example generated conditional node
check_config_exists:
  type: conditional
  description: "Check if configuration file exists"
  condition:
    type: path_check
    path: "${config_path}"
    check: is_file
  branches:
    on_true: load_config
    on_false: error_config_missing
```

**Switch (3+ branches):** Determine whether to use chained conditionals or a
`user_prompt` node:

```pseudocode
PROCESS_SWITCH(conditional):
  IF conditional.branches_are_value_based:
    # Value-based switch: chain conditional nodes
    # e.g., if status == "A" -> ..., elif status == "B" -> ...
    FOR i, branch IN enumerate(conditional.branches):
      IF i < len(conditional.branches) - 1:
        cond_node = {
          id: slugify(conditional.description + "_check_" + branch.label),
          type: "conditional",
          condition: {
            type: "state_check",
            field: conditional.switch_field,
            operator: "equals",
            value: branch.value
          },
          branches: {
            on_true: slugify(branch.label),
            on_false: slugify(conditional.description + "_check_" + conditional.branches[i+1].label)
          }
        }
      ELSE:
        # Last branch is the default
        cond_node = direct_route_to(branch)
  ELSE:
    # User-driven switch: use user_prompt node
    prompt_node = create_user_prompt_node({
      question: conditional.description,
      options: conditional.branches
    })
```

### Step 3.3: Process User Interactions

Map user interaction points from the analysis to `user_prompt` nodes:

```pseudocode
function create_user_prompt_node(interaction):
  node_id = slugify("prompt_" + interaction.header OR interaction.question[:30])

  options = []
  on_response = {}

  FOR option IN interaction.options:
    option_id = slugify(option.label)
    options.append({
      id: option_id,
      label: option.label,
      description: option.description OR ""
    })
    on_response[option_id] = {
      consequence: [{
        type: "mutate_state",
        operation: "set",
        field: "computed.user_selection",
        value: option_id
      }],
      next_node: null  # Wired in Step 3.4
    }

  RETURN {
    id: node_id,
    type: "user_prompt",
    prompt: {
      question: interaction.question,
      header: interaction.header[:12] OR interaction.question[:12],
      options: options
    },
    on_response: on_response
  }
```

Example generated user_prompt node:

```yaml
prompt_output_format:
  type: user_prompt
  prompt:
    question: "What output format would you like?"
    header: "Format"
    options:
      - id: yaml
        label: "YAML"
        description: "Structured YAML output"
      - id: markdown
        label: "Markdown"
        description: "Markdown report format"
      - id: json
        label: "JSON"
        description: "Machine-readable JSON"
  on_response:
    yaml:
      consequence:
        - type: mutate_state
          operation: set
          field: computed.output_format
          value: "yaml"
      next_node: generate_output
    markdown:
      consequence:
        - type: mutate_state
          operation: set
          field: computed.output_format
          value: "markdown"
      next_node: generate_output
    json:
      consequence:
        - type: mutate_state
          operation: set
          field: computed.output_format
          value: "json"
      next_node: generate_output
```

### Step 3.4: Connect Transitions

Wire up all `on_success`, `on_failure`, `branches`, and `on_response.*.next_node`
targets:

```pseudocode
WIRE_TRANSITIONS():
  nodes = computed.workflow.nodes
  order = computed.workflow.node_order

  FOR i, node_id IN enumerate(order):
    node = nodes[node_id]

    SWITCH node.type:
      CASE "action":
        # Sequential: on_success -> next node in order
        IF i < len(order) - 1:
          node.on_success = order[i + 1]
        ELSE:
          node.on_success = "success"

        # Error: route to the appropriate error ending
        node.on_failure = determine_error_ending(node)

      CASE "conditional":
        # Branches already set in Step 3.2
        # Verify branch targets exist
        ASSERT nodes[node.branches.on_true] OR is_ending(node.branches.on_true)
        ASSERT nodes[node.branches.on_false] OR is_ending(node.branches.on_false)

      CASE "user_prompt":
        # Wire each response option to the correct next node
        FOR option_id, handler IN node.on_response:
          IF handler.next_node IS null:
            # Default: route to the next sequential node
            IF i < len(order) - 1:
              handler.next_node = order[i + 1]
            ELSE:
              handler.next_node = "success"
```

**Error ending determination:**

```pseudocode
function determine_error_ending(node):
  # Match node context to the most appropriate error ending
  IF node involves file operations:
    RETURN "error_file_not_found"
  ELIF node involves validation:
    RETURN "error_validation_failed"
  ELIF node involves user interaction:
    RETURN "error_user_cancelled"
  ELSE:
    RETURN "error_operation_failed"
```

After wiring, verify no null transitions remain:

```pseudocode
VERIFY_TRANSITIONS():
  FOR node_id, node IN computed.workflow.nodes:
    IF node.type == "action":
      ASSERT node.on_success IS NOT null, "Missing on_success for " + node_id
      ASSERT node.on_failure IS NOT null, "Missing on_failure for " + node_id
    IF node.type == "conditional":
      ASSERT node.branches.on_true IS NOT null
      ASSERT node.branches.on_false IS NOT null
    IF node.type == "user_prompt":
      FOR option_id, handler IN node.on_response:
        ASSERT handler.next_node IS NOT null, "Missing next_node for " + node_id + "." + option_id
```

---

## Phase 4: Generate Endings

### Step 4.1: Success Ending

Create the success ending with a summary of computed outputs:

```pseudocode
BUILD_SUCCESS_ENDING():
  summary_fields = {}

  # Collect output variables from the analysis
  IF computed.analysis.output_variables:
    FOR var IN computed.analysis.output_variables:
      summary_fields[var.name] = "${computed." + var.name + "}"

  computed.workflow.endings = {
    success: {
      type: "success",
      message: computed.workflow.name + " completed successfully",
      summary: summary_fields
    }
  }
```

Generated YAML:

```yaml
success:
  type: success
  message: "{skill_name} completed successfully"
  summary:
    files_created: "${computed.files_created}"
    nodes_generated: "${computed.node_count}"
```

### Step 4.2: Error Endings

Generate error endings for each detected failure path. Always include these
common endings, plus any skill-specific ones:

```pseudocode
BUILD_ERROR_ENDINGS():
  # Common error endings
  common_errors = {
    error_file_not_found: {
      type: "error",
      message: "Required file not found",
      recovery: "Verify the file path and try again",
      details: "Check that the target file exists and is readable"
    },
    error_validation_failed: {
      type: "error",
      message: "Validation failed",
      recovery: "Review the validation errors and fix the issues",
      details: "One or more validation checks did not pass"
    },
    error_user_cancelled: {
      type: "error",
      message: "Operation cancelled by user",
      recovery: "Re-invoke the skill when ready to proceed"
    },
    error_operation_failed: {
      type: "error",
      message: "Operation failed unexpectedly",
      recovery: "Check the error details and retry",
      details: "An unexpected error occurred during execution"
    }
  }

  # Add common errors to endings
  FOR error_id, error IN common_errors:
    computed.workflow.endings[error_id] = error

  # Add skill-specific error endings from analysis
  IF computed.analysis.error_paths:
    FOR error_path IN computed.analysis.error_paths:
      error_id = "error_" + slugify(error_path.name)
      computed.workflow.endings[error_id] = {
        type: "error",
        message: error_path.description,
        recovery: error_path.recovery OR null,
        details: error_path.details OR null
      }

  # Always add safety ending
  computed.workflow.endings.error_safety = {
    type: "error",
    category: "safety",
    message: "I can't help with that request.",
    recovery: {
      suggestion: "Please rephrase your request to focus on legitimate use cases."
    }
  }
```

---

## Phase 5: Validate Workflow

### Step 5.1: Structural Validation

Run a series of checks to ensure the generated workflow is structurally sound:

```pseudocode
VALIDATE_WORKFLOW():
  errors = []
  warnings = []

  nodes = computed.workflow.nodes
  endings = computed.workflow.endings
  start = computed.workflow.start_node

  # Check 1: start_node exists
  IF start NOT IN nodes:
    errors.append("start_node '{start}' does not exist in nodes")

  # Check 2: All transition targets are valid (node or ending)
  valid_targets = set(nodes.keys()) | set(endings.keys())

  FOR node_id, node IN nodes:
    IF node.type == "action":
      IF node.on_success NOT IN valid_targets:
        errors.append("Node '{node_id}' on_success targets '{node.on_success}' which does not exist")
      IF node.on_failure NOT IN valid_targets:
        errors.append("Node '{node_id}' on_failure targets '{node.on_failure}' which does not exist")

    IF node.type == "conditional":
      IF node.branches.on_true NOT IN valid_targets:
        errors.append("Node '{node_id}' on_true targets '{node.branches.on_true}' which does not exist")
      IF node.branches.on_false NOT IN valid_targets:
        errors.append("Node '{node_id}' on_false targets '{node.branches.on_false}' which does not exist")

    IF node.type == "user_prompt":
      FOR option_id, handler IN node.on_response:
        IF handler.next_node NOT IN valid_targets:
          errors.append("Node '{node_id}' response '{option_id}' targets '{handler.next_node}' which does not exist")

  # Check 3: No orphan nodes (unreachable from start)
  reachable = bfs_reachable(start, nodes, endings)
  orphans = set(nodes.keys()) - reachable
  IF len(orphans) > 0:
    warnings.append("Orphan nodes detected (unreachable from start): " + ", ".join(orphans))

  # Check 4: All paths lead to an ending
  FOR node_id IN nodes:
    IF NOT has_path_to_ending(node_id, nodes, endings):
      errors.append("Node '{node_id}' has no path to any ending")

  computed.workflow.validation = {
    passed: len(errors) == 0,
    error_count: len(errors),
    warning_count: len(warnings),
    errors: errors,
    warnings: warnings
  }
```

**BFS reachability helper:**

```pseudocode
function bfs_reachable(start, nodes, endings):
  visited = set()
  queue = [start]

  WHILE queue IS NOT empty:
    current = queue.pop(0)
    IF current IN visited:
      CONTINUE
    visited.add(current)

    IF current IN endings:
      CONTINUE  # Endings are terminal

    IF current NOT IN nodes:
      CONTINUE  # Invalid target, caught by Check 2

    node = nodes[current]
    targets = get_all_transition_targets(node)
    FOR target IN targets:
      IF target NOT IN visited:
        queue.append(target)

  RETURN visited
```

### Step 5.2: Report Validation Results

Display validation results to the user:

**If validation passes:**

```
## Workflow Validation: PASSED

- **Nodes:** {len(computed.workflow.nodes)}
- **Endings:** {len(computed.workflow.endings)}
- **All transition targets valid**
- **All nodes reachable from start**
- **All paths lead to an ending**

{if computed.workflow.validation.warning_count > 0}
**Warnings ({computed.workflow.validation.warning_count}):**
{for warning in computed.workflow.validation.warnings}
- {warning}
{/for}
{/if}
```

**If validation fails:**

```
## Workflow Validation: FAILED

**Errors ({computed.workflow.validation.error_count}):**
{for error in computed.workflow.validation.errors}
- {error}
{/for}

{if computed.workflow.validation.warning_count > 0}
**Warnings ({computed.workflow.validation.warning_count}):**
{for warning in computed.workflow.validation.warnings}
- {warning}
{/for}
{/if}

Please review and fix the issues before writing files.
Returning to Phase 3 to correct node transitions...
```

If validation fails, loop back to Phase 3 Step 3.4 to repair transitions. After two
failed attempts, halt and display the full error list for manual intervention.

---

## Phase 6: Write Files

### Step 6.1: Check Existing Files

Determine the target directory from the analysis:

```pseudocode
DETERMINE_TARGET():
  IF computed.analysis.skill_path:
    computed.target_directory = parent_directory(computed.analysis.skill_path)
  ELSE:
    computed.target_directory = prompt_for_path()
```

Check if files already exist and ask the user how to handle them:

```json
{
  "questions": [{
    "question": "Found existing files in the target directory. How should I proceed?",
    "header": "Overwrite",
    "multiSelect": false,
    "options": [
      {"label": "Backup and replace", "description": "Rename existing files to .backup, then write new files"},
      {"label": "Overwrite", "description": "Replace existing files without creating backups"},
      {"label": "Cancel", "description": "Do not write any files"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_EXISTING_FILES(response):
  SWITCH response:
    CASE "Backup and replace":
      IF file_exists(computed.target_directory + "/SKILL.md"):
        Bash("mv {computed.target_directory}/SKILL.md {computed.target_directory}/SKILL.md.backup")
      IF file_exists(computed.target_directory + "/workflow.yaml"):
        Bash("mv {computed.target_directory}/workflow.yaml {computed.target_directory}/workflow.yaml.backup")
      computed.backup_created = true
    CASE "Overwrite":
      computed.backup_created = false
    CASE "Cancel":
      DISPLAY "File generation cancelled."
      EXIT
```

If no existing files are found, skip this prompt and proceed directly.

### Step 6.2: Load BLUEPRINT_LIB_VERSION.yaml

Read the centralized version configuration for template substitution:

```pseudocode
LOAD_LIB_VERSION():
  lib_config_path = CLAUDE_PLUGIN_ROOT + "/BLUEPRINT_LIB_VERSION.yaml"

  IF file_exists(lib_config_path):
    lib_config = Read(lib_config_path)
    computed.lib_version = lib_config.lib_version       # e.g., "v3.0.0"
    computed.lib_ref = lib_config.lib_ref               # e.g., "hiivmind/hiivmind-blueprint-lib@v3.0.0"
    computed.lib_raw_url = lib_config.lib_raw_url       # raw GitHub URL base
    computed.schema_version = lib_config.schema_version # e.g., "2.3"
  ELSE:
    # Fallback to hardcoded defaults
    computed.lib_version = "v3.0.0"
    computed.lib_ref = "hiivmind/hiivmind-blueprint-lib@v3.0.0"
    computed.lib_raw_url = "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v3.0.0"
    computed.schema_version = "2.3"
```

### Step 6.3: Write workflow.yaml

Assemble the full workflow.yaml content from `computed.workflow` and write it:

```pseudocode
WRITE_WORKFLOW():
  # Build the YAML document
  workflow_content = render_workflow_yaml(
    name:                computed.workflow.name,
    version:             computed.workflow.version,
    description:         computed.workflow.description,
    definitions_source:  computed.lib_ref,
    entry_preconditions: computed.workflow.entry_preconditions,
    initial_state:       computed.workflow.initial_state,
    start_node:          computed.workflow.start_node,
    nodes:               computed.workflow.nodes,
    endings:             computed.workflow.endings
  )

  # Add header comment
  header = "# Generated by bp-author-prose-migrate\n"
  header += "# Source: " + computed.analysis.skill_path + "\n"
  header += "# Generated: " + current_iso_timestamp() + "\n\n"

  Write(computed.target_directory + "/workflow.yaml", header + workflow_content)
  computed.files_written = ["workflow.yaml"]
```

Use the structure defined in `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
as the output format guide. Ensure:

- `definitions.source` references the lib_ref from BLUEPRINT_LIB_VERSION.yaml
- `initial_state` includes output and prompts configuration blocks
- Nodes are ordered: start node first, happy path in order, branches after branch points, error nodes last
- All node IDs use snake_case
- All endings include a `message` field

### Step 6.4: Generate SKILL.md

Generate the thin-loader SKILL.md using the template at
`${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`:

```pseudocode
GENERATE_SKILL_MD():
  template = Read(CLAUDE_PLUGIN_ROOT + "/templates/SKILL.md.template")

  # Determine the skill directory name (last segment of target path)
  skill_directory = basename(computed.target_directory)

  # Perform placeholder substitution
  skill_md = template
    .replace("{{skill_name}}", computed.workflow.name)
    .replace("{{description}}", computed.workflow.description)
    .replace("{{allowed_tools}}", computed.analysis.frontmatter.allowed_tools
                                   OR "Read, Write, Edit, Bash, Glob, AskUserQuestion")
    .replace("{{title}}", titlecase(computed.workflow.name.replace("-", " ")))
    .replace("{{parent_plugin_name}}", computed.analysis.plugin_name OR "hiivmind-blueprint-author")
    .replace("{{skill_short_name}}", skill_directory.split("-")[-1] OR skill_directory)
    .replace("{{skill_directory}}", skill_directory)
    .replace("{{lib_version}}", computed.lib_version)

  # Handle conditional sections
  IF computed.workflow has user_prompt nodes:
    # Keep runtime flags and intent detection sections
    skill_md = enable_section(skill_md, "if_runtime_flags")
    skill_md = enable_section(skill_md, "if_intent_detection")
  ELSE:
    skill_md = remove_section(skill_md, "if_runtime_flags")
    skill_md = remove_section(skill_md, "if_intent_detection")

  # Populate related skills section
  skill_md = populate_related_skills(skill_md, computed.analysis.related_skills)

  Write(computed.target_directory + "/SKILL.md", skill_md)
  computed.files_written.append("SKILL.md")
```

### Step 6.5: Configure Prompt Modes

If the workflow contains `user_prompt` nodes, determine the target interface:

```json
{
  "questions": [{
    "question": "What interface will this workflow primarily run on?",
    "header": "Interface",
    "multiSelect": false,
    "options": [
      {"label": "Claude Code CLI (Recommended)", "description": "Interactive mode with AskUserQuestion"},
      {"label": "Multi-interface", "description": "Support CLI, web, API, and agents"},
      {"label": "Text-based fallback", "description": "Tabular mode for non-Claude environments"},
      {"label": "Skip", "description": "Don't configure prompt modes"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PROMPT_MODE(response):
  SWITCH response:
    CASE "Claude Code CLI (Recommended)":
      # Default config already set in Step 2.3 -- no changes
      PASS
    CASE "Multi-interface":
      # Full multi-modal config already set in Step 2.3 -- verify all modes present
      ASSERT computed.workflow.initial_state.prompts.modes.web == "forms"
      ASSERT computed.workflow.initial_state.prompts.modes.api == "structured"
      ASSERT computed.workflow.initial_state.prompts.modes.agent == "autonomous"
    CASE "Text-based fallback":
      # Override to tabular-only mode
      computed.workflow.initial_state.prompts = {
        mode: "tabular",
        tabular: {
          match_strategy: "prefix",
          other_handler: "prompt"
        }
      }
      # Re-write workflow.yaml with updated prompts config
      GOTO Step 6.3
    CASE "Skip":
      # Remove prompts section entirely
      del computed.workflow.initial_state.prompts
      # Re-write workflow.yaml
      GOTO Step 6.3
```

### Step 6.6: Check for Validation Patterns

If the analysis detected validation-style conditionals (multiple assertions or checks
grouped together), offer audit mode:

```pseudocode
CHECK_AUDIT_MODE():
  IF computed.analysis.has_validation_patterns:
    # Ask user about audit mode
    ASK_USER_AUDIT_MODE()
  ELSE:
    SKIP to Phase 7
```

If the user opts for audit mode, iterate through conditional nodes that contain
composite `all_of` conditions and add `audit` configuration:

```yaml
# Example audit-enabled conditional
validate_prerequisites:
  type: conditional
  condition:
    type: all_of
    conditions:
      - type: tool_check
        tool: git
        capability: available
      - type: path_check
        path: "${config_path}"
        check: is_file
  audit:
    enabled: true
    output: computed.validation_errors
    messages:
      tool_check: "Required tool not installed"
      path_check: "Configuration file not found"
  branches:
    on_true: proceed
    on_false: show_validation_errors
```

After adding audit configuration, re-write workflow.yaml (return to Step 6.3).

---

## Phase 7: Report

### Step 7.1: Display Generation Summary

Present a final summary of everything that was generated:

```
## Migration Complete: {computed.workflow.name}

**Target directory:** {computed.target_directory}

### Files Created
- `workflow.yaml` -- {len(computed.workflow.nodes)} nodes, {len(computed.workflow.endings)} endings
- `SKILL.md` -- Thin loader with remote execution references

{if computed.backup_created}
### Backups Created
- `SKILL.md.backup` -- Original prose-based skill
- `workflow.yaml.backup` -- Previous workflow (if existed)
{/if}

### Workflow Structure
- **Start node:** {computed.workflow.start_node}
- **Node count:** {len(computed.workflow.nodes)}
- **Action nodes:** {count action nodes}
- **Conditional nodes:** {count conditional nodes}
- **User prompt nodes:** {count user_prompt nodes}
- **Ending count:** {len(computed.workflow.endings)}

### Execution Semantics
The SKILL.md references execution semantics from hiivmind-blueprint-lib@{computed.lib_version}
via raw GitHub URLs. This ensures the skill works in standalone plugins without local dependencies.

### Validation
{computed.workflow.validation.passed ? "All checks passed" : "Warnings present -- review above"}
```

### Step 7.2: Offer Next Steps

Ask the user what they want to do after generation:

```json
{
  "questions": [{
    "question": "Files generated successfully. What would you like to do next?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {"label": "Test the skill", "description": "Invoke the converted skill to verify it works"},
      {"label": "Show diff", "description": "Compare the original SKILL.md with the new workflow"},
      {"label": "Done", "description": "Migration complete, no further action"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_STEPS(response):
  SWITCH response:
    CASE "Test the skill":
      DISPLAY "Invoke the skill with:"
      DISPLAY ""
      DISPLAY "  Skill(skill: \"{computed.workflow.name}\")"
      DISPLAY ""
      DISPLAY "Or via the gateway command if configured."
    CASE "Show diff":
      IF computed.backup_created:
        Bash("diff {computed.target_directory}/SKILL.md.backup {computed.target_directory}/SKILL.md")
      ELSE:
        DISPLAY "No backup was created. Cannot show diff."
    CASE "Done":
      DISPLAY "Migration complete. {computed.workflow.name} is ready for use."
```

---

## Key State Flow

```
computed.analysis (from bp-author-prose-analyze)
    |
    v
Phase 1: Validate
    |
    v
Phase 2: computed.workflow.scaffold
    |        - name, version, description
    |        - entry_preconditions
    |        - initial_state (with output + prompts config)
    v
Phase 3: computed.workflow.nodes
    |        - action nodes
    |        - conditional nodes
    |        - user_prompt nodes
    |        - transition wiring
    v
Phase 4: computed.workflow.endings
    |        - success ending
    |        - error endings (common + skill-specific)
    v
Phase 5: computed.workflow.validation
    |        - structural checks
    |        - reachability
    |        - path-to-ending
    v
Phase 6: Written files
    |        - workflow.yaml
    |        - SKILL.md (thin loader)
    v
Phase 7: Report + next steps
```

---

## Reference Documentation

- **Node Generation Procedure:** `patterns/node-generation-procedure.md` (local to this skill)
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Consequence Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
- **Precondition Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
- **Prompt Modes Reference:** `${CLAUDE_PLUGIN_ROOT}/references/prompt-modes.md`
- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **BLUEPRINT_LIB_VERSION:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`

---

## Related Skills

- Skill discovery and inventory: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/SKILL.md`
- Deep skill analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`
- Plugin structure analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-analyze/SKILL.md`
- Batch conversion: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-batch/SKILL.md`
