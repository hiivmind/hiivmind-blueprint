---
name: bp-skill-create
description: >
  This skill should be used when the user asks to "create a new skill", "scaffold skill",
  "initialize skill", "new skill", "start new skill", "add skill to plugin",
  or needs to create a brand new skill from scratch. Triggers on
  "create skill", "new skill", "scaffold", "init skill", "add skill", "start skill".
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
inputs:
  - name: skill_name
    type: string
    required: false
    description: Kebab-case skill name (prompted if not provided)
outputs:
  - name: skill_path
    type: string
    description: Path to the created skill directory
  - name: files_created
    type: array
    description: List of all files created during scaffolding
---

# Scaffold New Skill from Templates

Create a brand new skill from scratch using the blueprint templates. A skill is a prose
orchestrator (SKILL.md) that optionally delegates specific phases to workflow definitions
in a `workflows/` subdirectory.

> **Placeholder Catalog:** `patterns/scaffold-checklist.md`
> **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
> **workflow.yaml Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
> **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

---

## Overview

This skill walks through a guided scaffolding process that:

1. Gathers skill name, description, inputs, and outputs from the user
2. Designs the skill's phases — which are prose-only, which are workflow-backed
3. Generates a populated SKILL.md with inputs/outputs/workflows frontmatter
4. Generates workflow files in `workflows/` for each workflow-backed phase
5. Creates any missing plugin infrastructure (plugin.json, definitions.yaml)
6. Validates all generated files and reports results

**Output artifacts:**

| File | Location | Generated From |
|------|----------|----------------|
| SKILL.md | `skills/{name}/SKILL.md` | `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template` |
| workflow(s) | `skills/{name}/workflows/*.yaml` | `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template` |
| plugin.json | `.claude-plugin/plugin.json` | Inline JSON (if not exists) |
| definitions.yaml | `.hiivmind/blueprint/definitions.yaml` | Copied from blueprint-lib catalog (if not exists) |

**Skill directory layout:**

```
skills/{skill-name}/
├── SKILL.md                    # Prose orchestrator (always present)
├── workflows/                  # Optional: workflow definitions
│   ├── {phase-name}.yaml      # One per workflow-backed phase
│   └── ...
└── patterns/                   # Optional: supporting pattern files
    └── *.md
```

---

## Phase 1: Gather Information

### Step 1.1: Get Skill Name

Ask the user for the name of the new skill. Use AskUserQuestion with free text input:

```json
{
  "questions": [{
    "question": "What should the new skill be named? Use kebab-case (e.g., 'my-plugin-analyze', 'repo-setup'). The name should follow the pattern: {plugin-prefix}-{action}.",
    "header": "Skill Name",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter name",
        "description": "Type a custom skill name in kebab-case"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_SKILL_NAME(response):
  raw_name = response.trim()

  # Validate kebab-case
  IF NOT matches(raw_name, /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/):
    DISPLAY "Invalid name. Use kebab-case: lowercase letters, numbers, hyphens only."
    DISPLAY "Examples: my-plugin-analyze, repo-setup, data-export"
    RETRY Step 1.1

  computed.skill_name = raw_name
  computed.skill_directory = raw_name

  # Derive short name (last segment after final hyphen group)
  segments = split(raw_name, "-")
  IF len(segments) > 2:
    computed.skill_short_name = join(segments[-2:], "-")
  ELSE:
    computed.skill_short_name = segments[-1]

  # Derive title from name
  computed.title = title_case(replace(raw_name, "-", " "))
```

Store in `computed.skill_name`, `computed.skill_directory`, `computed.skill_short_name`, and `computed.title`.

### Step 1.2: Get Skill Description

Ask for a one-line description of what the skill does:

```json
{
  "questions": [{
    "question": "Describe what this skill does in one sentence (used for the frontmatter description and trigger keyword matching).",
    "header": "Description",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter description",
        "description": "One sentence describing what the skill does and when to use it"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_DESCRIPTION(response):
  raw_desc = response.trim()

  # Build frontmatter description with trigger keywords
  computed.description = "This skill should be used when the user asks to \""
    + raw_desc + "\". Triggers on \""
    + computed.skill_short_name + "\"."

  # Validate length
  IF len(computed.description) > 1024:
    DISPLAY "Description too long (max 1024 chars). Please shorten."
    RETRY Step 1.2
```

