# Validation Skills Plan

## Context

Two validation skills needed:

1. **hiivmind-blueprint-validate** (existing) - Workflow validation for framework users
2. **hiivmind-blueprint-lib-validation** (new) - Framework/type validation for maintainers & plugin authors

Both need updating to use schemas from `hiivmind-blueprint-lib` via `check-jsonschema` CLI.

## Skill Organization

| Skill | Validates | Audience |
|-------|-----------|----------|
| `hiivmind-blueprint-validate` | workflow.yaml, intent-mapping.yaml | Framework users |
| `hiivmind-blueprint-lib-validation` | consequence/precondition definitions, node types | Maintainers, plugin authors |

**Schema Location**: Sibling path `../hiivmind-blueprint-lib/schema/`

---

## Files to Modify/Create

### Skill 1: hiivmind-blueprint-validate (UPDATE)
- `skills/hiivmind-blueprint-validate/SKILL.md` - Update existing skill

### Skill 2: hiivmind-blueprint-lib-validation (CREATE)
- `skills/hiivmind-blueprint-lib-validation/SKILL.md` - New skill

---

## Skill 1: hiivmind-blueprint-validate

**Purpose**: Validate workflow.yaml files for framework users

### Changes Required

1. **Update schema references** - Point to `../hiivmind-blueprint-lib/schema/`
2. **Use check-jsonschema CLI** - Replace Python jsonschema with CLI tool
3. **Update branch references** - `branches.true/false` → `branches.on_true/on_false`
4. **Simplify scope** - Remove type definition validation (moved to new skill)

### Validation Command Pattern

```bash
SCHEMA_DIR="${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema"
LIB_SCHEMA="file://${SCHEMA_DIR}/"

~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  workflow.yaml
```

### Schema Mapping

| What | Schema |
|------|--------|
| workflow.yaml | `workflow.json` |
| intent-mapping.yaml | `intent-mapping.json` |
| logging.yaml (plugin config) | `logging-config.json` |

---

## Skill 2: hiivmind-blueprint-lib-validation

**Purpose**: Validate framework type definitions for maintainers and plugin authors

### Skill Description (SKILL.md frontmatter)

```yaml
name: hiivmind-blueprint-lib-validation
description: >
  This skill should be used when the user asks to "validate type definitions",
  "check consequence definitions", "validate preconditions", "lint blueprint-lib",
  "check framework types", or wants to validate YAML files in hiivmind-blueprint-lib.
  Triggers on "validate lib", "check types", "validate consequences", "validate preconditions".
allowed-tools: Read, Glob, Grep, Bash
```

### What It Validates

| Type | Schema | Path Pattern |
|------|--------|--------------|
| Consequence definitions | `consequence-definition.json` | `consequences/**/*.yaml` |
| Precondition definitions | `precondition-definition.json` | `preconditions/**/*.yaml` |
| Node type definitions | (no schema yet) | `nodes/**/*.yaml` |
| Reusable workflows | `workflow.json` | `workflows/**/*.yaml` |

### Validation Flow

1. **Detect target**: Directory or file path provided
2. **Classify files**: Based on path (consequences/, preconditions/, workflows/)
3. **Select schema**: Map file type to schema
4. **Run validation**: Use check-jsonschema for each file
5. **Report results**: Summary with pass/fail counts

### Validation Command Patterns

```bash
SCHEMA_DIR="/path/to/hiivmind-blueprint-lib/schema"
LIB_SCHEMA="file://${SCHEMA_DIR}/"

# Consequences
~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/consequence-definition.json" \
  consequences/core/*.yaml consequences/extensions/*.yaml

# Preconditions
~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/precondition-definition.json" \
  preconditions/core/*.yaml preconditions/extensions/*.yaml

# Workflows
~/.rye/shims/check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  workflows/core/*.yaml
```

---

## Verification

After implementation:

```bash
# Test workflow validation (Skill 1)
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint
/hiivmind-blueprint validate commands/hiivmind-blueprint/workflow.yaml

# Test lib validation (Skill 2)
cd /home/nathanielramm/git/hiivmind/hiivmind-blueprint-lib
/hiivmind-blueprint lib-validation consequences/
/hiivmind-blueprint lib-validation preconditions/
/hiivmind-blueprint lib-validation .  # All types

# Expected: All pass (we fixed issues earlier this session)
```
