# Type Validation Rules

Rules for validating precondition and consequence types against the type catalog.

## Valid Precondition Types

| Type | Description |
|------|-------------|
| `state_check` | Check state variable value |
| `path_check` | Check file/directory existence |
| `tool_check` | Check tool availability/version |
| `source_check` | Check source repository state |
| `log_state` | Check logging state |
| `fetch_check` | Check fetch/download state |
| `evaluate_expression` | Evaluate arbitrary expression |
| `all_of` | Composite: all conditions must pass |
| `any_of` | Composite: at least one condition must pass |
| `none_of` | Composite: no condition may pass |
| `xor_of` | Composite: exactly one condition must pass |
| `python_module_available` | Check Python module availability |
| `network_available` | Check network connectivity |

## Valid Consequence Types

| Type | Description |
|------|-------------|
| `create_checkpoint` | Create a rollback checkpoint |
| `rollback_checkpoint` | Restore from checkpoint |
| `spawn_agent` | Spawn a sub-agent |
| `inline` | Inline content |
| `invoke_skill` | Invoke another skill |
| `evaluate` | Evaluate an expression |
| `compute` | Compute a value |
| `display` | Display content to user |
| `init_log` | Initialize logging |
| `log_node` | Log node execution |
| `log_entry` | Log an entry with level |
| `log_session_snapshot` | Snapshot current session |
| `finalize_log` | Finalize log file |
| `write_log` | Write log to disk |
| `apply_log_retention` | Apply log retention policy |
| `output_ci_summary` | Output CI summary |
| `set_flag` | Set a boolean flag |
| `mutate_state` | Mutate state (set, append, clear, merge) |
| `set_timestamp` | Set a timestamp |
| `compute_hash` | Compute content hash |
| `evaluate_keywords` | Evaluate keyword matches |
| `parse_intent_flags` | Parse intent flags |
| `match_3vl_rules` | Match 3-value-logic rules |
| `dynamic_route` | Dynamic routing |
| `local_file_ops` | Local file operations (read, write, mkdir, delete) |
| `git_ops_local` | Local git operations (clone, pull, fetch, get-sha) |
| `web_ops` | Web operations (fetch, cache) |
| `run_command` | Run a shell command |
| `install_tool` | Install a tool |

## Deprecated Consequence Type Mappings

| Old Type | New Type | Operation Parameter |
|----------|----------|---------------------|
| `read_file` | `local_file_ops` | `operation: read` |
| `write_file` | `local_file_ops` | `operation: write` |
| `create_directory` | `local_file_ops` | `operation: mkdir` |
| `delete_file` | `local_file_ops` | `operation: delete` |
| `clone_repo` | `git_ops_local` | `operation: clone` |
| `git_pull` | `git_ops_local` | `operation: pull` |
| `git_fetch` | `git_ops_local` | `operation: fetch` |
| `get_sha` | `git_ops_local` | `operation: get-sha` |
| `web_fetch` | `web_ops` | `operation: fetch` |
| `cache_web_content` | `web_ops` | `operation: cache` |
| `run_script` | `run_command` | `interpreter: auto` |
| `run_python` | `run_command` | `interpreter: python` |
| `run_bash` | `run_command` | `interpreter: bash` |
| `set_state` | `mutate_state` | `operation: set` |
| `append_state` | `mutate_state` | `operation: append` |
| `clear_state` | `mutate_state` | `operation: clear` |
| `merge_state` | `mutate_state` | `operation: merge` |
| `log_event` | `log_entry` | `level: info` |
| `log_warning` | `log_entry` | `level: warning` |
| `log_error` | `log_entry` | `level: error` |
| `display_message` | `display` | `format: text` |
| `display_table` | `display` | `format: table` |

## Deprecated Precondition Type Mappings

| Old Type | New Type | Parameter |
|----------|----------|-----------|
| `flag_set` | `state_check` | `operator: true` |
| `flag_not_set` | `state_check` | `operator: false` |
| `state_equals` | `state_check` | `operator: equals` |
| `state_not_null` | `state_check` | `operator: not_null` |
| `state_is_null` | `state_check` | `operator: null` |
| `file_exists` | `path_check` | `check: exists` |
| `directory_exists` | `path_check` | `check: is_directory` |
| `config_exists` | `path_check` | `check: exists` |
| `tool_available` | `tool_check` | `capability: available` |
| `tool_version_gte` | `tool_check` | `capability: version_gte` |
| `tool_authenticated` | `tool_check` | `capability: authenticated` |
| `count_equals` | `evaluate_expression` | expression form |
| `count_above` | `evaluate_expression` | expression form |
| `count_below` | `evaluate_expression` | expression form |

## Composite Type Recursion

Composite precondition types (`all_of`, `any_of`, `none_of`, `xor_of`) contain a
`conditions` array. Each element must be recursively validated as a precondition.
