---
name: bp-build
description: >
  This skill should be used when the user asks to "create a new skill", "scaffold skill",
  "build a skill", "new skill from scratch", "start a new skill", "add skill to plugin",
  "build from idea". Triggers on "create", "new", "build", "scaffold", "idea",
  "start skill", "add skill".
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

# Build New Skill from Idea

Create a brand new skill from scratch using the blueprint templates. A skill is a prose
orchestrator (SKILL.md) that optionally delegates specific phases to workflow definitions
in a `workflows/` subdirectory.

> **Placeholder Catalog:** `patterns/scaffold-checklist.md`
> **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
> **workflow.yaml Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
> **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

---

## Overview

This skill walks through a guided build process that:

1. Detects invocation mode from flags (scaffold-only, target engine, or full guided flow)
2. Gathers skill name, description, inputs, outputs, and feature selections from the user
3. Designs the skill's phases — which are prose-only, which are workflow-backed
4. Scaffolds all files (SKILL.md, workflows, plugin infrastructure)
5. Selects target engine for output format (placeholder — defaults to Claude Code)
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

## Phase 1: Mode Detection

Parse invocation arguments to determine build mode and behavior.

### Step 1.1: Parse Flags

Inspect invocation arguments for mode flags:

```pseudocode
PARSE_MODE(args):
  computed.mode = "full"
  computed.scaffold_only = false
  computed.target_engine = null

  IF args contains "--scaffold-only":
    computed.mode = "scaffold-only"
    computed.scaffold_only = true
    # Requires skill_name input — skip to Phase 4 (Scaffold)
    IF inputs.skill_name IS NULL:
      FAIL "--scaffold-only requires a skill_name input"
    computed.skill_name = inputs.skill_name
    SKIP to Phase 4

  ELIF args contains "--target <engine>":
    computed.mode = "target"
    computed.target_engine = extract_value(args, "--target")
    # Re-export existing skill for a different engine — Phase 5 only
    IF inputs.skill_name IS NULL:
      FAIL "--target requires a skill_name input"
    computed.skill_name = inputs.skill_name
    SKIP to Phase 5

  ELSE:
    computed.mode = "full"
    # Full guided flow: Phase 2 → 3 → 4 → 5 → 6
```

### Step 1.2: Resolve Skill Name from Input

If `inputs.skill_name` was provided (and mode is "full"), pre-populate it:

```pseudocode
RESOLVE_INPUT_NAME():
  IF inputs.skill_name IS NOT NULL:
    raw_name = inputs.skill_name.trim()
    IF matches(raw_name, /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/):
      computed.skill_name = raw_name
      computed.skill_name_from_input = true
      # Still run full flow but skip the name prompt in Phase 2
    ELSE:
      DISPLAY "Provided skill_name is not valid kebab-case. Will prompt."
      computed.skill_name_from_input = false
  ELSE:
    computed.skill_name_from_input = false
```

---

## Phase 2: Gather

Collect all information needed to build the skill.

### Step 2.1: Get Skill Name

If `computed.skill_name_from_input` is true, skip this step.

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
    RETRY Step 2.1

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

### Step 2.2: Get Skill Description

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
    RETRY Step 2.2
```

### Step 2.3: Get Inputs and Outputs

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

### Step 2.4: Get Plugin Structure

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

### Step 2.5: Get Feature Selections

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

## Phase 3: Design

Define the skill's phase structure and confirm with the user.

### Step 3.1: Define Skill Phases

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

### Step 3.2: Display Phase Summary

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

## Phase 4: Scaffold

Generate all files: SKILL.md, workflow files, and plugin infrastructure.

### Step 4.1: Detect Context

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
  gateway_files = Glob("commands/*.md")
  gateway_files += Glob("commands/*/SKILL.md")
  computed.context.has_gateway = len(gateway_files) > 0

  # Check for existing execution guide
  exec_guide_files = Glob(".hiivmind/blueprint/execution-guide.md")
  computed.context.has_execution_guide = len(exec_guide_files) > 0

  # Check for existing engine entrypoint
  entrypoint_files = Glob(".hiivmind/blueprint/engine_entrypoint.md")
  computed.context.has_engine_entrypoint = len(entrypoint_files) > 0

  # Check for existing config
  config_files = Glob(".hiivmind/blueprint/config.yaml")
  computed.context.has_config = len(config_files) > 0

  # If plugin.json exists, extract parent plugin name
  IF computed.context.has_plugin_manifest:
    manifest = Read(".claude-plugin/plugin.json")
    computed.parent_plugin_name = extract_json(manifest, ".name")
  ELSE:
    computed.parent_plugin_name = basename(cwd())
```

