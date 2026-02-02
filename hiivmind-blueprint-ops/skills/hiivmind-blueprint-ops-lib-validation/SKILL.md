---
name: hiivmind-blueprint-ops-lib-validation
description: >
  This skill should be used when the user asks to "validate type definitions",
  "check consequence definitions", "validate preconditions", "lint blueprint-lib",
  "check framework types", "validate lib", or wants to validate YAML files in hiivmind-blueprint-lib.
  Triggers on "validate lib", "check types", "validate consequences", "validate preconditions",
  "lib validation", "framework validation", or when validating files in consequences/ or preconditions/ directories.
allowed-tools: Read, Glob, Grep, Bash
---

# Validate Framework Type Definitions

Validate consequence, precondition, and workflow definition files against JSON schemas using check-jsonschema CLI.

> **Schema Location:** `${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema/`

---

## Overview

This skill validates framework type definitions for maintainers and plugin authors:

| Type | Schema | File |
|------|--------|------|
| Consequence definitions | `definitions/consequence-definition.json` | `consequences/consequences.yaml` |
| Precondition definitions | `definitions/precondition-definition.json` | `preconditions/preconditions.yaml` |
| Reusable workflows | `authoring/workflow.json` | `workflows/*.yaml` |
| Node type definitions | `definitions/node-definition.json` | `nodes/workflow_nodes.yaml` |

---

## Prerequisites

| Requirement | Check | Error Message |
|-------------|-------|---------------|
| check-jsonschema installed | `which check-jsonschema` | "check-jsonschema required. Install: pip install check-jsonschema" |

---

## Phase 1: Detect Target

### Step 1.1: Determine Validation Scope

If user provided a path:
1. Check if it's a file or directory
2. Classify based on path pattern:
   - `consequences/` → Consequence definitions
   - `preconditions/` → Precondition definitions
   - `workflows/` → Workflow definitions
   - `nodes/` → Node type definitions
   - `.` or no path → All types

If no path provided:
1. Check if current directory is `hiivmind-blueprint-lib` or contains type definition directories
2. If not, ask user for the path to validate

### Step 1.2: Fetch Schema Files from Remote

The schema files are fetched from `hiivmind-blueprint-lib` using the same protocol as execution semantics.

```bash
# Extract lib version from BLUEPRINT_LIB_VERSION.yaml
LIB_VERSION=$(yq '.lib_version' "${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml")

# Create temp directory for schemas
SCHEMA_DIR=$(mktemp -d)

# Fetch with gh api (primary) or curl (fallback)
fetch_schema() {
  local schema_file="$1"
  local version="$2"
  local output_path="$3"

  # Try gh api first
  if gh api "repos/hiivmind/hiivmind-blueprint-lib/contents/schema/${schema_file}?ref=${version}" \
    --jq '.content' 2>/dev/null | base64 -d > "$output_path" 2>/dev/null; then
    return 0
  fi

  # Fallback to raw URL
  if curl -sL "https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/${version}/schema/${schema_file}" \
    -o "$output_path" 2>/dev/null; then
    return 0
  fi

  echo "ERROR: Failed to fetch schema/${schema_file}@${version}" >&2
  return 1
}

# Create subdirectories to match lib schema structure
mkdir -p "$SCHEMA_DIR/definitions" "$SCHEMA_DIR/authoring"

# Fetch definition schemas (in schema/definitions/ subdirectory)
fetch_schema "definitions/consequence-definition.json" "$LIB_VERSION" "$SCHEMA_DIR/definitions/consequence-definition.json"
fetch_schema "definitions/precondition-definition.json" "$LIB_VERSION" "$SCHEMA_DIR/definitions/precondition-definition.json"
fetch_schema "definitions/node-definition.json" "$LIB_VERSION" "$SCHEMA_DIR/definitions/node-definition.json"

# Fetch authoring schemas (in schema/authoring/ subdirectory)
fetch_schema "authoring/workflow.json" "$LIB_VERSION" "$SCHEMA_DIR/authoring/workflow.json"

# Fetch common schema (at schema root)
fetch_schema "common.json" "$LIB_VERSION" "$SCHEMA_DIR/common.json"

# Verify schemas were fetched
if [ ! -f "$SCHEMA_DIR/definitions/consequence-definition.json" ]; then
  echo "Error: Failed to fetch schemas from hiivmind-blueprint-lib@${LIB_VERSION}"
  exit 1
fi
```

### Step 1.3: Enumerate Files to Validate

Based on scope, glob for matching files:

```bash
# Consequences
CONSEQUENCE_FILES=$(find consequences -name "*.yaml" -type f 2>/dev/null)

# Preconditions
PRECONDITION_FILES=$(find preconditions -name "*.yaml" -type f 2>/dev/null)

# Workflows
WORKFLOW_FILES=$(find workflows -name "*.yaml" -type f 2>/dev/null)

# Node types
NODE_FILES=$(find nodes -name "*.yaml" -type f 2>/dev/null)
```

---

## Phase 2: Run Validation

### Step 2.1: Set Up Schema Base URI

The schemas use `$ref` composition, requiring `--base-uri` for relative reference resolution:

```bash
# SCHEMA_DIR was populated by remote fetch in Step 1.2
LIB_SCHEMA="file://${SCHEMA_DIR}/"
```

