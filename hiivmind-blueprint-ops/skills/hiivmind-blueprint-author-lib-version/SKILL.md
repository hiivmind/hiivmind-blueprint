---
name: hiivmind-blueprint-author-lib-version
description: >
  Update the external hiivmind-blueprint-lib version references across the plugin.
  Use when upgrading to a new hiivmind-blueprint-lib release. Triggers on
  "update lib version", "upgrade blueprint-lib", "set lib version", "bump lib",
  "update external lib", "sync lib version", "change blueprint lib version".
allowed-tools: Read, Write, Edit, Bash, AskUserQuestion, WebFetch
---

# Update External Library Version

Updates references to the external hiivmind-blueprint-lib package across this plugin.

> **Config File:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`
> **External Lib:** [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib)

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Purpose |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | JSON processing |
| `yq` | **Mandatory** | `command -v yq` | YAML processing |
| `gh` | Recommended | `command -v gh` | GitHub API access (private repos) |

If mandatory tools are missing, exit with error and installation guidance.


---

## Overview

This skill centralizes updates to the external `hiivmind-blueprint-lib` version.
When you upgrade to a new version of the lib, this skill:

1. Updates `BLUEPRINT_LIB_VERSION.yaml` with the new version
2. Updates all workflow.yaml files that reference the lib
3. Updates all documentation files with version references
4. Reports all changed files

---

## Phase 1: Check Current State

### Step 1.1: Read Current Version Config

Read the current `BLUEPRINT_LIB_VERSION.yaml`:

```
config = read_yaml("${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml")

current_version = config.lib_version      # e.g., "v2.1.0"
current_ref = config.lib_ref              # e.g., "hiivmind/hiivmind-blueprint-lib@v2.1.0"
```

### Step 1.2: Check Available Versions (Optional)

Optionally fetch the latest releases from GitHub to show available versions:

```bash
# Get latest 5 tags from hiivmind-blueprint-lib
gh api repos/hiivmind/hiivmind-blueprint-lib/tags --jq '.[0:5] | .[].name'
```

Display current state:

```
## Current External Library Version

**Current:** {current_version}
**Reference:** {current_ref}

### Latest Available Versions
- v2.2.0 (latest)
- v2.1.0 (current)
- v2.0.0
- ...
```

---

## Phase 2: Determine Target Version

### Step 2.1: Ask User for Target Version

**Ask user** for the version to upgrade to:
```json
{
  "questions": [{
    "question": "Which version of hiivmind-blueprint-lib should we use?",
    "header": "Version",
    "multiSelect": false,
    "options": [
      {"label": "v2.2.0 (latest)", "description": "Latest release with new features"},
      {"label": "v2.1.0 (current)", "description": "Currently configured version"},
      {"label": "Specify version", "description": "Enter a specific version tag"}
    ]
  }]
}
```

If "Specify version" selected, prompt for custom input.

### Step 2.2: Validate Target Version

Verify the target version exists:

```bash
# Check if tag exists
gh api repos/hiivmind/hiivmind-blueprint-lib/git/refs/tags/{target_version} 2>/dev/null
```

If tag doesn't exist, report error and ask for different version.

---

## Phase 3: Find Files to Update

### Step 3.1: Scan for Version References

Find all files containing the current version string:

```bash
# Find files with current lib reference
grep -r "{current_ref}" --include="*.yaml" --include="*.md" "${CLAUDE_PLUGIN_ROOT}" | cut -d: -f1 | sort -u