### Step 1.3: Get Inputs and Outputs

Ask the user to define the skill's inputs (what it needs) and outputs (what it produces):

```json
{
  "questions": [{
    "question": "What inputs does this skill need? List each as 'name: description' (one per line), or type 'none' if the skill takes no inputs.",
    "header": "Inputs",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter inputs",
        "description": "One input per line: 'name: description'"
      },
      {
        "label": "No inputs",
        "description": "This skill takes no explicit inputs"
      }
    ]
  }]
}
```

Then ask for outputs:

```json
{
  "questions": [{
    "question": "What outputs does this skill produce? List each as 'name: description' (one per line), or type 'none'.",
    "header": "Outputs",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter outputs",
        "description": "One output per line: 'name: description'"
      },
      {
        "label": "No outputs",
        "description": "This skill produces no structured outputs"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_INPUTS_OUTPUTS(input_response, output_response):
  # Parse inputs
  IF input_response == "No inputs":
    computed.inputs = []
  ELSE:
    computed.inputs = []
    FOR line IN split(input_response, "\n"):
      parts = split(line, ":", max=2)
      computed.inputs.append({
        name: trim(parts[0]),
        type: "string",           # Default; user can refine later
        required: true,
        description: trim(parts[1]) IF len(parts) > 1 ELSE ""
      })

  # Parse outputs
  IF output_response == "No outputs":
    computed.outputs = []
  ELSE:
    computed.outputs = []
    FOR line IN split(output_response, "\n"):
      parts = split(line, ":", max=2)
      computed.outputs.append({
        name: trim(parts[0]),
        type: "string",
        description: trim(parts[1]) IF len(parts) > 1 ELSE ""
      })
```

### Step 1.4: Get Plugin Structure

Ask the user what type of plugin this skill belongs to:

```json
{
  "questions": [{
    "question": "What type of plugin structure is this skill part of?",
    "header": "Structure",
    "multiSelect": false,
    "options": [
      {
        "label": "Single-skill plugin",
        "description": "One skill only, no gateway"
      },
      {
        "label": "Multi-skill plugin",
        "description": "Multiple skills, no gateway routing"
      },
      {
        "label": "Multi-skill with gateway",
        "description": "Multiple skills with intent-based routing"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_STRUCTURE(response):
  SWITCH response:
    CASE "Single-skill plugin":
      computed.structure = "single"
      computed.needs_gateway = false
    CASE "Multi-skill plugin":
      computed.structure = "multi"
      computed.needs_gateway = false
    CASE "Multi-skill with gateway":
      computed.structure = "multi-gateway"
      computed.needs_gateway = true
```

### Step 1.5: Get Feature Selections

Ask the user which optional features the skill should include:

```json
{
  "questions": [{
    "question": "Which optional features should the new skill include?",
    "header": "Features",
    "multiSelect": true,
    "options": [
      {
        "label": "Intent detection",
        "description": "Parse user input for intent flags and route to actions"
      },
      {
        "label": "Runtime flags",
        "description": "Support --verbose, --quiet, --debug, --no-log flags"
      },
      {
        "label": "Help system",
        "description": "Include --help flag and help display sections"
      },
      {
        "label": "Visualization",
        "description": "Include ASCII workflow graph in SKILL.md"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_FEATURES(response):
  computed.features = {
    intent_detection: "Intent detection" IN response,
    runtime_flags:    "Runtime flags" IN response,
    help_system:      "Help system" IN response,
    visualization:    "Visualization" IN response
  }
```

---

## Phase 2: Design Phases

### Step 2.1: Define Skill Phases

Ask the user to describe the major phases of their skill. Each phase is either prose
(LLM follows instructions directly) or workflow-backed (delegates to a YAML workflow).