### Step 2.2: Validate Consequence Definitions

The lib uses a single consolidated consequences.yaml file (not core/extensions subdirectories).

```bash
# Validate consolidated consequence definitions file
check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/consequence-definition.json" \
  consequences/consequences.yaml
```

**What it validates:**
- Required fields: `schema_version`, `category`, `description`, `consequences`
- Each consequence has: `type`, `description.brief`, `parameters`, `payload`
- Payload structure: `kind`, `effect`, optional `tool`, `state_writes`, `state_reads`
- Parameter definitions: `name`, `type`, `required`, `description`
- Example structure if present

### Step 2.3: Validate Precondition Definitions

The lib uses a single consolidated preconditions.yaml file.

```bash
check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/precondition-definition.json" \
  preconditions/preconditions.yaml
```

**What it validates:**
- Required fields: `schema_version`, `category`, `description`, `preconditions`
- Each precondition has: `type`, `description.brief`, `parameters`, `evaluation`
- Evaluation structure: `effect`, optional `reads`, `functions`
- Parameter definitions: `name`, `type`, `required`, `description`

### Step 2.4: Validate Workflow Definitions

```bash
check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/authoring/workflow.json" \
  workflows/*.yaml
```

**What it validates:**
- Required fields: `name`, `version`, `start_node`, `nodes`, `endings`
- Node structure per type (action, conditional, user_prompt, validation_gate, reference)
- Ending structure: `type`, optional `message`, `summary`, `recovery`
- Valid node type enum values

### Step 2.5: Validate Node Type Definitions

The lib uses a single consolidated workflow_nodes.yaml file.

```bash
check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/node-definition.json" \
  nodes/workflow_nodes.yaml
```

**What it validates:**
- Required fields: `schema_version`, `category`, `nodes`
- Each node has: `type`, `description.brief`, `fields`, `execution`
- Field definitions: `name`, `type`, `description`, optional `required`, `properties`, `items`
- Execution structure: `effect`, optional `state_reads`, `state_writes`
- Deprecation structure if present: `since`, `replacement`, `reason`
- Example structure if present: `title`, `yaml`, optional `explanation`

---

## Phase 3: Generate Report

### Step 3.1: Collect Results

Track pass/fail for each file:

```yaml
results:
  consequences:
    total: 8
    passed: 7
    failed: 1
    errors:
      - file: "consequences/extensions/git.yaml"
        message: "Missing required field: payload.kind"
  preconditions:
    total: 5
    passed: 5
    failed: 0
    errors: []
  workflows:
    total: 1
    passed: 1
    failed: 0
    errors: []
```

### Step 3.2: Format Report

```
════════════════════════════════════════════
  Blueprint Lib Type Definition Validation
════════════════════════════════════════════

Summary
───────
✓ Consequences: 7/8 passed
✓ Preconditions: 5/5 passed
✓ Workflows: 1/1 passed

Errors (1)
──────────
✗ consequences/extensions/git.yaml
  Missing required field: payload.kind
  At path: $.consequences[2].payload

Total: 13/14 files passed
```

### Step 3.3: Exit Code

- Exit 0 if all files pass
- Exit 1 if any file fails validation

---

## Quick Reference

### Validate All Types

```bash
# SCHEMA_DIR is populated by remote fetch (see Step 1.2)
# LIB_SCHEMA is the file:// base URI for $ref resolution
LIB_SCHEMA="file://${SCHEMA_DIR}/"

# From hiivmind-blueprint-lib directory (with fetched schemas)
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/consequence-definition.json" \
  consequences/consequences.yaml

check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/precondition-definition.json" \
  preconditions/preconditions.yaml

check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/authoring/workflow.json" \
  workflows/*.yaml

check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/node-definition.json" \
  nodes/workflow_nodes.yaml
```

### Validate Single File

```bash
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/definitions/consequence-definition.json" \
  consequences/consequences.yaml
```

### Check Schema is Valid

```bash
check-jsonschema --check-metaschema "$SCHEMA_DIR/definitions/consequence-definition.json"
```

---

## Common Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `'schema_version' is a required property` | Missing version | Add `schema_version: "1.0"` at top |
| `'brief' is a required property` | Description missing brief | Change `description: "text"` to `description: { brief: "text" }` |
| `'effect' is a required property` | Payload missing effect | Add `effect: "description of what happens"` to payload |
| `Additional properties not allowed` | Extra fields | Remove unlisted fields or check schema version |
| `not valid under any of the given schemas` | Wrong enum value | Check valid values for `kind`, `type`, etc. |

---

## Schema Files Reference

| Schema Path | Purpose |
|-------------|---------|
| `common.json` | Shared definitions (semver, identifiers, parameters) |
| `definitions/consequence-definition.json` | Consequence YAML file structure |
| `definitions/precondition-definition.json` | Precondition YAML file structure |
| `definitions/node-definition.json` | Node type definition YAML files |
| `authoring/workflow.json` | Workflow YAML file structure |
| `authoring/node-types.json` | Node type enum/structure (used by workflow.json) |
| `authoring/intent-mapping.json` | Intent mapping YAML file structure |
| `config/logging.json` | Plugin logging.yaml structure |

---

## Related Skills

- Validate workflows: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-validate/SKILL.md`
- Upgrade workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-upgrade/SKILL.md`
