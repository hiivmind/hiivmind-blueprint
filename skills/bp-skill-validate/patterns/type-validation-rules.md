> **Used by:** `SKILL.md` Phase 5

# Type Validation Rules

Valid type references for {computed.lib_version}, deprecated type detection, and migration suggestions.

---

## Valid Precondition Types ({computed.lib_version})

13 types across 10 categories:

| Category | Type | Required Parameters | Optional Parameters |
|----------|------|-------------------|-------------------|
| core/composite | `all_of` | `conditions` (array) | - |
| core/composite | `any_of` | `conditions` (array) | - |
| core/composite | `none_of` | `conditions` (array) | - |
| core/composite | `xor_of` | `conditions` (array) | - |
| core/expression | `evaluate_expression` | `expression` (string) | - |
| core/state | `state_check` | `field`, `operator` | `value` (for equals/not_equals) |
| core/filesystems | `path_check` | `path`, `check` | `args` (for contains_text) |
| core/logging | `log_state` | `aspect` | `args` (for level_enabled) |
| core/tools | `tool_check` | `tool`, `capability` | `args` (for version_gte) |
| core/python | `python_module_available` | `module` | - |
| core/network | `network_available` | - | `target` |
| core/git | `source_check` | `source_id`, `aspect` | - |
| core/web_fetch | `fetch_check` | `from`, `aspect` | - |

### Parameter Enums

| Type | Parameter | Valid Values |
|------|-----------|-------------|
| `state_check` | `operator` | `equals`, `not_equals`, `null`, `not_null`, `true`, `false` |
| `path_check` | `check` | `exists`, `is_file`, `is_directory`, `contains_text` |
| `tool_check` | `capability` | `available`, `version_gte`, `authenticated`, `daemon_ready` |
| `log_state` | `aspect` | `initialized`, `finalized`, `level_enabled` |
| `source_check` | `aspect` | `exists`, `cloned`, `has_updates` |
| `fetch_check` | `aspect` | `succeeded`, `has_content` |

### Composite Type Recursion

Composite types (`all_of`, `any_of`, `none_of`, `xor_of`) contain nested `conditions` arrays. Each element must itself be a valid precondition. Validation must recurse:

```
function validate_precondition(condition, context):
    if condition.type in ["all_of", "any_of", "none_of", "xor_of"]:
        if "conditions" not in condition or not is_array(condition.conditions):
            report_error("${context}: composite '${condition.type}' requires 'conditions' array")
            return
        if len(condition.conditions) == 0:
            report_warning("${context}: composite '${condition.type}' has empty conditions array")
        for i, sub in enumerate(condition.conditions):
            validate_precondition(sub, "${context}.conditions[${i}]")
    else:
        // Validate leaf precondition type and required params
        validate_leaf_precondition(condition, context)
```

---

## Valid Consequence Types ({computed.lib_version})

31 types across 12 categories:

| Category | Type | Required Parameters | Optional Parameters |
|----------|------|-------------------|-------------------|
| core/control | `create_checkpoint` | `name` | - |
| core/control | `rollback_checkpoint` | `name` | - |
| core/control | `spawn_agent` | `subagent_type`, `prompt` | `store_as` |
| core/control | `inline` | `description`, `pseudocode` | `store_as` |
| core/control | `invoke_skill` | `skill` | `args` |
| core/evaluation | `evaluate` | `expression`, `set_flag` | - |
| core/evaluation | `compute` | `expression`, `store_as` | - |
| core/interaction | `display` | `format`, `content` | `title`, `headers` |
| core/logging | `init_log` | - | `workflow_name`, `workflow_version` |
| core/logging | `log_node` | - | `node`, `outcome`, `details` |
| core/logging | `log_entry` | `level`, `message` | `context`, `error_type` |
| core/logging | `log_session_snapshot` | - | `description`, `write_intermediate` |
| core/logging | `finalize_log` | `outcome` | `summary` |
| core/logging | `write_log` | - | `format`, `path` |
| core/logging | `apply_log_retention` | `path` | `strategy`, `count`, `days` |
| core/logging | `output_ci_summary` | - | `format`, `annotations` |
| core/state | `set_flag` | `flag` | `value` |
| core/state | `mutate_state` | `operation`, `field` | `value` |
| core/utility | `set_timestamp` | `store_as` | - |
| core/utility | `compute_hash` | `from`, `store_as` | - |
| core/intent | `evaluate_keywords` | `input`, `keyword_sets`, `store_as` | - |
| core/intent | `parse_intent_flags` | `input`, `flag_definitions`, `store_as` | - |
| core/intent | `match_3vl_rules` | `flags`, `rules`, `store_as` | - |
| core/intent | `dynamic_route` | `action` | - |
| extensions/file-system | `local_file_ops` | `operation`, `path` | `content`, `store_as` |
| extensions/git | `git_ops_local` | `operation` | `repo_path`, `args`, `store_as` |
| extensions/web | `web_ops` | `operation` | `url`, `store_as`, `from`, `dest`, `prompt` |
| extensions/scripting | `run_command` | - | `interpreter`, `script`, `args`, `store_as`, `env`, `venv` |
| extensions/package | `install_tool` | `tool` | `install_command`, `skip_if_available` |