### Step 4.2: Create Directories

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

### Step 4.3: Load and Populate SKILL.md Template

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

### Step 4.4: Write SKILL.md

```pseudocode
WRITE_SKILL_MD():
  output_path = computed.skill_path + "/SKILL.md"
  Write(output_path, computed.populated_skill_template)
  computed.files_created.append(output_path)

  DISPLAY "Created: " + output_path
```

### Step 4.5: Generate Workflow Files

For each workflow-backed phase, generate a workflow YAML file in the `workflows/` subdirectory.

**Load workflow template:**

```pseudocode
LOAD_WORKFLOW_TEMPLATE():
  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template"
  computed.workflow_template = Read(template_path)

  IF computed.workflow_template IS EMPTY:
    FAIL "Could not read workflow.yaml template at: " + template_path
```

**Generate each workflow file:**

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

**If no workflow phases:** Skip workflow generation.

```pseudocode
IF len(computed.workflow_phases) == 0:
  DISPLAY "No workflow-backed phases — skipping workflow generation."
  SKIP Step 4.5
```

### Step 4.6: Create Plugin Infrastructure

Create any missing infrastructure files.

**Create plugin manifest:**

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

**Create definitions file:**

If `.hiivmind/blueprint/definitions.yaml` does not exist, create it by scanning the plugin's
workflow files for used types and pulling matching definitions from the blueprint-lib catalog.
If the file already exists, perform an idempotent merge of any newly-referenced types.

```pseudocode
SCAN_WORKFLOW_TYPES():
  # Scan all workflow YAML files for type references
  consequence_types = set()
  precondition_types = set()

  workflow_files = Glob("skills/*/workflows/*.yaml")
  workflow_files += Glob("commands/*/workflow.yaml")

  FOR wf_path IN workflow_files:
    wf = READ_YAML(wf_path)

    # Scan action nodes for consequence types
    FOR node_id, node IN wf.nodes:
      IF node.type == "action" AND "actions" IN node:
        FOR action IN node.actions:
          IF "type" IN action:
            consequence_types.add(action.type)

      # Scan conditional nodes for precondition types
      IF node.type == "conditional" AND "condition" IN node:
        precondition_types.add(node.condition.type)
        IF node.condition.type IN ["composite", "all_of", "any_of", "none_of", "xor_of"]:
          FOR sub IN (node.condition.conditions OR []):
            IF "type" IN sub:
              precondition_types.add(sub.type)

      # Scan user_prompt consequence handlers
      IF node.type == "user_prompt" AND "on_response" IN node:
        FOR resp_id, handler IN node.on_response:
          IF "consequence" IN handler:
            FOR action IN handler.consequence:
              IF "type" IN action:
                consequence_types.add(action.type)

    # Scan entry_preconditions
    IF "entry_preconditions" IN wf:
      FOR pre IN wf.entry_preconditions:
        IF "type" IN pre:
          precondition_types.add(pre.type)

  RETURN { consequence_types, precondition_types }


CREATE_DEFINITIONS():
  Bash("mkdir -p .hiivmind/blueprint/")

  scanned = SCAN_WORKFLOW_TYPES()

  IF computed.context.has_definitions:
    # Idempotent merge: add any new types not already in definitions
    existing = READ_YAML(".hiivmind/blueprint/definitions.yaml")
    existing_consequence_types = set(existing.consequences.keys()) IF existing.consequences ELSE set()
    existing_precondition_types = set(existing.preconditions.keys()) IF existing.preconditions ELSE set()

    new_consequences = scanned.consequence_types - existing_consequence_types
    new_preconditions = scanned.precondition_types - existing_precondition_types

    IF len(new_consequences) == 0 AND len(new_preconditions) == 0:
      DISPLAY "Definitions file up to date — no new types found"
      RETURN

    # Merge new types from catalog into existing file
    FOR type_name IN new_consequences:
      catalog_def = LOOKUP_CATALOG_CONSEQUENCE(type_name)
      IF catalog_def:
        existing.consequences[type_name] = catalog_def

    FOR type_name IN new_preconditions:
      catalog_def = LOOKUP_CATALOG_PRECONDITION(type_name)
      IF catalog_def:
        existing.preconditions[type_name] = catalog_def

    Write(".hiivmind/blueprint/definitions.yaml", YAML_DUMP(existing))
    computed.files_updated.append(".hiivmind/blueprint/definitions.yaml")
    DISPLAY "Updated: .hiivmind/blueprint/definitions.yaml (added " +
            str(len(new_consequences) + len(new_preconditions)) + " types)"
    RETURN

  # New file: build from scan results + catalog
  definitions = BUILD_DEFINITIONS_FROM_CATALOG(scanned)
  Write(".hiivmind/blueprint/definitions.yaml", definitions)
  computed.files_created.append(".hiivmind/blueprint/definitions.yaml")
  DISPLAY "Created: .hiivmind/blueprint/definitions.yaml (" +
          str(len(scanned.consequence_types)) + " consequence types, " +
          str(len(scanned.precondition_types)) + " precondition types from workflow scan)"
```

