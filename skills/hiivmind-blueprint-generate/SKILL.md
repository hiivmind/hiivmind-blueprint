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

### Step 2.2: Check Library Files

Verify the target plugin has the required libraries:

```
required_libs = [
  "lib/workflow/schema.md",
  "lib/workflow/execution.md",
  "lib/workflow/preconditions.md",
  "lib/workflow/consequences.md",
  "lib/workflow/state.md"
]

missing_libs = []
for lib in required_libs:
  if not file_exists("{plugin_root}/{lib}"):
    missing_libs.append(lib)
```

If missing libraries, **ask user**:
```json
{
  "questions": [{
    "question": "Required workflow libraries are missing. Copy from hiivmind-blueprint?",
    "header": "Libraries",
    "multiSelect": false,
    "options": [
      {"label": "Copy libraries", "description": "Copy workflow lib files to this plugin"},
      {"label": "Skip", "description": "Assume libraries will be added manually"},
      {"label": "Cancel", "description": "Exit - libraries required for workflow execution"}
    ]
  }]
}
```

---

## Phase 3: Generate Files

### Step 3.1: Create Backup (if requested)

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

### Step 3.2: Generate workflow.yaml

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

### Step 3.3: Generate Thin Loader SKILL.md

Generate the minimal SKILL.md that loads and executes the workflow:

```markdown
---
name: {workflow.name}
description: >
  {workflow.description}
allowed-tools: Read, Glob, Grep, Write, Edit, AskUserQuestion, Bash, WebFetch
---

# {Title from workflow name}

Execute this workflow deterministically. State persists in conversation context.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/{skill_dir}/workflow.yaml`

---

## Execution Instructions

### Phase 1: Initialize

1. **Load workflow.yaml** from this skill directory:
   Read: `${CLAUDE_PLUGIN_ROOT}/skills/{skill_dir}/workflow.yaml`

2. **Check entry preconditions** (see `${CLAUDE_PLUGIN_ROOT}/lib/workflow/preconditions.md`):
   - Evaluate each precondition in `entry_preconditions`
   - If ANY fails: display error, STOP

3. **Initialize runtime state** from `workflow.initial_state`

---

### Phase 2: Execution Loop

Execute nodes until an ending is reached:

```
LOOP:
  1. Get current node from workflow.nodes[current_node]

  2. Check for ending:
     - IF current_node is in workflow.endings:
       - Display ending.message
       - If error with recovery: suggest recovery skill
       - STOP

  3. Execute by node.type:

     ACTION:
     - Execute each action in node.actions
     - Route via on_success or on_failure

     CONDITIONAL:
     - Evaluate node.condition
     - Route via branches.true or branches.false

     USER_PROMPT:
     - Present AskUserQuestion from node.prompt
     - Store response, apply consequences
     - Route via on_response handler

     VALIDATION_GATE:
     - Evaluate all node.validations
     - Route via on_valid or on_invalid

     REFERENCE:
     - Load and execute node.doc section
     - Route via next_node

  4. Record in history and continue

UNTIL ending reached
```

---

## Reference

- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`
- **Preconditions:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/preconditions.md`
- **Consequences:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/consequences.md`
- **State Model:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/state.md`
```

Write to: `{target}/SKILL.md`

### Step 3.4: Copy Library Files (if requested)

If user requested library copy:

```bash
# Create lib directories
mkdir -p "{plugin_root}/lib/workflow"

# Copy each library file
for lib in missing_libs:
  cp "{blueprint_root}/{lib}" "{plugin_root}/{lib}"
```

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
- `SKILL.md` (thin loader)

{if backup_created}
### Backups Created
- `SKILL.md.backup`
- `workflow.yaml.backup`
{/if}

{if libs_copied}
### Libraries Copied
{for each lib}
- `{lib}`
{/for}
{/if}

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
| `SKILL.md` | Thin loader that executes workflow |
| `SKILL.md.backup` | Original skill (if backup requested) |
| `workflow.yaml.backup` | Previous workflow (if backup requested) |

---

## Reference Documentation

- **Workflow Generation:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/workflow-generation.md`
- **Thin Loader Template:** `${CLAUDE_PLUGIN_ROOT}/templates/thin-loader.md.template`
- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`

---

## Related Skills

- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert to workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Initialize project: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
