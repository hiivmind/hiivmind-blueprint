# Workflow State Model

Runtime state structure for workflow execution. State persists across conversation turns and enables deterministic routing.

---

## State Structure

```yaml
# Workflow identity
workflow_name: "add-source"
workflow_version: "1.0.0"

# Position tracking
current_node: "ask_source_type"
previous_node: "check_url_provided"

# Execution history
history:
  - node: "locate_corpus"
    outcome: { success: true }
    timestamp: "2025-01-22T10:30:00Z"
  - node: "check_url_provided"
    outcome: { branch: "false" }
    timestamp: "2025-01-22T10:30:01Z"

# User interaction results
user_responses:
  ask_source_type:
    id: "git"
    raw: { selected: "Git repository" }
  collect_git_url:
    id: "other"
    raw: { text: "https://github.com/pola-rs/polars" }

# Computed values from actions
computed:
  config:
    schema_version: 2
    corpus:
      name: "polars"
    sources: []
  source_id: "polars"
  repo_url: "https://github.com/pola-rs/polars"
  sha: "abc123def456"
  files_count: 42

# Boolean routing flags
flags:
  config_found: true
  manifest_detected: false
  is_first_source: true
  clone_succeeded: true

# Rollback snapshots
checkpoints:
  before_clone:
    # Full state snapshot at checkpoint creation
    current_node: "execute_clone"
    flags: { ... }
    computed: { ... }

# Workflow-specific fields (from initial_state)
phase: "setup"
source_type: "git"
source_url: "https://github.com/pola-rs/polars"
```

---

## Field Reference

### Identity Fields

| Field | Type | Description |
|-------|------|-------------|
| `workflow_name` | string | Name from workflow.yaml |
| `workflow_version` | string | Version from workflow.yaml |

### Position Fields

| Field | Type | Description |
|-------|------|-------------|
| `current_node` | string | Node currently being executed |
| `previous_node` | string | Last executed node |

### History

Array of executed node records:

```yaml
history:
  - node: "locate_corpus"           # Node name
    outcome:                        # Execution result
      success: true                 # For action nodes
      # OR
      branch: "true"                # For conditional nodes
      # OR
      response: "git"               # For user_prompt nodes
    timestamp: "2025-01-22T10:30:00Z"
```

**Use cases:**
- Debugging execution path
- Detecting loops
- Audit trail

### User Responses

Results from user_prompt nodes, keyed by node name:

```yaml
user_responses:
  ask_source_type:
    id: "git"                       # Option id selected
    raw:                            # Raw AskUserQuestion response
      selected: "Git repository"
  collect_git_url:
    id: "other"                     # "other" for custom input
    raw:
      text: "https://github.com/..."
```

**Accessing in expressions:**
```yaml
expression: "user_responses.ask_source_type.id == 'git'"
```

### Computed Values

Results from action consequences, organized hierarchically:

```yaml
computed:
  # From read_config
  config:
    schema_version: 2
    corpus: { name: "polars" }
    sources: []

  # From compute/evaluate
  source_id: "polars"
  repo_name: "polars"
  repo_owner: "pola-rs"

  # From web_fetch
  manifest_check:
    status: 200
    content: "# Polars\n..."
    url: "https://..."

  # From get_sha
  sha: "abc123def456"

  # Nested structures
  source_config:
    type: "git"
    branch: "main"
    docs_root: "docs"
```

**Accessing in expressions:**
```yaml
expression: "computed.config.sources.length == 0"
value: "${computed.source_id}"
```

### Flags

Boolean values for routing decisions:

```yaml
flags:
  config_found: true
  manifest_detected: false
  is_first_source: true
  clone_succeeded: true
  user_confirmed: false
```

**Setting flags:**
```yaml
- type: set_flag
  flag: manifest_detected
  value: true

- type: evaluate
  expression: "len(computed.config.sources) == 0"
  set_flag: is_first_source
```

**Checking flags:**
```yaml
condition:
  type: flag_set
  flag: manifest_detected
```

### Checkpoints

State snapshots for rollback:

```yaml
checkpoints:
  before_clone:
    current_node: "execute_clone"
    previous_node: "collect_git_details"
    flags:
      config_found: true
      manifest_detected: false
    computed:
      config: { ... }
      source_id: "polars"
    # ... full state copy
```

**Creating:**
```yaml
- type: create_checkpoint
  name: "before_clone"
```

**Restoring:**
```yaml
- type: rollback_checkpoint
  name: "before_clone"
```

### Custom Fields

Fields from `workflow.initial_state` that aren't in the standard structure:

```yaml
# From workflow.yaml initial_state
phase: "setup"
source_type: "git"
source_url: null
```

These are workflow-specific and accessed directly:

```yaml
condition:
  type: state_equals
  field: source_type
  value: "git"
```

---

## State Access Patterns

### Dot Notation

Access nested fields with dots:

