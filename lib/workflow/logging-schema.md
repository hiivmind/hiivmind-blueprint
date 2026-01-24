# Logging Schema

Defines the structure of workflow execution logs. This schema is domain-agnostic; plugins extend it with custom event types and domain-specific fields.

---

## Log Structure

```yaml
# Complete log structure
metadata:
  workflow_name: string       # Workflow identifier
  workflow_version: string    # Workflow version
  skill_name: string | null   # Invoking skill name
  plugin_name: string | null  # Parent plugin name
  execution_path: string      # Skill/command path

  # Session tracking (populated when SessionStart hook is installed)
  session:
    id: string | null              # Claude Code session UUID
    transcript_path: string | null # Path to conversation .jsonl
    invocation_index: number       # Which skill invocation in session (1-based)
    snapshot_points: []            # Mid-session snapshot markers

parameters:                   # Captured from initial_state.flags
  key: value                  # Runtime parameters

execution:
  start_time: ISO8601         # Execution start timestamp
  end_time: ISO8601 | null    # Execution end timestamp
  duration_seconds: number | null  # Total duration
  outcome: OutcomeType | null # Final result
  ending_node: string | null  # Last executed node

node_history:                 # Ordered list of executed nodes
  - node: string              # Node identifier
    timestamp: ISO8601        # Execution timestamp
    outcome: NodeOutcome      # Node result
    details: object           # Arbitrary context

events:                       # Domain-specific structured events
  - type: string              # Event type identifier
    timestamp: ISO8601        # Event timestamp
    data: object              # Event payload

warnings:                     # Warning messages
  - message: string           # Warning text
    timestamp: ISO8601        # When warning occurred
    node: string              # Source node
    context: object           # Additional context

errors:                       # Error records
  - message: string           # Error text
    error_type: string        # Error classification
    timestamp: ISO8601        # When error occurred
    node: string              # Source node
    context: object           # Error details
    recoverable: boolean      # Whether execution continued

summary: string | null        # Human-readable summary
```

---

## Field Definitions

### metadata

Static information about the workflow execution context.

| Field | Type | Description |
|-------|------|-------------|
| `workflow_name` | string | Unique workflow identifier (from workflow.id) |
| `workflow_version` | string | Workflow version string (default: "1.0") |
| `skill_name` | string? | Name of the skill that invoked workflow |
| `plugin_name` | string? | Name of the plugin containing the skill |
| `execution_path` | string | Full path to skill/command directory |
| `session` | object? | Claude Code session context (see below) |

### session

Session tracking information. Populated automatically when the SessionStart hook is installed. Enables linking workflow logs to Claude Code conversation transcripts.

| Field | Type | Description |
|-------|------|-------------|
| `id` | string? | Claude Code session UUID |
| `transcript_path` | string? | Path to conversation `.jsonl` file |
| `invocation_index` | number | Which skill invocation in this session (1-based) |
| `snapshot_points` | array | Mid-session snapshot markers (see `log_session_snapshot`) |

**Snapshot point structure:**
```yaml
snapshot_points:
  - timestamp: ISO8601       # When snapshot was taken
    node: string             # Node that triggered snapshot
    description: string      # What decision was made
    log_path: string | null  # Path if intermediate log was written
```

**Session state file:** `.logs/.session-state.yaml`

The `init_log` consequence maintains a session state file to track invocation order across multiple skill calls in a single Claude Code session:

```yaml
current_session:
  id: "608e490e-d5b2-420f-89e0-e64d2e858764"
  invocation_count: 3
  invocations:
    - index: 1
      skill: "corpus-refresh"
      log_path: ".logs/corpus-refresh-20240124-153000.yaml"
      timestamp: "2024-01-24T15:30:00Z"
    - index: 2
      skill: "my-workflow"
      log_path: ".logs/my-workflow-20240124-153500.yaml"
      timestamp: "2024-01-24T15:35:00Z"
    - index: 3
      skill: "corpus-enhance"
      log_path: ".logs/corpus-enhance-20240124-154000.yaml"
      timestamp: "2024-01-24T15:40:00Z"
```

This enables:
- "What skills ran in this session?" → Read session state
- "Show all logs from session X" → Filter by `session.id`
- "What was the sequence?" → Order by `invocation_index`

