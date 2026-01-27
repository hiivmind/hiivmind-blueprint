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
2. Checking for engine and types updates
3. Identifying deprecated patterns
4. Applying migrations to latest schema
5. Updating `.hiivmind/blueprint/` files

---

## Schema Versions

| Version | Key Features | Breaking Changes |
|---------|--------------|------------------|
| 1.0.0 | Initial schema | - |
| 1.1.0 | Added `validation_gate` node type | None |
| 1.2.0 | Added `reference` node type | None |
| 2.0.0 | New consequence format | `set_state` syntax changed |
| 2.1.0 | External definitions, `.hiivmind/blueprint/` structure | Lock file location changed |

---

## Upgrade Modes

This skill supports two upgrade modes:

### Mode 1: Workflow Schema Upgrade
Migrate workflow.yaml files to latest schema version (2.0.0+).

### Mode 2: Infrastructure Upgrade
Update `.hiivmind/blueprint/` files (engine.md, types.lock) to latest versions.

**Invocation:**
- `/hiivmind-blueprint upgrade` - Full upgrade (schema + infrastructure)
- `/hiivmind-blueprint upgrade --check` - Check for updates without applying
- `/hiivmind-blueprint upgrade --schema-only` - Only upgrade workflow schema
- `/hiivmind-blueprint upgrade --infra-only` - Only upgrade engine/types

---

## Phase 1: Discover Workflows and Infrastructure

### Step 1.1: Check Infrastructure Version

Read current infrastructure versions from `.hiivmind/blueprint/types.lock`:

```
IF file_exists(".hiivmind/blueprint/types.lock"):
  lock_file = read_yaml(".hiivmind/blueprint/types.lock")
  current_engine_version = lock_file.engine.version
  current_types_versions = lock_file.types
ELSE:
  # Legacy plugin without types.lock
  current_engine_version = null
  current_types_versions = {}
```

### Step 1.2: Find Workflow Files

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

### Step 1.3: Select Target

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

## Phase 5: Update Infrastructure

### Step 5.1: Check for Engine Updates

Fetch latest engine version from GitHub:

```
latest_engine = fetch_github_release("hiivmind/hiivmind-blueprint", "latest")
current_engine = lock_file.engine.version

IF latest_engine.version > current_engine:
  engine_update_available = true
  engine_update = {
    from: current_engine,
    to: latest_engine.version,
    url: latest_engine.assets["engine.md"]
  }
```

### Step 5.2: Check for Types Updates

For each type source in lock file:

```
FOR each source, entry IN lock_file.types:
  # Parse version request (e.g., "@v1" → major version constraint)
  IF entry.requested is not exact version:
    latest = resolve_latest_version(source, entry.requested)
    IF latest > entry.resolved:
      types_updates.append({
        source: source,
        from: entry.resolved,
        to: latest
      })
```

### Step 5.3: Present Infrastructure Update Plan

If updates available:

```
## Infrastructure Updates Available

**Engine:**
- Current: {current_engine_version}
- Latest: {latest_engine_version}
- Changelog: {changelog_url}

**Types:**
{for each update}
- {source}: {from} → {to}
{/for}
```

### Step 5.4: Apply Infrastructure Updates

**Ask user:**
```json
{
  "questions": [{
    "question": "Apply infrastructure updates?",
    "header": "Update",
    "multiSelect": false,
    "options": [
      {"label": "Apply all", "description": "Update engine and types"},
      {"label": "Engine only", "description": "Only update engine.md"},
      {"label": "Types only", "description": "Only update type definitions"},
      {"label": "Skip", "description": "Keep current versions"}
    ]
  }]
}
```

If updates requested:

```bash
# Update engine.md
IF engine_update:
  # Fetch new engine from cache or download
  cache_path="~/.claude/cache/hiivmind/blueprint/engine/{latest_version}/"
  mkdir -p "{cache_path}"

  # Download if not cached
  IF NOT file_exists("{cache_path}/engine.md"):
    fetch_and_cache(engine_update.url, cache_path)

  # Copy to plugin
  cp "{cache_path}/engine.md" ".hiivmind/blueprint/engine.md"

# Update types.lock
update_lock_file(".hiivmind/blueprint/types.lock", {
  engine: {
    version: latest_engine_version,
    sha256: compute_sha256(".hiivmind/blueprint/engine.md"),
    source: "hiivmind/hiivmind-blueprint@{latest_version}"
  },
  types: updated_types_entries
})
```

### Step 5.5: Update SKILL.md (if needed)

If the skill's SKILL.md is a thin loader, check if it needs updates:

- References to old library paths (e.g., `lib/workflow/` → `.hiivmind/blueprint/`)
- Missing new node type documentation
- Outdated execution instructions

If updates needed:

```
# Update paths to use new .hiivmind/blueprint/ structure
sed -i 's|lib/workflow/engine.md|.hiivmind/blueprint/engine.md|g' SKILL.md
```

---

## Phase 6: Verify and Report

### Step 6.1: Validate Upgraded Workflow

Read back and verify:
1. Valid YAML syntax
2. All nodes reachable
3. All transitions valid
4. No orphaned endings

### Step 6.2: Validate Infrastructure

Check infrastructure files:
1. `.hiivmind/blueprint/engine.md` exists and is readable
2. `.hiivmind/blueprint/types.lock` has valid schema
3. Lock file versions match actual files

### Step 6.3: Report Results

```
## Upgrade Complete

**Workflow:** {workflow_path}
**Previous version:** {old_version}
**New version:** 2.0.0

### Migrations Applied ({count})
{for each applied migration}
- {migration_name}: {changes_made} changes
{/for}

### Infrastructure Updates
{if engine_updated}
- Engine: {old_engine_version} → {new_engine_version}
{/if}
{if types_updated}
- Types: {for each update}{source}: {from} → {to}{/for}
{/if}

### Files Modified
- `{workflow_path}` (upgraded)
- `{workflow_path}.backup` (backup created)
{if infra_updated}
- `.hiivmind/blueprint/engine.md` (updated)
- `.hiivmind/blueprint/types.lock` (updated)
{/if}
{if skill_updated}
- `{skill_path}` (thin loader updated)
{/if}

### Verification
- YAML syntax: Valid
- Node reachability: All nodes reachable
- Transition validity: All transitions valid
- Infrastructure: Valid

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

- **Workflow Engine:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`
- **Type Loader:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/type-loader.md`
- **Plugin Structure:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/plugin-structure.md`
- **Types Lock Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/schema/types-lock-schema.json`

---

## Related Skills

- Initialize project: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Generate gateway: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-gateway/SKILL.md`
