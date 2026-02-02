# Shared Consequence Patterns

> **ARCHIVED:** This document is preserved for reference. The authoritative sources are:
> - `lib/consequences/definitions/` - YAML type definitions with examples

---

Common patterns and conventions used across all consequence types.

---

## Parameter Interpolation

All string parameters support `${}` interpolation from workflow state:

```yaml
- type: write_file
  path: "data/uploads/${computed.source_id}/README.md"
  content: "# ${computed.source_id}\n\nUpload documents here."
```

### Interpolation Sources

| Syntax | Source |
|--------|--------|
| `${field}` | Top-level state field |
| `${computed.field}` | Computed state values |
| `${config.field}` | Loaded config values |
| `${flags.flag_name}` | Boolean flags |
| `${arguments}` | User input arguments |

### Nested Access

Dot notation accesses nested fields:

```yaml
value: "${computed.source_config.repo_owner}"
```

Array index access:

```yaml
value: "${config.sources[0].id}"
```

---

## Standard Parameter Types

### store_as

Specifies where to store result in state:

```yaml
- type: read_file
  path: "config.yaml"
  store_as: config           # state.config = result

- type: get_sha
  repo_path: ".source/main"
  store_as: computed.sha     # state.computed.sha = result
```

**Convention:** Use `computed.` prefix for derived values.

### from

Specifies source field to read from:

```yaml
- type: compute_hash
  from: computed.manifest_content    # Read from state.computed.manifest_content
  store_as: computed.manifest_hash
```

### field

Specifies state field to operate on:

```yaml
- type: set_state
  field: source_type         # Target field
  value: git

- type: append_state
  field: computed.errors     # Array field to append to
  value: "Missing required field"
```

### path

File system path (supports interpolation):

```yaml
- type: read_file
  path: "data/index.md"

- type: write_file
  path: "data/uploads/${computed.source_id}/README.md"
```

---

## Failure Handling

### Default Behavior

If a consequence fails:
1. Remaining consequences in the action are skipped
2. Action node routes to `on_failure` if defined
3. Partial state mutations may persist

### Using Checkpoints

For operations that need rollback capability:

```yaml
actions:
  - type: create_checkpoint
    name: "before_risky_operation"
  - type: clone_repo
    url: "${source_url}"
    dest: ".source/temp"
  # If clone fails, can rollback in on_failure handler
```

### allow_failure Parameter

Some consequences support `allow_failure: true`:

```yaml
- type: web_fetch
  url: "${source_url}/llms.txt"
  store_as: computed.manifest_check
  allow_failure: true    # 4xx/5xx doesn't fail the action
```

When `allow_failure: true`:
- HTTP errors store error info in result rather than failing
- Execution continues to next consequence
- Check result status in subsequent logic

---

## Sequential Execution

Consequences always execute in order. Each consequence can depend on results from previous ones:

```yaml
actions:
  # 1. Load config first
  - type: read_file
    path: "config.yaml"
    store_as: config

  # 2. Now config is available for evaluation
  - type: evaluate
    expression: "len(config.sources) == 0"
    set_flag: is_first_source

  # 3. Use flag in subsequent logic
  - type: set_state
    field: computed.mode
    value: "${flags.is_first_source ? 'init' : 'add'}"
```

---

## Naming Conventions

### Consequence Types

- Use `snake_case` for type names
- Verb-noun format: `read_file`, `set_flag`, `clone_repo`
- Prefix with domain: `git_pull`, `web_fetch`

### State Fields

- Use `snake_case` for field names
- Group related fields under `computed.` namespace
- Use descriptive names: `computed.source_config`, not `computed.sc`

### Checkpoint Names

- Use descriptive names: `before_clone`, `after_validation`
- Prefix with timing: `before_`, `after_`

---

## Related Documentation

- **Parent:** [../README.md](../README.md) - Consequence taxonomy
- **Core consequences:** [workflow.md](workflow.md) - State, evaluation, control flow, etc.
- **Extensions:** [../extensions/](../extensions/) - Domain-specific consequences
