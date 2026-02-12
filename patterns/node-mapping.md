# Node Mapping Pattern

Map analyzed skill structures to workflow node types.

> **Full Type Reference:**
> - Consequences: `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
> - Preconditions: `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
> - Node Features: `${CLAUDE_PLUGIN_ROOT}/references/node-features.md`
> - Prompt Modes: `${CLAUDE_PLUGIN_ROOT}/references/prompt-modes.md`

---

## Node Type Selection

```
                    Analyze Element Type
                           |
       +-------------------+-------------------+
       v                   v                   v
   Tool Call          Conditional          User Input
       |                   |                   |
       v                   v                   v
   ACTION             How many              USER_PROMPT
    NODE              branches?               NODE
                           |
               +-----------+-----------+
               v                       v
          2 branches              3+ branches
               |                       |
               v                       v
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
    - type: local_file_ops
      operation: read
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
    type: path_check
    path: "data/config.yaml"
    check: is_file
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
        - type: mutate_state
          operation: set
          field: source_type
          value: git
      next_node: collect_git_url
    local:
      next_node: collect_local_path
```

### Conditional with Audit Mode (Validation)

> **Note:** `validation_gate` was removed in v2.0.0. Use `conditional` with `audit` mode instead.

```yaml
validate_prerequisites:
  type: conditional
  description: "Validate prerequisites before proceeding"
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
      tool_check: "Git required"
      path_check: "No config.yaml"
  branches:
    on_true: proceed
    on_false: show_error
```

Audit mode evaluates ALL conditions (no short-circuit) and collects detailed results in `computed.validation_errors`.

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
| "if file exists" | `path_check` (check: is_file) |
| "if directory exists" | `path_check` (check: is_directory) |
| "if config exists" | `path_check` (path: data/config.yaml, check: is_file) |
| "if [flag] is set" | `state_check` (field: flags.X, operator: "true") |
| "if [field] is X" | `state_check` (operator: equals) |
| "if [field] has value" | `state_check` (operator: not_null) |
| "if array is empty" | `evaluate_expression` (len(field) == 0) |
| "if array has items" | `evaluate_expression` (len(field) > 0) |
| "if [complex]" | `evaluate_expression` |

---

## Tool to Consequence Mapping

| Prose | Consequence |
|-------|-------------|
| Read file | `local_file_ops` (operation: read) |
| Write file | `local_file_ops` (operation: write) |
| Create directory | `local_file_ops` (operation: mkdir) |
| Delete file | `local_file_ops` (operation: delete) |
| Git clone | `git_ops_local` (operation: clone) |
| Git pull | `git_ops_local` (operation: pull) |
| Git fetch | `git_ops_local` (operation: fetch) |
| Get commit SHA | `git_ops_local` (operation: get-sha) |
| Fetch URL | `web_ops` (operation: fetch) |
| Cache content | `web_ops` (operation: cache) |
| Run script | `run_command` |
| Store value | `mutate_state` (operation: set) |
| Append to array | `mutate_state` (operation: append) |
| Set flag | `set_flag` |
| Show message | `display` (format: text) |
| Show table | `display` (format: table) |

---

## Full Consequence Type Reference

### core/control
| Type | Purpose |
|------|---------|
| `create_checkpoint` | Save state snapshot |
| `rollback_checkpoint` | Restore from checkpoint |
| `spawn_agent` | Launch background agent |
| `inline` | Execute embedded pseudocode |
| `invoke_skill` | Invoke another skill |

### core/evaluation
| Type | Purpose |
|------|---------|
| `evaluate` | Evaluate expression to flag |
| `compute` | Compute and store value |

### core/interaction
| Type | Purpose | Operations/Formats |
|------|---------|-------------------|
| `display` | Display content to user | format: text, table, json, markdown |

### core/logging
| Type | Purpose |
|------|---------|
| `init_log` | Initialize log session |
| `log_node` | Record node execution |
| `log_entry` | Log event/warning/error (level: info/warning/error) |
| `log_session_snapshot` | Capture state snapshot |
| `finalize_log` | Complete log |
| `write_log` | Write log to file |
| `apply_log_retention` | Clean up old logs |
| `output_ci_summary` | CI environment output |
| `install_tool` | Install CLI tool |

### core/state
| Type | Purpose | Operations |
|------|---------|------------|
| `set_flag` | Set boolean flag | - |
| `mutate_state` | Mutate state field | operation: set, append, clear, merge |

### core/utility
| Type | Purpose |
|------|---------|
| `set_timestamp` | Store current timestamp |
| `compute_hash` | Compute SHA-256 hash |

### core/intent
| Type | Purpose |
|------|---------|
| `evaluate_keywords` | Simple keyword matching |
| `parse_intent_flags` | Parse 3VL flags |
| `match_3vl_rules` | Match flags to rules |
| `dynamic_route` | Set dynamic target |

