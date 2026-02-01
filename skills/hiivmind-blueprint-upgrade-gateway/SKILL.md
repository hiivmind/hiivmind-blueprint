---
name: hiivmind-blueprint-upgrade-gateway
description: >
  This skill should be used when the user asks to "upgrade gateway", "upgrade command",
  "migrate gateway command", "update gateway to latest", "fix deprecated gateway",
  "modernize gateway", "normalize gateway loader", "thin out gateway", or needs to update
  existing gateway command workflows to the latest schema version. Triggers on "upgrade gateway",
  "blueprint upgrade-gateway", "hiivmind-blueprint upgrade-gateway", "migrate gateway schema",
  "update gateway version", "normalize fat gateway", or when gateway workflows use deprecated
  patterns or gateway loaders exceed template size limits. NOTE: For skills in skills/, use
  hiivmind-blueprint-upgrade instead.
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Upgrade Gateway Workflow

Migrate existing gateway command workflow.yaml files to the latest schema version with deprecation fixes and new features.

**Scope:** Gateway commands in `commands/` directory only. For skills, use `/hiivmind-blueprint upgrade`.

---

## Overview

This skill upgrades gateway command workflows by:
1. Detecting the current schema version
2. Identifying deprecated patterns (including local engine.md references)
3. Applying migrations to latest schema
4. Migrating gateway .md files to use remote execution references
5. Removing obsolete `.hiivmind/blueprint/engine.md` files
6. Normalizing "fat" gateway loaders to match gateway-command.md.template

---

## Schema Versions

| Version | Key Features | Breaking Changes |
|---------|--------------|------------------|
| 1.0.0 | Initial schema | - |
| 1.1.0 | Added `validation_gate` node type | None |
| 1.2.0 | Added `reference` node type | None |
| 2.0.0 | New consequence format | `set_state` syntax changed |
| 2.1.0 | External definitions, `.hiivmind/blueprint/` structure | Lock file location changed |
| 2.2.0 | Remote execution references | Local engine.md removed, loaders use raw GitHub URLs |

---

## Upgrade Modes

This skill supports four upgrade modes:

### Mode 1: Workflow Schema Upgrade
Migrate workflow.yaml files to latest schema version (2.0.0+).

### Mode 2: Execution Reference Migration
Migrate gateway .md files from local engine.md references to remote execution URLs.

### Mode 3: Infrastructure Cleanup
Remove obsolete `.hiivmind/blueprint/engine.md` files (no longer needed).

### Mode 4: Loader Normalization
Normalize "fat" gateway loaders to match `gateway-command.md.template`. Fat loaders contain execution pseudocode and framework documentation that belongs in blueprint-lib.

**Note:** This skill only handles gateways in `commands/` directory. For skills in `skills/`, use `/hiivmind-blueprint upgrade`.

**Invocation:**
- `/hiivmind-blueprint upgrade-gateway` - Full upgrade (all modes)
- `/hiivmind-blueprint upgrade-gateway --check` - Check for updates without applying
- `/hiivmind-blueprint upgrade-gateway --schema-only` - Only upgrade workflow schema
- `/hiivmind-blueprint upgrade-gateway --refs-only` - Only migrate execution references
- `/hiivmind-blueprint upgrade-gateway --normalize-only` - Only normalize fat loaders
- `/hiivmind-blueprint upgrade-gateway --skip-normalize` - Skip loader normalization

---

## Phase 1: Discover Workflows and Infrastructure

### Step 1.1: Check for Legacy Engine Files

Check if plugin has obsolete local engine.md:

```
has_legacy_engine = file_exists(".hiivmind/blueprint/engine.md")

IF has_legacy_engine:
  # This plugin needs migration to remote execution references
  needs_execution_migration = true
ELSE:
  needs_execution_migration = false
```

### Step 1.2: Find Gateway Workflow Files

Scan for existing gateway workflows:

```
workflows = Glob("commands/**/workflow.yaml")
```

For each workflow found, verify it's a gateway (has intent-mapping.yaml sibling):

```yaml
gateways:
  - path: "commands/my-gateway/workflow.yaml"
    loader_path: "commands/my-gateway/my-gateway.md"
    intent_mapping_path: "commands/my-gateway/intent-mapping.yaml"
    directory: "commands/my-gateway"
```

**Validation:** Skip any command without `intent-mapping.yaml` sibling (not a gateway).

### Step 1.3: Select Target

If multiple gateways found:

**Ask user:**
```json
{
  "questions": [{
    "question": "Which gateway would you like to upgrade?",
    "header": "Target",
    "multiSelect": false,
    "options": [
      {"label": "All gateways", "description": "Upgrade all {count} gateways"},
      {"label": "Select specific", "description": "Choose which gateways to upgrade"},
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
## Upgrade Plan: {gateway_name}

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

## Phase 5: Migrate Execution References

### Step 5.1: Check for Legacy Engine References

Scan gateway .md files for local engine.md references:

```
# Patterns that indicate legacy references:
legacy_patterns = [
  ".hiivmind/blueprint/engine.md",
  "lib/workflow/engine.md",
  "${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md"
]

for gateway_md in Glob("commands/**/*.md"):
  # Skip if no workflow.yaml sibling (not a gateway command)
  if not file_exists(dirname(gateway_md) + "/workflow.yaml"):
    continue
  # Skip if no intent-mapping.yaml sibling (not a gateway)
  if not file_exists(dirname(gateway_md) + "/intent-mapping.yaml"):
    continue

  content = Read(gateway_md)
  for pattern in legacy_patterns:
    if pattern in content:
      needs_migration.append(gateway_md)
```

### Step 5.2: Extract Library Version

Read workflow.yaml to get definitions.source version:

```
workflow = Read("{gateway_dir}/workflow.yaml")
definitions_source = workflow.definitions.source
# e.g., "hiivmind/hiivmind-blueprint-lib@v2.0.0"

lib_version = definitions_source.split("@")[1]  # e.g., "v2.0.0"
```

### Step 5.3: Present Migration Plan

If legacy references found:

```
## Execution Reference Migration

**Found {count} gateway .md files with local engine.md references.**

These will be updated to use remote execution semantics from:
- hiivmind-blueprint-lib@{lib_version}

### Changes
- Replace local engine.md reference with Execution Reference table
- Add raw GitHub URLs for traversal.yaml, state.yaml, etc.
- Remove dependency on local .hiivmind/blueprint/engine.md
```

### Step 5.4: Apply Execution Reference Migration

**Ask user:**
```json
{
  "questions": [{
    "question": "Migrate gateway .md files to remote execution references?",
    "header": "Migrate",
    "multiSelect": false,
    "options": [
      {"label": "Apply", "description": "Update gateway .md files with remote URLs"},
      {"label": "Skip", "description": "Keep local references"}
    ]
  }]
}
```

If migration requested, for each gateway .md:

```
# Replace local engine reference section with remote URLs table
old_section = """
## Reference

- **Engine:** `${CLAUDE_PLUGIN_ROOT}/.hiivmind/blueprint/engine.md`
"""

new_section = """
## Execution Reference

Execution semantics from [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) (version: {lib_version}):

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{lib_version}/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{lib_version}/execution/state.yaml) |
| ... | ... |
"""

Edit(gateway_md, old_section, new_section)
```

### Step 5.5: Remove Obsolete Engine File

If `.hiivmind/blueprint/engine.md` exists and all gateway .md files have been migrated:

**Ask user:**
```json
{
  "questions": [{
    "question": "Remove obsolete .hiivmind/blueprint/engine.md?",
    "header": "Cleanup",
    "multiSelect": false,
    "options": [
      {"label": "Remove", "description": "Delete the obsolete engine.md file"},
      {"label": "Keep", "description": "Keep engine.md for reference (will be ignored)"}
    ]
  }]
}
```

If removal requested:

```bash
rm ".hiivmind/blueprint/engine.md"

# Remove directory if empty (only had engine.md)
rmdir ".hiivmind/blueprint" 2>/dev/null || true
```

---

## Phase 6: Normalize Fat Gateway Loaders

Normalize gateway loaders (.md files in `commands/`) that contain execution pseudocode and framework documentation that belongs in blueprint-lib, not in the loader.

**Note:** This phase only handles gateways in `commands/` directory. For skills, use `/hiivmind-blueprint upgrade`.

### Step 6.1: Detect Fat Gateway Loaders

For each gateway .md in `commands/` with sibling workflow.yaml AND intent-mapping.yaml:

```
loaders = []
THRESHOLD = 200  # Lines - fixed threshold for gateways

# Find all gateway loaders (commands/ directory only, with intent-mapping.yaml)
for gateway_md in Glob("commands/**/*.md"):
  dir = dirname(gateway_md)
  if file_exists(dir + "/workflow.yaml") AND file_exists(dir + "/intent-mapping.yaml"):
    loaders.append({path: gateway_md})