```yaml
# Top-level
field: source_type

# Computed nested
field: computed.config.corpus.name

# User response
field: user_responses.ask_source_type.id

# Flag
field: flags.config_found
```

### Array Access

Access array elements with brackets:

```yaml
# First source
field: computed.config.sources[0].id

# Last history entry
field: history[-1].node
```

### Variable Interpolation

Use `${...}` in string values:

```yaml
path: ".source/${computed.source_id}/docs"
message: "Found ${computed.files_count} files in ${source_type} source"
```

---

## State Lifecycle

### Initialization

```
1. Load workflow.yaml
2. Create empty state structure
3. Copy workflow.initial_state fields
4. Copy workflow.initial_state.flags
5. Set current_node = workflow.start_node
```

### During Execution

```
For each node:
1. Execute node (may modify computed, flags, user_responses)
2. Append to history
3. Update previous_node, current_node
```

### On Error

```
If action fails:
1. State may be partially modified
2. If checkpoint exists, can rollback
3. Route to on_failure node
```

### On Completion

```
When ending reached:
1. State is final
2. History contains full execution path
3. Summary can reference final computed values
```

---

## State Persistence

State exists in conversation context and persists across turns:

**Turn 1:**
```
User invokes skill
→ Initialize state
→ Execute nodes until user_prompt
→ Present AskUserQuestion
→ State persists...
```

**Turn 2:**
```
User responds
→ Resume from user_prompt node
→ Store response in state.user_responses
→ Continue execution
→ State persists...
```

**Turn N:**
```
Workflow reaches ending
→ Display result
→ State complete
```

---

## State Validation

### Invariants

| Rule | Enforcement |
|------|-------------|
| `current_node` must exist | Checked before execution |
| `flags` values must be boolean | Type coercion on set |
| `history` entries immutable | Append-only |
| `checkpoints` preserve deep copies | Clone on create |

### Type Coercion

```yaml
# Strings become strings
set_state field: source_type value: "git"

# Numbers stay numbers
set_state field: computed.count value: 42

# Arrays preserved
append_state field: computed.urls value: { path: "/api" }

# Booleans for flags
set_flag flag: found value: true
```

---

## Debugging State

### Display Current State

```yaml
- type: display_message
  message: |
    Current state:
    - Node: ${current_node}
    - Source type: ${source_type}
    - Flags: config_found=${flags.config_found}, manifest=${flags.manifest_detected}
    - Computed sources: ${computed.config.sources.length}
```

### State Dump

For debugging, dump full state as YAML:

```
[DEBUG] State at node 'ask_source_type':
workflow_name: add-source
current_node: ask_source_type
previous_node: check_url_provided
flags:
  config_found: true
  manifest_detected: false
  is_first_source: true
computed:
  config: { sources: [] }
user_responses: {}
history:
  - { node: locate_corpus, outcome: { success: true } }
  - { node: check_url_provided, outcome: { branch: false } }
```

---

## State Examples

### Fresh Start

```yaml
workflow_name: add-source
workflow_version: "1.0.0"
current_node: locate_corpus
previous_node: null
history: []
user_responses: {}
computed: {}
flags:
  config_found: false
  manifest_detected: false
  is_first_source: false
checkpoints: {}
phase: start
source_type: null
source_url: null
```

### After Config Read

```yaml
current_node: check_url_provided
previous_node: locate_corpus
history:
  - node: locate_corpus
    outcome: { success: true }
computed:
  config:
    schema_version: 2
    corpus: { name: polars }
    sources: []
flags:
  config_found: true
  is_first_source: true
```

### After User Selection

```yaml
current_node: collect_git_url
previous_node: ask_source_type
user_responses:
  ask_source_type:
    id: git
    raw: { selected: "Git repository" }
source_type: git
flags:
  config_found: true
  is_first_source: true
```

### Ready for Clone

```yaml
current_node: execute_clone
computed:
  config: { ... }
  source_id: polars
  repo_url: "https://github.com/pola-rs/polars"
  branch: main
  docs_root: docs
checkpoints:
  before_clone:
    # Full state snapshot
flags:
  config_found: true
  is_first_source: true
source_type: git
```

### Successful Completion

```yaml
current_node: success  # ending
computed:
  config: { sources: [{ id: polars, ... }] }
  source_id: polars
  sha: abc123
  files_count: 42
flags:
  config_found: true
  is_first_source: true
  clone_succeeded: true
history:
  # Full execution path
  - { node: locate_corpus, ... }
  - { node: check_url_provided, ... }
  - { node: ask_source_type, ... }
  - { node: collect_git_url, ... }
  - { node: execute_clone, ... }
  - { node: update_config, ... }
```

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - YAML structure
- **Preconditions:** `lib/workflow/preconditions.md` - Boolean evaluations
- **Consequences:** `lib/workflow/consequences.md` - State mutations
- **Execution:** `lib/workflow/execution.md` - Turn loop
