> **Used by:** `SKILL.md` Phase 3
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

# Node Generation Procedure

Complete reference for mapping prose skill patterns to workflow node types,
consequence types, precondition types, and prompt modes. This document is the
primary lookup table for Phase 3 of the migration skill.

---

## Consequence Type Selection Guide

When converting prose actions to workflow consequences, match the prose description
to the appropriate consequence type. All types below are from the {computed.lib_version} consolidated
type system (see `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md` for the
consolidation mapping from legacy types).

### File Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "read file", "load file", "open file" | local_file_ops | read | path, encoding (default: utf-8) |
| "write file", "save file", "output to file" | local_file_ops | write | path, content, mode (default: overwrite) |
| "append to file", "add to file" | local_file_ops | write | path, content, mode: append |
| "create directory", "make folder", "mkdir" | local_file_ops | mkdir | path, recursive (default: true) |
| "delete file", "remove file" | local_file_ops | delete | path, force (default: false) |
| "copy file", "duplicate file" | local_file_ops | copy | source, destination |
| "move file", "rename file" | local_file_ops | move | source, destination |
| "check file size", "get file info" | local_file_ops | stat | path |

### Git Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "clone repo", "clone repository" | git_ops_local | clone | url, destination, branch (optional) |
| "pull changes", "git pull" | git_ops_local | pull | remote (default: origin), branch |
| "fetch updates", "git fetch" | git_ops_local | fetch | remote (default: origin) |
| "get commit SHA", "current commit" | git_ops_local | get-sha | ref (default: HEAD) |
| "check status", "git status" | git_ops_local | status | path (optional) |
| "create branch", "checkout -b" | git_ops_local | create-branch | name, from (optional) |
| "commit changes", "git commit" | git_ops_local | commit | message, files (optional) |

### Web Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "fetch URL", "download", "HTTP GET" | web_ops | fetch | url, headers (optional) |
| "cache content", "store web response" | web_ops | cache | url, cache_key, ttl (optional) |
| "POST request", "send data" | web_ops | post | url, body, headers |
| "check URL", "ping endpoint" | web_ops | head | url |

### Command Execution

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "run script", "execute script" | run_command | interpreter: auto | command, working_dir (optional) |
| "run bash", "shell command" | run_command | interpreter: bash | command, working_dir (optional) |
| "run python", "python script" | run_command | interpreter: python | command OR script_path |
| "run node", "node script" | run_command | interpreter: node | command OR script_path |
| "install package", "pip install" | run_command | interpreter: auto | command: "pip install {pkg}" |

### State Management

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "store value", "set variable", "save to state" | mutate_state | set | field, value |
| "append to list", "add to array" | mutate_state | append | field, value |
| "clear variable", "reset field" | mutate_state | clear | field |
| "merge objects", "combine state" | mutate_state | merge | field, value (object) |
| "increment counter", "add to count" | mutate_state | set | field: computed expression |
| "set flag", "enable flag" | mutate_state | set | field: flags.{name}, value: true |
| "clear flag", "disable flag" | mutate_state | set | field: flags.{name}, value: false |
| "toggle flag" | mutate_state | set | field: flags.{name}, value: !current |

### Display Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "show message", "display text", "print" | display | format: text | content |
| "show table", "display table", "list items" | display | format: table | data, columns |
| "show JSON", "dump JSON" | display | format: json | data |
| "show markdown", "render markdown" | display | format: markdown | content |
| "show progress", "status update" | display | format: text | content (with progress info) |
| "show warning", "alert user" | display | format: text | content, level: warning |

### Logging Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "log event", "record action", "track step" | log_entry | level: info | message, data (optional) |
| "log warning", "warn about" | log_entry | level: warning | message, data (optional) |
| "log error", "record failure" | log_entry | level: error | message, data (optional) |
| "log debug", "trace execution" | log_entry | level: debug | message, data (optional) |

### Evaluation Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "calculate", "compute", "derive value" | evaluate | expression | expression, output_field |
| "format string", "template string" | evaluate | template | template, output_field |
| "parse YAML", "parse JSON" | evaluate | parse | input, format (yaml/json), output_field |
| "count items", "get length" | evaluate | expression | expression: "len({field})" |

### Skill Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "invoke skill", "call skill", "delegate to" | invoke_skill | -- | skill_name, args (optional) |
| "run workflow", "execute subflow" | invoke_skill | -- | skill_name, context (optional) |

### Control Flow Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "save checkpoint", "save progress" | create_checkpoint | -- | checkpoint_id, state_fields |
| "rollback", "restore checkpoint" | rollback_checkpoint | -- | checkpoint_id |
| "custom logic", "inline transform" | inline | -- | code (pseudocode block) |
| "run in background", "async task" | spawn_agent | -- | task, context |

### Intent Detection Operations

| Prose Pattern | Type | Operation | Key Parameters |
|---------------|------|-----------|----------------|
| "detect intent", "parse keywords" | parse_intent_flags | -- | input, keywords |
| "match rules", "apply intent rules" | match_3vl_rules | -- | flags, rules |
| "dynamic route", "route by intent" | dynamic_route | -- | match_result |

