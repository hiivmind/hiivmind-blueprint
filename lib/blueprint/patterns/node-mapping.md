# Node Mapping Pattern

Map analyzed skill structures to workflow node types.

---

## Node Type Selection

```
                    Analyze Element Type
                           │
       ┌───────────────────┼───────────────────┐
       ▼                   ▼                   ▼
   Tool Call          Conditional          User Input
       │                   │                   │
       ▼                   ▼                   ▼
   ACTION             How many              USER_PROMPT
    NODE              branches?               NODE
                           │
               ┌───────────┴───────────┐
               ▼                       ▼
          2 branches              3+ branches
               │                       │
               ▼                       ▼
          CONDITIONAL              USER_PROMPT
             NODE                  or MULTI-COND
```

---

## Node Type Examples

### Action Node

```yaml
read_config:
  type: action
  description: "Read config.yaml"
  actions:
    - type: read_file
      path: "data/config.yaml"
      store_as: computed.config
  on_success: next_node
  on_failure: error_config_missing
```

### Conditional Node

```yaml
check_config:
  type: conditional
  condition:
    type: file_exists
    path: "data/config.yaml"
  branches:
    on_true: load_config
    on_false: create_config
```

### User Prompt Node

```yaml
ask_source_type:
  type: user_prompt
  prompt:
    question: "What type of source?"
    header: "Source"
    options:
      - id: git
        label: "Git repository"
        description: "Clone a repo"
      - id: local
        label: "Local files"
        description: "Add local files"
  on_response:
    git:
      consequence:
        - type: set_state
          field: source_type
          value: git
      next_node: collect_git_url
    local:
      next_node: collect_local_path
```

### Validation Gate Node

```yaml
validate_prerequisites:
  type: validation_gate
  validations:
    - type: tool_available
      tool: git
      error_message: "Git required"
    - type: config_exists
      error_message: "No config.yaml"
  on_valid: proceed
  on_invalid: show_error
```

### Reference Node

```yaml
clone_repository:
  type: reference
  doc: "lib/corpus/patterns/sources/git.md"
  section: "Clone Repository"
  context:
    repo_url: "${source_url}"
  next_node: verify_clone
```

---

## Condition Type Selection

| Prose Pattern | Condition Type |
|---------------|----------------|
| "if file exists" | `file_exists` |
| "if directory exists" | `directory_exists` |
| "if config exists" | `config_exists` |
| "if [flag] is set" | `flag_set` |
| "if [field] is X" | `state_equals` |
| "if [field] has value" | `state_not_null` |
| "if [complex]" | `evaluate_expression` |

---

## Tool to Consequence Mapping

| Prose | Consequence |
|-------|-------------|
| Read file | `read_file` |
| Read config | `read_config` |
| Write file | `write_file` |
| Edit file | `edit_file` |
| Bash command | `run_command` |
| Git clone | `clone_repo` |
| Fetch URL | `web_fetch` |

---

## Node Naming Conventions

| Purpose | Pattern | Example |
|---------|---------|---------|
| Read/Load | `read_*`, `load_*` | `read_config` |
| Check | `check_*`, `validate_*` | `check_exists` |
| Ask user | `ask_*`, `select_*` | `ask_source_type` |
| Execute | `execute_*`, `run_*` | `execute_clone` |
| Error | `error_*` | `error_no_config` |
| Route | `route_*` | `route_by_type` |

---

## Related Documentation

- **Skill Analysis:** `lib/blueprint/patterns/skill-analysis.md`
- **Workflow Generation:** `lib/blueprint/patterns/workflow-generation.md`
- **Node Type Definitions:** `hiivmind-blueprint-lib/nodes/*/index.yaml`