**Create execution guide:**

Copy the execution guide from the framework's authoritative source to the target plugin.

```pseudocode
CREATE_EXECUTION_GUIDE():
  IF file_exists(".hiivmind/blueprint/execution-guide.md"):
    SKIP "Execution guide already exists"
    RETURN

  Bash("mkdir -p .hiivmind/blueprint/")

  source_path = "${CLAUDE_PLUGIN_ROOT}/lib/patterns/execution-guide.md"
  content = Read(source_path)

  IF content IS EMPTY:
    DISPLAY "WARNING: Could not read execution guide from: " + source_path
    RETURN

  Write(".hiivmind/blueprint/execution-guide.md", content)
  computed.files_created.append(".hiivmind/blueprint/execution-guide.md")
  DISPLAY "Created: .hiivmind/blueprint/execution-guide.md"
```

**Create engine entrypoint (gateway plugins only):**

For plugins with a gateway command, provision the engine entrypoint from template.

```pseudocode
CREATE_ENGINE_ENTRYPOINT():
  IF NOT computed.context.has_gateway:
    RETURN  # Not a gateway plugin — engine entrypoint not needed

  IF file_exists(".hiivmind/blueprint/engine_entrypoint.md"):
    SKIP "Engine entrypoint already exists"
    RETURN

  Bash("mkdir -p .hiivmind/blueprint/")

  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template"
  template = Read(template_path)

  IF template IS EMPTY:
    DISPLAY "WARNING: Could not read engine entrypoint template from: " + template_path
    RETURN

  result = template
  result = replace(result, "{{engine_version}}", "2.0.0")
  # Remove {{#if_gateway}}...{{/if_gateway}} markers (keep content — this IS a gateway plugin)
  result = replace(result, "{{#if_gateway}}", "")
  result = replace(result, "{{/if_gateway}}", "")

  Write(".hiivmind/blueprint/engine_entrypoint.md", result)
  computed.files_created.append(".hiivmind/blueprint/engine_entrypoint.md")
  DISPLAY "Created: .hiivmind/blueprint/engine_entrypoint.md (v2.0.0)"
```

**Create config (gateway plugins only):**

For plugins with a gateway command, provision the config from template.

