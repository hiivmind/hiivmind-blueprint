# Preconditions Catalog

Complete reference for all 9 precondition types available in hiivmind-blueprint-lib.

> **Examples:** `hiivmind/hiivmind-blueprint-lib/examples/preconditions.yaml`
> **Definitions:** `hiivmind/hiivmind-blueprint-lib/preconditions/core.yaml`, `preconditions/extensions.yaml`

---

## Overview

Preconditions are boolean checks used in:
- `entry_preconditions` - Guard workflow entry
- `conditional` nodes - Branch based on state
- `audit` mode - Validate multiple conditions

They are organized into 8 categories:

| Category | Count | Purpose |
|----------|-------|---------|
| core/composite | 1 | Logical combinators (all, any, none, xor) |
| core/expression | 1 | Arbitrary expression evaluation |
| core/state | 1 | State inspection (consolidated) |
| extensions/filesystem | 1 | Path checks (consolidated) |
| extensions/tools | 1 | Tool availability (consolidated) |
| extensions/python | 1 | Python module availability |
| extensions/network | 1 | Network connectivity |
| extensions/git | 1 | Source repository checks (consolidated) |
| extensions/web | 1 | Web fetch result checks (consolidated) |

---

## core/composite

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `composite` | Combine conditions with logical operators | `operator`, `conditions` |

**Operators:** `all` (AND), `any` (OR), `none` (NOR), `xor` (exactly one)

**Short-circuit behavior:**
- `operator: all` stops on first false
- `operator: any` stops on first true
- `operator: none` and `operator: xor` evaluate all conditions

```yaml
# All conditions must be true (was: all_of)
condition:
  type: composite
  operator: all
  conditions:
    - type: tool_check
      tool: git
      capability: available
    - type: path_check
      path: "data/config.yaml"
      check: is_file

# At least one condition true (was: any_of)
condition:
  type: composite
  operator: any
  conditions:
    - type: state_check
      field: source_type
      operator: equals
      value: git
    - type: state_check
      field: source_type
      operator: equals
      value: local

# No conditions true (was: none_of)
condition:
  type: composite
  operator: none
  conditions:
    - type: state_check
      field: flags.error_occurred
      operator: "true"

# Exactly one true (was: xor_of)
condition:
  type: composite
  operator: xor
  conditions:
    - type: state_check
      field: flags.use_cache
      operator: "true"
    - type: state_check
      field: flags.force_refresh
      operator: "true"
```

---

## core/expression

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `evaluate_expression` | Evaluate arbitrary boolean expression | `expression` |

**Supported functions:** `len()`, `contains()`, `startswith()`, `endswith()`

**Operators:** `==`, `!=`, `>`, `<`, `>=`, `<=`, `&&`, `||`, `!`

**Array length checks** (replaces count_equals, count_above, count_below):
```yaml
# Check array is empty
condition:
  type: evaluate_expression
  expression: "len(computed.sources) == 0"

# Check array has items
condition:
  type: evaluate_expression
  expression: "len(computed.sources) > 0"

# Check array length below threshold
condition:
  type: evaluate_expression
  expression: "len(computed.items) < 100"
```

---

## core/state

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `state_check` | Check state field values | `field`, `operator`, `value` |

**Operators:** `equals`, `not_equals`, `null`, `not_null`, `true`, `false`

```yaml
# Check flag is true (was: flag_set)
condition:
  type: state_check
  field: flags.config_loaded
  operator: "true"

# Check flag is false (was: flag_not_set)
condition:
  type: state_check
  field: flags.error_occurred
  operator: "false"

# Check field equals value (was: state_equals)
condition:
  type: state_check
  field: source_type
  operator: equals
  value: git

# Check field has value (was: state_not_null)
condition:
  type: state_check
  field: computed.repo_url
  operator: not_null

# Check field is null (was: state_is_null)
condition:
  type: state_check
  field: computed.error
  operator: "null"
```

---

## extensions/filesystem

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `path_check` | Check file/directory existence | `path`, `check`, `args` |

**Checks:** `exists`, `is_file`, `is_directory`, `contains_text`

```yaml
# Check file exists (was: file_exists)
condition:
  type: path_check
  path: "data/config.yaml"
  check: is_file

# Check directory exists (was: directory_exists)
condition:
  type: path_check
  path: ".source/${computed.source_id}"
  check: is_directory

# Check path exists (file or directory)
condition:
  type: path_check
  path: "${computed.output_path}"
  check: exists

# Check file contains text (was: index_is_placeholder)
condition:
  type: path_check
  path: "data/index.md"
  check: contains_text
  args:
    pattern: "Run hiivmind-corpus-build"
```

---

## extensions/tools

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `tool_check` | Check tool availability and version | `tool`, `capability`, `args` |

**Capabilities:** `available`, `version_gte`

```yaml
# Check tool in PATH (was: tool_available)
condition:
  type: tool_check
  tool: git
  capability: available

# Check tool version (was: tool_version_gte)
condition:
  type: tool_check
  tool: node
  capability: version_gte
  args:
    min_version: "18.0"
```

---

## extensions/python

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `python_module_available` | Check Python module importable | `module` |

