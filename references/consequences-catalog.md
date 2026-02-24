# Consequences Catalog

Complete reference for all 22 consequence types available in hiivmind-blueprint-lib.

> **Examples:** `hiivmind/hiivmind-blueprint-lib/examples/consequences.yaml`
> **Definitions:** `hiivmind/hiivmind-blueprint-lib/consequences/core.yaml`, `consequences/intent.yaml`, `consequences/extensions.yaml`

---

## Overview

Consequences are actions executed when a node runs or a user responds. They are organized into 10 categories:

| Category | Count | Purpose |
|----------|-------|---------|
| core/control | 5 | Workflow control (checkpoints, rollback, spawn, inline, invoke_skill) |
| core/evaluation | 2 | Expression and computation |
| core/interaction | 1 | User-facing output |
| core/logging | 2 | Node tracking and event logging |
| core/state | 2 | State manipulation |
| core/utility | 1 | Timestamps |
| core/intent | 3 | Intent detection (3VL) |
| extensions/file-system | 1 | File operations (consolidated) |
| extensions/git | 1 | Git operations (consolidated) |
| extensions/web | 1 | Web fetching (consolidated) |
| extensions/scripting | 1 | Script execution (consolidated) |
| extensions/package | 1 | Tool installation |
| extensions/hashing | 1 | Content hashing |

---

## core/control

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `create_checkpoint` | Save state snapshot for rollback | `name` |
| `rollback_checkpoint` | Restore state from checkpoint | `name` |
| `spawn_agent` | Launch background agent | `subagent_type`, `prompt`, `store_as` |
| `inline` | Execute embedded pseudocode | `description`, `pseudocode`, `store_as` |
| `invoke_skill` | Invoke another skill | `skill`, `args` |

---

## core/evaluation

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `evaluate` | Evaluate expression to flag | `expression`, `set_flag` |
| `compute` | Compute value and store | `expression`, `store_as` |

---

## core/interaction

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `display` | Display content in various formats | `format`, `content`, `title`, `headers` |

**Formats:** `text`, `table`, `json`, `markdown`

```yaml
# Text/markdown message
- type: display
  format: text
  content: "Operation completed successfully"

# Table display
- type: display
  format: table
  title: "Results"
  headers: [ID, Name, Status]
  content: "${computed.results}"
```

---

## core/logging

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `log_node` | Record node execution | `node`, `outcome`, `details` |
| `log_entry` | Log event/warning/error | `level`, `message`, `context` |

**log_entry levels:** `debug`, `info`, `warning`, `error`

```yaml
# Info event
- type: log_entry
  level: info
  message: "Processing started"

# Warning
- type: log_entry
  level: warning
  message: "Rate limit approaching"

# Error
- type: log_entry
  level: error
  message: "Clone failed"
  error_type: git_error
  context:
    exit_code: "${computed.exit_code}"
```

---

## core/state

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `set_flag` | Set boolean flag | `flag`, `value` |
| `mutate_state` | Mutate state field | `operation`, `field`, `value` |

**mutate_state operations:** `set`, `append`, `clear`, `merge`

```yaml
# Set a value
- type: mutate_state
  operation: set
  field: computed.repo_url
  value: "https://github.com/example/repo"

# Append to array
- type: mutate_state
  operation: append
  field: computed.items
  value: "${computed.new_item}"

# Clear a field
- type: mutate_state
  operation: clear
  field: computed.temp_data

# Merge into object
- type: mutate_state
  operation: merge
  field: computed.config
  value:
    updated_at: "${computed.timestamp}"
```

---

## core/utility

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `set_timestamp` | Store current ISO timestamp | `store_as` |

---

## core/intent

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `evaluate_keywords` | Simple keyword matching | `input`, `keyword_sets`, `store_as` |
| `parse_intent_flags` | Parse 3VL flags from input | `input`, `flag_definitions`, `store_as` |
| `match_3vl_rules` | Match flags against rules | `flags`, `rules`, `store_as` |

---

## extensions/file-system

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `local_file_ops` | File operations | `operation`, `path`, `content`, `store_as` |

**Operations:** `read`, `write`, `mkdir`, `delete`

```yaml
# Read file
- type: local_file_ops
  operation: read
  path: "data/config.yaml"
  store_as: computed.config

# Write file
- type: local_file_ops
  operation: write
  path: "${computed.output_path}"
  content: "${computed.content}"

# Create directory
- type: local_file_ops
  operation: mkdir
  path: ".output/reports"

# Delete file
- type: local_file_ops
  operation: delete
  path: "${computed.temp_file}"
```

---

## extensions/git

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `git_ops_local` | Git operations | `operation`, `repo_path`, `args`, `store_as` |

**Operations:** `clone`, `pull`, `fetch`, `get-sha`

```yaml
# Clone repository
- type: git_ops_local
  operation: clone
  args:
    url: "${computed.repo_url}"
    dest: ".source/${computed.source_id}"
    branch: main
    depth: 1

# Pull updates
- type: git_ops_local
  operation: pull
  repo_path: ".source/${computed.source_id}"

# Get commit SHA
- type: git_ops_local
  operation: get-sha
  repo_path: ".source/${computed.source_id}"
  store_as: computed.current_sha
```