```json
{
  "questions": [{
    "question": "Describe the major phases of this skill. For each phase, indicate whether it's prose-driven or workflow-backed.\n\nExamples:\n- 'Gather: Read files and collect data (prose)'\n- 'Validate: Check all prerequisites (workflow)'\n- 'Report: Display results to user (prose)'",
    "header": "Phases",
    "multiSelect": false,
    "options": [
      {
        "label": "Enter phases",
        "description": "One phase per line: 'Name: Description (prose|workflow)'"
      },
      {
        "label": "Simple skill",
        "description": "Single prose phase — no workflow definitions needed"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PHASES(response):
  IF response == "Simple skill":
    computed.phases = [{
      number: 1,
      title: "Execute",
      type: "prose",
      prose_instructions: "TODO: Add execution instructions here."
    }]
    computed.workflow_phases = []
    RETURN

  computed.phases = []
  computed.workflow_phases = []
  phase_number = 1

  FOR line IN split(response, "\n"):
    # Parse "Name: Description (prose|workflow)"
    match = regex(line, /^(.+?):\s*(.+?)\s*\((prose|workflow)\)\s*$/)
    IF match:
      phase = {
        number: phase_number,
        title: trim(match[1]),
        type: match[3],                    # "prose" or "workflow"
        description: trim(match[2])
      }

      IF phase.type == "prose":
        phase.prose_instructions = "TODO: Add " + phase.title + " instructions here."
      ELSE:
        # Derive workflow filename from phase title
        workflow_filename = kebab_case(phase.title) + ".yaml"
        phase.workflow_file = workflow_filename
        computed.workflow_phases.append({
          filename: workflow_filename,
          workflow_id: computed.skill_name + "-" + kebab_case(phase.title),
          description: phase.description,
          phase_title: phase.title
        })

      computed.phases.append(phase)
      phase_number += 1
```

### Step 2.2: Display Phase Summary

Present the designed phases for user confirmation:

```
## Phase Design

| # | Phase | Type | Artifact |
|---|-------|------|----------|
{for phase in computed.phases}
| {phase.number} | {phase.title} | {phase.type} | {phase.workflow_file OR "—"} |
{/for}

Coverage: {computed.coverage}
Workflow files to generate: {len(computed.workflow_phases)}

Proceed with this design? [Y/n]
```

```pseudocode
COMPUTE_COVERAGE():
  IF len(computed.workflow_phases) == 0:
    computed.coverage = "none"
  ELSE IF len(computed.workflow_phases) == len(computed.phases):
    computed.coverage = "full"
  ELSE:
    computed.coverage = "partial"
```

---

## Phase 3: Generate SKILL.md

### Step 3.1: Detect Context

Examine the current working directory for existing plugin infrastructure:

```pseudocode
DETECT_CONTEXT():
  # Check for plugin manifest
  plugin_manifest_files = Glob(".claude-plugin/plugin.json")
  computed.context.has_plugin_manifest = len(plugin_manifest_files) > 0

  # Check for skills directory
  skills_dirs = Glob("skills/")
  computed.context.has_skills_dir = len(skills_dirs) > 0

  # Check for existing skills (to derive parent plugin name)
  existing_skills = Glob("skills/*/SKILL.md")
  computed.context.existing_skill_count = len(existing_skills)

  # Check for definitions file
  definitions_files = Glob(".hiivmind/blueprint/definitions.yaml")
  computed.context.has_definitions = len(definitions_files) > 0

  # Check for existing gateway command
  gateway_files = Glob("commands/*/SKILL.md")
  computed.context.has_gateway = len(gateway_files) > 0

  # If plugin.json exists, extract parent plugin name
  IF computed.context.has_plugin_manifest:
    manifest = Read(".claude-plugin/plugin.json")
    computed.parent_plugin_name = extract_json(manifest, ".name")
  ELSE:
    computed.parent_plugin_name = basename(cwd())
```

### Step 3.2: Create Directories

```pseudocode
CREATE_DIRECTORIES():
  # Create skills/ if needed
  IF NOT computed.context.has_skills_dir:
    Bash("mkdir -p skills/")

  # Create skill directory
  skill_path = "skills/" + computed.skill_directory
  Bash("mkdir -p " + skill_path)
  computed.skill_path = skill_path

  # Create workflows/ if any workflow-backed phases
  IF len(computed.workflow_phases) > 0:
    Bash("mkdir -p " + skill_path + "/workflows/")

  # Create .hiivmind/blueprint/ if definitions needed
  IF NOT computed.context.has_definitions:
    Bash("mkdir -p .hiivmind/blueprint/")

  # Create .claude-plugin/ if plugin manifest needed
  IF NOT computed.context.has_plugin_manifest:
    Bash("mkdir -p .claude-plugin/")
```