```yaml
condition:
  type: python_module_available
  module: yaml
```

---

## extensions/network

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `network_available` | Check internet connectivity | `target` (optional) |

```yaml
# Default (checks github.com)
condition:
  type: network_available

# Custom target
condition:
  type: network_available
  target: "https://api.example.com/health"
```

---

## extensions/git

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `source_check` | Check source repository status | `source_id`, `aspect` |

**Aspects:** `exists`, `cloned`, `has_updates`

```yaml
# Check source in config (was: source_exists)
condition:
  type: source_check
  source_id: polars
  aspect: exists

# Check source cloned (was: source_cloned)
condition:
  type: source_check
  source_id: "${computed.source_id}"
  aspect: cloned

# Check for updates (was: source_has_updates)
condition:
  type: source_check
  source_id: "${computed.source_id}"
  aspect: has_updates
```

---

## extensions/web

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `fetch_check` | Check web fetch result | `from`, `aspect` |

**Aspects:** `succeeded`, `has_content`

```yaml
# Check fetch succeeded (was: fetch_succeeded)
condition:
  type: fetch_check
  from: computed.page_fetch
  aspect: succeeded

# Check fetch has content (was: fetch_returned_content)
condition:
  type: fetch_check
  from: computed.page_fetch
  aspect: has_content
```

---

## Quick Reference by Use Case

| Need To Check... | Use This Precondition |
|------------------|----------------------|
| File exists | `path_check` (check: is_file) |
| Directory exists | `path_check` (check: is_directory) |
| Config loaded | `path_check` (path: data/config.yaml) |
| Tool installed | `tool_check` (capability: available) |
| Tool version | `tool_check` (capability: version_gte) |
| Flag is set | `state_check` (operator: "true") |
| Field has value | `state_check` (operator: not_null) |
| Field equals X | `state_check` (operator: equals) |
| Array is empty | `evaluate_expression` (len(field) == 0) |
| Array has items | `evaluate_expression` (len(field) > 0) |
| Multiple conditions | `composite` (operator: all/any) |
| Exclusion check | `composite` (operator: none) |
| Exactly one | `composite` (operator: xor) |
| Complex logic | `evaluate_expression` |

---

## Prose Pattern Mapping

Use this table when converting prose skill descriptions to preconditions:

| Prose Pattern | Precondition | Parameters |
|---------------|--------------|------------|
| "if file exists" | `path_check` | check: is_file, path |
| "if directory exists" | `path_check` | check: is_directory, path |
| "if config exists" | `path_check` | path: data/config.yaml, check: is_file |
| "if [flag] is set" | `state_check` | field: flags.X, operator: "true" |
| "if [flag] is not set" | `state_check` | field: flags.X, operator: "false" |
| "if [field] equals X" | `state_check` | field, operator: equals, value |
| "if [field] has value" | `state_check` | field, operator: not_null |
| "if [field] is empty" | `state_check` | field, operator: "null" |
| "if array has items" | `evaluate_expression` | expression: "len(field) > 0" |
| "if array is empty" | `evaluate_expression` | expression: "len(field) == 0" |
| "requires [tool]" | `tool_check` | tool, capability: available |
| "requires [tool] version X" | `tool_check` | tool, capability: version_gte, args.min_version |
| "if online" | `network_available` | target (optional) |
| "if all of" | `composite` | operator: all, conditions |
| "if any of" | `composite` | operator: any, conditions |
| "if none of" | `composite` | operator: none, conditions |
| "if exactly one" | `composite` | operator: xor, conditions |
| "if [complex condition]" | `evaluate_expression` | expression |

---

## Audit Mode Usage

When using `conditional` nodes with `audit.enabled: true`, preconditions are evaluated non-short-circuit to collect all failures:

```yaml
validate_prerequisites:
  type: conditional
  condition:
    type: composite
    operator: all
    conditions:
      - type: tool_check
        tool: git
        capability: available
      - type: path_check
        path: "data/config.yaml"
        check: is_file
  audit:
    enabled: true
    output: computed.validation_errors
    messages:
      tool_check: "Git is required"
      path_check: "No config.yaml found"
  branches:
    on_true: proceed
    on_false: show_errors
```

---

## Fetching Examples

```bash
# All precondition examples
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/preconditions.yaml \
  --jq '.content' | base64 -d

# Examples for a specific category
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/preconditions.yaml \
  --jq '.content' | base64 -d | yq '.examples["core/state"]'

# Examples for a specific type
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/preconditions.yaml \
  --jq '.content' | base64 -d | yq '.examples["core/state"].state_check'

# Canonical type definition (core)
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/preconditions/core.yaml \
  --jq '.content' | base64 -d | yq '.preconditions.state_check'
```

---

## Related Documentation

- **Examples:** `hiivmind/hiivmind-blueprint-lib/examples/preconditions.yaml`
- **Definitions:** `hiivmind/hiivmind-blueprint-lib/preconditions/core.yaml`, `preconditions/extensions.yaml`
- **Node Mapping Pattern:** `lib/patterns/node-mapping.md`
- **Workflow Generation:** `lib/patterns/workflow-generation.md`
