# Plan: Logging Mechanism for hiivmind-corpus-refresh

## Context

The refresh workflow now exists (`workflow.yaml` + thin `SKILL.md`). This plan adds logging support for:
- Detailed execution path and decision history
- CI/automated workflow audit trails
- Cross-repository usage (skill runs from corpus repos, not the meta-plugin)

## Design Questions

### Key Considerations

| Factor | Implication |
|--------|-------------|
| Runs from corpus repos | Logs must be written to corpus repo, not meta-plugin |
| CI/automation use | Need structured output, exit codes, parseable summaries |
| Git history noise | Full logs would bloat history; need selective commit strategy |
| Debugging needs | Detailed logs needed locally even if not committed |
| Audit requirements | Need traceable history of what changed and when |

## Proposed Design: Per-Run Log Files with Configurable Options

### Core Design: One Full Log Per Run (Committed by Default)

**Directory:** `data/logs/`

**Files:** `refresh-{YYYY-MM-DD-HHMMSS}.yaml` (one per run)

**Purpose:** Complete audit trail with full execution detail, committed to git

**Format:**
```yaml
# Refresh Log
# Generated: 2025-01-24T10:30:00.000Z

metadata:
  workflow_version: "1.0.0"
  corpus_name: "hiivmind-corpus-polars"
  corpus_path: "/home/user/.claude/skills/hiivmind-corpus-polars"

parameters:
  auto_approve: false
  status_only: false
  log_format: "yaml"         # yaml | json | markdown
  ci_output: "github"        # github | plain | json | none

execution:
  start_time: "2025-01-24T10:30:00.000Z"
  end_time: "2025-01-24T10:30:45.000Z"
  duration_seconds: 45
  mode: "update"             # status | update
  outcome: "success"         # success | partial | error
  ending_node: "success"

sources:
  checked: 3
  updated: 2
  details:
    - source_id: "polars"
      type: "git"
      status: "stale"
      indexed_sha: "abc123"
      upstream_sha: "def456"
      commits_behind: 15
      action: "updated"
      new_sha: "def456"

    - source_id: "team-docs"
      type: "local"
      status: "current"
      action: "skipped"

changes:
  - source_id: "polars"
    added_files:
      - "docs/guides/new-feature.md"
    modified_files:
      - "docs/reference/expressions.md"
    deleted_files: []

index_updates:
  files_modified:
    - "data/index.md"
    - "data/index-reference.md"
  entries_added: 1
  entries_removed: 0
  keywords_preserved: true

node_history:
  - node: "read_config"
    timestamp: "2025-01-24T10:30:00.100Z"
    outcome: "success"

  - node: "check_has_sources"
    timestamp: "2025-01-24T10:30:00.150Z"
    outcome: "branch:true"

  - node: "prompt_command_mode"
    timestamp: "2025-01-24T10:30:02.000Z"
    outcome: "response:update"
    user_selection: "update"

  # ... full decision path

errors: []
warnings:
  - "Web source 'blog' cache is 14 days old"

summary: "Updated polars (15 commits). Index: +1 entry."
```

**Git behavior:** Committed by default (in `data/logs/`)

### Configuration Options

**Log retention (configurable, default: no purge):**
```yaml
# In corpus config.yaml or via CLI flag
logging:
  retention:
    strategy: "none"         # none | days | count
    days: 30                 # if strategy: days
    count: 20                # if strategy: count
```

**Log format (configurable):**
```yaml
logging:
  format: "yaml"             # yaml | json | markdown
  location: "data/logs/"     # override log directory
  gitignore: false           # true to not commit logs
```

### CI Output (Configurable Format)

**Flag:** `--ci-output={format}`

**Formats:**

#### 1. GitHub Actions (`--ci-output=github`, default in CI)
```
::group::Refresh Summary
Corpus: hiivmind-corpus-polars
Mode: update
Sources: 3 checked, 2 updated
Outcome: SUCCESS
Duration: 45s
::endgroup::

::notice file=data/index.md::Index updated with 1 new entry
::notice file=data/config.yaml::Source SHAs updated
```

#### 2. Plain Text (`--ci-output=plain`)
```
REFRESH_OUTCOME=success
REFRESH_MODE=update
REFRESH_SOURCES_CHECKED=3
REFRESH_SOURCES_UPDATED=2
REFRESH_DURATION=45
REFRESH_LOG=data/logs/refresh-2025-01-24-103000.yaml
```

#### 3. JSON (`--ci-output=json`)
```json
{
  "outcome": "success",
  "mode": "update",
  "sources_checked": 3,
  "sources_updated": 2,
  "duration_seconds": 45,
  "log_file": "data/logs/refresh-2025-01-24-103000.yaml"
}
```

#### 4. None (`--ci-output=none`)
No structured CI output, just normal display_message output.

## Implementation Plan

### Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `lib/workflow/consequences/extensions/logging.md` | **Create** | New logging consequence types |
| `lib/corpus/patterns/refresh-logging.md` | **Create** | Logging schema and format documentation |
| `skills/hiivmind-corpus-refresh/workflow.yaml` | **Modify** | Add logging nodes at key points |
| `skills/hiivmind-corpus-refresh/SKILL.md` | **Modify** | Document logging flags |

### New Consequence Types