### Step 3.3: Load and Populate SKILL.md Template

Read the SKILL.md template and substitute all placeholders:

```pseudocode
GENERATE_SKILL_MD():
  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template"
  template = Read(template_path)

  IF template IS EMPTY:
    FAIL "Could not read SKILL.md template at: " + template_path

  result = template

  # ── Core substitutions ──
  result = replace(result, "{{skill_name}}", computed.skill_name)
  result = replace(result, "{{description}}", computed.description)
  result = replace(result, "{{allowed_tools}}", compute_allowed_tools())
  result = replace(result, "{{title}}", computed.title)
  result = replace(result, "{{parent_plugin_name}}", computed.parent_plugin_name)
  result = replace(result, "{{skill_short_name}}", computed.skill_short_name)
  result = replace(result, "{{skill_directory}}", computed.skill_directory)
  result = replace(result, "{{overview}}", computed.phases[0].description
    OR "TODO: Add skill overview here.")

  # ── Inputs/Outputs ──
  result = populate_inputs_section(result, computed.inputs)
  result = populate_outputs_section(result, computed.outputs)

  # ── Workflows list ──
  IF len(computed.workflow_phases) > 0:
    result = enable_section(result, "if_workflows")
    result = populate_workflows_list(result, computed.workflow_phases)
  ELSE:
    result = remove_section(result, "if_workflows")

  # ── Phases ──
  result = populate_phases(result, computed.phases)

  # ── Conditional sections ──
  IF computed.features.runtime_flags:
    result = enable_section(result, "if_runtime_flags")
  ELSE:
    result = remove_section(result, "if_runtime_flags")

  IF computed.features.intent_detection:
    result = enable_section(result, "if_intent_detection")
  ELSE:
    result = remove_section(result, "if_intent_detection")

  IF computed.features.visualization:
    result = enable_section(result, "workflow_graph")
    result = replace(result, "{{graph_ascii}}", generate_starter_graph())
  ELSE:
    result = remove_section(result, "workflow_graph")

  # ── Examples and related skills ──
  result = enable_section(result, "examples")
  result = populate_starter_examples(result)
  result = enable_section(result, "related_skills")
  result = populate_related_skills(result)

  RETURN result
```

**Helper: populate_phases():**

```pseudocode
function populate_phases(template, phases):
  phases_content = ""

  FOR phase IN phases:
    phases_content += "### Phase " + str(phase.number) + ": " + phase.title + "\n\n"

    IF phase.type == "prose":
      phases_content += phase.prose_instructions + "\n\n"
    ELSE:
      phases_content += "Execute `workflows/" + phase.workflow_file
        + "` following the execution guide:\n\n"
      phases_content += "1. Read `.hiivmind/blueprint/definitions.yaml` — build type registry\n"
      phases_content += "2. Read `${CLAUDE_PLUGIN_ROOT}/skills/"
        + computed.skill_directory + "/workflows/" + phase.workflow_file + "`\n"
      phases_content += "3. Follow `.hiivmind/blueprint/execution-guide.md` (Init → Execute → Complete)\n\n"

  # Replace the {{#phases}} ... {{/phases}} block with generated content
  RETURN replace_section(template, "phases", phases_content)
```

**Helper: compute_allowed_tools():**

```pseudocode
function compute_allowed_tools():
  tools = ["Read", "Write", "Glob", "Bash", "AskUserQuestion"]
  RETURN join(tools, ", ")
```

### Step 3.4: Write SKILL.md

```pseudocode
WRITE_SKILL_MD():
  output_path = computed.skill_path + "/SKILL.md"
  Write(output_path, computed.populated_skill_template)
  computed.files_created.append(output_path)

  DISPLAY "Created: " + output_path
