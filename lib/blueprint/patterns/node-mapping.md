# Node Mapping Pattern

Mapping analyzed skill structures to workflow node types. This pattern converts prose patterns into the appropriate workflow node configurations.

---

## Overview

Node mapping transforms analysis results into workflow nodes:

```
Analysis Phase/Action → Workflow Node Type → Node Configuration
```

The goal is to select the most appropriate node type for each extracted element while preserving the original behavior.

---

## Node Type Selection

### Decision Tree

```
┌─────────────────────────────────────────────────────────────────┐
│                    Analyze Element Type                          │
└─────────────────────────────────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
   Tool Call              Conditional              User Input
        │                       │                       │
        ▼                       ▼                       ▼
   ┌─────────┐            ┌─────────┐            ┌─────────┐
   │ ACTION  │            │ How many│            │ USER    │
   │  NODE   │            │branches?│            │ PROMPT  │
   └─────────┘            └─────────┘            │  NODE   │
                                │                └─────────┘
                    ┌───────────┴───────────┐
                    ▼                       ▼
               2 branches              3+ branches
                    │                       │
                    ▼                       ▼
             ┌───────────┐           ┌───────────┐
             │CONDITIONAL│           │ USER      │
             │   NODE    │           │ PROMPT or │
             └───────────┘           │ MULTI-COND│
                                     └───────────┘
```

---

## Action Node Mapping

### When to Use

- Single tool call
- Multiple sequential tool calls
- Computations/evaluations
- State mutations

### Mapping Patterns

**Single Tool Call:**
```yaml
# From prose: "Read the config.yaml file"
nodes:
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

**Multiple Sequential Operations:**
```yaml
# From prose: "Read config, then validate format, then extract sources"
nodes:
  process_config:
    type: action
    description: "Read and process config"
    actions:
      - type: read_config
        store_as: config
      - type: evaluate
        expression: "config.schema_version >= 2"
        set_flag: valid_schema
      - type: compute
        expression: "config.sources.length"
        store_as: computed.source_count
    on_success: check_sources
    on_failure: error_invalid_config
```

### Tool to Consequence Mapping

| Prose Tool | Consequence Type | Key Parameters |
|------------|------------------|----------------|
| Read file | `read_file` | path, store_as |
| Read config | `read_config` | store_as |
| Write file | `write_file` | path, content |
| Edit file | `edit_file` | path, old, new |
| Bash command | `run_command` | command, store_as |
| Git clone | `clone_repo` | url, dest, branch |
| Fetch URL | `web_fetch` | url, store_as |

---

## Conditional Node Mapping

### When to Use

- Binary decisions (if-else)
- Boolean flag checks
- State-based routing

### Mapping Patterns

**Simple If-Else:**
```yaml
# From prose: "If config exists, proceed; otherwise create new"
nodes:
  check_config:
    type: conditional
    description: "Check if config exists"
    condition:
      type: file_exists
      path: "data/config.yaml"
    branches:
      true: load_config
      false: create_config
```

**Flag-Based:**
```yaml
# From prose: "If we detected a manifest, use it"
nodes:
  route_by_manifest:
    type: conditional
    condition:
      type: flag_set
      flag: manifest_detected
    branches:
      true: use_manifest
      false: ask_source_type
```

**Expression-Based:**
```yaml
# From prose: "If this is the first source, skip setup"
nodes:
  check_first_source:
    type: conditional
    condition:
      type: evaluate_expression
      expression: "computed.config.sources.length == 0"
    branches:
      true: skip_setup
      false: full_setup
```

### Condition Type Selection

| Prose Pattern | Condition Type |
|---------------|----------------|
| "if file exists" | `file_exists` |
| "if directory exists" | `directory_exists` |
| "if config exists" | `config_exists` |
| "if [flag] is set" | `flag_set` |
| "if [field] is X" | `state_equals` |
| "if [field] has value" | `state_not_null` |
| "if [complex expression]" | `evaluate_expression` |

---

## User Prompt Node Mapping

### When to Use

- User must choose from options
- User must provide input
- Confirmation required

### Mapping Patterns

**Choice Selection:**
```yaml
# From prose: "Ask user what type of source to add"
nodes:
  ask_source_type:
    type: user_prompt
    prompt:
      question: "What type of source would you like to add?"
      header: "Source"
      options:
        - id: git
          label: "Git repository"
          description: "Clone a repo with documentation"
        - id: local
          label: "Local files"
          description: "Add files from your machine"
        - id: web
          label: "Web pages"
          description: "Cache web content"
    on_response:
      git:
        consequence:
          - type: set_state
            field: source_type
            value: git
        next_node: collect_git_url
      local:
        next_node: collect_local_path
      web:
        next_node: collect_web_urls
```

**Confirmation:**
```yaml
# From prose: "Ask user to confirm before proceeding"
nodes:
  confirm_delete:
    type: user_prompt
    prompt:
      question: "Are you sure you want to delete this source?"
      header: "Confirm"
      options:
        - id: yes
          label: "Yes, delete"
          description: "Permanently remove the source"
        - id: no
          label: "Cancel"
          description: "Keep the source"
    on_response:
      yes:
        next_node: execute_delete
      no:
        next_node: cancelled
