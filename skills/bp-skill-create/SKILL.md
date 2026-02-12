---
name: bp-skill-create
description: >
  This skill should be used when the user asks to "create a new skill", "scaffold skill",
  "initialize skill", "new workflow skill", "start new skill", "add skill to plugin",
  or needs to create a brand new skill with workflow support from scratch. Triggers on
  "create skill", "new skill", "scaffold", "init skill", "add skill", "start skill".
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Scaffold New Skill from Templates

Create a brand new workflow-based skill from scratch using the blueprint templates.
Unlike `bp-prose-migrate` (which converts existing prose), this skill generates
all files from templates with no pre-existing content required.

> **Placeholder Catalog:** `patterns/scaffold-checklist.md`
> **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
> **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
> **workflow.yaml Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`

---

## Overview

This skill walks through a guided scaffolding process that:

1. Gathers skill name, plugin structure type, and desired features from the user
2. Detects existing infrastructure in the target directory (plugin manifest, engine entrypoint, etc.)
3. Creates the directory structure for the new skill
4. Generates a populated SKILL.md from the template
5. Generates a starter workflow.yaml from the template
6. Creates any missing plugin infrastructure files
7. Validates all generated files and reports results

**Output artifacts:**

| File | Location | Generated From |
|------|----------|----------------|
| SKILL.md | `skills/{skill-name}/SKILL.md` | `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template` |
| workflow.yaml | `skills/{skill-name}/workflow.yaml` | `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template` |
| plugin.json | `.claude-plugin/plugin.json` | Inline JSON structure (if not exists) |
| engine_entrypoint.md | `.hiivmind/blueprint/engine_entrypoint.md` | `${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template` |
| config.yaml | `.hiivmind/blueprint/config.yaml` | Generated from `${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template` |

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
  # e.g., "bp-skill-create" -> "skill-create"
  #        "my-plugin-analyze" -> "analyze"
  segments = split(raw_name, "-")
  IF len(segments) > 2:
    computed.skill_short_name = join(segments[-2:], "-")
  ELSE:
    computed.skill_short_name = segments[-1]

  # Derive title from name
  computed.title = title_case(replace(raw_name, "-", " "))
```

Store in `computed.skill_name`, `computed.skill_directory`, `computed.skill_short_name`, and `computed.title`.

### Step 1.2: Get Plugin Structure

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
      computed.needs_intent_mapping = false
    CASE "Multi-skill plugin":
      computed.structure = "multi"
      computed.needs_gateway = false
      computed.needs_intent_mapping = false
    CASE "Multi-skill with gateway":
      computed.structure = "multi-gateway"
      computed.needs_gateway = true
      computed.needs_intent_mapping = true
```

Store in `computed.structure`, `computed.needs_gateway`, and `computed.needs_intent_mapping`.

### Step 1.3: Get Feature Selections

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

Store in `computed.features`.

---

## Phase 2: Detect Context

### Step 2.1: Check Existing Infrastructure

Examine the current working directory (or user-specified target directory) for existing
plugin infrastructure. Use Glob and Read to detect what already exists.

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

  # Check for engine entrypoint
  entrypoint_files = Glob(".hiivmind/blueprint/engine_entrypoint.md")
  computed.context.has_engine_entrypoint = len(entrypoint_files) > 0

  # Check for config file
  config_files = Glob(".hiivmind/blueprint/config.yaml")
  computed.context.has_config_file = len(config_files) > 0

  # Check for existing gateway command
  gateway_files = Glob("commands/*/workflow.yaml")
  computed.context.has_gateway = len(gateway_files) > 0

  # If plugin.json exists, extract parent plugin name
  IF computed.context.has_plugin_manifest:
    manifest = Read(".claude-plugin/plugin.json")
    computed.parent_plugin_name = extract_json(manifest, ".name")
  ELSE:
    # Derive from directory name
    computed.parent_plugin_name = basename(cwd())

  # If config file exists, read lib version
  IF computed.context.has_config_file:
    config_content = Read(".hiivmind/blueprint/config.yaml")
    computed.lib_version = extract_yaml(config_content, ".lib_version")
    computed.lib_ref = extract_yaml(config_content, ".lib_ref")
  ELSE:
    # Config file is required — will be created in Phase 6
    computed.lib_version = null
    computed.lib_ref = null
```

### Step 2.2: Determine Required Actions

Based on the detected context, determine which creation steps are needed:

| Context Flag | Value | Action Needed |
|-------------|-------|---------------|
| `has_plugin_manifest` | `false` | Create `.claude-plugin/plugin.json` in Phase 6 |
| `has_skills_dir` | `false` | Create `skills/` directory in Phase 3 |
| `has_engine_entrypoint` | `false` | Create engine entrypoint in Phase 6 |
| `has_config_file` | `false` | Create .hiivmind/blueprint/config.yaml in Phase 6 |
| `has_gateway` | `false` AND `needs_gateway` is `true` | Note: gateway creation is a separate skill |

```pseudocode
DETERMINE_ACTIONS():
  computed.actions = {
    create_plugin_manifest:  NOT computed.context.has_plugin_manifest,
    create_skills_dir:       NOT computed.context.has_skills_dir,
    create_skill_dir:        true,   # Always needed for the new skill
    create_engine_entrypoint: NOT computed.context.has_engine_entrypoint,
    create_config_file:      NOT computed.context.has_config_file,
    generate_skill_md:       true,   # Always needed
    generate_workflow_yaml:  true,   # Always needed
    note_gateway_needed:     computed.needs_gateway AND NOT computed.context.has_gateway
  }

  # Count actions for progress reporting
  computed.actions.total = count_true_values(computed.actions)
```

Display a summary of detected context and planned actions:

```
## Context Detection

| Infrastructure | Found | Action |
|---------------|-------|--------|
| Plugin manifest (.claude-plugin/plugin.json) | {yes/no} | {Create / Already exists} |
| Skills directory (skills/) | {yes/no} | {Create / Already exists} |
| Engine entrypoint (.hiivmind/blueprint/) | {yes/no} | {Create / Already exists} |
| Library version file | {yes/no} | {Create / Already exists} |
| Existing gateway | {yes/no} | {Note needed / Already exists / Not applicable} |

**Planned:** {computed.actions.total} creation steps for skill **{computed.skill_name}**
```

---

## Phase 3: Create Directory Structure

### Step 3.1: Create Directories

Create the necessary directories based on the actions determined in Phase 2.

```pseudocode
CREATE_DIRECTORIES():
  # Create skills/ if needed
  IF computed.actions.create_skills_dir:
    Bash("mkdir -p skills/")

  # Always create the skill directory
  skill_path = "skills/" + computed.skill_directory
  Bash("mkdir -p " + skill_path)
  computed.skill_path = skill_path

  # Create .hiivmind/blueprint/ if engine entrypoint is needed
  IF computed.actions.create_engine_entrypoint:
    Bash("mkdir -p .hiivmind/blueprint/")

  # Create .claude-plugin/ if plugin manifest is needed
  IF computed.actions.create_plugin_manifest:
    Bash("mkdir -p .claude-plugin/")
```

Verify all directories were created:

```pseudocode
VERIFY_DIRECTORIES():
  expected_dirs = [computed.skill_path]
  IF computed.actions.create_engine_entrypoint:
    expected_dirs.append(".hiivmind/blueprint/")
  IF computed.actions.create_plugin_manifest:
    expected_dirs.append(".claude-plugin/")

  FOR dir IN expected_dirs:
    IF NOT directory_exists(dir):
      FAIL "Failed to create directory: " + dir
```

---

## Phase 4: Generate SKILL.md

### Step 4.1: Load Template

Read the SKILL.md template from the plugin's template directory:

```pseudocode
LOAD_SKILL_TEMPLATE():
  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template"
  computed.skill_template = Read(template_path)

  IF computed.skill_template IS EMPTY:
    FAIL "Could not read SKILL.md template at: " + template_path
```

### Step 4.2: Substitute Placeholders

Replace all `{{placeholder}}` values in the template with computed values.
Refer to `patterns/scaffold-checklist.md` for the complete placeholder catalog
with sources, defaults, and descriptions.

**Core placeholder substitutions:**

| Placeholder | Source | Value |
|------------|--------|-------|
| `{{skill_name}}` | `computed.skill_name` | User input from Step 1.1 |
| `{{description}}` | Generated | Auto-generated from skill name and features |
| `{{allowed_tools}}` | Computed | Based on feature selections |
| `{{title}}` | `computed.title` | Title-cased version of skill name |
| `{{parent_plugin_name}}` | `computed.parent_plugin_name` | From plugin.json or directory name |
| `{{skill_short_name}}` | `computed.skill_short_name` | Last segment(s) of skill name |
| `{{skill_directory}}` | `computed.skill_directory` | Same as skill name |
| `{{lib_version}}` | `computed.lib_version` | From `.hiivmind/blueprint/config.yaml` |
| `{{lib_ref}}` | `computed.lib_ref` | From `.hiivmind/blueprint/config.yaml` |

**Conditional section handling:**

```pseudocode
SUBSTITUTE_SKILL_PLACEHOLDERS(template):
  result = template

  # Core substitutions
  result = replace(result, "{{skill_name}}", computed.skill_name)
  result = replace(result, "{{description}}", generate_description())
  result = replace(result, "{{allowed_tools}}", compute_allowed_tools())
  result = replace(result, "{{title}}", computed.title)
  result = replace(result, "{{parent_plugin_name}}", computed.parent_plugin_name)
  result = replace(result, "{{skill_short_name}}", computed.skill_short_name)
  result = replace(result, "{{skill_directory}}", computed.skill_directory)
  result = replace(result, "{{lib_version}}", computed.lib_version)
  result = replace(result, "{{lib_ref}}", computed.lib_ref)

  # Conditional sections: runtime flags
  IF computed.features.runtime_flags:
    result = enable_section(result, "if_runtime_flags")
  ELSE:
    result = remove_section(result, "if_runtime_flags")

  # Conditional sections: intent detection
  IF computed.features.intent_detection:
    result = enable_section(result, "if_intent_detection")
  ELSE:
    result = remove_section(result, "if_intent_detection")

  # Conditional sections: workflow graph visualization
  IF computed.features.visualization:
    result = enable_section(result, "workflow_graph")
    result = replace(result, "{{graph_ascii}}", generate_starter_graph())
  ELSE:
    result = remove_section(result, "workflow_graph")

  # Conditional sections: examples (include a starter example)
  result = enable_section(result, "examples")
  result = populate_starter_examples(result)

  # Related skills section
  result = enable_section(result, "related_skills")
  result = populate_related_skills(result)

  RETURN result
```

**Helper: generate_description():**

```pseudocode
function generate_description():
  desc = "This skill should be used when the user asks to \""
  desc += replace(computed.skill_short_name, "-", " ")
  desc += "\". Triggers on \""
  desc += computed.skill_short_name
  desc += "\"."
  RETURN desc
```

**Helper: compute_allowed_tools():**

```pseudocode
function compute_allowed_tools():
  tools = ["Read", "Write", "Glob", "Bash"]
  # All skills need AskUserQuestion for the execution protocol
  tools.append("AskUserQuestion")
  RETURN join(tools, ", ")
```

### Step 4.3: Write SKILL.md

Write the populated template to the skill directory:

```pseudocode
WRITE_SKILL_MD():
  output_path = computed.skill_path + "/SKILL.md"
  Write(output_path, computed.populated_skill_template)
  computed.files_created.append(output_path)

  DISPLAY "Created: " + output_path
```

---

## Phase 5: Generate workflow.yaml

### Step 5.1: Load Template

Read the workflow.yaml template:

```pseudocode
LOAD_WORKFLOW_TEMPLATE():
  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template"
  computed.workflow_template = Read(template_path)

  IF computed.workflow_template IS EMPTY:
    FAIL "Could not read workflow.yaml template at: " + template_path
```

### Step 5.2: Substitute Placeholders and Build Starter Nodes

Replace placeholders and generate an initial set of workflow nodes based on the
selected features.

**Core placeholder substitutions:**

| Placeholder | Source | Value |
|------------|--------|-------|
| `{{skill_id}}` | `computed.skill_name` | Same as skill name |
| `{{description}}` | Generated | Same description as SKILL.md |
| `{{lib_ref}}` | `computed.lib_ref` | Library reference string |
| `{{state_variables}}` | Computed | Comma-separated list of initial state fields |
| `{{start_node}}` | Computed | Name of the first node |
| `{{success_message}}` | Computed | Derived from skill name |

```pseudocode
SUBSTITUTE_WORKFLOW_PLACEHOLDERS(template):
  result = template

  # Core substitutions
  result = replace(result, "{{skill_id}}", computed.skill_name)
  result = replace(result, "{{description}}", generate_description())
  result = replace(result, "{{lib_ref}}", computed.lib_ref)
  result = replace(result, "{{state_variables}}", "phase, flags, computed")
  result = replace(result, "{{success_message}}", computed.title + " completed successfully")

  # Determine start node based on features
  IF computed.features.intent_detection:
    result = replace(result, "{{start_node}}", "parse_intent")
  ELSE:
    result = replace(result, "{{start_node}}", "start_execution")

  # Build starter nodes
  nodes = build_starter_nodes()
  result = replace_nodes_section(result, nodes)

  RETURN result
```

**Helper: build_starter_nodes():**

Generate a minimal set of working nodes. The user will expand these after scaffolding.

```pseudocode
function build_starter_nodes():
  nodes = []

  # If intent detection enabled, add intent parsing nodes
  IF computed.features.intent_detection:
    nodes.append({
      id: "parse_intent",
      type: "action",
      description: "Parse user input for intent flags",
      actions: [{ type: "mutate_state", operation: "set", field: "computed.intent_parsed", value: true }],
      on_success: "route_intent",
      on_failure: "error_intent"
    })
    nodes.append({
      id: "route_intent",
      type: "conditional",
      description: "Route based on detected intent",
      condition: { type: "state_check", field: "computed.intent_parsed", operator: "true" },
      branches: { on_true: "start_execution", on_false: "ask_clarification" }
    })
    nodes.append({
      id: "ask_clarification",
      type: "user_prompt",
      prompt: {
        question: "What would you like to do?",
        header: "Action",
        options: [
          { id: "proceed", label: "Proceed", description: "Continue with default action" },
          { id: "cancel", label: "Cancel", description: "Cancel operation" }
        ]
      },
      on_response: {
        proceed: { next_node: "start_execution" },
        cancel: { next_node: "cancelled" }
      }
    })

  # Core execution node (always present)
  nodes.append({
    id: "start_execution",
    type: "action",
    description: "Begin main skill execution",
    actions: [{ type: "mutate_state", operation: "set", field: "phase", value: "executing" }],
    on_success: "complete",
    on_failure: "error_execution"
  })

  # Completion node
  nodes.append({
    id: "complete",
    type: "action",
    description: "Finalize and display results",
    actions: [{ type: "display", format: "text", content: "Operation complete." }],
    on_success: "success",
    on_failure: "error_execution"
  })

  RETURN nodes
```

### Step 5.3: Write workflow.yaml

Write the populated workflow template to the skill directory:

```pseudocode
WRITE_WORKFLOW():
  output_path = computed.skill_path + "/workflow.yaml"
  Write(output_path, computed.populated_workflow_template)
  computed.files_created.append(output_path)

  DISPLAY "Created: " + output_path
```

---

## Phase 6: Create Plugin Infrastructure

Create any missing infrastructure files that the skill depends on.

### Step 6.1: Create Plugin Manifest

If `.claude-plugin/plugin.json` does not exist, create it:

```pseudocode
CREATE_PLUGIN_MANIFEST():
  IF NOT computed.actions.create_plugin_manifest:
    SKIP "Plugin manifest already exists"
    RETURN

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

**JSON structure for new plugin.json:**

```json
{
  "name": "{computed.parent_plugin_name}",
  "version": "1.0.0",
  "description": "Plugin containing {computed.skill_name}",
  "skills": [
    {
      "name": "{computed.skill_name}",
      "path": "skills/{computed.skill_directory}/SKILL.md"
    }
  ]
}
```

If the manifest already exists but the new skill is not listed, add it to the `skills` array:

```pseudocode
UPDATE_EXISTING_MANIFEST():
  IF computed.context.has_plugin_manifest:
    manifest = Read(".claude-plugin/plugin.json")
    parsed = json_parse(manifest)

    # Check if skill already registered
    skill_entry = find(parsed.skills, s => s.name == computed.skill_name)
    IF skill_entry IS NULL:
      parsed.skills.append({
        "name": computed.skill_name,
        "path": "skills/" + computed.skill_directory + "/SKILL.md"
      })
      Write(".claude-plugin/plugin.json", json_format(parsed, indent=2))
      computed.files_updated.append(".claude-plugin/plugin.json")
      DISPLAY "Updated: .claude-plugin/plugin.json (added skill entry)"
```

### Step 6.2: Create Engine Entrypoint

If `.hiivmind/blueprint/engine_entrypoint.md` does not exist, generate it from the template:

```pseudocode
CREATE_ENGINE_ENTRYPOINT():
  IF NOT computed.actions.create_engine_entrypoint:
    SKIP "Engine entrypoint already exists"
    RETURN

  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template"
  template = Read(template_path)

  IF template IS EMPTY:
    FAIL "Could not read engine entrypoint template at: " + template_path

  # Substitute the engine version and lib version placeholders
  result = replace(template, "{{engine_version}}", "1.0.0")
  result = replace(result, "{{lib_version}}", computed.lib_version)

  Write(".hiivmind/blueprint/engine_entrypoint.md", result)
  computed.files_created.append(".hiivmind/blueprint/engine_entrypoint.md")

  DISPLAY "Created: .hiivmind/blueprint/engine_entrypoint.md"
```

### Step 6.3: Create Blueprint Config

If `.hiivmind/blueprint/config.yaml` does not exist, generate it from the template:

```pseudocode
CREATE_CONFIG_FILE():
  IF NOT computed.actions.create_config_file:
    SKIP "Config file already exists"
    RETURN

  # Generate from the config template
  template_path = "${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template"
  template_content = Read(template_path)

  IF template_content IS EMPTY:
    FAIL "Could not read config template at: " + template_path

  # Substitute placeholders in template
  rendered_content = replace(template_content, "{{lib_version}}", computed.lib_version)
  rendered_content = replace(rendered_content, "{{lib_ref}}", computed.lib_ref)

  Bash("mkdir -p .hiivmind/blueprint/")
  Write(".hiivmind/blueprint/config.yaml", rendered_content)
  computed.files_created.append(".hiivmind/blueprint/config.yaml")

  DISPLAY "Created: .hiivmind/blueprint/config.yaml"
```

---

## Phase 7: Verify and Report

### Step 7.1: Validate Generated Files

Check that all expected files exist and are non-empty:

```pseudocode
VALIDATE_FILES():
  computed.validation = { passed: [], failed: [] }

  expected_files = [
    computed.skill_path + "/SKILL.md",
    computed.skill_path + "/workflow.yaml"
  ]

  IF computed.actions.create_plugin_manifest:
    expected_files.append(".claude-plugin/plugin.json")
  IF computed.actions.create_engine_entrypoint:
    expected_files.append(".hiivmind/blueprint/engine_entrypoint.md")
  IF computed.actions.create_config_file:
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
```

### Step 7.2: Display Summary

Present a comprehensive summary of everything that was created:

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
│       ├── engine_entrypoint.md {new/existing}
│       └── config.yaml {new/existing}
├── skills/
│   └── {computed.skill_directory}/
│       ├── SKILL.md          ← NEW
│       └── workflow.yaml     ← NEW

### Configuration

- **Skill name:** {computed.skill_name}
- **Plugin structure:** {computed.structure}
- **Library version:** {computed.lib_version}
- **Features:** {comma-separated list of enabled features}

### Next Steps

1. **Edit workflow.yaml** -- Add domain-specific nodes to `skills/{computed.skill_directory}/workflow.yaml`
2. **Update SKILL.md description** -- Refine the auto-generated description with trigger keywords
3. **Add entry preconditions** -- Define tool and file requirements in workflow.yaml
{if computed.needs_gateway AND NOT computed.context.has_gateway}
4. **Create gateway** -- Run `bp-gateway-create` to set up gateway routing
{/if}
5. **Test the skill** -- Invoke with `Skill(skill: "{computed.skill_name}")`
```

### Step 7.3: Offer Next Actions

Ask the user what they want to do next:

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {
        "label": "Edit workflow",
        "description": "Open the generated workflow.yaml to add nodes and logic"
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
    CASE "Edit workflow":
      workflow_path = computed.skill_path + "/workflow.yaml"
      DISPLAY "Opening " + workflow_path + " for editing."
      DISPLAY "The starter workflow contains placeholder nodes. Replace them with your skill's logic."
      DISPLAY "See ${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md for node patterns."
      # Read and display the generated workflow for the user to review
      content = Read(workflow_path)
      DISPLAY content
      EXIT

    CASE "Add another skill":
      DISPLAY "Starting new skill scaffold..."
      # Reset computed state for a fresh run
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
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
- **workflow.yaml Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Engine Entrypoint Template:** `${CLAUDE_PLUGIN_ROOT}/templates/engine-entrypoint.md.template`
- **Config Template:** `${CLAUDE_PLUGIN_ROOT}/templates/config.yaml.template`

---

## Related Skills

- Plugin discovery and classification: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-plugin-discover/SKILL.md`
- Deep skill analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-analyze/SKILL.md`
- Prose-to-workflow migration: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-prose-migrate/SKILL.md`
- Gateway creation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-gateway-create/SKILL.md`
- Skill validation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/SKILL.md`