### Parameter Enums

| Type | Parameter | Valid Values |
|------|-----------|-------------|
| `display` | `format` | `text`, `table`, `json`, `markdown` |
| `log_entry` | `level` | `debug`, `info`, `warning`, `error` |
| `mutate_state` | `operation` | `set`, `append`, `clear`, `merge` |
| `local_file_ops` | `operation` | `read`, `write`, `mkdir`, `delete` |
| `git_ops_local` | `operation` | `clone`, `pull`, `fetch`, `get-sha` |
| `web_ops` | `operation` | `fetch`, `cache` |
| `run_command` | `interpreter` | `auto`, `bash`, `python`, `node`, `ruby` |

---

## Deprecated Type Detection

### Deprecated Consequence Types

| Deprecated Type | Replacement | Operation Parameter | Category |
|----------------|-------------|-------------------|----------|
| `read_file` | `local_file_ops` | `operation: read` | File ops |
| `write_file` | `local_file_ops` | `operation: write` | File ops |
| `create_directory` | `local_file_ops` | `operation: mkdir` | File ops |
| `delete_file` | `local_file_ops` | `operation: delete` | File ops |
| `clone_repo` | `git_ops_local` | `operation: clone` | Git ops |
| `git_pull` | `git_ops_local` | `operation: pull` | Git ops |
| `git_fetch` | `git_ops_local` | `operation: fetch` | Git ops |
| `get_sha` | `git_ops_local` | `operation: get-sha` | Git ops |
| `web_fetch` | `web_ops` | `operation: fetch` | Web ops |
| `cache_web_content` | `web_ops` | `operation: cache` | Web ops |
| `run_script` | `run_command` | `interpreter: auto` | Scripting |
| `run_python` | `run_command` | `interpreter: python` | Scripting |
| `run_bash` | `run_command` | `interpreter: bash` | Scripting |
| `set_state` | `mutate_state` | `operation: set` | State |
| `append_state` | `mutate_state` | `operation: append` | State |
| `clear_state` | `mutate_state` | `operation: clear` | State |
| `merge_state` | `mutate_state` | `operation: merge` | State |
| `log_event` | `log_entry` | `level: info` | Logging |
| `log_warning` | `log_entry` | `level: warning` | Logging |
| `log_error` | `log_entry` | `level: error` | Logging |
| `display_message` | `display` | `format: text` | Display |
| `display_table` | `display` | `format: table` | Display |

### Deprecated Precondition Types

