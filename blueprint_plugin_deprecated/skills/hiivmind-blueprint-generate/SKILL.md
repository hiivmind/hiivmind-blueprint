---
name: hiivmind-blueprint-generate
description: >
  This skill should be used when the user asks to "generate workflow files", "write workflow.yaml",
  "create thin loader", "output skill files", "save converted workflow", "write files to skill directory",
  or needs to write the generated workflow and thin SKILL.md to disk. Triggers on "generate files",
  "blueprint generate", "hiivmind-blueprint generate", "write workflow", "save skill",
  or after running hiivmind-blueprint-convert.
allowed-tools: Read, Write, Edit, AskUserQuestion, Bash
---

# Generate Workflow Files

Write the converted workflow and thin loader SKILL.md to the skill directory.

> **Pattern Documentation:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/workflow-generation.md`

---

## Overview

This skill takes a converted workflow (from `hiivmind-blueprint-convert`) and:
1. Writes `workflow.yaml` to the skill directory
2. Generates a thin loader `SKILL.md` that executes the workflow
3. Optionally backs up the original SKILL.md
4. Copies required library files if not present

---

## Prerequisites

Before running this skill:
1. Run `hiivmind-blueprint-analyze` on the target skill
2. Run `hiivmind-blueprint-convert` to generate the workflow
3. Have `computed.workflow` available in state

If no workflow is available, this skill will invoke the convert skill first.

---

## Phase 1: Validate Prerequisites

### Step 1.1: Check for Workflow

If `computed.workflow` exists in state:
1. Validate it has required fields:
   - `name`
   - `start_node`
   - `nodes`
   - `endings`
2. Proceed to Phase 2

If no workflow available:
1. **Ask user** for next step:
   ```json
   {
     "questions": [{
       "question": "No converted workflow found. What would you like to do?",
       "header": "Workflow",
       "multiSelect": false,
       "options": [
         {"label": "Convert first", "description": "Analyze and convert a skill, then generate"},
         {"label": "Load from file", "description": "Load workflow.yaml from an existing file"},
         {"label": "Cancel", "description": "Exit without generating"}
       ]
     }]
   }
   ```
2. Based on response:
   - **Convert first**: Invoke `hiivmind-blueprint-convert`, then continue
   - **Load from file**: Ask for path, read and parse YAML, continue
   - **Cancel**: Exit with message

### Step 1.2: Determine Target Directory

If `computed.analysis.skill_path` exists:
- Extract directory from path
- Use as target directory

Otherwise, **ask user**:
```json
{
  "questions": [{
    "question": "Where should I generate the workflow files?",
    "header": "Location",
    "multiSelect": false,
    "options": [
      {"label": "Current directory", "description": "Write to ./"},
      {"label": "Provide path", "description": "Specify a skill directory path"},
      {"label": "New skill", "description": "Create a new skill directory"}
    ]
  }]
}
```

Based on response, set `computed.target_directory`.

---

## Phase 2: Prepare Generation

### Step 2.1: Check Existing Files

Check if files already exist in target:

```
existing_files = []
if file_exists("{target}/SKILL.md"):
  existing_files.append("SKILL.md")
if file_exists("{target}/workflow.yaml"):
  existing_files.append("workflow.yaml")
```

If files exist, **ask user**:
```json
{
  "questions": [{
    "question": "Found existing files: {files}. What should I do?",
    "header": "Overwrite",
    "multiSelect": false,
    "options": [
      {"label": "Backup and replace", "description": "Create .backup files and overwrite"},
      {"label": "Overwrite", "description": "Replace without backup"},
      {"label": "Cancel", "description": "Don't modify existing files"}
    ]
  }]
}
```

### Step 2.2: Check Blueprint Infrastructure

Verify the target plugin has the `.hiivmind/blueprint/` directory structure:

```
# The .hiivmind/blueprint/ directory is optional - only needed for logging.yaml
# Execution semantics are fetched from hiivmind-blueprint-lib at runtime
```

If plugin uses custom logging configuration, `.hiivmind/blueprint/logging.yaml` should exist.

### Step 2.3: Determine Type Definitions Source

Check if workflow specifies external definitions:

```
if computed.workflow.definitions:
  definitions_source = computed.workflow.definitions.source
else:
  # Default to hiivmind-blueprint-lib
  definitions_source = "hiivmind/hiivmind-blueprint-lib@v2.0.0"

# Extract lib_version for templates (e.g., "v2.0.0" from "hiivmind/hiivmind-blueprint-lib@v2.0.0")
lib_version = definitions_source.split("@")[1]  # e.g., "v2.0.0"
```

The `lib_version` is passed to templates for constructing raw GitHub URLs to execution semantics.

---

## Phase 3: Generate Files

### Step 3.1: Create Blueprint Infrastructure (Optional)

The `.hiivmind/blueprint/` directory is only needed for plugin-wide logging configuration:

```bash
# Only create if logging.yaml is needed
if [ needs_custom_logging ]; then
  mkdir -p "{plugin_root}/.hiivmind/blueprint"
  # Create logging.yaml with plugin defaults
