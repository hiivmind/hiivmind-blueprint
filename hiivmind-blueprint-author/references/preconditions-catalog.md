# Preconditions Catalog

Complete reference for all 14 precondition types available in hiivmind-blueprint-lib v3.0.0.

> **Examples:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/examples/preconditions.yaml`
> **Definitions:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/preconditions/preconditions.yaml`
> **Migration Guide:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/docs/v3-migration.md`

---

## Overview

Preconditions are boolean checks used in:
- `entry_preconditions` - Guard workflow entry
- `conditional` nodes - Branch based on state
- `audit` mode - Validate multiple conditions

They are organized into 10 categories:

| Category | Count | Purpose |
|----------|-------|---------|
| core/composite | 4 | Logical combinators (AND, OR, NOR, XOR) |
| core/expression | 1 | Arbitrary expression evaluation |
| core/filesystems | 1 | Path checks (consolidated) |
| core/logging | 1 | Logging state checks (consolidated) |
| core/state | 1 | State inspection (consolidated) |
| core/tools | 1 | Tool availability (consolidated) |
| core/python | 1 | Python module availability |
| core/network | 1 | Network connectivity |
| core/git | 1 | Source repository checks (consolidated) |
| core/web_fetch | 1 | Web fetch result checks (consolidated) |

---

## core/composite

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `all_of` | All conditions true (AND) | `conditions` |
| `any_of` | At least one true (OR) | `conditions` |
| `none_of` | No conditions true (NOR) | `conditions` |
| `xor_of` | Exactly one true (XOR) | `conditions` |

**Short-circuit behavior:**
- `all_of` stops on first false
- `any_of` stops on first true
- `none_of` and `xor_of` evaluate all conditions

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

## core/filesystems

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

## core/logging

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `log_state` | Check logging lifecycle state | `aspect`, `args` |

**Aspects:** `initialized`, `finalized`, `level_enabled`

```yaml
# Check if logging initialized (was: log_initialized)
condition:
  type: log_state
  aspect: initialized

# Check if logging finalized (was: log_finalized)
condition:
  type: log_state
  aspect: finalized

# Check if log level enabled (was: log_level_enabled)
condition:
  type: log_state
  aspect: level_enabled
  args:
    level: debug
```

---

## core/tools

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `tool_check` | Check tool availability and capabilities | `tool`, `capability`, `args` |

**Capabilities:** `available`, `version_gte`, `authenticated`, `daemon_ready`

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

# Check tool authenticated (was: tool_authenticated)
condition:
  type: tool_check
  tool: gh
  capability: authenticated

# Check daemon running (was: tool_daemon_ready)
condition:
  type: tool_check
  tool: docker
  capability: daemon_ready
```

---

## core/python

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `python_module_available` | Check Python module importable | `module` |

```yaml
condition:
  type: python_module_available
  module: yaml
```

---

## core/network

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

## core/git

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

## core/web_fetch

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
| GitHub CLI authenticated | `tool_check` (tool: gh, capability: authenticated) |
| Docker running | `tool_check` (tool: docker, capability: daemon_ready) |
| Flag is set | `state_check` (operator: "true") |
| Field has value | `state_check` (operator: not_null) |
| Field equals X | `state_check` (operator: equals) |
| Array is empty | `evaluate_expression` (len(field) == 0) |
| Array has items | `evaluate_expression` (len(field) > 0) |
| Multiple conditions | `all_of`, `any_of` |
| Exclusion check | `none_of` |
| Exactly one | `xor_of` |
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
| "if logged in" | `tool_check` | tool, capability: authenticated |
| "if daemon running" | `tool_check` | tool, capability: daemon_ready |
| "if online" | `network_available` | target (optional) |
| "if all of" | `all_of` | conditions |
| "if any of" | `any_of` | conditions |
| "if none of" | `none_of` | conditions |
| "if exactly one" | `xor_of` | conditions |
| "if [complex condition]" | `evaluate_expression` | expression |

---

## Audit Mode Usage

When using `conditional` nodes with `audit.enabled: true`, preconditions are evaluated non-short-circuit to collect all failures:

```yaml
validate_prerequisites:
  type: conditional
  condition:
    type: all_of
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
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/preconditions.yaml?ref=v3.0.0 \
  --jq '.content' | base64 -d

# Examples for a specific category
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/preconditions.yaml?ref=v3.0.0 \
  --jq '.content' | base64 -d | yq '.examples["core/state"]'

# Examples for a specific type
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/preconditions.yaml?ref=v3.0.0 \
  --jq '.content' | base64 -d | yq '.examples["core/state"].state_check'

# Canonical type definition
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/preconditions/preconditions.yaml?ref=v3.0.0 \
  --jq '.content' | base64 -d | yq '.preconditions.state_check'
```

---

## Related Documentation

- **Examples:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/examples/preconditions.yaml`
- **Definitions:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/preconditions/preconditions.yaml`
- **Migration Guide:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/docs/v3-migration.md`
- **Node Mapping Pattern:** `lib/patterns/node-mapping.md`
- **Workflow Generation:** `lib/patterns/workflow-generation.md`