| Deprecated Type | Replacement | Parameter | Category |
|----------------|-------------|-----------|----------|
| `flag_set` | `state_check` | `operator: "true"` | State |
| `flag_not_set` | `state_check` | `operator: "false"` | State |
| `state_equals` | `state_check` | `operator: equals` | State |
| `state_not_null` | `state_check` | `operator: not_null` | State |
| `state_is_null` | `state_check` | `operator: "null"` | State |
| `file_exists` | `path_check` | `check: is_file` | Filesystem |
| `directory_exists` | `path_check` | `check: is_directory` | Filesystem |
| `config_exists` | `path_check` | `check: is_file` | Filesystem |
| `index_exists` | `path_check` | `check: exists` | Filesystem |
| `tool_available` | `tool_check` | `capability: available` | Tools |
| `tool_version_gte` | `tool_check` | `capability: version_gte` | Tools |
| `tool_authenticated` | `tool_check` | `capability: authenticated` | Tools |
| `tool_daemon_ready` | `tool_check` | `capability: daemon_ready` | Tools |
| `source_exists` | `source_check` | `aspect: exists` | Git |
| `source_cloned` | `source_check` | `aspect: cloned` | Git |
| `source_has_updates` | `source_check` | `aspect: has_updates` | Git |
| `log_initialized` | `log_state` | `aspect: initialized` | Logging |
| `log_finalized` | `log_state` | `aspect: finalized` | Logging |
| `log_level_enabled` | `log_state` | `aspect: level_enabled` | Logging |
| `fetch_succeeded` | `fetch_check` | `aspect: succeeded` | Web |
| `fetch_returned_content` | `fetch_check` | `aspect: has_content` | Web |
| `count_equals` | `evaluate_expression` | `expression: "len(field) == N"` | Expression |
| `count_above` | `evaluate_expression` | `expression: "len(field) > N"` | Expression |
| `count_below` | `evaluate_expression` | `expression: "len(field) < N"` | Expression |

### Deprecated Node Type

| Deprecated Type | Replacement | Migration |
|----------------|-------------|-----------|
| `validation_gate` | `conditional` | Add `audit: { enabled: true, output: computed.validation_errors }` |

---

## Migration Suggestion Format

When a deprecated type is detected, produce a suggestion in this format:

**For consequences:**
```
[WARN] Node '${node_id}' action[${i}]: type '${old_type}' is deprecated (v2.x).
  Replace with:
    type: ${new_type}
    operation: ${operation}
  See: ${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md
```

**For preconditions:**
```
[WARN] Node '${node_id}' condition: type '${old_type}' is deprecated (v2.x).
  Replace with:
    type: ${new_type}
    ${param_name}: ${param_value}
  See: ${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md
```

**For validation_gate node type:**
```
[WARN] Node '${node_id}': type 'validation_gate' was removed in v2.0.
  Replace with:
    type: conditional
    condition:
      type: all_of
      conditions: [... move validations here ...]
    audit:
      enabled: true
      output: computed.validation_errors
    branches:
      on_true: ${proceed_node}
      on_false: ${error_node}
  See: ${CLAUDE_PLUGIN_ROOT}/references/node-features.md (Audit Mode section)
```

---

## Validation Pseudocode Summary

```
function validate_all_types(workflow):
    issues = []

    // 1. Entry preconditions
    if "entry_preconditions" in workflow:
        for i, precond in enumerate(workflow.entry_preconditions):
            issues.extend(validate_precondition_type(precond, "entry_preconditions[${i}]"))

    // 2. Node conditions (conditional nodes)
    for node_id, node in workflow.nodes:
        if node.type == "conditional" and "condition" in node:
            issues.extend(validate_precondition_type(node.condition, "nodes.${node_id}.condition"))

    // 3. Action consequences
    for node_id, node in workflow.nodes:
        if node.type == "action" and "actions" in node:
            for i, action in enumerate(node.actions):
                issues.extend(validate_consequence_type(action, "nodes.${node_id}.actions[${i}]"))

    // 4. User prompt response consequences
    for node_id, node in workflow.nodes:
        if node.type == "user_prompt" and "on_response" in node:
            for handler_id, handler in node.on_response:
                if "consequence" in handler:
                    for i, action in enumerate(handler.consequence):
                        issues.extend(validate_consequence_type(
                            action,
                            "nodes.${node_id}.on_response.${handler_id}.consequence[${i}]"
                        ))

    return issues
```

---

## Related Documentation

- **Consequences Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
- **Preconditions Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
- **{computed.lib_version} Migration Guide:** `hiivmind/hiivmind-blueprint-lib@{computed.lib_version}/docs/v3-migration.md`
- **Workflow Generation (type quick ref):** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