---

## Precondition Type Selection Guide

Use this table when generating `entry_preconditions` (Phase 2, Step 2.2) and
`condition` blocks inside conditional nodes (Phase 3, Step 3.2).

### State Checks

| Prose Pattern | Type | Operator | Parameters |
|---------------|------|----------|------------|
| "if flag is set", "when enabled" | state_check | true | field: flags.{name} |
| "if flag is not set", "when disabled" | state_check | false | field: flags.{name} |
| "if field equals X", "when value is X" | state_check | equals | field, value: X |
| "if field is not X", "when value differs" | state_check | not_equals | field, value: X |
| "if field has value", "when not empty" | state_check | not_null | field |
| "if field is empty", "when null" | state_check | null | field |
| "if field contains X", "includes" | state_check | contains | field, value: X |
| "if field matches pattern" | state_check | matches | field, pattern |

### Path Checks

| Prose Pattern | Type | Check | Parameters |
|---------------|------|-------|------------|
| "if file exists" | path_check | exists | path |
| "if file is a file" | path_check | is_file | path |
| "if directory exists" | path_check | is_directory | path |
| "if file contains text" | path_check | contains_text | path, text |
| "if config file exists" | path_check | is_file | path: config path |
| "if index exists" | path_check | is_file | path: index path |

### Tool Checks

| Prose Pattern | Type | Capability | Parameters |
|---------------|------|------------|------------|
| "requires tool", "tool must be installed" | tool_check | available | tool: {name} |
| "requires version X+", "minimum version" | tool_check | version_gte | tool: {name}, version: X |
| "must be authenticated", "logged in" | tool_check | authenticated | tool: {name} |
| "daemon must be running" | tool_check | daemon_ready | tool: {name} |

### Source Checks

| Prose Pattern | Type | Aspect | Parameters |
|---------------|------|--------|------------|
| "if source exists", "repo available" | source_check | exists | source |
| "if already cloned", "repo present" | source_check | cloned | source, path |
| "if updates available", "new commits" | source_check | has_updates | source |

### Composite Checks

| Prose Pattern | Type | Parameters |
|---------------|------|------------|
| "if all conditions met", "all of" | all_of | conditions: [...] |
| "if any condition met", "any of" | any_of | conditions: [...] |
| "if no conditions met", "none of" | none_of | conditions: [...] |
| "if exactly one", "exclusive or" | xor_of | conditions: [...] |

### Expression Checks

| Prose Pattern | Type | Parameters |
|---------------|------|------------|
| "if count equals N" | evaluate_expression | expression: "len({field}) == N" |
| "if count above N" | evaluate_expression | expression: "len({field}) > N" |
| "if count below N" | evaluate_expression | expression: "len({field}) < N" |
| "if expression is true" | evaluate_expression | expression: "{arbitrary}" |

### Fetch Checks

| Prose Pattern | Type | Aspect | Parameters |
|---------------|------|--------|------------|
| "if fetch succeeded" | fetch_check | succeeded | url (optional) |
| "if response has content" | fetch_check | has_content | url (optional) |

### Log State Checks

| Prose Pattern | Type | Aspect | Parameters |
|---------------|------|--------|------------|
| "if logging initialized" | log_state | initialized | -- |
| "if log finalized" | log_state | finalized | -- |
| "if log level enabled" | log_state | level_enabled | level |

---

## Prompt Mode Selection Table

When the analysis contains user interaction patterns, select the appropriate prompt
mode for the generated `user_prompt` nodes. The mode determines how the prompt is
rendered across different interfaces.

### Mode Selection

| Prose Pattern | Mode | Configuration | Best For |
|---------------|------|---------------|----------|
| "ask user to select", "choose one" | interactive | (default) | Claude Code CLI |
| "present numbered list", "pick from list" | interactive | (default) | Claude Code CLI |
| "present table and wait", "tabular selection" | tabular | match_strategy: prefix | Non-Claude CLIs |
| "allow custom input", "other option" | tabular | other_handler: route | Free-form input needed |
| "exact match required", "strict selection" | tabular | match_strategy: exact | Precise commands |
| "web form", "browser interface" | forms | modes.web: forms | Web deployment |
| "API endpoint", "programmatic interface" | structured | modes.api: structured | API consumers |
| "agent decides", "autonomous selection" | autonomous | modes.agent: autonomous | Agent pipelines |

### Mode Configuration Examples

**Interactive (default for Claude Code):**
No additional configuration needed. AskUserQuestion renders as an interactive prompt.

**Tabular (for non-Claude environments):**
```yaml
prompts:
  mode: "tabular"
  tabular:
    match_strategy: "prefix"     # "prefix" | "exact" | "fuzzy"
    other_handler: "prompt"      # "prompt" | "route" | "reject"
```

