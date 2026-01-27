# Embedded Type Definitions

This directory contains embedded fallback type definitions for offline/airgapped scenarios.

## Usage

Reference in workflow.yaml:

```yaml
# Option 1: Fallback to embedded on fetch failure
definitions:
  source: hiivmind/hiivmind-blueprint-types@v1.0.0
  fallback: embedded

# Option 2: Always use local
definitions:
  source: local
  path: ${CLAUDE_PLUGIN_ROOT}/lib/types/bundle.yaml
```

## Contents

| File | Description |
|------|-------------|
| `bundle.yaml` | Aggregated type definitions (43 consequences, 27 preconditions) |

## Source

These definitions are extracted from [hiivmind-blueprint-types](https://github.com/hiivmind/hiivmind-blueprint-types).

For the authoritative, versioned source, reference the GitHub release:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-types@v1.0.0
```

## Updating

To update embedded definitions:

1. Download the latest bundle from GitHub releases
2. Replace `bundle.yaml` with the new version
3. Update the version comment in the file header

## Type Inventory

### Consequences (43)

| Category | Count | Types |
|----------|-------|-------|
| core/state | 5 | set_flag, set_state, append_state, clear_state, merge_state |
| core/evaluation | 2 | evaluate, compute |
| core/interaction | 2 | display_message, display_table |
| core/control | 3 | create_checkpoint, rollback_checkpoint, spawn_agent |
| core/skill | 2 | invoke_pattern, invoke_skill |
| core/utility | 2 | set_timestamp, compute_hash |
| core/intent | 4 | evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route |
| core/logging | 10 | init_log, log_node, log_event, log_warning, log_error, log_session_snapshot, finalize_log, write_log, apply_log_retention, output_ci_summary |
| extensions/file-system | 4 | read_file, write_file, create_directory, delete_file |
| extensions/git | 4 | clone_repo, get_sha, git_pull, git_fetch |
| extensions/web | 2 | web_fetch, cache_web_content |
| extensions/scripting | 3 | run_script, run_python, run_bash |

### Preconditions (27)

| Category | Count | Types |
|----------|-------|-------|
| core/filesystem | 5 | config_exists, index_exists, index_is_placeholder, file_exists, directory_exists |
| core/state | 8 | flag_set, flag_not_set, state_equals, state_not_null, state_is_null, count_equals, count_above, count_below |
| core/tool | 2 | tool_available, python_module_available |
| core/composite | 3 | all_of, any_of, none_of |
| core/expression | 1 | evaluate_expression |
| core/logging | 3 | log_initialized, log_level_enabled, log_finalized |
| extensions/source | 3 | source_exists, source_cloned, source_has_updates |
| extensions/web | 2 | fetch_succeeded, fetch_returned_content |