# Find files with current version in raw URLs
grep -r "hiivmind-blueprint-lib/{current_version}" --include="*.md" "${CLAUDE_PLUGIN_ROOT}" | cut -d: -f1 | sort -u
```

### Step 3.2: Categorize Files

Categorize files by type:

| Category | Pattern | Update Method |
|----------|---------|---------------|
| Version Config | `BLUEPRINT_LIB_VERSION.yaml` | Full rewrite |
| Workflow Files | `**/workflow.yaml` | Update `definitions.source` |
| Documentation | `**/*.md` | Find/replace version strings |
| Templates | `templates/*.template` | Already uses `{{lib_ref}}` variable |

---

## Phase 4: Preview Changes

### Step 4.1: Show Change Plan

Display all files that will be modified:

```
## Version Update Plan

**From:** {current_version} → **To:** {target_version}

### Files to Update

| File | Type | Changes |
|------|------|---------|
| BLUEPRINT_LIB_VERSION.yaml | Config | lib_version, lib_ref, lib_raw_url |
| commands/*/workflow.yaml | Workflow | definitions.source |
| references/*.md | Docs | Version references in URLs |
| ... | ... | ... |

**Total:** {file_count} files
```

### Step 4.2: Confirm Update

**Ask user** to confirm:
```json
{
  "questions": [{
    "question": "Ready to update {file_count} files from {current_version} to {target_version}?",
    "header": "Confirm",
    "multiSelect": false,
    "options": [
      {"label": "Yes, update all", "description": "Apply changes to all files"},
      {"label": "Show details", "description": "Preview exact changes first"},
      {"label": "Cancel", "description": "Don't make any changes"}
    ]
  }]
}
```

---

## Phase 5: Apply Updates

### Step 5.1: Update BLUEPRINT_LIB_VERSION.yaml

Rewrite the config file with new values:

```yaml
# External Library Reference Configuration
# ... (header comments)

lib_version: "{target_version}"
lib_ref: "hiivmind/hiivmind-blueprint-lib@{target_version}"
lib_raw_url: "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/{target_version}"
schema_version: "2.2"  # Update if schema changed
```

### Step 5.2: Update Workflow Files

For each `workflow.yaml` with `definitions.source`:

```bash
# Update definitions.source line
yq -i '.definitions.source = "hiivmind/hiivmind-blueprint-lib@{target_version}"' "{file}"
```

### Step 5.3: Update Documentation Files

For each documentation file with version references:

```bash
# Replace version in lib references
sed -i "s|hiivmind-blueprint-lib@{current_version}|hiivmind-blueprint-lib@{target_version}|g" "{file}"

# Replace version in raw URLs
sed -i "s|hiivmind-blueprint-lib/{current_version}|hiivmind-blueprint-lib/{target_version}|g" "{file}"
```

### Step 5.4: Update Engine Entrypoint

If `.hiivmind/blueprint/engine_entrypoint.md` exists, update lib_version references:

```bash
if [[ -f .hiivmind/blueprint/engine_entrypoint.md ]]; then
  # Update lib_version references in the engine entrypoint
  sed -i "s|hiivmind-blueprint-lib@{current_version}|hiivmind-blueprint-lib@{target_version}|g" \
    .hiivmind/blueprint/engine_entrypoint.md

  sed -i "s|hiivmind-blueprint-lib/{current_version}|hiivmind-blueprint-lib/{target_version}|g" \
    .hiivmind/blueprint/engine_entrypoint.md

  echo "✓ Updated .hiivmind/blueprint/engine_entrypoint.md"
fi
```

This ensures the engine entrypoint references the correct lib version.

---

## Phase 6: Verify and Report

### Step 6.1: Verify Updates

Read back key files to verify updates applied correctly:

```
# Verify BLUEPRINT_LIB_VERSION.yaml
new_config = read_yaml("${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml")
assert new_config.lib_version == target_version
```

### Step 6.2: Check for Missed References

Search for any remaining old version references:

```bash
grep -r "{current_version}" --include="*.yaml" --include="*.md" "${CLAUDE_PLUGIN_ROOT}" | grep -v ".backup"
```

If found, report them for manual review.

### Step 6.3: Report Results

Display update summary:

```
## Version Update Complete

**Updated:** {current_version} → {target_version}

### Files Modified
{for each updated_file}
- {file_path} ✅
{/for}

### Verification
- BLUEPRINT_LIB_VERSION.yaml: ✅ Updated
- Workflow files: {workflow_count} updated
- Documentation: {doc_count} updated

### Next Steps
1. Review changes with `git diff`
2. Test a workflow that uses the lib
3. Commit with: `git commit -m "chore: bump blueprint-lib to {target_version}"`
```

---

## Rollback

If something goes wrong, the version can be reverted by running this skill again
with the previous version as the target.

---

## Reference Documentation

- **Version Config:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`
- **External Lib:** [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib)
- **Templates:** `${CLAUDE_PLUGIN_ROOT}/templates/` (use `{{lib_ref}}` variable)

---

## Related Skills

- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-generate/SKILL.md`
- Validate workflows: `/hiivmind-blueprint-ops validate`
