---
name: hiivmind-blueprint-lib-validation
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

| Type | Schema | Path Pattern |
|------|--------|--------------|
| Consequence definitions | `consequence-definition.json` | `consequences/**/*.yaml` |
| Precondition definitions | `precondition-definition.json` | `preconditions/**/*.yaml` |
| Reusable workflows | `workflow.json` | `workflows/**/*.yaml` |
| Node type definitions | `node-definition.json` | `nodes/**/*.yaml` |

---

## Prerequisites

| Requirement | Check | Error Message |
|-------------|-------|---------------|
| check-jsonschema installed | `~/.rye/shims/check-jsonschema --version` | "check-jsonschema required. Install: pip install check-jsonschema" |

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

### Step 1.2: Locate Schema Directory

The schema files are in `hiivmind-blueprint-lib/schema/`:

```bash
# If running from hiivmind-blueprint
SCHEMA_DIR="${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema"

# If running from hiivmind-blueprint-lib
SCHEMA_DIR="${PWD}/schema"

# Verify schema directory exists
if [ ! -d "$SCHEMA_DIR" ]; then
  echo "Error: Schema directory not found at $SCHEMA_DIR"
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
SCHEMA_DIR="${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema"
LIB_SCHEMA="file://${SCHEMA_DIR}/"
```

### Step 2.2: Validate Consequence Definitions

```bash
# Validate all consequence definition files
for file in consequences/**/*.yaml; do
  echo "Validating: $file"
  ~/.rye/shims/check-jsonschema \
    --base-uri "$LIB_SCHEMA" \
    --schemafile "$SCHEMA_DIR/consequence-definition.json" \
    "$file"
done
```

**Or batch validation (faster):**

```bash
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/consequence-definition.json" \
  consequences/core/*.yaml consequences/extensions/*.yaml
```

**What it validates:**
- Required fields: `schema_version`, `category`, `description`, `consequences`
- Each consequence has: `type`, `description.brief`, `parameters`, `payload`
- Payload structure: `kind`, `effect`, optional `tool`, `state_writes`, `state_reads`
- Parameter definitions: `name`, `type`, `required`, `description`
- Example structure if present

### Step 2.3: Validate Precondition Definitions

```bash
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/precondition-definition.json" \
  preconditions/core/*.yaml preconditions/extensions/*.yaml
```

**What it validates:**
- Required fields: `schema_version`, `category`, `description`, `preconditions`
- Each precondition has: `type`, `description.brief`, `parameters`, `evaluation`
- Evaluation structure: `effect`, optional `reads`, `functions`
- Parameter definitions: `name`, `type`, `required`, `description`

### Step 2.4: Validate Workflow Definitions

```bash
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  workflows/core/*.yaml
```

**What it validates:**
- Required fields: `name`, `version`, `start_node`, `nodes`, `endings`
- Node structure per type (action, conditional, user_prompt, validation_gate, reference)
- Ending structure: `type`, optional `message`, `summary`, `recovery`
- Valid node type enum values

### Step 2.5: Validate Node Type Definitions

```bash
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/node-definition.json" \
  nodes/core/*.yaml nodes/extensions/*.yaml
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
SCHEMA_DIR="/path/to/hiivmind-blueprint-lib/schema"
LIB_SCHEMA="file://${SCHEMA_DIR}/"

# From hiivmind-blueprint-lib directory
~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/consequence-definition.json" \
  consequences/**/*.yaml

~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/precondition-definition.json" \
  preconditions/**/*.yaml

~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  workflows/**/*.yaml

~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/node-definition.json" \
  nodes/**/*.yaml
```

### Validate Single File

```bash
~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/consequence-definition.json" \
  consequences/core/state.yaml
```

### Check Schema is Valid

```bash
~/.rye/shims/check-jsonschema --check-metaschema "$SCHEMA_DIR/consequence-definition.json"
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

| Schema | Purpose |
|--------|---------|
| `common.json` | Shared definitions (semver, identifiers, parameters) |
| `consequence-definition.json` | Consequence YAML file structure |
| `precondition-definition.json` | Precondition YAML file structure |
| `workflow.json` | Workflow YAML file structure |
| `node-definition.json` | Node type definition YAML files (nodes/core/*.yaml) |
| `node-types.json` | Node type enum/structure (used by workflow.json) |
| `intent-mapping.json` | Intent mapping YAML file structure |
| `logging-config.json` | Plugin logging.yaml structure |

---

## Related Skills

- Validate workflows: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-validate/SKILL.md`
- Upgrade workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-upgrade/SKILL.md`
