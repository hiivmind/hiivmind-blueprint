---
name: hiivmind-blueprint-author-init
description: >
  This skill should be used when the user asks to "initialize blueprint", "set up workflow conversion",
  "prepare plugin for workflows", "add workflow support", "copy workflow libraries",
  or needs to prepare a plugin for deterministic workflow patterns. Triggers on "init blueprint",
  "blueprint init", "hiivmind-blueprint init", "setup workflows", "add workflow libs",
  or when starting to convert skills in a new plugin.
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Initialize Blueprint Project

Set up a plugin for deterministic workflow conversion by copying required libraries and creating the directory structure.

---

## Overview

This skill prepares a Claude Code plugin to use workflow patterns by:
1. Detecting the project context (existing plugin vs. new)
2. Copying the workflow and intent detection libraries
3. Creating the blueprint patterns directory (optional)
4. Setting up templates for skill conversion

---

## Phase 1: Detect Context

### Step 1.1: Check Current Directory

Detect what kind of project we're in:

```
flags:
  is_plugin: false         # Has .claude-plugin/plugin.json
  has_skills: false        # Has skills/ directory
  has_workflow_lib: false  # Has lib/workflow/
```

**Detection:**

1. Check for plugin manifest:
   ```
   if file_exists(".claude-plugin/plugin.json"):
     flags.is_plugin = true
   ```

2. Check for skills directory:
   ```
   if directory_exists("skills/"):
     flags.has_skills = true
   ```

3. Check for existing libraries:
   ```
   if file_exists("lib/workflow/engine.md"):
     flags.has_workflow_lib = true
   ```

### Step 1.2: Determine Action

Based on flags, determine what needs to be done:

| Context | Action |
|---------|--------|
| Not a plugin | Offer to create plugin structure |
| Plugin, no libs | Copy libraries |
| Plugin, has libs | Check if update needed |
| Has everything | Confirm ready for conversion |

---

## Phase 2: Confirm Setup

### Step 2.1: Present Options

**Ask user** what to set up:

```json
{
  "questions": [{
    "question": "What would you like to initialize for workflow support?",
    "header": "Setup",
    "multiSelect": true,
    "options": [
      {"label": "Workflow library", "description": "Core workflow execution (lib/workflow/)"},
      {"label": "Blueprint patterns", "description": "Skill analysis patterns (lib/blueprint/)"},
      {"label": "Templates", "description": "Workflow and loader templates"}
    ]
  }]
}
```

Store selections in `computed.setup_options`.

### Step 2.2: Confirm Overwrites

If any selected libraries already exist:

```json
{
  "questions": [{
    "question": "Some files already exist. How should I handle them?",
    "header": "Existing",
    "multiSelect": false,
    "options": [
      {"label": "Skip existing", "description": "Only copy missing files"},
      {"label": "Overwrite all", "description": "Replace with latest versions"},
      {"label": "Cancel", "description": "Don't modify anything"}
    ]
  }]
}
```

---

## Phase 3: Copy Libraries

### Step 3.1: Create Directories

Create required directory structure:

```bash
mkdir -p lib/workflow
mkdir -p lib/blueprint/patterns
mkdir -p templates
mkdir -p templates/node-templates
```

### Step 3.2: Copy Workflow Library

If "Workflow library" selected, copy these files from hiivmind-blueprint:

| Source | Destination |
|--------|-------------|
| `lib/workflow/schema.md` | `lib/workflow/schema.md` |
| `lib/workflow/execution.md` | `lib/workflow/execution.md` |
| `lib/workflow/preconditions.md` | `lib/workflow/preconditions.md` |
| `lib/workflow/consequences.md` | `lib/workflow/consequences.md` |
| `lib/workflow/state.md` | `lib/workflow/state.md` |

**Copy method:**
1. Read each source file from hiivmind-blueprint plugin
2. Write to target location
3. Track copied files in `computed.copied_files`

### Step 3.3: Copy Blueprint Patterns

If "Blueprint patterns" selected, copy:

