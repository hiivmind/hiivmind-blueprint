# Migration Table

> **Used by:** `SKILL.md` Phase 2, Step 2.2 and Phase 3
> **Schema versions:** 2.0 -> 2.1 -> 2.2 -> 2.3 -> 2.4
> **Type definitions:** [hiivmind-blueprint-lib {computed.lib_version}](https://github.com/hiivmind/hiivmind-blueprint-lib/tree/{computed.lib_version})

This document provides the complete before/after YAML examples for each migration step.
Each section shows exactly what changes structurally in the workflow.yaml file.

---

## Migration 2.0 -> 2.1: Remove validation_gate Nodes

The `validation_gate` node type was deprecated in v2.1 and replaced by `conditional` nodes
with `audit` configuration. The audit mode evaluates all conditions without short-circuiting
and collects per-condition error messages.

### Before (v2.0)

```yaml
nodes:
  validate_prerequisites:
    type: validation_gate
    description: "Check all prerequisites"
    validations:
      - type: file_exists
        path: "${config_path}"
        error_message: "Config file not found at ${config_path}"
      - type: tool_available
        tool: "git"
        error_message: "Git is required but not installed"
      - type: tool_available
        tool: "jq"
        error_message: "jq is required but not installed"
    on_valid: proceed_with_setup
    on_invalid: show_validation_errors
```

### After (v2.1)

```yaml
nodes:
  validate_prerequisites:
    type: conditional
    description: "Check all prerequisites"
    condition:
      type: all_of
      conditions:
        - type: file_exists
          path: "${config_path}"
        - type: tool_available
          tool: "git"
        - type: tool_available
          tool: "jq"
    audit:
      enabled: true
      output: computed.validation_errors
      messages:
        file_exists: "Config file not found at ${config_path}"
        tool_available: "Required tool not installed"
    branches:
      on_true: proceed_with_setup
      on_false: show_validation_errors
```

### Field Mapping

| v2.0 Field | v2.1 Field |
|------------|------------|
| `type: validation_gate` | `type: conditional` |
| `validations[]` | `condition.conditions[]` |
| `validations[].error_message` | `audit.messages[type]` |
| `on_valid` | `branches.on_true` |
| `on_invalid` | `branches.on_false` |
| _(not present)_ | `audit.enabled: true` |
| _(not present)_ | `audit.output: computed.validation_errors` |

### Edge Cases

- If a `validation_gate` has only one validation, it still becomes a `conditional` with
  `all_of` containing a single condition. This keeps the pattern consistent.
- If multiple validations share the same type (e.g., two `file_exists` checks), the audit
  messages key must be disambiguated by appending an index: `file_exists_0`, `file_exists_1`.
- The `audit.output` field defaults to `computed.validation_errors` but can be customized
  per node if the workflow uses multiple validation gates.

---

## Migration 2.1 -> 2.2: Unify Output Config

In v2.1, logging and display were configured separately under `initial_state.logging` and
`initial_state.display`. In v2.2, these are merged into a single `initial_state.output`
configuration.

### Before (v2.1)

```yaml
initial_state:
  phase: "start"
  logging:
    enabled: true
    level: "info"
    format: "yaml"
    location: ".logs/"
    ci_mode: false
    retention:
      strategy: "count"
      count: 10
  display:
    enabled: true
    batch:
      enabled: true
      threshold: 3
    use_icons: true
```

### After (v2.2)

```yaml
initial_state:
  phase: "start"
  output:
    level: "normal"
    display_enabled: true
    batch_enabled: true
    batch_threshold: 3
    use_icons: true
    log_enabled: true
    log_format: "yaml"
    log_location: ".logs/"
    ci_mode: false
```

### Field Mapping

| v2.1 Field | v2.2 Field | Default |
|------------|------------|---------|
| `logging.enabled` | `output.log_enabled` | `true` |
| `logging.level` | `output.level` | `"normal"` |
| `logging.format` | `output.log_format` | `"yaml"` |
| `logging.location` | `output.log_location` | `".logs/"` |
| `logging.ci_mode` | `output.ci_mode` | `false` |
| `display.enabled` | `output.display_enabled` | `true` |
| `display.batch.enabled` | `output.batch_enabled` | `true` |
| `display.batch.threshold` | `output.batch_threshold` | `3` |
| `display.use_icons` | `output.use_icons` | `true` |

### Notes

- The `logging.retention` block is removed in v2.2. Retention is now managed at the engine
  level, not per-workflow.
- The `logging.level` mapping: `"info"` maps to `"normal"`, `"debug"` maps to `"debug"`,
  `"warning"` maps to `"quiet"`.
  Level mapping table: `info -> normal`, `debug -> debug`, `warning -> quiet`, `error -> silent`.
- If neither `logging` nor `display` existed in v2.1, the full output config is created
  with all defaults.

---

## Migration 2.2 -> 2.3: Add Prompts Configuration

In v2.3, a `prompts` configuration is added under `initial_state` to support multi-modal
prompt delivery (Claude Code interactive, web forms, API structured responses, autonomous
agent mode).

### Before (v2.2)

```yaml
initial_state:
  phase: "start"
  output:
    level: "normal"
    display_enabled: true
    batch_enabled: true
    batch_threshold: 3
    use_icons: true
    log_enabled: true
    log_format: "yaml"
    log_location: ".logs/"
    ci_mode: false
```

### After (v2.3)

```yaml
initial_state:
  phase: "start"
  output:
    level: "normal"
    display_enabled: true
    batch_enabled: true
    batch_threshold: 3
    use_icons: true
    log_enabled: true
    log_format: "yaml"
    log_location: ".logs/"
    ci_mode: false
  prompts:
    interface: "auto"
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.7
```

### New Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `prompts.interface` | string | `"auto"` | Auto-detect interface or specify explicitly |
| `prompts.modes.claude_code` | string | `"interactive"` | Prompt mode when running in Claude Code CLI |
| `prompts.modes.web` | string | `"forms"` | Prompt mode when running in web interface |
| `prompts.modes.api` | string | `"structured"` | Prompt mode when invoked via API |
| `prompts.modes.agent` | string | `"autonomous"` | Prompt mode when running as agent sub-task |
| `prompts.tabular.match_strategy` | string | `"prefix"` | How to match tabular option selections |
| `prompts.tabular.other_handler` | string | `"prompt"` | How to handle unmatched tabular input |
| `prompts.autonomous.strategy` | string | `"best_match"` | Decision strategy in autonomous mode |
| `prompts.autonomous.confidence_threshold` | float | `0.7` | Minimum confidence for auto-selection |

### Notes

- This migration is additive only. No existing fields are modified or removed.
- If the workflow has no `user_prompt` nodes, the prompts config is still added for
  forward compatibility. The engine ignores it when no prompts are encountered.

---

## Migration 2.3 -> 2.4: Required Configs

In v2.4, both `output` and `prompts` configurations under `initial_state` become required
fields. Previously they were optional with engine-level defaults; now they must be explicitly
present in the workflow.yaml.

### Before (v2.3 -- minimal, configs optional)

```yaml
initial_state:
  phase: "start"
  computed: {}
```

### After (v2.4 -- configs required, defaults filled)

```yaml
initial_state:
  phase: "start"
  computed: {}
  output:
    level: "normal"
    display_enabled: true
    batch_enabled: true
    batch_threshold: 3
    use_icons: true
    log_enabled: true
    log_format: "yaml"
    log_location: ".logs/"
    ci_mode: false
  prompts:
    interface: "auto"
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.7
```

### Required Output Fields (v2.4)

| Field | Required | Default |
|-------|----------|---------|
| `output.level` | Yes | `"normal"` |
| `output.display_enabled` | Yes | `true` |
| `output.batch_enabled` | Yes | `true` |
| `output.batch_threshold` | Yes | `3` |
| `output.use_icons` | Yes | `true` |
| `output.log_enabled` | Yes | `true` |
| `output.log_format` | Yes | `"yaml"` |
| `output.log_location` | Yes | `".logs/"` |
| `output.ci_mode` | Yes | `false` |

### Required Prompts Fields (v2.4)

| Field | Required | Default |
|-------|----------|---------|
| `prompts.interface` | Yes | `"auto"` |
| `prompts.modes` | Yes | (see defaults above) |
| `prompts.tabular` | Yes | (see defaults above) |
| `prompts.autonomous` | Yes | (see defaults above) |

### Notes

- If a v2.3 workflow already had complete `output` and `prompts` sections, this migration
  is a no-op. The idempotency check in Phase 2 will detect this and skip the step.
- Partial configs (e.g., `output` present but missing `batch_threshold`) are completed
  by filling only the missing fields with defaults. Existing values are preserved.

---

## Type Consolidation Table (v2.x -> v3.0.0)

This consolidation applies to all consequence and precondition types used in nodes.
It runs after schema version migrations as a separate pass.

### Consequence Types

| Old Type (v2.x) | New Type (v3.0.0) | Operation | Notes |
|------------------|-------------------|-----------|-------|
| `read_file` | `local_file_ops` | `read` | Path param preserved |
| `write_file` | `local_file_ops` | `write` | Path + content preserved |
| `create_directory` | `local_file_ops` | `mkdir` | Path param preserved |
| `delete_file` | `local_file_ops` | `delete` | Path param preserved |
| `clone_repo` | `git_ops_local` | `clone` | URL + dest preserved |
| `git_pull` | `git_ops_local` | `pull` | Remote + branch preserved |
| `git_fetch` | `git_ops_local` | `fetch` | Remote preserved |
| `get_sha` | `git_ops_local` | `get-sha` | Ref preserved |
| `web_fetch` | `web_ops` | `fetch` | URL preserved |
| `cache_web_content` | `web_ops` | `cache` | URL + ttl preserved |
| `run_script` | `run_command` | `interpreter: auto` | Command preserved |
| `run_python` | `run_command` | `interpreter: python` | Command preserved |
| `run_bash` | `run_command` | `interpreter: bash` | Command preserved |
| `set_state` | `mutate_state` | `set` | Field + value preserved |
| `append_state` | `mutate_state` | `append` | Field + value preserved |
| `clear_state` | `mutate_state` | `clear` | Field preserved |
| `merge_state` | `mutate_state` | `merge` | Field + value preserved |
| `log_event` | `log_entry` | `level: info` | Message preserved |
| `log_warning` | `log_entry` | `level: warning` | Message preserved |
| `log_error` | `log_entry` | `level: error` | Message preserved |
| `display_message` | `display` | `format: text` | Content preserved |
| `display_table` | `display` | `format: table` | Headers + rows preserved |

### Precondition Types

| Old Type (v2.x) | New Type (v3.0.0) | Parameter | Notes |
|------------------|-------------------|-----------|-------|
| `flag_set` | `state_check` | `operator: true` | Field preserved |
| `flag_not_set` | `state_check` | `operator: false` | Field preserved |
| `state_equals` | `state_check` | `operator: equals` | Field + value preserved |
| `state_not_null` | `state_check` | `operator: not_null` | Field preserved |
| `state_is_null` | `state_check` | `operator: null` | Field preserved |
| `file_exists` | `path_check` | `check: exists` | Path preserved |
| `directory_exists` | `path_check` | `check: is_directory` | Path preserved |
| `config_exists` | `path_check` | `check: exists` | Path preserved |
| `index_exists` | `path_check` | `check: exists` | Path preserved |
| `tool_available` | `tool_check` | `capability: available` | Tool preserved |
| `tool_version_gte` | `tool_check` | `capability: version_gte` | Tool + version preserved |
| `tool_authenticated` | `tool_check` | `capability: authenticated` | Tool preserved |
| `tool_daemon_ready` | `tool_check` | `capability: daemon_ready` | Tool preserved |
| `source_exists` | `source_check` | `aspect: exists` | Source preserved |
| `source_cloned` | `source_check` | `aspect: cloned` | Source preserved |
| `source_has_updates` | `source_check` | `aspect: has_updates` | Source preserved |
| `log_initialized` | `log_state` | `aspect: initialized` | |
| `log_finalized` | `log_state` | `aspect: finalized` | |
| `log_level_enabled` | `log_state` | `aspect: level_enabled` | Level preserved |
| `fetch_succeeded` | `fetch_check` | `aspect: succeeded` | |
| `fetch_returned_content` | `fetch_check` | `aspect: has_content` | |
| `count_equals` | `evaluate_expression` | `len(field) == N` | Rewritten as expression |
| `count_above` | `evaluate_expression` | `len(field) > N` | Rewritten as expression |
| `count_below` | `evaluate_expression` | `len(field) < N` | Rewritten as expression |

### Example: Type Consolidation in a Node

**Before (v2.x types):**

```yaml
setup_workspace:
  type: action
  description: "Set up local workspace"
  actions:
    - type: clone_repo
      url: "${repo_url}"
      destination: "${workspace_dir}"
    - type: set_state
      field: workspace.ready
      value: true
    - type: display_message
      content: "Workspace ready at ${workspace_dir}"
  on_success: check_config
  on_failure: error_clone
```

**After (v3.0.0 types):**

```yaml
setup_workspace:
  type: action
  description: "Set up local workspace"
  actions:
    - type: git_ops_local
      operation: clone
      url: "${repo_url}"
      destination: "${workspace_dir}"
    - type: mutate_state
      operation: set
      field: workspace.ready
      value: true
    - type: display
      format: text
      content: "Workspace ready at ${workspace_dir}"
  on_success: check_config
  on_failure: error_clone
```

---

## Related Documentation

- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Idempotency Guards:** `patterns/idempotency-guards.md`
