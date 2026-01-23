# Workflow Schema Specification

Deterministic YAML workflows for hiivmind-corpus skills, based on the Kleene/Flametree state machine pattern.

## Design Philosophy

**Core insight:** "When we detect state in our sources, we should be setting flags and deciding our next step on those flags."

Current skills describe conditional logic as prose, allowing improvisation. The new pattern:

1. **Detect** state via preconditions (pure boolean)
2. **Set** flags via consequences (deterministic mutations)
3. **Decide** next node based on flags (explicit routing)

---

## File Structure

Each skill directory contains:

```
skills/hiivmind-corpus-{name}/
├── SKILL.md           # Thin loader with execution instructions
├── workflow.yaml      # Deterministic workflow graph
└── references/        # Complex procedure docs (optional)
    └── {topic}.md
```

---

## Workflow YAML Schema

```yaml
# Required: Workflow identity
name: "skill-name"                    # String: matches skill directory name
version: "1.0.0"                      # Semver: workflow version
description: "Trigger description"   # String: copied to SKILL.md frontmatter

# Required: Entry gate (all must pass to start)
entry_preconditions:
  - type: config_exists              # Precondition type
  - type: tool_available
    tool: git                        # Parameters for precondition

# Required: Initial runtime state
initial_state:
  phase: "start"                     # String: current phase label
  source_type: null                  # null | string: detected source type
  flags:                             # Boolean flags for routing
    config_found: false
    manifest_detected: false
    is_first_source: false
  computed: {}                       # Object: stores action outputs

# Required: Starting point
start_node: locate_corpus            # String: must exist in nodes

# Required: Workflow graph
nodes:
  node_name:                         # String: unique node identifier
    type: action                     # Node type (see below)
    # ... type-specific fields

# Required: Terminal states
endings:
  success:                           # Ending identifier
    type: success                    # success | error
    message: "Source added"          # Display message
  error_no_config:
    type: error
    message: "No config.yaml found"
    recovery: "hiivmind-corpus-init" # Optional: suggest recovery skill
```

---

## Node Types

### 1. Action Node

Executes one or more operations, then routes based on success/failure.

```yaml
node_name:
  type: action
  description: "Optional description for debugging"
  actions:
    - type: read_config              # Consequence type
      store_as: "config"             # Store result in state.computed
    - type: set_flag
      flag: config_found
      value: true
    - type: evaluate
      expression: "len(config.sources) == 0"
      set_flag: is_first_source
  on_success: next_node              # Route on all actions succeeding
  on_failure: error_node             # Route on any action failing
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"action"` |
| `description` | No | Human-readable purpose |
| `actions` | Yes | Array of consequence objects |
| `on_success` | Yes | Node/ending to route to on success |
| `on_failure` | Yes | Node/ending to route to on failure |

### 2. Conditional Node

Branches based on a precondition evaluation.

```yaml
node_name:
  type: conditional
  description: "Route based on detected state"
  condition:
    type: flag_set                   # Precondition type
    flag: manifest_detected          # Precondition parameters
  branches:
    true: present_manifest_option    # Route when condition is true
    false: ask_source_type           # Route when condition is false
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"conditional"` |
| `description` | No | Human-readable purpose |
| `condition` | Yes | Single precondition object |
| `branches.true` | Yes | Node/ending when true |
| `branches.false` | Yes | Node/ending when false |

### 3. User Prompt Node

Presents an AskUserQuestion and routes based on response.

```yaml
node_name:
  type: user_prompt
  prompt:
    question: "What type of source would you like to add?"
    header: "Source"                 # Max 12 chars
    options:
      - id: git
        label: "Git repository"
        description: "Clone repo with docs folder"
      - id: local
        label: "Local files"
        description: "Files on your machine"
      - id: web
        label: "Web pages"
        description: "Cache blog posts/articles"
  on_response:
    git:
      consequence:                   # Optional: apply before routing
        - type: set_state
          field: source_type
          value: git
      next_node: collect_git_url
    local:
      consequence:
        - type: set_state
          field: source_type
          value: local
      next_node: collect_local_info
    web:
      next_node: collect_web_urls    # Can route without consequence
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"user_prompt"` |
| `prompt.question` | Yes | Question text |
| `prompt.header` | Yes | Short label (max 12 chars) |
| `prompt.options` | Yes | Array of options (2-4) |
| `prompt.options[].id` | Yes | Unique identifier for routing |
| `prompt.options[].label` | Yes | Display text |
| `prompt.options[].description` | Yes | Explanation |
| `on_response` | Yes | Map of id → {consequence?, next_node} |

### 4. Validation Gate Node

Runs multiple preconditions; all must pass to proceed.

```yaml
node_name:
  type: validation_gate
  description: "Validate before proceeding"
  validations:
    - type: file_exists
      path: "data/config.yaml"
      error_message: "Config file missing"
    - type: tool_available
      tool: git
      error_message: "Git is not installed"
  on_valid: proceed_node
  on_invalid: show_validation_errors
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"validation_gate"` |
| `description` | No | Human-readable purpose |
| `validations` | Yes | Array of preconditions with error_message |
| `on_valid` | Yes | Node/ending when all pass |
| `on_invalid` | Yes | Node/ending when any fail |