```pseudocode
CREATE_CONFIG():
  IF NOT computed.context.has_gateway:
    RETURN  # Not a gateway plugin — config not needed

  IF file_exists(".hiivmind/blueprint/config.yaml"):
    SKIP "Config already exists"
    RETURN

  Bash("mkdir -p .hiivmind/blueprint/")

  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template"
  template = Read(template_path)

  IF template IS EMPTY:
    DISPLAY "WARNING: Could not read config template from: " + template_path
    RETURN

  # Read current lib_version from blueprint-lib reference
  lib_version = Read("${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/config.yaml")
    .extract("lib_version") OR "v3.1.1"
  lib_ref = "hiivmind/hiivmind-blueprint-lib@" + lib_version

  result = template
  result = replace(result, "{{engine_version}}", "2.0.0")
  result = replace(result, "{{lib_version}}", lib_version)
  result = replace(result, "{{lib_ref}}", lib_ref)
  result = replace(result, "{{schema_version}}", "2.3")

  Write(".hiivmind/blueprint/config.yaml", result)
  computed.files_created.append(".hiivmind/blueprint/config.yaml")
  DISPLAY "Created: .hiivmind/blueprint/config.yaml"
```

**Orchestrate infrastructure provisioning:**

```pseudocode
ORCHESTRATE_INFRASTRUCTURE():
  # Always provision these (all plugin types with workflow-backed skills)
  CREATE_PLUGIN_MANIFEST()
  CREATE_DEFINITIONS()
  CREATE_EXECUTION_GUIDE()

  # Gateway-specific provisioning (only if plugin has commands/ directory)
  IF computed.context.has_gateway:
    CREATE_ENGINE_ENTRYPOINT()
    CREATE_CONFIG()
```

---

## Phase 5: Target

> **TODO:** Engine target selection and export is pending design work in
> hiivmind-blueprint-lib. See design doc: hiivmind-blueprint-central/docs/plans/2026-03-08-blueprint-journey-redesign.md
>
> When implemented, this phase will:
> - Detect target engine from project context or `--target` flag
> - Generate engine-specific output (Claude Code command, OpenClaw manifest, etc.)
> - Currently defaults to Claude Code output format.

### Step 5.1: Engine Selection (Placeholder)

```pseudocode
SELECT_TARGET_ENGINE():
  IF computed.target_engine IS NOT NULL:
    # Validate that the engine is supported
    supported_engines = ["claude-code"]   # Only Claude Code for now
    IF computed.target_engine NOT IN supported_engines:
      DISPLAY "Engine '" + computed.target_engine + "' is not yet supported."
      DISPLAY "Supported engines: " + join(supported_engines, ", ")
      DISPLAY "Defaulting to claude-code."
    computed.target_engine = "claude-code"
  ELSE:
    computed.target_engine = "claude-code"

  DISPLAY "Target engine: " + computed.target_engine + " (default)"
```

### Step 5.2: Engine-Specific Export (Placeholder)

```pseudocode
EXPORT_FOR_ENGINE():
  # Currently a no-op — Claude Code is the default and only output format.
  # When additional engines are supported, this step will:
  #   1. Read the generated SKILL.md and workflow files
  #   2. Transform them into the target engine's format
  #   3. Write engine-specific output files
  #   4. Update computed.files_created with any additional files

  DISPLAY "Output format: Claude Code SKILL.md (default)"
```

---

## Phase 6: Validate

Check all generated files and present results to the user.

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
  IF ".hiivmind/blueprint/definitions.yaml" IN computed.files_created OR computed.context.has_definitions:
    expected_files.append(".hiivmind/blueprint/definitions.yaml")

  # Always-required blueprint files (for plugins with workflow-backed skills)
  IF len(computed.workflow_phases) > 0:
    expected_files.append(".hiivmind/blueprint/execution-guide.md")

  # Gateway-required blueprint files
  IF computed.context.has_gateway:
    expected_files.append(".hiivmind/blueprint/engine_entrypoint.md")
    expected_files.append(".hiivmind/blueprint/config.yaml")

  FOR file IN expected_files:
    IF file_exists(file) AND file_size(file) > 0:
      computed.validation.passed.append(file)
    ELSE:
      computed.validation.failed.append(file)

  IF len(computed.validation.failed) > 0:
    DISPLAY "WARNING: Some files failed validation:"
    FOR file IN computed.validation.failed:
      DISPLAY "  - MISSING: " + file
      IF file contains "execution-guide.md":
        DISPLAY "    Fix: Run bp-build again, or copy from ${CLAUDE_PLUGIN_ROOT}/lib/patterns/execution-guide.md"
      IF file contains "engine_entrypoint.md":
        DISPLAY "    Fix: Run bp-build again, or populate from ${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template"
      IF file contains "config.yaml" AND file contains "blueprint":
        DISPLAY "    Fix: Run bp-build again, or populate from ${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template"
      IF file contains "definitions.yaml":
        DISPLAY "    Fix: Run bp-build again to scan workflow types and generate definitions"