```

---

## Phase 4: Generate Workflow Files

For each workflow-backed phase, generate a workflow YAML file in the `workflows/` subdirectory.

### Step 4.1: Load Workflow Template

```pseudocode
LOAD_WORKFLOW_TEMPLATE():
  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template"
  computed.workflow_template = Read(template_path)

  IF computed.workflow_template IS EMPTY:
    FAIL "Could not read workflow.yaml template at: " + template_path
```

### Step 4.2: Generate Each Workflow File

For each entry in `computed.workflow_phases`, substitute placeholders and generate starter nodes:

```pseudocode
GENERATE_WORKFLOWS():
  FOR wf IN computed.workflow_phases:
    result = computed.workflow_template

    # Core substitutions — note: {{workflow_id}} not {{skill_id}}
    result = replace(result, "{{workflow_id}}", wf.workflow_id)
    result = replace(result, "{{description}}", wf.description)
    result = replace(result, "{{state_variables}}", "phase, flags, computed")
    result = replace(result, "{{start_node}}", "start_" + kebab_to_snake(wf.phase_title))
    result = replace(result, "{{success_message}}", wf.phase_title + " completed successfully")

    # Build starter nodes for this workflow
    nodes = build_workflow_starter_nodes(wf)
    result = replace_nodes_section(result, nodes)

    # Write to workflows/ subdirectory
    output_path = computed.skill_path + "/workflows/" + wf.filename
    Write(output_path, result)
    computed.files_created.append(output_path)

    DISPLAY "Created: " + output_path
```

**Helper: build_workflow_starter_nodes():**

```pseudocode
function build_workflow_starter_nodes(wf):
  start_id = "start_" + kebab_to_snake(wf.phase_title)
  nodes = []

  # Start node
  nodes.append({
    id: start_id,
    type: "action",
    description: "Begin " + wf.phase_title,
    actions: [{
      type: "mutate_state",
      operation: "set",
      field: "phase",
      value: wf.phase_title
    }],
    on_success: "complete",
    on_failure: "error_execution"
  })

  # Completion node
  nodes.append({
    id: "complete",
    type: "action",
    description: "Finalize " + wf.phase_title + " results",
    actions: [{
      type: "display",
      format: "text",
      content: wf.phase_title + " complete."
    }],
    on_success: "success",
    on_failure: "error_execution"
  })

  RETURN nodes
```

**If no workflow phases:** Skip this entire phase.

```pseudocode
IF len(computed.workflow_phases) == 0:
  DISPLAY "No workflow-backed phases — skipping workflow generation."
  SKIP Phase 4
```

---

## Phase 5: Create Plugin Infrastructure

Create any missing infrastructure files.

### Step 5.1: Create Plugin Manifest

If `.claude-plugin/plugin.json` does not exist, create it:

```pseudocode
CREATE_PLUGIN_MANIFEST():
  IF computed.context.has_plugin_manifest:
    # Add skill to existing manifest if not already listed
    manifest = Read(".claude-plugin/plugin.json")
    parsed = json_parse(manifest)
    skill_entry = find(parsed.skills, s => s.name == computed.skill_name)
    IF skill_entry IS NULL:
      parsed.skills.append({
        "name": computed.skill_name,
        "path": "skills/" + computed.skill_directory + "/SKILL.md"
      })
      Write(".claude-plugin/plugin.json", json_format(parsed, indent=2))
      computed.files_updated.append(".claude-plugin/plugin.json")
      DISPLAY "Updated: .claude-plugin/plugin.json (added skill entry)"
    RETURN

  # Create new manifest
  manifest = {
    "name": computed.parent_plugin_name,
    "version": "1.0.0",
    "description": "Plugin containing " + computed.skill_name,
    "skills": [
      {
        "name": computed.skill_name,
        "path": "skills/" + computed.skill_directory + "/SKILL.md"
      }
    ]
  }

  Write(".claude-plugin/plugin.json", json_format(manifest, indent=2))
  computed.files_created.append(".claude-plugin/plugin.json")
  DISPLAY "Created: .claude-plugin/plugin.json"