### 5. Reference Node

Loads and executes a reference document section.

```yaml
node_name:
  type: reference
  doc: "lib/corpus/patterns/sources/git.md"
  section: "Clone Repository"        # Optional: specific section
  context:                           # Variables to pass to doc
    repo_url: "${computed.repo_url}"
    source_id: "${computed.source_id}"
  next_node: verify_clone
```

**Fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"reference"` |
| `doc` | Yes | Path to reference document |
| `section` | No | Section heading to execute |
| `context` | No | Variables available in doc |
| `next_node` | Yes | Node/ending after doc execution |

---

## Variable Interpolation

Within workflow YAML, use `${...}` for variable references:

```yaml
# Reference state fields
expression: "${source_type} == 'git'"

# Reference computed values
url: "${computed.repo_url}"

# Reference user responses
section: "${user_responses.select_sections}"

# Reference flags
condition: "${flags.manifest_detected}"
```

**Resolution order:**
1. `state.computed.{name}`
2. `state.flags.{name}`
3. `state.user_responses.{name}`
4. `state.{field}`

---

## Endings

Terminal states that stop workflow execution.

```yaml
endings:
  success:
    type: success
    message: "Source added successfully to corpus"
    summary:                         # Optional: structured result
      source_id: "${computed.source_id}"
      source_type: "${source_type}"
      files_count: "${computed.files_count}"

  error_no_config:
    type: error
    message: "No config.yaml found in current directory"
    recovery: "hiivmind-corpus-init" # Suggest recovery skill
    details: "Run from a corpus directory containing data/config.yaml"

  cancelled:
    type: error
    message: "Operation cancelled by user"
```

**Ending fields:**
| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `"success"` or `"error"` |
| `message` | Yes | Display to user |
| `recovery` | No | Skill to suggest on error |
| `details` | No | Additional context |
| `summary` | No | Structured output (success only) |

---

## Complete Example

```yaml
name: add-source
version: "1.0.0"
description: >
  Add documentation source to corpus. Triggers: "add source", "add git repo"...

entry_preconditions:
  - type: config_exists

initial_state:
  phase: "locate"
  source_type: null
  source_url: null
  flags:
    config_found: false
    manifest_detected: false
    is_first_source: false
  computed: {}

start_node: locate_corpus

nodes:
  locate_corpus:
    type: action
    description: "Find and read corpus configuration"
    actions:
      - type: read_config
        store_as: config
      - type: set_flag
        flag: config_found
        value: true
      - type: evaluate
        expression: "len(config.sources) == 0"
        set_flag: is_first_source
    on_success: check_url_provided
    on_failure: error_no_config

  check_url_provided:
    type: conditional
    condition:
      type: state_not_null
      field: source_url
    branches:
      true: try_llms_txt_detection
      false: ask_source_type

  ask_source_type:
    type: user_prompt
    prompt:
      question: "What type of documentation source would you like to add?"
      header: "Source type"
      options:
        - id: git
          label: "Git repository"
          description: "Clone a repo containing docs"
        - id: local
          label: "Local files"
          description: "Upload files from your machine"
        - id: web
          label: "Web pages"
          description: "Cache blog posts or articles"
    on_response:
      git:
        consequence:
          - type: set_state
            field: source_type
            value: git
        next_node: collect_git_url
      local:
        consequence:
          - type: set_state
            field: source_type
            value: local
        next_node: collect_local_info
      web:
        consequence:
          - type: set_state
            field: source_type
            value: web
        next_node: collect_web_urls

  # ... additional nodes ...

endings:
  success:
    type: success
    message: "Source '${computed.source_id}' added to corpus"
    summary:
      source_id: "${computed.source_id}"
      source_type: "${source_type}"

  error_no_config:
    type: error
    message: "No config.yaml found"
    recovery: "hiivmind-corpus-init"
    details: "This skill must run from a corpus directory"
```

---

## Validation Rules

### Structural Validation

| Rule | Error |
|------|-------|
| `name` must match skill directory | "Workflow name mismatch" |
| `start_node` must exist in `nodes` | "Start node not found" |
| All `on_success`/`on_failure` must exist | "Invalid transition target" |
| All `branches` targets must exist | "Invalid branch target" |
| All `next_node` must exist | "Invalid next_node target" |
| `on_response` must cover all option ids | "Missing response handler" |

### Runtime Validation

| Rule | Error |
|------|-------|
| Entry preconditions must pass | "Entry gate failed: {message}" |
| Precondition types must be known | "Unknown precondition type" |
| Consequence types must be known | "Unknown consequence type" |
| Variable references must resolve | "Unresolved variable: ${name}" |

---

## Related Documentation

- **Preconditions:** `lib/workflow/preconditions/` - All precondition types
- **Consequences:** `lib/workflow/consequences/` - All consequence types (modular structure)
  - `consequences/core/` - 20 core workflow consequences
  - `consequences/extensions/` - 10 generic domain extensions
- **Execution:** `lib/workflow/execution.md` - Turn loop implementation
- **State:** `lib/workflow/state.md` - Runtime state structure
- **JSON Schema:** `lib/schema/workflow-schema.json` - Formal schema definition
