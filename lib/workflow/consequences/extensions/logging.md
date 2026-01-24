# Logging Consequences

Generic workflow execution logging for audit trails, debugging, and CI integration. These consequences are domain-agnostic and can be extended by plugins with custom event types.

---

## Overview

| Consequence | Purpose |
|-------------|---------|
| `init_log` | Initialize log structure with workflow metadata |
| `log_node` | Record node execution in history |
| `log_event` | Log structured domain-specific events |
| `log_warning` | Add warning message to log |
| `log_error` | Add error with context to log |
| `finalize_log` | Complete log with timing and outcome |
| `write_log` | Write log to file in specified format |
| `apply_log_retention` | Clean up old log files per retention policy |
| `output_ci_summary` | Format output for CI environments |

**Total logging consequences:** 9

---

## init_log

Initialize the log structure at workflow start. Should be called once at the beginning of workflow execution.

```yaml
- type: init_log
  workflow_name: "${workflow.id}"
  workflow_version: "${workflow.version}"
  skill_name: "${initial_state.skill_name}"
  plugin_name: "${initial_state.plugin_name}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `workflow_name` | string | Yes | Workflow identifier |
| `workflow_version` | string | No | Workflow version (default: "1.0") |
| `skill_name` | string | No | Name of invoking skill |
| `plugin_name` | string | No | Name of parent plugin |
| `execution_path` | string | No | Skill/command path (auto-detected) |

**Effect:**
```
state.log = {
  metadata: {
    workflow_name: workflow_name,
    workflow_version: workflow_version ?? "1.0",
    skill_name: skill_name ?? null,
    plugin_name: plugin_name ?? null,
    execution_path: execution_path ?? cwd
  },
  parameters: extract_flags(initial_state.flags),
  execution: {
    start_time: now_iso8601(),
    end_time: null,
    duration_seconds: null,
    outcome: null,
    ending_node: null
  },
  node_history: [],
  events: [],
  warnings: [],
  errors: [],
  summary: null
}
state.flags.log_initialized = true
```

**Level gate:** Always executes (logging initialization is level-independent).

---

## log_node

Record node execution in the log history. Captures timing, outcome, and optional details.

```yaml
- type: log_node
  node: "${current_node.id}"
  outcome: "success"
  details:
    files_processed: "${computed.file_count}"
    duration_ms: "${computed.step_duration}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `node` | string | Yes | Node identifier |
| `outcome` | string | Yes | Execution result: success, skipped, error, blocked |
| `details` | object | No | Arbitrary key-value pairs for context |

**Effect:**
```
if logging.level >= "info":
  state.log.node_history.push({
    node: node,
    timestamp: now_iso8601(),
    outcome: outcome,
    details: details ?? {}
  })
```

**Level gate:** Requires `info` level or higher.

---

## log_event

Log a structured domain-specific event. This is the primary mechanism for plugins to add custom logging without defining new consequences.

```yaml
- type: log_event
  event_type: "source_checked"
  data:
    source_id: "${source.id}"
    status: "up_to_date"
    commits_behind: 0
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `event_type` | string | Yes | Domain-specific event identifier |
| `data` | object | No | Event payload (arbitrary structure) |
| `level` | string | No | Minimum level to record (default: "info") |

**Effect:**
```
effective_level = level ?? "info"
if logging.level >= effective_level:
  state.log.events.push({
    type: event_type,
    timestamp: now_iso8601(),
    data: data ?? {}
  })
```

**Level gate:** Configurable per-event via `level` parameter.

**Domain Examples:**

```yaml
# Corpus: source status
- type: log_event
  event_type: "source_status"
  data:
    source_id: "${source.id}"
    type: "${source.type}"
    status: "${computed.source_status}"

# GitHub: operation executed
- type: log_event
  event_type: "gh_operation"
  data:
    domain: "issues"
    operation: "create"
    issue_number: "${computed.issue_number}"

# Build: artifact created
- type: log_event
  event_type: "artifact_created"
  data:
    path: "${computed.output_path}"
    size_bytes: "${computed.size}"
    checksum: "${computed.sha256}"
```

---

## log_warning

Add a warning message to the log. Warnings indicate potential issues that don't prevent execution.

```yaml
- type: log_warning
  message: "Source ${source.id} has uncommitted changes"
  context:
    source_id: "${source.id}"
    dirty_files: "${computed.dirty_count}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `message` | string | Yes | Warning message |
| `context` | object | No | Additional context for debugging |
| `node` | string | No | Node that generated warning (auto-detected) |