fi
```

**Note:** `engine.md` is no longer copied to target plugins. Execution semantics are fetched
from hiivmind-blueprint-lib via raw GitHub URLs at runtime. This ensures standalone plugins
work correctly without requiring a local copy of the engine.

### Step 3.2: Create Backup (if requested)

If backup was requested:

```bash
# Backup existing files
if [ -f "{target}/SKILL.md" ]; then
  mv "{target}/SKILL.md" "{target}/SKILL.md.backup"
fi
if [ -f "{target}/workflow.yaml" ]; then
  mv "{target}/workflow.yaml" "{target}/workflow.yaml.backup"
fi
```

### Step 3.4: Generate workflow.yaml

Convert the workflow object to YAML and write:

```yaml
# Generated by hiivmind-blueprint
# Source: {original_skill_path}
# Generated: {timestamp}

name: "{computed.workflow.name}"
version: "{computed.workflow.version}"
description: >
  {computed.workflow.description}

entry_preconditions:
{yaml_format(computed.workflow.entry_preconditions)}

initial_state:
{yaml_format(computed.workflow.initial_state)}

start_node: {computed.workflow.start_node}

nodes:
{yaml_format(computed.workflow.nodes)}

endings:
{yaml_format(computed.workflow.endings)}
```

Write to: `{target}/workflow.yaml`

### Step 3.5: Generate Thin Loader SKILL.md

Generate the minimal SKILL.md that loads and executes the workflow.
Use the template at `${CLAUDE_PLUGIN_ROOT}/templates/skill-with-executor.md.template` with:

- `{{lib_version}}` = version extracted from definitions.source (e.g., "v2.0.0")
- `{{skill_directory}}` = target skill directory name
- `{{definitions_source}}` = full definitions source string
- Other placeholders from workflow metadata

The template includes:
- Execution Reference table with raw GitHub URLs to hiivmind-blueprint-lib
- Phase 1/2/3 quick reference
- Type definitions reference

Write to: `{target}/SKILL.md`


---

## Phase 4: Verify Generation

### Step 4.1: Validate Written Files

Read back the written files and verify:

1. **workflow.yaml:**
   - Parses as valid YAML
   - Has all required sections
   - Node transitions are valid

2. **SKILL.md:**
   - Has valid frontmatter
   - References the workflow.yaml

### Step 4.2: Report Results

Display generation summary:

```
## Generation Complete

**Target:** {target_directory}

### Files Created
- `workflow.yaml` ({node_count} nodes, {ending_count} endings)
- `SKILL.md` (thin loader with remote execution references)

{if backup_created}
### Backups Created
- `SKILL.md.backup`
- `workflow.yaml.backup`
{/if}

### Execution Semantics
The SKILL.md references execution semantics from hiivmind-blueprint-lib via raw GitHub URLs.
This ensures the skill works correctly in standalone plugins without local dependencies.

### Next Steps
1. Test the skill by invoking it
2. Review workflow.yaml if behavior differs from original
3. Commit changes to version control
```

---

## Phase 5: Optional Cleanup

### Step 5.1: Offer Cleanup Options

**Ask user** about next steps:
```json
{
  "questions": [{
    "question": "Files generated successfully. What else would you like to do?",
    "header": "Cleanup",
    "multiSelect": false,
    "options": [
      {"label": "Test the skill", "description": "Invoke the converted skill to verify it works"},
      {"label": "Show diff", "description": "Compare old and new SKILL.md"},
      {"label": "Done", "description": "Generation complete, no further action"}
    ]
  }]
}
```

Based on response:
- **Test the skill**: Invoke the skill
- **Show diff**: Display differences between backup and new
- **Done**: Exit with success message

---

## Output Summary

Files generated by this skill:

| File | Description |
|------|-------------|
| `workflow.yaml` | Deterministic workflow definition |
| `SKILL.md` | Thin loader with remote execution references |
| `SKILL.md.backup` | Original skill (if backup requested) |
| `workflow.yaml.backup` | Previous workflow (if backup requested) |

**Note:** `engine.md` is no longer copied. Execution semantics are fetched from hiivmind-blueprint-lib at runtime.

---

## Reference Documentation

- **Workflow Generation:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/workflow-generation.md`
- **Plugin Structure:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/plugin-structure.md`
- **Thin Loader Template:** `${CLAUDE_PLUGIN_ROOT}/templates/skill-with-executor.md.template`
- **Workflow Engine:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`

---

## Related Skills

- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert to workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Initialize project: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
