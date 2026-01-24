---
name: hiivmind-blueprint-upgrade
description: >
  This skill should be used when the user asks to "upgrade workflow", "migrate workflow schema",
  "update workflow to latest", "fix deprecated workflow", "modernize workflow.yaml",
  or needs to update existing workflows to the latest schema version. Triggers on "upgrade workflow",
  "blueprint upgrade", "hiivmind-blueprint upgrade", "migrate schema", "update workflow version",
  or when workflows use deprecated patterns.
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Upgrade Workflow

Migrate existing workflow.yaml files to the latest schema version with deprecation fixes and new features.

---

## Overview

This skill upgrades workflows by:
1. Detecting the current schema version
2. Identifying deprecated patterns
3. Applying migrations to latest schema
4. Optionally adding new features

---

## Schema Versions

| Version | Key Features | Breaking Changes |
|---------|--------------|------------------|
| 1.0.0 | Initial schema | - |
| 1.1.0 | Added `validation_gate` node type | None |
| 1.2.0 | Added `reference` node type | None |
| 2.0.0 | New consequence format | `set_state` syntax changed |

---

## Phase 1: Discover Workflows

### Step 1.1: Find Workflow Files

Scan for existing workflows:

```
workflows = Glob("**/workflow.yaml")
```

For each workflow found:
```yaml
workflows:
  - path: "skills/example-skill/workflow.yaml"
    skill_path: "skills/example-skill/SKILL.md"
    directory: "skills/example-skill"
```

### Step 1.2: Select Target

If multiple workflows found:

**Ask user:**
```json
{
  "questions": [{
    "question": "Which workflow would you like to upgrade?",
    "header": "Target",
    "multiSelect": false,
    "options": [
      {"label": "All workflows", "description": "Upgrade all {count} workflows"},
      {"label": "Select specific", "description": "Choose which workflows to upgrade"},
      {"label": "Cancel", "description": "Exit without changes"}
    ]
  }]
}
```

Store selection in `computed.targets`.

---

## Phase 2: Analyze Current State

### Step 2.1: Read Workflow

For each target workflow:

```
content = Read(workflow_path)
```

Parse YAML to extract:
- `version` field
- `nodes` structure
- `endings` structure
- Any deprecated patterns

### Step 2.2: Detect Schema Version

Check for version indicators:

```
function detect_version(workflow):
  # Explicit version
  if workflow.version:
    return workflow.version

  # Infer from patterns
  if has_reference_nodes(workflow):
    return "1.2.0"
  if has_validation_gate_nodes(workflow):
    return "1.1.0"

  # Check consequence format
  for node in workflow.nodes:
    for action in node.actions:
      if action.type == "set_state" and "field" in action:
        return "2.0.0"
      if action.type == "set_state" and "state" in action:
        return "1.0.0"  # Old format

  return "1.0.0"  # Default assumption
```

### Step 2.3: Identify Issues

Scan for deprecated patterns:

**Deprecated in 2.0.0:**
```yaml
# OLD (1.x)
- type: set_state
  state:
    flags:
      some_flag: true

# NEW (2.0)
- type: set_state
  field: flags.some_flag
  value: true
```

**Missing recommended fields:**
- No `version` field
- No `description` on nodes
- Missing `on_failure` handlers
- Endings without `recovery` on error type

Build issues list:
```yaml
issues:
  - type: deprecated_pattern
    location: "nodes.some_node.actions[0]"
    pattern: "old_set_state_format"
    severity: "warning"
    auto_fixable: true

  - type: missing_field
    location: "workflow"
    field: "version"
    severity: "info"
    auto_fixable: true
```

---

## Phase 3: Plan Migrations

### Step 3.1: Build Migration Plan

Based on detected version and target version:

```yaml
migrations:
  - name: "add_version_field"
    applies_when: "version is missing"
    action: "Add version: '2.0.0' to workflow root"

  - name: "update_set_state_format"
    applies_when: "old set_state format detected"
    action: "Convert state object to field/value pairs"

  - name: "add_node_descriptions"
    applies_when: "nodes missing descriptions"
    action: "Generate descriptions from node names"

  - name: "add_error_recovery"
    applies_when: "error endings without recovery"
    action: "Add recovery suggestions to error endings"
```

### Step 3.2: Present Plan

Show the migration plan:

```
## Upgrade Plan: {workflow_name}

**Current version:** {detected_version}
**Target version:** 2.0.0

### Migrations to Apply ({count})

{for each migration}
#### {migration_name}
- **Reason:** {reason}
- **Changes:** {change_count} locations
- **Risk:** {low/medium/high}
{/for}

### Issues Found ({count})
{for each issue}
- **{severity}:** {description} at {location}
{/for}
```

### Step 3.3: Confirm Upgrade

**Ask user:**
```json
{
  "questions": [{
    "question": "How would you like to proceed with the upgrade?",
    "header": "Upgrade",
    "multiSelect": false,
    "options": [
      {"label": "Apply all", "description": "Apply all {count} migrations automatically"},
      {"label": "Review each", "description": "Confirm each migration individually"},
      {"label": "Dry run", "description": "Show changes without applying"},
      {"label": "Cancel", "description": "Exit without changes"}
    ]
  }]
}
```