Add to `lib/workflow/consequences/extensions/logging.md`:

```yaml
# 1. Initialize log structure
- type: init_log
  store_as: computed.log
  metadata:
    workflow_version: "${workflow_version}"
    corpus_name: "${config.corpus.name}"
    corpus_path: "${PWD}"

# 2. Record node execution (auto-called or explicit)
- type: log_node
  node: "${current_node}"
  outcome: "success"           # success | branch:{value} | response:{id}
  details: {}                  # optional extra context

# 3. Log source status result
- type: log_source_status
  source_id: "${current_source.id}"
  type: "${current_source.type}"
  status: "${computed.status}"
  indexed_sha: "${current_source.last_commit_sha}"
  upstream_sha: "${computed.upstream_sha}"

# 4. Log changes for a source
- type: log_source_changes
  source_id: "${current_source.id}"
  changes: "${computed.file_changes}"

# 5. Log index update
- type: log_index_update
  files: "${computed.index_files_modified}"
  entries_added: "${computed.entries_added}"
  entries_removed: "${computed.entries_removed}"

# 6. Finalize and write log
- type: write_log
  format: "${flags.log_format || 'yaml'}"   # yaml | json | markdown
  location: "${flags.log_location || 'data/logs/'}"
  filename: "refresh-${computed.timestamp_slug}.yaml"

# 7. Apply retention policy (if configured)
- type: apply_log_retention
  strategy: "${config.logging.retention.strategy || 'none'}"
  days: "${config.logging.retention.days}"
  count: "${config.logging.retention.count}"

# 8. Output CI summary
- type: output_ci_summary
  format: "${flags.ci_output || 'none'}"    # github | plain | json | none
```

### Workflow Integration Points

```
read_config
    │
    ▼
init_log  ◄── NEW: Initialize log with metadata
    │
    ▼
[... validation nodes ...]
    │
    ├── Each node: auto log_node via execution loop
    │
    ▼
[... status check nodes ...]
    │
    ├── Each source: log_source_status
    │
    ▼
[... update nodes ...]
    │
    ├── Each source: log_source_changes
    │
    ▼
[... index update nodes ...]
    │
    ├── log_index_update
    │
    ▼
apply_log_retention  ◄── NEW: Clean old logs if configured
    │
    ▼
write_log  ◄── NEW: Write full log file
    │
    ▼
output_ci_summary  ◄── NEW: CI-formatted output
    │
    ▼
present_completion
```

### Entry Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `--no-log` | boolean | false | Skip writing log file |
| `--log-format` | string | "yaml" | Log format: yaml, json, or markdown |
| `--log-location` | string | "data/logs/" | Override log directory |
| `--ci-output` | string | "none" | CI output: github, plain, json, or none |
| `--log-gitignore` | boolean | false | Add log to .gitignore (not committed) |

### Config Schema Addition

Add optional `logging` section to corpus `config.yaml`:

```yaml
# Optional logging configuration
logging:
  # Retention policy (default: none)
  retention:
    strategy: "none"    # none | days | count
    days: 30            # if strategy: days
    count: 20           # if strategy: count

  # Default log settings (can be overridden by CLI flags)
  defaults:
    format: "yaml"
    location: "data/logs/"
    ci_output: "none"
    gitignore: false
```

### Log File Naming

Format: `refresh-{YYYY-MM-DD}-{HHMMSS}.{ext}`

Examples:
- `refresh-2025-01-24-103045.yaml`
- `refresh-2025-01-24-103045.json`
- `refresh-2025-01-24-103045.md`

### Markdown Format (Alternative)

When `--log-format=markdown`:

```markdown
# Refresh Log: 2025-01-24 10:30:45

## Summary

| Field | Value |
|-------|-------|
| Corpus | hiivmind-corpus-polars |
| Mode | update |
| Outcome | success |
| Duration | 45s |

## Sources

### polars (git)
- **Status:** stale → updated
- **SHA:** abc123 → def456
- **Commits behind:** 15

### team-docs (local)
- **Status:** current (skipped)

## Changes

### polars
- **Added:** docs/guides/new-feature.md
- **Modified:** docs/reference/expressions.md

## Index Updates
- data/index.md (+1 entry)
- data/index-reference.md (modified)

## Execution Path
1. read_config ✓
2. check_has_sources → true
3. prompt_command_mode → "update"
...
```

## Verification

After implementation:

### Basic Logging
1. Run `refresh --auto-approve` → verify `data/logs/refresh-{timestamp}.yaml` created
2. Run refresh interactively → verify node history captures user responses
3. Check log contains all expected sections (metadata, sources, changes, node_history)

### Format Options
4. Test `--log-format=json` → verify valid JSON output
5. Test `--log-format=markdown` → verify readable markdown
6. Test `--no-log` → verify no log file created

### CI Output
7. Test `--ci-output=github` → verify `::group::` and `::notice::` annotations
8. Test `--ci-output=plain` → verify KEY=VALUE format
9. Test `--ci-output=json` → verify parseable JSON summary

### Retention
10. Configure `logging.retention.strategy: count` with `count: 3`
11. Run 5 refreshes → verify only 3 most recent logs remain

### Git Integration
12. Verify `data/logs/` is committed by default
13. Test `--log-gitignore` → verify log added to .gitignore