### extensions/file-system
| Type | Purpose | Operations |
|------|---------|------------|
| `local_file_ops` | File operations | operation: read, write, mkdir, delete |

### extensions/git
| Type | Purpose | Operations |
|------|---------|------------|
| `git_ops_local` | Git operations | operation: clone, pull, fetch, get-sha |

### extensions/web
| Type | Purpose | Operations |
|------|---------|------------|
| `web_ops` | Web operations | operation: fetch, cache |

### extensions/scripting
| Type | Purpose |
|------|---------|
| `run_command` | Execute script (interpreter: auto, bash, python, node) |

### extensions/package
| Type | Purpose |
|------|---------|
| `install_tool` | Install CLI tool |

---

## Full Precondition Type Reference

### core/composite
| Type | Purpose |
|------|---------|
| `all_of` | All conditions true (AND) |
| `any_of` | At least one true (OR) |
| `none_of` | No conditions true (NOR) |
| `xor_of` | Exactly one true (XOR) |

### core/expression
| Type | Purpose |
|------|---------|
| `evaluate_expression` | Evaluate boolean expression (use len() for array counts) |

### core/state
| Type | Purpose | Operators |
|------|---------|-----------|
| `state_check` | Check state field values | operator: equals, not_equals, null, not_null, true, false |

### core/filesystems
| Type | Purpose | Checks |
|------|---------|--------|
| `path_check` | Check file/directory | check: exists, is_file, is_directory, contains_text |

### core/logging
| Type | Purpose | Aspects |
|------|---------|---------|
| `log_state` | Check logging state | aspect: initialized, finalized, level_enabled |

### core/tools
| Type | Purpose | Capabilities |
|------|---------|--------------|
| `tool_check` | Check tool availability | capability: available, version_gte, authenticated, daemon_ready |
| `python_module_available` | Check Python module | - |

### core/network
| Type | Purpose |
|------|---------|
| `network_available` | Check connectivity |

### core/git
| Type | Purpose | Aspects |
|------|---------|---------|
| `source_check` | Check source repo | aspect: exists, cloned, has_updates |

### core/web_fetch
| Type | Purpose | Aspects |
|------|---------|---------|
| `fetch_check` | Check fetch result | aspect: succeeded, has_content |

---

## Remote Workflow References

Use `reference` nodes with `workflow` parameter for remote workflows:

```yaml
detect_intent:
  type: reference
  workflow: {computed.lib_ref}:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
  next_node: "${computed.dynamic_target}"
```

**Key differences from `invoke_skill`:**
- `reference` shares state with parent (recommended for sub-workflows)
- `invoke_skill` isolates state (new conversation)

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

## User Prompt Mode Configuration

When converting prose that involves user interaction, consider which prompt mode to use:

### When to Use Interactive Mode (Default)

- Running in Claude Code with tool access
- Want structured chip-style option selection
- Need multi-select capability
- Prefer automatic response parsing

### When to Use Tabular Mode

- Running in environments without AskUserQuestion tool
- Want text-based interaction
- Need flexible input matching (typo tolerance)
- Want to support custom "other" responses via text

### Mode Configuration

Configure mode at the workflow level in `initial_state.prompts`:

```yaml
initial_state:
  prompts:
    mode: "tabular"              # "interactive" (default) or "tabular"
    tabular:
      match_strategy: "prefix"   # "exact" | "prefix" | "fuzzy"
      other_handler: "prompt"    # "prompt" | "route" | "fail"
```

### Prose Analysis Indicators

| Prose Pattern | Suggested Mode | Match Strategy |
|---------------|----------------|----------------|
| "Ask user to select..." | interactive | N/A |
| "Present options and wait for text..." | tabular | prefix |
| "Allow user to type choice or custom value" | tabular | prefix + route |
| "Exact match required" | tabular | exact |
| "Tolerate typos in selection" | tabular | fuzzy |

### Converting Prose to User Prompt

**Prose:**
```
Ask the user which format they prefer:
- Markdown (portable, human-readable)
- JSON (machine-parseable)
Allow them to type a prefix like "mark" to select.
```

**Workflow:**
```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"

nodes:
  select_format:
    type: user_prompt
    prompt:
      question: "Which format do you prefer?"
      header: "Format"
      options:
        - id: markdown
          label: "Markdown"
          description: "Portable, human-readable"
        - id: json
          label: "JSON"
          description: "Machine-parseable"
    on_response:
      markdown:
        next_node: generate_markdown
      json:
        next_node: generate_json
```

---

## Related Documentation

- **Skill Analysis:** `lib/blueprint/patterns/skill-analysis.md`
- **Workflow Generation:** `lib/blueprint/patterns/workflow-generation.md`
- **Node Type Definitions:** `hiivmind/hiivmind-blueprint-lib@{computed.lib_version}/nodes/workflow_nodes.yaml`
- **Prompts Config:** `lib/workflow/prompts-config-loader.md`