---

## extensions/web

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `web_ops` | Web operations | `operation`, `url`, `store_as`, `from`, `dest` |

**Operations:** `fetch`, `cache`

```yaml
# Fetch URL
- type: web_ops
  operation: fetch
  url: "${computed.doc_url}"
  store_as: computed.page_content
  prompt: "Extract the main content"

# Cache fetched content
- type: web_ops
  operation: cache
  from: computed.page_content
  dest: ".cache/${computed.filename}"
```

---

## extensions/scripting

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `run_command` | Execute script | `interpreter`, `script`, `args`, `store_as` |

**Interpreters:** `auto`, `bash`, `python`, `node`, `ruby`

```yaml
# Auto-detect interpreter
- type: run_command
  script: "scripts/process.py"
  args:
    - "--input"
    - "${computed.input_file}"
  store_as: computed.output

# Explicit bash
- type: run_command
  interpreter: bash
  script: "scripts/build.sh"
  env:
    BUILD_DIR: "${computed.build_path}"

# Python with venv
- type: run_command
  interpreter: python
  script: "scripts/analyze.py"
  venv: ".venv"
```

---

## extensions/package

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `install_tool` | Install CLI tool | `tool`, `install_command`, `skip_if_available` |

---

## extensions/hashing

| Type | Purpose | Key Parameters |
|------|---------|----------------|
| `compute_hash` | Compute SHA-256 hash | `from`, `store_as` |

---

## Quick Reference by Use Case

| Need To... | Use This Consequence |
|------------|---------------------|
| Save progress | `create_checkpoint` |
| Undo changes | `rollback_checkpoint` |
| Run background task | `spawn_agent` |
| Show user a message | `display` (format: text) |
| Show a table | `display` (format: table) |
| Read a file | `local_file_ops` (operation: read) |
| Write a file | `local_file_ops` (operation: write) |
| Clone a repo | `git_ops_local` (operation: clone) |
| Pull updates | `git_ops_local` (operation: pull) |
| Fetch URL | `web_ops` (operation: fetch) |
| Run a script | `run_command` |
| Store a value | `mutate_state` (operation: set) |
| Set a flag | `set_flag` |
| Add to a list | `mutate_state` (operation: append) |
| Log an event | `log_entry` (level: info) |
| Log a warning | `log_entry` (level: warning) |
| Log an error | `log_entry` (level: error) |
| Detect intent | `parse_intent_flags`, `match_3vl_rules` |
| Call another skill | `invoke_skill` |
| Compute a hash | `compute_hash` |

---

## Prose Pattern Mapping

Use this table when converting prose skill descriptions to consequences:

| Prose Pattern | Consequence | Parameters |
|---------------|-------------|------------|
| "save progress", "checkpoint" | `create_checkpoint` | name |
| "run in background", "spawn" | `spawn_agent` | subagent_type, prompt |
| "show message", "display", "output" | `display` | format: text, content |
| "show table" | `display` | format: table, headers, content |
| "log", "record event" | `log_entry` | level: info, message |
| "warn", "log warning" | `log_entry` | level: warning, message |
| "error", "log error" | `log_entry` | level: error, message |
| "read file", "load" | `local_file_ops` | operation: read, path |
| "write file", "save" | `local_file_ops` | operation: write, path, content |
| "create directory" | `local_file_ops` | operation: mkdir, path |
| "clone", "clone repo" | `git_ops_local` | operation: clone, args.url |
| "pull", "update repo" | `git_ops_local` | operation: pull, repo_path |
| "fetch URL", "download" | `web_ops` | operation: fetch, url |
| "cache content" | `web_ops` | operation: cache, from, dest |
| "run script", "execute" | `run_command` | interpreter, script |
| "install", "ensure tool" | `install_tool` | tool |
| "store", "set", "remember" | `mutate_state` | operation: set, field, value |
| "append", "add to list" | `mutate_state` | operation: append, field, value |
| "clear", "reset" | `mutate_state` | operation: clear, field |
| "calculate", "compute" | `evaluate`, `compute` | expression |
| "hash", "checksum" | `compute_hash` | from, store_as |
| "invoke skill", "call skill" | `invoke_skill` | skill |

---

## Fetching Examples

```bash
# All consequence examples
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/consequences.yaml \
  --jq '.content' | base64 -d

# Examples for a specific category
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/consequences.yaml \
  --jq '.content' | base64 -d | yq '.examples["core/control"]'

# Examples for a specific type
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/consequences.yaml \
  --jq '.content' | base64 -d | yq '.examples["core/control"].create_checkpoint'

# Canonical type definition (core)
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/consequences/core.yaml \
  --jq '.content' | base64 -d | yq '.consequences.create_checkpoint'
```

---

## Related Documentation

- **Examples:** `hiivmind/hiivmind-blueprint-lib/examples/consequences.yaml`
- **Definitions:** `hiivmind/hiivmind-blueprint-lib/consequences/core.yaml`, `consequences/intent.yaml`, `consequences/extensions.yaml`
- **Node Mapping Pattern:** `lib/patterns/node-mapping.md`
- **Workflow Generation:** `lib/patterns/workflow-generation.md`
