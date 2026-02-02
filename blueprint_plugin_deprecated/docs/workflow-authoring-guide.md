# Workflow Authoring Guide

Create and maintain workflow.yaml files for deterministic skill execution.

## Workflow Structure

Every workflow has these top-level sections:

```yaml
name: "my-skill"
version: "1.0.0"
description: >
  What this workflow does

entry_preconditions:
  - type: config_exists

initial_state:
  phase: "start"
  computed: {}

start_node: first_action

nodes:
  first_action:
    type: action
    # ...

endings:
  success:
    type: success
    message: "Done!"
```

## Node Types

### Action Node

Execute tool calls and computations:

```yaml
read_config:
  type: action
  description: "Load configuration"
  actions:
    - type: read_file
      path: "data/config.yaml"
      store_as: computed.config
    - type: evaluate
      expression: "computed.config.version >= 2"
      set_flag: valid_version
  on_success: validate_config
  on_failure: error_no_config
```

**Key fields:**
- `actions` - Array of consequences to execute
- `on_success` - Next node on success
- `on_failure` - Node for failure handling

### Conditional Node

Branch based on conditions:

```yaml
check_config:
  type: conditional
  description: "Check if config exists"
  condition:
    type: file_exists
    path: "data/config.yaml"
  branches:
    on_true: load_config
    on_false: create_config
```

**Key fields:**
- `condition` - Precondition to evaluate
- `branches.on_true` - Node if condition is true
- `branches.on_false` - Node if condition is false

### User Prompt Node

Get input from user:

```yaml
ask_source_type:
  type: user_prompt
  prompt:
    question: "What type of source would you like to add?"
    header: "Source"  # Max 12 characters
    options:
      - id: git
        label: "Git repository"
        description: "Clone a repo"
      - id: local
        label: "Local files"
        description: "Add from filesystem"
  on_response:
    git:
      consequence:
        - type: set_state
          field: source_type
          value: "git"
      next_node: collect_git_url
    local:
      next_node: collect_local_path
```

**Key fields:**
- `prompt.question` - Question text
- `prompt.header` - Short label (max 12 chars)
- `prompt.options` - 2-4 choices (id, label, description)
- `on_response` - Handler per option ID

### Validation Gate Node

Check multiple prerequisites:

```yaml
validate_prerequisites:
  type: validation_gate
  description: "Verify all requirements"
  validations:
    - type: tool_available
      tool: git
      error_message: "Git is required"
    - type: config_exists
      error_message: "Run init first"
  on_valid: proceed
  on_invalid: show_errors
```

**Key fields:**
- `validations` - Array of preconditions with error_message
- `on_valid` - Node if all pass
- `on_invalid` - Node if any fail

### Reference Node

Include another workflow or document:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
  next_node: execute_action
```

**Key fields:**
- `workflow` (or `doc`) - Reference to load
- `context` - Variables to pass
- `next_node` - Node after reference completes

## Endings

Every path must reach an ending:

```yaml
endings:
  success:
    type: success
    message: "Workflow completed"
    summary:
      files_processed: "${computed.count}"

  error_no_config:
    type: error
    message: "Configuration not found"
    recovery: "my-plugin-init"
    details: "Run init first to create config.yaml"

  cancelled:
    type: error
    message: "Operation cancelled by user"
```

**Ending types:** `success`, `error`, `failure`, `cancelled`

## State Management

### Initial State

```yaml
initial_state:
  phase: "start"
  source_type: null
  flags:
    config_loaded: false
  computed: {}
```

### Setting State

```yaml
actions:
  - type: set_state
    field: source_type
    value: "git"

  - type: set_flag
    flag: config_loaded
    value: true
```

### Reading State

Use `${variable}` interpolation:

```yaml
- type: read_file
  path: "${computed.file_path}"
  store_as: computed.content
```

## Common Consequences

| Consequence | Use For |
|-------------|---------|
| `set_state` | Set a state field |
| `set_flag` | Set a boolean flag |
| `read_file` | Read file to state |
| `read_config` | Read config.yaml |
| `write_file` | Write content to file |
| `clone_repo` | Clone git repository |
| `web_fetch` | Fetch URL content |
| `evaluate` | Evaluate expression to flag |
| `compute` | Compute expression to state |

See `hiivmind-blueprint-lib/consequences/` for all types.

## Common Preconditions

| Precondition | Checks |
|--------------|--------|
| `file_exists` | File at path exists |
| `directory_exists` | Directory at path exists |
| `config_exists` | config.yaml exists |
| `tool_available` | CLI tool is installed |
| `flag_set` | Boolean flag is true |
| `state_equals` | State field equals value |
| `evaluate_expression` | Complex expression |

See `hiivmind-blueprint-lib/preconditions/` for all types.

## Validation

Use `check-jsonschema` to validate:

```bash
SCHEMA_DIR="../hiivmind-blueprint-lib/schema"
~/.rye/shims/check-jsonschema \
  --base-uri "file://${SCHEMA_DIR}/" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  workflow.yaml
```

Or use the validate skill:

```
/hiivmind-blueprint validate workflow.yaml
```

## Best Practices

1. **Node naming:** Use snake_case, verb_object format
2. **Descriptions:** Every node should have a description
3. **Error handling:** All action nodes need on_failure
4. **State isolation:** Use `computed.` prefix for workflow-computed values
5. **Version pinning:** Use exact versions for remote references
6. **Testing:** Validate after any changes

## Next Steps

- [Logging Reference](logging-reference.md) - Configure workflow logging
- [Intent Detection Guide](intent-detection-guide.md) - Gateway routing