```

### Response Handling

When mapping user responses, consider:

1. **Consequence before routing** - Set state based on selection
2. **Custom input handling** - "other" option for free-form input
3. **Multi-select** - When multiple options can be selected

---

## Validation Gate Node Mapping

### When to Use

- Multiple prerequisites must be met
- Error messages needed for each failure
- All-or-nothing validation

### Mapping Patterns

**Prerequisites Check:**
```yaml
# From prose: "Ensure git is installed, config exists, and user has auth"
nodes:
  validate_prerequisites:
    type: validation_gate
    description: "Check all prerequisites"
    validations:
      - type: tool_available
        tool: git
        error_message: "Git is required but not installed"
      - type: config_exists
        error_message: "No config.yaml found. Run init first."
      - type: file_exists
        path: ".git-credentials"
        error_message: "Git credentials not configured"
    on_valid: proceed_with_clone
    on_invalid: show_prerequisites_error
```

### When to Use Validation Gate vs Multiple Conditionals

| Scenario | Use |
|----------|-----|
| All checks must pass, single failure path | Validation Gate |
| Different actions for different failures | Multiple Conditionals |
| Want to collect all errors | Validation Gate |
| Want to short-circuit on first failure | Conditionals |

---

## Reference Node Mapping

### When to Use

- Complex procedure documented elsewhere
- Reusable sub-workflows
- External pattern execution

### Mapping Patterns

```yaml
# From prose: "Follow the git clone procedure from patterns"
nodes:
  clone_repository:
    type: reference
    doc: "lib/corpus/patterns/sources/git.md"
    section: "Clone Repository"
    context:
      repo_url: "${source_url}"
      dest_path: ".source/${computed.source_id}"
    next_node: verify_clone
```

---

## Phase to Node Chain Mapping

### Linear Phase

```yaml
# Prose phase with sequential steps becomes action chain:
#
# Phase: Process File
# 1. Read the file
# 2. Transform content
# 3. Write output

nodes:
  process_file:
    type: action
    actions:
      - type: read_file
        path: "${input_path}"
        store_as: computed.content
      - type: compute
        expression: "transform(computed.content)"
        store_as: computed.transformed
      - type: write_file
        path: "${output_path}"
        content: "${computed.transformed}"
    on_success: process_complete
    on_failure: error_processing
```

### Phase with Internal Branching

```yaml
# Prose phase with conditional becomes multiple nodes:
#
# Phase: Validate Input
# 1. Check if file exists
# 2. If exists, read it; otherwise create template
# 3. Validate content

nodes:
  check_file:
    type: conditional
    condition:
      type: file_exists
      path: "${input_path}"
    branches:
      true: read_existing
      false: create_template

  read_existing:
    type: action
    actions:
      - type: read_file
        path: "${input_path}"
        store_as: computed.content
    on_success: validate_content
    on_failure: error_read

  create_template:
    type: action
    actions:
      - type: write_file
        path: "${input_path}"
        content: "${template_content}"
      - type: set_state
        field: computed.content
        value: "${template_content}"
    on_success: validate_content
    on_failure: error_create

  validate_content:
    type: action
    actions:
      - type: evaluate
        expression: "computed.content.length > 0"
        set_flag: content_valid
    on_success: check_validity
    on_failure: error_validation
```

---

## Node Naming Conventions

### Patterns

| Node Purpose | Naming Pattern | Examples |
|--------------|----------------|----------|
| Read/Load | `read_*`, `load_*` | `read_config`, `load_index` |
| Check/Validate | `check_*`, `validate_*` | `check_exists`, `validate_input` |
| Ask user | `ask_*`, `select_*`, `confirm_*` | `ask_source_type`, `confirm_delete` |
| Execute action | `execute_*`, `run_*`, `do_*` | `execute_clone`, `run_build` |
| Error states | `error_*` | `error_no_config`, `error_invalid` |
| Route decisions | `route_*`, `decide_*` | `route_by_type`, `decide_action` |

### Naming Guidelines

1. Use snake_case
2. Be descriptive but concise
3. Action nodes: verb_object format
4. Conditional nodes: check_condition or route_by_factor format
5. User prompts: ask_what or select_what format

---

## Edge Case Handling

### Loops in Prose

If prose describes a loop:
```
"For each source, process and validate"
```

Map to:
1. Action node that processes array
2. Or spawn_agent for parallel processing
3. Or reference to loop pattern document

### Complex Expressions

If prose uses complex conditions:
```
"If the file is large (>1MB) and contains images, use special handler"
```

Map to:
```yaml
condition:
  type: evaluate_expression
  expression: "computed.file_size > 1048576 && computed.has_images"
```

### Error Recovery

If prose describes recovery:
```
"If clone fails, try with different credentials"
```

Map to:
```yaml
clone_repo:
  type: action
  actions:
    - type: clone_repo
      url: "${repo_url}"
  on_success: verify_clone
  on_failure: try_alternate_auth  # Recovery path

try_alternate_auth:
  type: action
  actions:
    - type: clone_repo
      url: "${repo_url}"
      auth: "ssh"
  on_success: verify_clone
  on_failure: error_clone_failed  # Final failure
```

---

## Related Documentation

- **Skill Analysis:** `lib/blueprint/patterns/skill-analysis.md`
- **Workflow Generation:** `lib/blueprint/patterns/workflow-generation.md`
- **Workflow Schema:** `lib/workflow/schema.md`
- **Preconditions:** `lib/workflow/preconditions.md`
- **Consequences:** `lib/workflow/consequences.md`