### parameters

Runtime parameters captured at workflow start. These come from `initial_state.flags` and any runtime overrides.

```yaml
parameters:
  verbose: true
  source_id: "polars"
  force: false
```

### execution

Timing and outcome information for the workflow run.

| Field | Type | Description |
|-------|------|-------------|
| `start_time` | ISO8601 | When execution began |
| `end_time` | ISO8601? | When execution ended (null if in progress) |
| `duration_seconds` | number? | Total execution time |
| `outcome` | OutcomeType? | Final execution result |
| `ending_node` | string? | Node ID where execution stopped |

**OutcomeType values:**
| Value | Meaning |
|-------|---------|
| `success` | All intended operations completed |
| `partial` | Some operations completed, some skipped/failed |
| `error` | Execution failed due to error |
| `cancelled` | User or system cancelled execution |

### node_history

Ordered record of node executions. Only populated when `logging.capture.nodes` is enabled.

```yaml
node_history:
  - node: "validate_config"
    timestamp: "2024-01-15T10:30:01Z"
    outcome: "success"
    details: {}

  - node: "check_source_polars"
    timestamp: "2024-01-15T10:30:05Z"
    outcome: "success"
    details:
      commits_behind: 0
      status: "up_to_date"

  - node: "update_index"
    timestamp: "2024-01-15T10:30:10Z"
    outcome: "skipped"
    details:
      reason: "no_changes"
```

**NodeOutcome values:**
| Value | Meaning |
|-------|---------|
| `success` | Node completed successfully |
| `skipped` | Node was skipped (precondition false, or conditional branch) |
| `error` | Node failed with error |
| `blocked` | Node blocked by dependency |

### events

Structured domain-specific events. The `type` field identifies the event kind; `data` contains domain-specific payload.

```yaml
events:
  - type: "source_checked"
    timestamp: "2024-01-15T10:30:03Z"
    data:
      source_id: "polars"
      source_type: "git"
      status: "up_to_date"
      commits_behind: 0

  - type: "index_updated"
    timestamp: "2024-01-15T10:30:12Z"
    data:
      entries_added: 5
      entries_removed: 2
      total_entries: 150
```

**Common event types by domain:**

| Domain | Event Types |
|--------|-------------|
| Corpus | `source_checked`, `source_cloned`, `index_updated`, `file_scanned` |
| GitHub | `issue_created`, `pr_merged`, `label_added`, `project_updated` |
| Build | `artifact_created`, `test_passed`, `deploy_started` |

### warnings

Non-fatal issues encountered during execution.

```yaml
warnings:
  - message: "Source 'polars' has uncommitted changes"
    timestamp: "2024-01-15T10:30:04Z"
    node: "check_source_polars"
    context:
      dirty_files: 3
      source_id: "polars"
```

### errors

Fatal or significant errors encountered during execution.

```yaml
errors:
  - message: "Failed to clone repository"
    error_type: "git_clone_failed"
    timestamp: "2024-01-15T10:30:08Z"
    node: "clone_source"
    context:
      url: "https://github.com/example/repo"
      exit_code: 128
      stderr: "fatal: repository not found"
    recoverable: false
```

**Common error_type values:**

| Type | Meaning |
|------|---------|
| `precondition_failed` | Entry condition not met |
| `tool_not_found` | Required tool unavailable |
| `file_not_found` | Expected file missing |
| `parse_error` | Failed to parse file content |
| `network_error` | Network operation failed |
| `git_error` | Git operation failed |
| `timeout` | Operation exceeded time limit |
| `user_cancelled` | User cancelled operation |

### summary

Human-readable summary of execution. Generated automatically or provided explicitly.

```yaml
summary: "Checked 3 sources, 1 had updates. Updated index with 5 new entries."
```

---

## Level-Based Capture

What gets logged depends on the configured log level:

| Level | node_history | events | warnings | errors | state_changes |
|-------|--------------|--------|----------|--------|---------------|
| `error` | ❌ | ❌ | ❌ | ✅ | ❌ |
| `warn` | ❌ | ❌ | ✅ | ✅ | ❌ |
| `info` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `debug` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `trace` | ✅ | ✅ | ✅ | ✅ | ✅ |

