# Workflow Preconditions

Preconditions are boolean evaluations used for:
- **Entry gates** - Determine if workflow can start
- **Conditional nodes** - Route based on state
- **Validation gates** - Multi-check before proceeding

All preconditions return `true` or `false`. No side effects.

---

## File System Preconditions

### config_exists

Check if corpus config.yaml exists.

```yaml
- type: config_exists
```

**Evaluation:**
```
file_exists("data/config.yaml")
```

**Use cases:**
- Entry gate for most skills
- Verify corpus is initialized

---

### index_exists

Check if corpus index.md exists.

```yaml
- type: index_exists
```

**Evaluation:**
```
file_exists("data/index.md")
```

---

### index_is_placeholder

Check if index contains placeholder text (not yet built).

```yaml
- type: index_is_placeholder
```

**Evaluation:**
```
file_contains("data/index.md", "Run hiivmind-corpus-build")
```

**Use cases:**
- Detect if build skill needs to run
- Skip re-build prompts if already populated

---

### file_exists

Check if arbitrary file exists.

```yaml
- type: file_exists
  path: ".source/polars/README.md"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | Yes | Path to check (relative to corpus root) |

**Evaluation:**
```
file_exists(path)
```

---

### directory_exists

Check if directory exists.

```yaml
- type: directory_exists
  path: ".source/polars"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | Yes | Path to check |

**Evaluation:**
```
directory_exists(path)
```

---

## Source Preconditions

### source_exists

Check if source ID exists in config.yaml.

```yaml
- type: source_exists
  id: "polars"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `id` | string | Yes | Source identifier |

**Evaluation:**
```
config.sources.any(s => s.id == id)
```

---

### source_cloned

Check if source has been cloned to .source/.

```yaml
- type: source_cloned
  id: "polars"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `id` | string | Yes | Source identifier |

**Evaluation:**
```
directory_exists(".source/{id}")
```

---

### source_has_updates

Check if git source has upstream changes.

```yaml
- type: source_has_updates
  id: "polars"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `id` | string | Yes | Source identifier (must be git type) |

**Evaluation:**
```
# Fetch latest
git -C .source/{id} fetch --quiet

# Compare
local_sha = git -C .source/{id} rev-parse HEAD
remote_sha = git -C .source/{id} rev-parse @{u}
return local_sha != remote_sha
```

---

## Tool Preconditions

### tool_available

Check if command-line tool is installed.

```yaml
- type: tool_available
  tool: git
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `tool` | string | Yes | Tool name |

**Evaluation:**
```bash
which {tool} >/dev/null 2>&1
```

**Common tools:**
- `git` - Version control
- `yq` - YAML processing
- `jq` - JSON processing
- `python3` - Python runtime

---

### python_module_available

Check if Python module is installed.

```yaml
- type: python_module_available
  module: pymupdf
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `module` | string | Yes | Python module name |

**Evaluation:**
```bash
python3 -c "import {module}" 2>/dev/null
```

---

## State Preconditions

### flag_set

Check if a boolean flag is true.

```yaml
- type: flag_set
  flag: manifest_detected
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `flag` | string | Yes | Flag name in state.flags |

**Evaluation:**
```
state.flags[flag] == true
```

---

### flag_not_set

Check if a boolean flag is false or undefined.

```yaml
- type: flag_not_set
  flag: config_found
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `flag` | string | Yes | Flag name in state.flags |

**Evaluation:**
```
state.flags[flag] != true
```

---

### state_equals

Check if state field equals specific value.

```yaml
- type: state_equals
  field: source_type
  value: git
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field path (dot notation for nested) |
| `value` | any | Yes | Expected value |

**Evaluation:**
```
get_state_value(field) == value
```

---

### state_not_null

Check if state field has a value.

```yaml
- type: state_not_null
  field: source_url
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field path |

**Evaluation:**
```
get_state_value(field) != null
```

---

### state_is_null

Check if state field is null/undefined.

```yaml
- type: state_is_null
  field: computed.error
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field path |

**Evaluation:**
```
get_state_value(field) == null
```

---

## Computed Value Preconditions

### count_equals

Check if array/list length equals value.