| Source | Destination |
|--------|-------------|
| `lib/blueprint/patterns/skill-analysis.md` | `lib/blueprint/patterns/skill-analysis.md` |
| `lib/blueprint/patterns/node-mapping.md` | `lib/blueprint/patterns/node-mapping.md` |
| `lib/blueprint/patterns/workflow-generation.md` | `lib/blueprint/patterns/workflow-generation.md` |

### Step 3.4: Copy Templates

If "Templates" selected, copy:

| Source | Destination |
|--------|-------------|
| `templates/workflow.yaml.template` | `templates/workflow.yaml.template` |
| `templates/thin-loader.md.template` | `templates/thin-loader.md.template` |

---

## Phase 4: Create Plugin Structure (if needed)

### Step 4.1: Check for Plugin Manifest

If `flags.is_plugin == false`:

**Ask user:**
```json
{
  "questions": [{
    "question": "No plugin manifest found. Would you like to create one?",
    "header": "Plugin",
    "multiSelect": false,
    "options": [
      {"label": "Create plugin.json", "description": "Set up as a Claude Code plugin"},
      {"label": "Skip", "description": "Just copy libraries without plugin setup"}
    ]
  }]
}
```

### Step 4.2: Create Plugin Manifest

If user wants plugin setup:

1. **Ask for plugin name:**
   ```json
   {
     "questions": [{
       "question": "What should the plugin be named?",
       "header": "Name",
       "multiSelect": false,
       "options": [
         {"label": "Use directory name", "description": "Name based on current directory"},
         {"label": "Custom name", "description": "I'll provide a name"}
       ]
     }]
   }
   ```

2. **Create manifest:**
   ```bash
   mkdir -p .claude-plugin
   ```

   Write `.claude-plugin/plugin.json`:
   ```json
   {
     "name": "{plugin_name}",
     "description": "Plugin with deterministic workflow support",
     "version": "1.0.0",
     "license": "MIT",
     "author": {
       "name": "{author_name}"
     }
   }
   ```

### Step 4.3: Create Skills Directory

If `flags.has_skills == false`:

```bash
mkdir -p skills
```

---

## Phase 5: Update CLAUDE.md

### Step 5.1: Check for CLAUDE.md

If `file_exists("CLAUDE.md")`:
- Offer to add workflow documentation section

If not exists:
- Offer to create basic CLAUDE.md

### Step 5.2: Add Workflow Section

If user wants CLAUDE.md update, add this section:

```markdown
## Workflow-Driven Skills

This plugin uses deterministic YAML workflows for skill execution.

### Library Documentation

- **Workflow Schema:** `lib/workflow/schema.md`
- **Execution Model:** `lib/workflow/execution.md`
- **Preconditions:** `lib/workflow/preconditions.md`
- **Consequences:** `lib/workflow/consequences.md`
- **State Model:** `lib/workflow/state.md`

### Converting Skills

To convert a prose-based skill to workflow:
1. Analyze: `/hiivmind-blueprint-author analyze`
2. Convert: `/hiivmind-blueprint-author convert`
3. Generate: `/hiivmind-blueprint-author generate`
```

---

## Phase 6: Verify Setup

### Step 6.1: Validate Installation

Check all expected files exist:

```
validation:
  workflow_lib:
    - lib/workflow/engine.md
```

### Step 6.2: Report Results

Display setup summary:

```
## Blueprint Initialization Complete

### Files Copied
{for each file in computed.copied_files}
- {file}
{/for}

### Directory Structure
{tree of created directories}

### Next Steps
1. Identify skills to convert with `/hiivmind-blueprint-author discover`
2. Analyze a skill with `/hiivmind-blueprint-author analyze [skill]`
3. Convert and generate with the blueprint workflow

### Documentation
- Workflow schema: `lib/workflow/schema.md`
- Preconditions: `lib/workflow/preconditions.md`
- Consequences: `lib/workflow/consequences.md`
```

---

## Reference Documentation

- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`
- **Plugin Structure:** See `plugin-dev:plugin-structure` skill

---

## Related Skills

- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-discover/SKILL.md`
- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-analyze/SKILL.md`
- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-generate/SKILL.md`