---

## Domain Extensions

Plugins can extend the log structure with domain-specific fields. By convention, domain fields are added at the top level:

```yaml
# Corpus domain extension
metadata: { ... }
execution: { ... }
node_history: [ ... ]
events: [ ... ]

# Domain-specific sections
sources:                      # Corpus-specific
  - id: "polars"
    status: "up_to_date"
    commits_behind: 0
  - id: "ibis"
    status: "updated"
    commits_behind: 5

index_changes:                # Corpus-specific
  added: 5
  removed: 2
  modified: 3
```

**Extension guidelines:**

1. Use descriptive top-level keys (not `extra` or `custom`)
2. Document extension fields in plugin's logging docs
3. Extension fields should be optional (core log works without them)
4. Use `events` array for most domain logging needs

---

## Output Formats

### YAML (default)

```yaml
metadata:
  workflow_name: hiivmind-corpus-refresh
  workflow_version: "1.0"
  skill_name: refresh
  plugin_name: hiivmind-corpus-polars
  execution_path: /path/to/skill

parameters:
  verbose: false
  force: false

execution:
  start_time: "2024-01-15T10:30:00Z"
  end_time: "2024-01-15T10:30:45Z"
  duration_seconds: 45
  outcome: success
  ending_node: complete

node_history:
  - node: validate_config
    timestamp: "2024-01-15T10:30:01Z"
    outcome: success
    details: {}

events:
  - type: source_checked
    timestamp: "2024-01-15T10:30:05Z"
    data:
      source_id: polars
      status: up_to_date

warnings: []
errors: []

summary: "Checked 3 sources, all up to date. No index changes needed."
```

### JSON

Same structure, JSON formatted. Useful for programmatic parsing.

### Markdown

Human-readable report format:

```markdown
# Execution Log: hiivmind-corpus-refresh

| Field | Value |
|-------|-------|
| Workflow | hiivmind-corpus-refresh v1.0 |
| Skill | refresh (hiivmind-corpus-polars) |
| Started | 2024-01-15T10:30:00Z |
| Duration | 45 seconds |
| Outcome | ✅ success |

## Summary

Checked 3 sources, all up to date. No index changes needed.

## Node History

| # | Node | Outcome | Time |
|---|------|---------|------|
| 1 | validate_config | ✅ success | 10:30:01 |
| 2 | check_sources | ✅ success | 10:30:05 |
| 3 | complete | ✅ success | 10:30:45 |

## Events

| Type | Time | Details |
|------|------|---------|
| source_checked | 10:30:05 | polars: up_to_date |
| source_checked | 10:30:10 | ibis: up_to_date |
| source_checked | 10:30:15 | narwhals: up_to_date |

## Warnings

_No warnings_

## Errors

_No errors_
```

---

## Filename Patterns

Default log filename pattern with available variables:

```
{skill_name}-{YYYYMMDD}-{HHMMSS}.{ext}
```

| Variable | Example | Description |
|----------|---------|-------------|
| `{skill_name}` | refresh | Skill name from metadata |
| `{workflow_name}` | hiivmind-corpus-refresh | Workflow ID |
| `{plugin_name}` | hiivmind-corpus-polars | Plugin name |
| `{YYYY}` | 2024 | 4-digit year |
| `{MM}` | 01 | 2-digit month |
| `{DD}` | 15 | 2-digit day |
| `{HH}` | 10 | 2-digit hour (24h) |
| `{mm}` | 30 | 2-digit minute |
| `{SS}` | 00 | 2-digit second |
| `{YYYYMMDD}` | 20240115 | Date compact |
| `{HHMMSS}` | 103000 | Time compact |
| `{timestamp}` | 20240115-103000 | Date-time compact |
| `{ext}` | yaml | Format extension |

---

## Related Documentation

- **Consequences:** `lib/workflow/consequences/core/logging.md` - Logging consequences
- **Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Config hierarchy
- **Session Tracking:** `lib/blueprint/patterns/session-tracking.md` - Hook setup and usage
- **Preconditions:** `lib/workflow/preconditions.md` - log_initialized, log_level_enabled
- **State:** `lib/workflow/state.md` - Runtime state structure