**Effect:**
```
if logging.level >= "warn":
  state.log.warnings.push({
    message: message,
    timestamp: now_iso8601(),
    node: node ?? current_node.id,
    context: context ?? {}
  })
```

**Level gate:** Requires `warn` level or higher.

---

## log_error

Add an error to the log with detailed context. Errors indicate failures that may affect outcome.

```yaml
- type: log_error
  message: "Failed to clone repository"
  error_type: "git_clone_failed"
  context:
    url: "${source.url}"
    exit_code: "${computed.exit_code}"
    stderr: "${computed.stderr}"
  recoverable: false
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `message` | string | Yes | Error message |
| `error_type` | string | No | Error classification |
| `context` | object | No | Error details for debugging |
| `node` | string | No | Node that generated error (auto-detected) |
| `recoverable` | boolean | No | Whether workflow continued (default: false) |

**Effect:**
```
if logging.level >= "error":
  state.log.errors.push({
    message: message,
    error_type: error_type ?? "unknown",
    timestamp: now_iso8601(),
    node: node ?? current_node.id,
    context: context ?? {},
    recoverable: recoverable ?? false
  })
```

**Level gate:** Requires `error` level or higher.

---

## finalize_log

Complete the log with execution timing, outcome, and summary. Should be called at workflow end (success, error, or cancel).

```yaml
- type: finalize_log
  outcome: "success"
  ending_node: "complete"
  summary: "Processed ${computed.source_count} sources, updated ${computed.updated_count}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `outcome` | string | Yes | Final result: success, partial, error, cancelled |
| `ending_node` | string | No | Last executed node (auto-detected) |
| `summary` | string | No | Human-readable execution summary |

**Effect:**
```
state.log.execution.end_time = now_iso8601()
state.log.execution.duration_seconds = time_diff_seconds(
  state.log.execution.start_time,
  state.log.execution.end_time
)
state.log.execution.outcome = outcome
state.log.execution.ending_node = ending_node ?? current_node.id
state.log.summary = summary ?? auto_generate_summary()
state.flags.log_finalized = true
```

**Outcome semantics:**
| Outcome | Meaning |
|---------|---------|
| `success` | Workflow completed all intended operations |
| `partial` | Some operations completed, some skipped/failed |
| `error` | Workflow failed to complete due to error |
| `cancelled` | User or system cancelled execution |

---

## write_log

Write the finalized log to a file. Supports multiple output formats.

```yaml
- type: write_log
  format: "yaml"
  path: ".logs/${workflow.id}-${timestamp}.yaml"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `format` | string | No | Output format: yaml, json, markdown (default: yaml) |
| `path` | string | No | Output path (supports interpolation, see defaults) |
| `include_node_history` | boolean | No | Include node_history array (default: true) |
| `include_events` | boolean | No | Include events array (default: true) |

**Path defaults:**
```
# Default path pattern:
".logs/{skill_name}-{YYYYMMDD-HHMMSS}.{ext}"

# Extension based on format:
yaml → .yaml
json → .json
markdown → .md
```

**Effect:**
```
log_content = format_log(state.log, format, {
  include_node_history: include_node_history ?? true,
  include_events: include_events ?? true
})
mkdir -p dirname(path)
write_file(path, log_content)
state.computed.log_path = path
```

**Format examples:**

YAML (default):
```yaml
metadata:
  workflow_name: hiivmind-corpus-refresh
  skill_name: refresh
  plugin_name: hiivmind-corpus-polars
execution:
  start_time: "2024-01-15T10:30:00Z"
  end_time: "2024-01-15T10:30:45Z"
  duration_seconds: 45
  outcome: success
# ...
```

Markdown:
```markdown
# Execution Log: hiivmind-corpus-refresh

**Outcome:** ✅ Success
**Duration:** 45 seconds
**Timestamp:** 2024-01-15T10:30:00Z

## Summary
Checked 3 sources, updated 1

## Node History
| Node | Outcome | Time |
|------|---------|------|
| validate_config | success | 10:30:01 |
...
```

---

## apply_log_retention

Clean up old log files according to retention policy.

```yaml
- type: apply_log_retention
  path: ".logs/"
  strategy: "count"
  count: 10
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `path` | string | Yes | Directory containing logs |
| `strategy` | string | Yes | Retention strategy: none, days, count |
| `days` | number | Conditional | Max age in days (required if strategy=days) |
| `count` | number | Conditional | Max files to keep (required if strategy=count) |
| `pattern` | string | No | Glob pattern for log files (default: "*.yaml") |