# Classify each loader
for loader in loaders:
  line_count = count_lines(loader.path)
  content = Read(loader.path)

  # Detection patterns for fat loaders
  has_pseudocode = matches(content, /### Phase \d:|LOOP:|FOR each|CONTINUE/)
  has_framework_docs = matches(content, /## Variable Interpolation/)
  has_extended_3vl = matches(content, /## 3VL Intent Detection/) AND section_lines > 20
  has_algorithm = matches(content, /# Algorithm:/)
  has_execution_loop = matches(content, /## Execution Loop|### Phase.*: Execution/)
  has_context_types = matches(content, /## Context Types/)

  is_fat = (line_count > THRESHOLD) AND
           (has_pseudocode OR has_framework_docs OR has_extended_3vl OR
            has_algorithm OR has_execution_loop)

  if is_fat:
    fat_loaders.append({
      path: loader.path,
      line_count: line_count,
      threshold: THRESHOLD,
      patterns_matched: [list of matched patterns]
    })
```

### Step 6.2: Present Detection Results

If fat loaders found:

```
## Gateway Loader Normalization Analysis

Found {count} fat gateway loaders that exceed template size:

| Loader | Lines | Threshold | Patterns |
|--------|-------|-----------|----------|
{for each fat_loader}
| `{path}` | {line_count} | {threshold} | {patterns} |
{/for}

### What Will Be Normalized

Fat gateway loaders contain execution pseudocode and framework documentation that:
- Duplicates content from blueprint-lib
- Makes loaders hard to maintain
- Violates the template pattern

After normalization, loaders will match `gateway-command.md.template` (~160 lines).

**Note:** For skills in `skills/`, use `/hiivmind-blueprint upgrade`.
```

### Step 6.3: Extract Preserved Content

For each fat gateway loader, extract sections to preserve:

```
function extract_preserved_sections(loader_path):
  content = Read(loader_path)

  preserved = {
    frontmatter: extract_yaml_frontmatter(content),
    title: extract_first_h1(content),
    workflow_graph: extract_section(content, "## Workflow Graph"),
    example_usage: extract_section(content, "## Quick Examples|## Example Usage"),
    related_skills: extract_section(content, "## Related Skills"),
    # Gateway-specific sections
    skill_tables: extract_sections(content, "## Available Skills|## Build Skills|## Read Skills|## Shared Skills"),
    help_commands: extract_section(content, "## Help Commands")
  }

  return preserved
```

### Step 6.4: Read Workflow Metadata

Extract library version from workflow.yaml:

```
workflow_path = dirname(loader_path) + "/workflow.yaml"
workflow = parse_yaml(Read(workflow_path))

# Extract version from definitions.source
# e.g., "hiivmind/hiivmind-blueprint-lib@v2.0.0" → "v2.0.0"
if workflow.definitions?.source:
  lib_version = workflow.definitions.source.split("@")[1]
else:
  lib_version = "v2.0.0"  # Default fallback
```

### Step 6.5: Present Normalization Plan

Show before/after comparison:

```
## Normalization Plan: {loader_path}

**Current:** {line_count} lines
**Target:** ~160 lines (gateway-command.md.template)
**Reduction:** {reduction_percent}%

### Sections to REMOVE (duplicates blueprint-lib)

{for each removed_section}
- **{section_name}** ({line_count} lines)
  - Reason: {reason}
{/for}

### Sections to PRESERVE

{for each preserved_section}
- **{section_name}** ({line_count} lines)
{/for}

### Template to Apply

`gateway-command.md.template` with:
- lib_version: {lib_version}
- plugin_name: {plugin_name}
- description: [from frontmatter]
```

### Step 6.6: Confirm Normalization

**Ask user:**
```json
{
  "questions": [{
    "question": "Normalize this gateway loader to match template?",
    "header": "Normalize",
    "multiSelect": false,
    "options": [
      {"label": "Apply", "description": "Normalize to template (~160 lines)"},
      {"label": "Preview", "description": "Show what the normalized loader will look like"},
      {"label": "Skip", "description": "Keep current loader"}
    ]
  }]
}
```

### Step 6.7: Apply Template

If normalization approved:

```
# Always use gateway-command template for gateways
template = Read("${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template")

# Replace template placeholders with extracted/derived values
normalized = template
  .replace("{{plugin_name}}", preserved.frontmatter.name or plugin_name)
  .replace("{{plugin_title}}", title_case(plugin_name))
  .replace("{{description}}", preserved.frontmatter.description)
  .replace("{{lib_version}}", lib_version)
  .replace("{{title}}", preserved.title)

# Insert preserved sections
if preserved.workflow_graph:
  normalized = insert_section(normalized, "## Workflow Graph", preserved.workflow_graph)

if preserved.example_usage:
  normalized = insert_after_section(normalized, "## Quick Examples", preserved.example_usage)

if preserved.skill_tables:
  normalized = replace_section(normalized, "## Available Operations", preserved.skill_tables)

if preserved.help_commands:
  normalized = replace_section(normalized, "## Help Commands", preserved.help_commands)

if preserved.related_skills:
  normalized = replace_section(normalized, "## Related Skills", preserved.related_skills)

# Create backup
Write(loader_path + ".backup", Read(loader_path))

# Write normalized loader
Write(loader_path, normalized)
```

### Step 6.8: Verify Normalization

After writing:

```
THRESHOLD = 200
new_line_count = count_lines(loader_path)

# Verify size reduction
if new_line_count > THRESHOLD:
  warn("Normalized loader still exceeds threshold ({new_line_count} > {THRESHOLD})")

# Verify required sections present for gateway loaders
required_sections = ["## Usage", "## Execution Reference", "## Related Skills"]

for section in required_sections:
  if not contains_section(loader_path, section):
    error("Missing required section: {section}")

# Verify workflow.yaml unchanged
workflow_unchanged = file_hash(workflow_path) == original_workflow_hash

# Verify intent-mapping.yaml unchanged
intent_unchanged = file_hash(intent_mapping_path) == original_intent_hash
```

---

## Phase 7: Verify and Report

### Step 7.1: Validate Upgraded Workflow

Read back and verify:
1. Valid YAML syntax
2. All nodes reachable
3. All transitions valid
4. No orphaned endings

### Step 7.2: Validate Execution References

Check that all gateway .md files now use remote URLs:
1. No remaining references to local engine.md
2. Execution Reference table present with valid URLs

### Step 7.3: Report Results

```
## Upgrade Complete

**Gateway:** {gateway_path}
**Previous version:** {old_version}
**New version:** 2.0.0

### Migrations Applied ({count})
{for each applied migration}
- {migration_name}: {changes_made} changes
{/for}

### Execution Reference Migration
{if refs_migrated}
- {count} gateway .md files updated to use remote execution URLs
- Library version: {lib_version}
{/if}

### Gateway Loader Normalization
{if loaders_normalized}
| Loader | Before | After | Reduction |
|--------|--------|-------|-----------|
{for each normalized_loader}
| `{path}` | {before_lines} | {after_lines} | {reduction}% |
{/for}
{else}
- No fat gateway loaders found (all within template size limits)
{/if}

### Files Modified
- `{workflow_path}` (upgraded)
- `{workflow_path}.backup` (backup created)
{if gateway_updated}
- `{gateway_path}` (execution references migrated)
{/if}
{if loaders_normalized}
{for each normalized_loader}
- `{path}` (normalized from {before_lines} to {after_lines} lines)
- `{path}.backup` (backup created)
{/for}
{/if}

### Files Removed
{if engine_removed}
- `.hiivmind/blueprint/engine.md` (obsolete, no longer needed)
{/if}

### Verification
- YAML syntax: Valid
- Node reachability: All nodes reachable
- Transition validity: All transitions valid
- Remote URLs: All resolve correctly
{if loaders_normalized}
- Normalized gateway loaders: All within template size limits
- workflow.yaml files: Unchanged (verified)
- intent-mapping.yaml files: Unchanged (verified)
{/if}

### Next Steps
1. Test the gateway to verify behavior unchanged
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

**New features:**
- `recovery` field on error endings
- `store_as` now supports nested paths
- Variable interpolation in node descriptions

### Version 2.1.0 → 2.2.0

**Breaking changes:**

1. **Local engine.md removed**

   Gateway .md files no longer reference a local `.hiivmind/blueprint/engine.md`.
   Instead, they include an "Execution Reference" table with raw GitHub URLs
   to hiivmind-blueprint-lib.

2. **Obsolete files to remove**
   - `.hiivmind/blueprint/engine.md` - No longer needed
   - The `.hiivmind/blueprint/` directory can be removed if only engine.md was in it

**Benefits of 2.2.0:**
- Standalone plugins work correctly without local lib dependencies
- Version pinning via `definitions.source` controls execution semantics
- Simpler plugin distribution (no engine.md to copy/maintain)

---

## Rollback

If issues after upgrade:

```bash
# Restore from backup
cp "{workflow_path}.backup" "{workflow_path}"
cp "{loader_path}.backup" "{loader_path}"
```

---

## Reference Documentation

- **Workflow Engine:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`
- **Type Loader:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/type-loader.md`
- **Plugin Structure:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/plugin-structure.md`

---

## Related Skills

- **Upgrade skills:** `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-upgrade/SKILL.md`
- Initialize project: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Generate gateway: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-gateway/SKILL.md`