```yaml
- type: count_equals
  field: computed.sources
  count: 0
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field containing array |
| `count` | number | Yes | Expected length |

**Evaluation:**
```
len(get_state_value(field)) == count
```

---

### count_above

Check if array length exceeds threshold.

```yaml
- type: count_above
  field: computed.discovered_urls
  min: 100
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field containing array |
| `min` | number | Yes | Minimum length (exclusive) |

**Evaluation:**
```
len(get_state_value(field)) > min
```

---

### count_below

Check if array length is below threshold.

```yaml
- type: count_below
  field: computed.errors
  max: 5
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field containing array |
| `max` | number | Yes | Maximum length (exclusive) |

**Evaluation:**
```
len(get_state_value(field)) < max
```

---

## Web Preconditions

### fetch_succeeded

Check if a previous web fetch succeeded.

```yaml
- type: fetch_succeeded
  from: computed.manifest_check
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `from` | string | Yes | State field with fetch result |

**Evaluation:**
```
get_state_value(from).status >= 200 && get_state_value(from).status < 300
```

---

### fetch_returned_content

Check if fetch returned non-empty content.

```yaml
- type: fetch_returned_content
  from: computed.llms_txt
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `from` | string | Yes | State field with fetch result |

**Evaluation:**
```
get_state_value(from).content != null && len(get_state_value(from).content) > 0
```

---

## Composite Preconditions

### all_of

All nested conditions must be true (logical AND).

```yaml
- type: all_of
  conditions:
    - type: config_exists
    - type: tool_available
      tool: git
    - type: flag_set
      flag: config_found
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `conditions` | array | Yes | Array of precondition objects |

**Evaluation:**
```
conditions.all(c => evaluate(c) == true)
```

---

### any_of

At least one condition must be true (logical OR).

```yaml
- type: any_of
  conditions:
    - type: tool_available
      tool: yq
    - type: python_module_available
      module: yaml
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `conditions` | array | Yes | Array of precondition objects |

**Evaluation:**
```
conditions.any(c => evaluate(c) == true)
```

---

### none_of

No conditions may be true (logical NOR).

```yaml
- type: none_of
  conditions:
    - type: source_exists
      id: "${computed.source_id}"
    - type: directory_exists
      path: ".source/${computed.source_id}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `conditions` | array | Yes | Array of precondition objects |

**Evaluation:**
```
conditions.none(c => evaluate(c) == true)
```

---

## Expression Precondition

### evaluate_expression

Evaluate arbitrary boolean expression.

```yaml
- type: evaluate_expression
  expression: "computed.files_count > 100 && source_type == 'git'"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `expression` | string | Yes | Boolean expression |

**Expression syntax:**
- Field access: `source_type`, `computed.count`, `flags.found`
- Comparisons: `==`, `!=`, `>`, `<`, `>=`, `<=`
- Logical: `&&`, `||`, `!`
- Functions: `len()`, `contains()`, `startswith()`, `endswith()`

**Examples:**
```yaml
# Check source count
expression: "len(config.sources) == 0"

# Check string content
expression: "source_type == 'git' && contains(source_url, 'github.com')"

# Check computed value
expression: "computed.manifest.page_count > 50"
```

---

## Precondition Evaluation Context

When a precondition is evaluated, it has access to:

| Variable | Description |
|----------|-------------|
| `state` | Full runtime state object |
| `state.flags` | Boolean flags |
| `state.computed` | Action outputs |
| `state.user_responses` | User prompt responses |
| `config` | Parsed data/config.yaml |
| `cwd` | Current working directory |

---

## Error Messages

Preconditions can include error messages for validation gates:

```yaml
validations:
  - type: config_exists
    error_message: "No config.yaml found. Run hiivmind-corpus-init first."
  - type: tool_available
    tool: git
    error_message: "Git is required but not installed."
```

The `error_message` field is optional for regular conditions but recommended for validation gates.

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - Workflow YAML structure
- **Consequences:** `lib/workflow/consequences.md` - State mutations
- **Execution:** `lib/workflow/execution.md` - Turn loop
- **State:** `lib/workflow/state.md` - Runtime state structure