```

### Step 5.2: Create Definitions File

If `.hiivmind/blueprint/definitions.yaml` does not exist, create a starter definitions file
with common types. The user should copy specific types from the hiivmind-blueprint-lib catalog
as needed.

```pseudocode
CREATE_DEFINITIONS():
  IF computed.context.has_definitions:
    SKIP "Definitions file already exists"
    RETURN

  Bash("mkdir -p .hiivmind/blueprint/")

  starter_definitions = """
# Type definitions for workflow execution
# Copy needed types from hiivmind-blueprint-lib catalog
# See: https://github.com/hiivmind/hiivmind-blueprint-lib

nodes:
  action:
    description: "Execute consequences, route on success/failure"
    execution:
      effect: |
        for action in node.actions:
          result = dispatch_consequence(action, state)
          if result.failed: return route_to(node.on_failure)
        return route_to(node.on_success)

  conditional:
    description: "Evaluate precondition and branch"
    execution:
      effect: |
        if audit.enabled:
          results = evaluate_all(node.condition)
          store(audit.output, results)
          passed = results.passed
        else:
          passed = evaluate(node.condition)
        return route_to(branches.on_true if passed else branches.on_false)

  user_prompt:
    description: "Present question to user, route by response"
    execution:
      effect: |
        prompt = build_prompt(node.prompt, state)
        response = present_and_await(prompt)
        state.user_responses[node_id] = response
        handler = node.on_response[response.selected_id]
        if handler.consequence: execute_each(handler.consequence)
        return route_to(handler.next_node)

consequences:
  mutate_state:
    description: "Modify workflow state"
    parameters:
      - name: operation
        type: string
        required: true
        enum: [set, append, clear, merge]
      - name: field
        type: string
        required: true
      - name: value
        type: any
        required: false
    payload:
      kind: state_mutation
      effect: |
        if operation == "set":    state[field] = value
        if operation == "append": state[field].push(value)
        if operation == "clear":  state[field] = null
        if operation == "merge":  state[field] = merge(state[field], value)

  set_flag:
    description: "Set boolean flag in workflow state"
    parameters:
      - name: flag
        type: string
        required: true
      - name: value
        type: boolean
        default: true
    payload:
      kind: state_mutation
      effect: |
        state.flags[params.flag] = params.value

  display:
    description: "Display content to user"
    parameters:
      - name: format
        type: string
        required: true
        enum: [text, table, json, markdown]
      - name: content
        type: any
        required: true
    payload:
      kind: side_effect
      effect: |
        render(params.content, format=params.format)

preconditions:
  state_check:
    description: "Check state field against a condition"
    parameters:
      - name: field
        type: string
        required: true
      - name: operator
        type: string
        required: true
    evaluation:
      effect: |
        val = resolve_path(state, field)
        if operator == "not_null": return val != null
        if operator == "equals":   return val == value
        if operator == "true":     return val == true

  composite:
    description: "Combine conditions with logical operators"
    parameters:
      - name: operator
        type: string
        required: true
        enum: [all, any, none, xor]
      - name: conditions
        type: array
        required: true
    evaluation:
      effect: |
        if operator == "all":  return all(evaluate(c) for c in conditions)
        if operator == "any":  return any(evaluate(c) for c in conditions)
        if operator == "none": return not any(evaluate(c) for c in conditions)
        if operator == "xor":  return sum(evaluate(c) for c in conditions) == 1
"""

  Write(".hiivmind/blueprint/definitions.yaml", starter_definitions)
  computed.files_created.append(".hiivmind/blueprint/definitions.yaml")
  DISPLAY "Created: .hiivmind/blueprint/definitions.yaml (starter types — add more from catalog as needed)"
```

---

## Phase 6: Validate and Report

### Step 6.1: Validate Generated Files

Check that all expected files exist and are non-empty:

```pseudocode
VALIDATE_FILES():
  computed.validation = { passed: [], failed: [] }

  expected_files = [
    computed.skill_path + "/SKILL.md"
  ]

  # Add workflow files
  FOR wf IN computed.workflow_phases:
    expected_files.append(computed.skill_path + "/workflows/" + wf.filename)

  # Add infrastructure files
  IF ".claude-plugin/plugin.json" IN computed.files_created:
    expected_files.append(".claude-plugin/plugin.json")
  IF ".hiivmind/blueprint/definitions.yaml" IN computed.files_created:
    expected_files.append(".hiivmind/blueprint/definitions.yaml")

  FOR file IN expected_files:
    IF file_exists(file) AND file_size(file) > 0:
      computed.validation.passed.append(file)
    ELSE:
      computed.validation.failed.append(file)

  IF len(computed.validation.failed) > 0:
    DISPLAY "WARNING: Some files failed validation:"
    FOR file IN computed.validation.failed:
      DISPLAY "  - MISSING: " + file
