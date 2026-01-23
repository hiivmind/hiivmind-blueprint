# Core Workflow Consequences

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

**Examples:**
```yaml
# Simple field
- type: set_state
  field: source_type
  value: git

# Nested field
- type: set_state
  field: computed.manifest.title
  value: "${fetch_result.title}"

# From interpolation
- type: set_state
  field: source_id
  value: "${computed.derived_id}"
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

**Expression syntax:** Same as `evaluate_expression` precondition. Supports:
- Comparison operators: `==`, `!=`, `<`, `>`, `<=`, `>=`
- Logical operators: `and`, `or`, `not`
- Functions: `len()`, `contains()`, `startswith()`, `endswith()`
- Field access: `config.sources[0].id`

**Examples:**
```yaml
# Check if array is empty
- type: evaluate
  expression: "len(config.sources) == 0"
  set_flag: is_first_source

# Check string content
- type: evaluate
  expression: "computed.source_type == 'git'"
  set_flag: is_git_source

# Compound conditions
- type: evaluate
  expression: "config.sources and len(config.sources) > 0"
  set_flag: has_sources
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

**Examples:**
```yaml
# Extract repo name from URL
- type: compute
  expression: "source_url.split('/').pop()"
  store_as: computed.repo_name

# Calculate count
- type: compute
  expression: "len(config.sources)"
  store_as: computed.source_count

# Construct string
- type: compute
  expression: "'hiivmind-corpus-' + computed.project_name"
  store_as: computed.corpus_id
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

**Notes:**
- Supports multiline messages using YAML `|` syntax
- All `${}` placeholders are interpolated from state
- Markdown formatting is preserved

**Examples:**

Simple status:
```yaml
- type: display_message
  message: "Source added successfully: ${computed.source_id}"
```

Detailed summary:
```yaml
- type: display_message
  message: |
    ## Indexing Complete

    - **Files analyzed:** ${computed.file_count}
    - **Sections created:** ${computed.section_count}
    - **Index location:** data/index.md
```

Warning:
```yaml
- type: display_message
  message: |
    **Warning:** Index is stale

    Last indexed: ${config.sources[0].last_indexed_at}
    Current SHA: ${computed.current_sha}
    Indexed SHA: ${config.sources[0].last_commit_sha}
```

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

**Notes:**
- `rows` can be a state reference (`"${computed.table_data}"`) or inline array
- Each row should be an array matching header count
- Renders as markdown table

**Examples:**

From state:
```yaml
actions:
  # First build the table data
  - type: set_state
    field: computed.sources_table
    value:
      - ["main", "git", "github.com/org/repo"]
      - ["uploads", "local", "data/uploads"]

  # Then display it
  - type: display_table
    title: "Configured Sources"
    headers: ["ID", "Type", "Location"]
    rows: "${computed.sources_table}"
```

Inline data:
```yaml
- type: display_table
  title: "Available Actions"
  headers: ["Command", "Description"]
  rows:
    - ["init", "Create new corpus"]
    - ["build", "Build index from docs"]
    - ["refresh", "Update from upstream"]
```

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

**Notes:**
- Creates deep copy of entire state
- Multiple checkpoints can coexist
- Checkpoint names should be descriptive

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

**Notes:**
- Restores complete state snapshot
- Does NOT rollback file system changes
- Fails if checkpoint doesn't exist

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

**Effect:**
```
agent_result = Task(
  subagent_type: subagent_type,
  prompt: interpolate(prompt),
  run_in_background: run_in_background
)
set_state_value(store_as, agent_result)
```

**Notes:**
- Uses Claude's Task tool to spawn subagent
- Background agents run concurrently
- Results are stored when agent completes
- Multiple spawn_agent calls can run in parallel

**Common agent types:**
- `source-scanner` - Analyze documentation source structure
- `Explore` - Search codebase for patterns
- `general-purpose` - Complex multi-step tasks

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

**Effect:**
1. Load document at path
2. If section specified, extract that section
3. Execute instructions with context variables
4. Return any outputs to workflow

**Notes:**
- Patterns are tool-agnostic algorithm documentation
- Context variables replace `${variable}` in pattern
- Section names match markdown headings
- Pattern may produce outputs stored in state

**Examples:**

Full pattern:
```yaml
- type: invoke_pattern
  path: "lib/blueprint/patterns/workflow-generation.md"