```

### Step 6.2: Display Summary

```
## Build Complete: {computed.skill_name}

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
- **Target engine:** {computed.target_engine}

### Next Steps

1. **Fill in prose phases** — Replace TODO placeholders in SKILL.md with real instructions
{if len(computed.workflow_phases) > 0}
2. **Add workflow nodes** — Expand starter nodes in `workflows/*.yaml` with domain-specific logic
3. **Add definitions** — Copy needed types from hiivmind-blueprint-lib catalog into definitions.yaml
{/if}
4. **Refine description** — Update frontmatter description with accurate trigger keywords
5. **Assess the skill** — Run `bp-assess` to check coverage position and fit
6. **Enhance structure** — Run `bp-enhance` to improve prose phases with pseudocode and decision tables
7. **Test the skill** — Invoke with `Skill(skill: "{computed.skill_name}")`
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
        "label": "Assess the skill",
        "description": "Run bp-assess to check coverage position and fit"
      },
      {
        "label": "Enhance the skill",
        "description": "Run bp-enhance to add structure to prose phases"
      },
      {
        "label": "Add another skill",
        "description": "Build another skill in the same plugin"
      },
      {
        "label": "Done",
        "description": "Build complete, no further action needed"
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

    CASE "Assess the skill":
      DISPLAY "To assess this skill, invoke:"
      DISPLAY "  bp-assess --skill " + computed.skill_path
      DISPLAY ""
      DISPLAY "bp-assess will classify coverage position, score complexity,"
      DISPLAY "and determine whether the formalization level is a good fit."

    CASE "Enhance the skill":
      DISPLAY "To enhance this skill, invoke:"
      DISPLAY "  bp-enhance --skill " + computed.skill_path
      DISPLAY ""
      DISPLAY "bp-enhance will help add structure (pseudocode, decision tables,"
      DISPLAY "pattern references) while keeping the prose orchestration approach."

    CASE "Add another skill":
      DISPLAY "Starting new skill build..."
      computed.files_created = []
      computed.files_updated = []
      GOTO Phase 2, Step 2.1

    CASE "Done":
      DISPLAY "Build complete. " + str(len(computed.files_created)) + " files created."
      EXIT
```

---

## State Flow

```
Phase 1          Phase 2         Phase 3          Phase 4           Phase 5      Phase 6
──────────────────────────────────────────────────────────────────────────────────────────
computed.mode -> computed        -> computed       -> computed       -> computed   -> Validate
computed         .skill_name      .phases            .skill_path      .target      + Report
.scaffold_only   computed         computed           computed          _engine      + Handoff
computed         .description     .workflow_phases   .files_created                 (bp-assess,
.target_engine   computed         computed           computed                        bp-enhance,
                 .inputs          .coverage          .files_updated                  bp-extract)
                 computed
                 .outputs
                 computed
                 .features
                 computed
                 .structure
```

---

## Reference Documentation

- **Placeholder Catalog:** `patterns/scaffold-checklist.md` (local to this skill)
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Execution Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/execution-guide.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
- **workflow.yaml Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`

---

## Related Skills

- **Assess skill coverage and fit:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- **Enhance skill structure:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-enhance/SKILL.md`
- **Extract to workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-extract/SKILL.md`
- **Maintain workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/SKILL.md`
- **Visualize workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