**Multi-interface:**
```yaml
prompts:
  interface: "auto"
  modes:
    claude_code: "interactive"
    web: "forms"
    api: "structured"
    agent: "autonomous"
```

**Autonomous (for agent-to-agent):**
```yaml
prompts:
  mode: "autonomous"
  autonomous:
    strategy: "best_match"            # "best_match" | "first_match" | "ask_human"
    confidence_threshold: 0.7         # Minimum confidence to auto-select
    fallback: "interactive"           # Fall back to this mode if below threshold
```

---

## Node Type Decision Tree

Use this decision tree to determine which node type to create for a given
analysis element:

```
Is this element a decision point?
├── No: Is it a user interaction?
│   ├── No: ACTION node
│   │   └── Map actions to consequence types using tables above
│   └── Yes: USER_PROMPT node
│       └── Map options and responses
└── Yes: How many branches?
    ├── 2 branches: CONDITIONAL node
    │   └── Map condition to precondition type
    ├── 3+ branches, value-based: Chain of CONDITIONAL nodes
    │   └── Each checks one value, routes to branch or next check
    └── 3+ branches, user-driven: USER_PROMPT node
        └── Each option routes to a different next_node
```

### Special Cases

**Validation gates (multiple assertions grouped together):**
Use a single CONDITIONAL node with `type: all_of` and `audit.enabled: true`.
This replaces the deprecated `validation_gate` node type.

```yaml
validate_inputs:
  type: conditional
  condition:
    type: all_of
    conditions:
      - type: state_check
        field: input_path
        operator: not_null
      - type: path_check
        path: "${input_path}"
        check: is_file
      - type: tool_check
        tool: yq
        capability: available
  audit:
    enabled: true
    output: computed.validation_errors
    messages:
      state_check: "Input path not provided"
      path_check: "Input file does not exist"
      tool_check: "yq is required but not installed"
  branches:
    on_true: process_input
    on_false: show_validation_errors
```

**Loop patterns (for-each, while, iterate):**
Loops in prose are modeled as a cycle in the node graph. Create an action node
that processes one item and increments a counter, then a conditional node that
checks if more items remain:

```yaml
process_item:
  type: action
  description: "Process current item"
  actions:
    - type: inline
      code: "process(computed.items[computed.current_index])"
    - type: mutate_state
      operation: set
      field: computed.current_index
      value: "${computed.current_index + 1}"
  on_success: check_more_items
  on_failure: error_operation_failed

check_more_items:
  type: conditional
  condition:
    type: evaluate_expression
    expression: "computed.current_index < len(computed.items)"
  branches:
    on_true: process_item      # Loop back
    on_false: loop_complete     # Exit loop
```

**Optional steps (do X if flag set, otherwise skip):**
Model as a conditional node where `on_false` skips ahead:

```yaml
check_optional_step:
  type: conditional
  condition:
    type: state_check
    field: flags.run_optional
    operator: true
  branches:
    on_true: run_optional_step
    on_false: next_required_step    # Skip the optional step
```

**Error recovery (try-catch patterns):**
Model with `on_failure` routing to a recovery node instead of an error ending:

```yaml
attempt_operation:
  type: action
  description: "Attempt the operation"
  actions:
    - type: web_ops
      operation: fetch
      url: "${target_url}"
  on_success: process_result
  on_failure: handle_fetch_error      # Recovery, not ending

handle_fetch_error:
  type: action
  description: "Handle fetch error, try fallback"
  actions:
    - type: display
      format: text
      content: "Primary fetch failed, trying fallback..."
    - type: web_ops
      operation: fetch
      url: "${fallback_url}"
  on_success: process_result
  on_failure: error_operation_failed   # Now route to error ending
```

---

## Transition Wiring Rules

After all nodes are created, apply these rules to wire transitions:

### Sequential Phases

When phases are linear (no branching), wire `on_success` from each node to the
first node of the next phase:

```
Phase 1 Node → Phase 2 Node → Phase 3 Node → success
```

### Branching Phases

When a phase contains conditionals, wire the branches to the correct targets
and ensure both branches eventually rejoin the main flow:

```
         ┌─ on_true  → Branch A Node → rejoin_node
Conditional
         └─ on_false → Branch B Node → rejoin_node
```

### Error Routing Priority

1. **Skill-specific error endings** take priority over generic ones
2. **Recoverable errors** route to recovery nodes, not endings
3. **Generic fallback** is `error_operation_failed`

### Dead-End Prevention

Every node must have all required transition fields populated:
- `action` nodes: `on_success` and `on_failure`
- `conditional` nodes: `branches.on_true` and `branches.on_false`
- `user_prompt` nodes: `on_response.{option_id}.next_node` for every option

---

## Related Documentation

- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Consequence Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
- **Precondition Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
- **Prompt Modes Reference:** `${CLAUDE_PLUGIN_ROOT}/references/prompt-modes.md`
- **Node Features Reference:** `${CLAUDE_PLUGIN_ROOT}/references/node-features.md`