```

### Step 6.2: Display Summary

```
## Scaffold Complete: {computed.skill_name}

### Files Created

| File | Status |
|------|--------|
{for file in computed.files_created}
| `{file}` | Created |
{/for}
{for file in computed.files_updated}
| `{file}` | Updated |
{/for}

### Directory Structure

{computed.parent_plugin_name}/
├── .claude-plugin/
│   └── plugin.json {new/existing}
├── .hiivmind/
│   └── blueprint/
│       └── definitions.yaml {new/existing}
├── skills/
│   └── {computed.skill_directory}/
│       ├── SKILL.md          ← NEW
{if len(computed.workflow_phases) > 0}
│       └── workflows/
{for wf in computed.workflow_phases}
│           └── {wf.filename}  ← NEW
{/for}
{/if}

### Configuration

- **Skill name:** {computed.skill_name}
- **Plugin structure:** {computed.structure}
- **Coverage:** {computed.coverage}
- **Phases:** {len(computed.phases)} ({len(computed.workflow_phases)} workflow-backed)
- **Inputs:** {len(computed.inputs)}
- **Outputs:** {len(computed.outputs)}

### Next Steps

1. **Fill in prose phases** — Replace TODO placeholders in SKILL.md with real instructions
{if len(computed.workflow_phases) > 0}
2. **Add workflow nodes** — Expand starter nodes in `workflows/*.yaml` with domain-specific logic
3. **Add definitions** — Copy needed types from hiivmind-blueprint-lib catalog into definitions.yaml
{/if}
4. **Refine description** — Update frontmatter description with accurate trigger keywords
{if computed.needs_gateway AND NOT computed.context.has_gateway}
5. **Create gateway** — Run `bp-gateway-create` to set up gateway routing
{/if}
6. **Test the skill** — Invoke with `Skill(skill: "{computed.skill_name}")`
```

### Step 6.3: Offer Next Actions

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {
        "label": "Edit SKILL.md",
        "description": "Open the generated SKILL.md to fill in prose phases"
      },
      {
        "label": "Edit workflows",
        "description": "Open the generated workflow files to add nodes"
      },
      {
        "label": "Add another skill",
        "description": "Scaffold another skill in the same plugin"
      },
      {
        "label": "Done",
        "description": "Scaffolding complete, no further action needed"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_ACTION(response):
  SWITCH response:
    CASE "Edit SKILL.md":
      skill_path = computed.skill_path + "/SKILL.md"
      DISPLAY "Opening " + skill_path + " for editing."
      content = Read(skill_path)
      DISPLAY content
      EXIT

    CASE "Edit workflows":
      FOR wf IN computed.workflow_phases:
        wf_path = computed.skill_path + "/workflows/" + wf.filename
        DISPLAY "---"
        DISPLAY "### " + wf.filename
        content = Read(wf_path)
        DISPLAY content
      EXIT

    CASE "Add another skill":
      DISPLAY "Starting new skill scaffold..."
      computed.files_created = []
      computed.files_updated = []
      GOTO Phase 1, Step 1.1

    CASE "Done":
      DISPLAY "Scaffold complete. " + str(len(computed.files_created)) + " files created."
      EXIT
```

---

## Reference Documentation

- **Placeholder Catalog:** `patterns/scaffold-checklist.md` (local to this skill)
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Execution Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/execution-guide.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
- **workflow.yaml Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`

---

## Related Skills

- Skill analysis (coverage, complexity, extraction candidates): `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-analyze/SKILL.md`
- Workflow extraction from prose phases: `${CLAUDE_PLUGIN_ROOT}/skills/bp-workflow-extract/SKILL.md`
- Skill validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/SKILL.md`
- Gateway creation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-gateway-create/SKILL.md`
- Plugin discovery: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-discover/SKILL.md`
