# Core Workflow Consequences

> **ARCHIVED:** This document is preserved for reference. The authoritative sources are:
> - `lib/consequences/definitions/core/state.yaml`
> - `lib/consequences/definitions/core/evaluation.yaml`
> - `lib/consequences/definitions/core/interaction.yaml`
> - `lib/consequences/definitions/core/control.yaml`
> - `lib/consequences/definitions/core/skill.yaml`
> - `lib/consequences/definitions/core/utility.yaml`

---

Fundamental workflow operations intrinsic to any workflow engine: state mutation, expression evaluation, user interaction, control flow, skill invocation, and utilities.

---

## State Mutation

### set_flag

Set a boolean flag.

```yaml
- type: set_flag
  flag: config_found
  value: true
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `flag` | string | Yes | Flag name |
| `value` | boolean | Yes | Value to set |

**Effect:**
```
state.flags[flag] = value
```

---

### set_state

Set any state field.

```yaml
- type: set_state
  field: source_type
  value: git
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field path (dot notation for nested) |
| `value` | any | Yes | Value to set (can use ${} interpolation) |

**Effect:**
```
set_state_value(field, value)
```

---

### append_state

Append value to array field.

```yaml
- type: append_state
  field: computed.discovered_urls
  value:
    path: "/api/users"
    title: "User API"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Array field path |
| `value` | any | Yes | Value to append |

**Effect:**
```
get_state_value(field).push(value)
```

---

### clear_state

Reset field to null/empty.

```yaml
- type: clear_state
  field: computed.errors
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Field to clear |

**Effect:**
```
set_state_value(field, null)
```

---

### merge_state

Merge object into state field.

```yaml
- type: merge_state
  field: computed.source_config
  value:
    repo_owner: "${computed.owner}"
    repo_name: "${computed.name}"
    branch: main
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `field` | string | Yes | Object field to merge into |
| `value` | object | Yes | Object to merge |

**Effect:**
```
Object.assign(get_state_value(field), value)
```

---

## Expression Evaluation

### evaluate

Evaluate expression and set flag based on result.

```yaml
- type: evaluate
  expression: "len(config.sources) == 0"
  set_flag: is_first_source
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `expression` | string | Yes | Boolean expression |
| `set_flag` | string | Yes | Flag to set with result |

**Effect:**
```
state.flags[set_flag] = eval(expression)
```

---

### compute

Run expression and store result.

```yaml
- type: compute
  expression: "source_url.split('/').pop()"
  store_as: computed.repo_name
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `expression` | string | Yes | Expression to evaluate |
| `store_as` | string | Yes | State field to store result |

**Effect:**
```
set_state_value(store_as, eval(expression))
```

---

## User Interaction

### display_message

Show message to user (informational).

```yaml
- type: display_message
  message: |
    Found ${computed.file_count} documentation files in source.
    Ready to proceed with indexing.
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `message` | string | Yes | Message with ${} interpolation |

**Effect:**
Display message to user. No state changes.

---

### display_table

Show tabular data to user.

```yaml
- type: display_table
  title: "Discovered Sources"
  headers: ["ID", "Type", "Location"]
  rows: "${computed.sources_table}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `title` | string | No | Table title |
| `headers` | array | Yes | Column headers |
| `rows` | string/array | Yes | Row data (state ref or literal) |

---

## Control Flow

### create_checkpoint

Save state snapshot for potential rollback.

```yaml
- type: create_checkpoint
  name: "before_clone"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name` | string | Yes | Checkpoint identifier |

**Effect:**
```
state.checkpoints[name] = deep_copy(state)
```

---

### rollback_checkpoint

Restore state from checkpoint.

```yaml
- type: rollback_checkpoint
  name: "before_clone"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `name` | string | Yes | Checkpoint to restore |

**Effect:**
```
state = state.checkpoints[name]
```

---

### spawn_agent

Launch a Task agent for parallel work.

```yaml
- type: spawn_agent
  subagent_type: "source-scanner"
  prompt: "Scan source ${source_id} for documentation structure"
  store_as: computed.scan_results.${source_id}
  run_in_background: true
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `subagent_type` | string | Yes | Agent type |
| `prompt` | string | Yes | Task prompt |
| `store_as` | string | Yes | State field for result |
| `run_in_background` | boolean | No | Async execution |

---

## Skill Invocation

### invoke_pattern

Execute a pattern document section.

```yaml
- type: invoke_pattern
  path: "lib/blueprint/patterns/skill-analysis.md"
  section: "Extract Phases"
  context:
    skill_path: "${computed.skill_path}"
    skill_content: "${computed.skill_content}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | Yes | Pattern document path |
| `section` | string | No | Specific section to execute |
| `context` | object | No | Variables available in pattern |

---

### invoke_skill

Invoke another skill and wait for completion.

```yaml
- type: invoke_skill
  skill: "hiivmind-blueprint-validate"
  args: "${computed.workflow_path}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `skill` | string | Yes | Skill name (without plugin prefix) |
| `args` | string | No | Arguments to pass to the skill |

---

## Utility

### set_timestamp

Set current ISO timestamp.

```yaml
- type: set_timestamp
  store_as: computed.indexed_at
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `store_as` | string | Yes | State field for timestamp |

**Effect:**
```
state.computed[store_as] = new Date().toISOString()
```

---

### compute_hash

Compute SHA-256 hash of content.

```yaml
- type: compute_hash
  from: computed.manifest_content
  store_as: computed.manifest_hash
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `from` | string | Yes | State field with content |
| `store_as` | string | Yes | State field for hash |

**Effect:**
```
hash = sha256(get_state_value(from))
set_state_value(store_as, "sha256:" + hash)
```

---

## Related Documentation

- **Parent:** [../README.md](../README.md) - Consequence taxonomy
- **Shared patterns:** [shared.md](shared.md) - Interpolation, standard parameters
- **Extensions:** [../extensions/](../extensions/) - Domain-specific consequences
- **State structure:** `lib/workflow/state.md` - Runtime state fields