---

## Phase 4: Apply Migrations

### Step 4.1: Create Backup

Before making changes:

```bash
cp "{workflow_path}" "{workflow_path}.backup"
```

### Step 4.2: Apply Each Migration

**Migration: add_version_field**
```yaml
# Add at top of workflow
version: "2.0.0"
```

**Migration: update_set_state_format**
```yaml
# Convert from:
- type: set_state
  state:
    flags:
      some_flag: true
    computed:
      result: "${value}"

# To:
- type: set_state
  field: flags.some_flag
  value: true
- type: set_state
  field: computed.result
  value: "${value}"
```

**Migration: add_node_descriptions**
```yaml
# Generate from node name
nodes:
  check_prerequisites:
    type: conditional
    description: "Check prerequisites"  # Added
    condition: ...
```

**Migration: add_error_recovery**
```yaml
# Add recovery to error endings
endings:
  error_missing_file:
    type: error
    message: "Required file not found: ${missing_file}"
    recovery:  # Added
      suggestion: "Ensure the file exists before running this skill"
      related_skill: "hiivmind-blueprint-init"
```

### Step 4.3: Write Updated Workflow

After all migrations applied:

```
Write(workflow_path, updated_workflow_yaml)
```

---

## Phase 5: Update SKILL.md (if needed)

### Step 5.1: Check Thin Loader

If the skill's SKILL.md is a thin loader, check if it needs updates:

- References to old library paths
- Missing new node type documentation
- Outdated execution instructions

### Step 5.2: Update Thin Loader

If updates needed:

```
# Update execution loop to include new node types
# Update reference documentation paths
# Add any new sections
```

---

## Phase 6: Verify and Report

### Step 6.1: Validate Upgraded Workflow

Read back and verify:
1. Valid YAML syntax
2. All nodes reachable
3. All transitions valid
4. No orphaned endings

### Step 6.2: Report Results

```
## Upgrade Complete

**Workflow:** {workflow_path}
**Previous version:** {old_version}
**New version:** 2.0.0

### Migrations Applied ({count})
{for each applied migration}
- {migration_name}: {changes_made} changes
{/for}

### Files Modified
- `{workflow_path}` (upgraded)
- `{workflow_path}.backup` (backup created)
{if skill_updated}
- `{skill_path}` (thin loader updated)
{/if}

### Verification
- YAML syntax: Valid
- Node reachability: All nodes reachable
- Transition validity: All transitions valid

### Next Steps
1. Test the skill to verify behavior unchanged
2. Review the backup if issues arise
3. Commit changes to version control
```

---

## Migration Reference

### Version 1.0.0 → 1.1.0

**New features:**
- `validation_gate` node type

**No breaking changes.**

### Version 1.1.0 → 1.2.0

**New features:**
- `reference` node type
- `context` field for reference nodes

**No breaking changes.**

### Version 1.2.0 → 2.0.0

**Breaking changes:**

1. **set_state consequence format**
   ```yaml
   # OLD
   - type: set_state
     state:
       key: value

   # NEW
   - type: set_state
     field: key
     value: value
   ```

2. **Ending recovery field**
   ```yaml
   # NEW: error endings should have recovery
   endings:
     some_error:
       type: error
       message: "..."
       recovery:
         suggestion: "..."
   ```

3. **Logging moved to core**
   ```yaml
   # OLD reference path
   lib/workflow/consequences/extensions/logging.md

   # NEW reference path
   lib/workflow/consequences/core/logging.md
   ```

**New features:**
- `recovery` field on error endings
- `store_as` now supports nested paths
- Variable interpolation in node descriptions
- Logging as core consequence with validation

### Logging Migration

Detect and migrate logging-related changes:

**Step 1: Update path references**
```bash
# Find files referencing old path
grep -rl "extensions/logging.md" .

# Update to new path
sed -i 's|extensions/logging\.md|core/logging.md|g' {file}
```

**Step 2: Add logging config if consequences exist**

If workflow uses logging consequences but has no config:

```yaml
# Detect: has logging consequences but no config
has_logging = any(node.actions[].type in logging_consequence_types)
has_config = initial_state.logging exists

if has_logging and not has_config:
  # Add default config
  initial_state:
    logging:
      enabled: true
      level: "info"
      auto:
        init: false      # Skill manages explicitly
        node_tracking: false
        finalize: false
        write: false
```

**Step 3: Version bump**
```yaml
# Update schema version for logging changes
version: "2.0.0"  # Reflects logging core promotion
```

---

## Rollback

If issues after upgrade:

```bash
# Restore from backup
cp "{workflow_path}.backup" "{workflow_path}"
```

---

## Reference Documentation

- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`
- **Consequences:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/consequences.md`
- **State Model:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/state.md`

---

## Related Skills

- Initialize project: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Generate gateway: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-gateway/SKILL.md`