**Effect:**
```
if strategy == "none":
  return  # No cleanup

files = glob(path, pattern ?? "*.yaml").sort_by_mtime()

if strategy == "count":
  to_delete = files[count:]  # Keep newest {count}
elif strategy == "days":
  cutoff = now() - days * 86400
  to_delete = files.filter(f => mtime(f) < cutoff)

for file in to_delete:
  delete_file(file)

state.computed.logs_deleted = len(to_delete)
```

---

## output_ci_summary

Format and output log summary for CI environments (GitHub Actions, etc.).

```yaml
- type: output_ci_summary
  format: "github"
  annotations: true
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `format` | string | No | CI format: github, plain, json, none (default: from config) |
| `annotations` | boolean | No | Emit annotations for errors/warnings (default: true) |
| `output_file` | string | No | Override GITHUB_STEP_SUMMARY path |

**Effect:**
```
if format == "none":
  return

if format == "github":
  # Write to GITHUB_STEP_SUMMARY
  summary_path = output_file ?? env.GITHUB_STEP_SUMMARY
  append_file(summary_path, format_github_summary(state.log))

  if annotations:
    for error in state.log.errors:
      echo "::error file={error.context.file},line={error.context.line}::{error.message}"
    for warning in state.log.warnings:
      echo "::warning::{warning.message}"

elif format == "plain":
  print(format_plain_summary(state.log))

elif format == "json":
  print(json_dumps(state.log))
```

**GitHub summary format:**
```markdown
## Workflow: hiivmind-corpus-refresh

| Metric | Value |
|--------|-------|
| Outcome | ✅ success |
| Duration | 45s |
| Nodes Executed | 12 |
| Warnings | 1 |
| Errors | 0 |

<details>
<summary>Node History</summary>

| Node | Outcome |
|------|---------|
| validate | ✅ |
| check_sources | ✅ |
...
</details>
```

---

## Automatic Logging (Auto-Mode)

When `logging.auto` is enabled, the framework automatically invokes logging consequences:

| Auto Setting | Consequence | When |
|--------------|-------------|------|
| `auto.init` | `init_log` | Before first node executes |
| `auto.node_tracking` | `log_node` | After each node completes |
| `auto.finalize` | `finalize_log` | At any ending node |
| `auto.write` | `write_log` | After finalize_log |

**Configuration:**
```yaml
initial_state:
  logging:
    auto:
      init: true           # Default
      node_tracking: true  # Default
      finalize: true       # Default
      write: true          # Default
```

Disable auto-logging to manage logging manually:
```yaml
initial_state:
  logging:
    auto:
      init: false     # Skill calls init_log explicitly
      finalize: false # Skill manages its own finalization
```

---

## Common Patterns

### Basic Workflow Logging

```yaml
phases:
  - id: setup
    nodes:
      - id: init_logging
        type: action
        consequences:
          - type: init_log
            workflow_name: "my-workflow"

  - id: process
    nodes:
      - id: do_work
        type: action
        consequences:
          - type: log_node
            node: "do_work"
            outcome: "success"

  - id: complete
    nodes:
      - id: finalize
        type: action
        ending: success
        consequences:
          - type: finalize_log
            outcome: "success"
          - type: write_log
            format: "yaml"
          - type: apply_log_retention
            path: ".logs/"
            strategy: "count"
            count: 10
```

### Conditional Error Logging

```yaml
- id: check_result
  type: conditional
  condition:
    type: state_equals
    field: computed.exit_code
    value: 0
  then: continue_processing
  else: log_failure

- id: log_failure
  type: action
  consequences:
    - type: log_error
      message: "Operation failed"
      context:
        exit_code: "${computed.exit_code}"
        stderr: "${computed.stderr}"
    - type: finalize_log
      outcome: "error"
```

### Domain Event Logging

```yaml
# Log domain-specific events for audit trail
- id: update_index
  type: action
  consequences:
    - type: log_event
      event_type: "index_updated"
      data:
        entries_added: "${computed.added_count}"
        entries_removed: "${computed.removed_count}"
        index_size: "${computed.total_entries}"
```

---

## Related Documentation

- **Parent:** [README.md](README.md) - Extension overview
- **Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Layered config
- **Schema:** `lib/workflow/logging-schema.md` - Log structure definition
- **Core consequences:** [../core/](../core/) - Fundamental workflow operations
- **Preconditions:** `lib/workflow/preconditions.md` - log_initialized, log_level_enabled