```

Specific section with context:
```yaml
- type: invoke_pattern
  path: "lib/blueprint/patterns/node-mapping.md"
  section: "Map Action Nodes"
  context:
    analysis: "${computed.analysis}"
    target_path: "${computed.output_path}"
```

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

**Effect:**
```
Invoke the Skill tool:
  Skill: {skill}
  Args: {args}
```

**Notes:**
- The invoked skill takes over the conversation
- This consequence is typically the last action before reaching a success ending
- Control returns to workflow when skill completes

**Examples:**

Delegate to validate:
```yaml
- type: invoke_skill
  skill: "hiivmind-blueprint-validate"
  args: "${computed.workflow_path}"
```

Delegate to generate:
```yaml
- type: invoke_skill
  skill: "hiivmind-blueprint-generate"
  args: ""
```

With computed arguments:
```yaml
- type: invoke_skill
  skill: "hiivmind-blueprint-analyze"
  args: "${computed.skill_name}"
```

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

**Output format:**
```
2025-01-23T14:30:00.000Z
```

**Examples:**

Record indexing time:
```yaml
- type: set_timestamp
  store_as: computed.indexed_at
```

Use in config update:
```yaml
actions:
  - type: set_timestamp
    store_as: computed.now
  - type: write_file
    path: "config.yaml"
    content: "last_updated: ${computed.now}"
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

**Output format:**
```
sha256:abc123def456...
```

The `sha256:` prefix identifies the hash algorithm used.

**Examples:**

Hash manifest for change detection:
```yaml
actions:
  - type: web_fetch
    url: "${base_url}/llms.txt"
    store_as: computed.manifest
  - type: compute_hash
    from: computed.manifest.content
    store_as: computed.manifest_hash
```

Compare with stored hash:
```yaml
- type: evaluate
  expression: "computed.manifest_hash != config.sources[0].content_hash"
  set_flag: content_changed
```

---

## Common Patterns

### Progress Feedback

```yaml
nodes:
  start_processing:
    type: action
    actions:
      - type: display_message
        message: "Starting analysis of ${computed.file_count} files..."
    on_success: process_files

  process_complete:
    type: action
    actions:
      - type: display_message
        message: "Processing complete. ${computed.processed_count} files indexed."
```

### Safe Risky Operations

```yaml
nodes:
  attempt_clone:
    type: action
    actions:
      - type: create_checkpoint
        name: "before_clone"
      - type: clone_repo
        url: "${source_url}"
        dest: ".source/temp"
    on_success: validate_clone
    on_failure: handle_clone_error

  handle_clone_error:
    type: action
    actions:
      - type: rollback_checkpoint
        name: "before_clone"
      - type: display_message
        message: "Clone failed. State restored."
    on_success: report_error
```

### Parallel Source Scanning

```yaml
nodes:
  scan_sources:
    type: action
    actions:
      # Spawn scanner for each source in parallel
      - type: spawn_agent
        subagent_type: "source-scanner"
        prompt: "Scan source main: ${config.sources[0].repo_url}"
        store_as: computed.scan_results.main
        run_in_background: true
      - type: spawn_agent
        subagent_type: "source-scanner"
        prompt: "Scan source secondary: ${config.sources[1].repo_url}"
        store_as: computed.scan_results.secondary
        run_in_background: true
    on_success: await_results
```

### Gateway Delegation

```yaml
nodes:
  route_to_skill:
    type: action
    actions:
      - type: invoke_skill
        skill: "${computed.target_skill}"
        args: "${arguments}"
    on_success: end_success
```

---

## Related Documentation

- **Parent:** [../README.md](../README.md) - Consequence taxonomy
- **Shared patterns:** [shared.md](shared.md) - Interpolation, standard parameters
- **Extensions:** [../extensions/](../extensions/) - Domain-specific consequences
- **State structure:** `lib/workflow/state.md` - Runtime state fields
- **Preconditions:** `lib/workflow/preconditions.md` - Expression syntax reference
- **Execution:** `lib/workflow/execution.md` - Workflow turn loop
