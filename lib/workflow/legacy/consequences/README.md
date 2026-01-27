# Workflow Consequences

> **ARCHIVED:** This document is preserved for reference. The authoritative source is:
> - **YAML Definitions:** `lib/consequences/definitions/index.yaml`
> - **Full type catalog:** `lib/consequences/definitions/core/*.yaml` and `extensions/*.yaml`

---

Consequences are operations that mutate state or perform actions during workflow execution. This directory organizes consequences into **core** (intrinsic workflow engine) and **extension** (domain-specific) modules.

## Structured Definitions (YAML)

The authoritative consequence definitions are now in **YAML format** for programmatic access:

```
lib/consequences/
├── definitions/
│   ├── index.yaml                    # Master index with type lookup
│   ├── core/
│   │   ├── state.yaml                # 5 types: set_flag, set_state, append_state, clear_state, merge_state
│   │   ├── evaluation.yaml           # 2 types: evaluate, compute
│   │   ├── interaction.yaml          # 2 types: display_message, display_table
│   │   ├── control.yaml              # 3 types: create_checkpoint, rollback_checkpoint, spawn_agent
│   │   ├── skill.yaml                # 2 types: invoke_pattern, invoke_skill
│   │   ├── utility.yaml              # 2 types: set_timestamp, compute_hash
│   │   ├── intent.yaml               # 4 types: evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route
│   │   └── logging.yaml              # 10 types: init_log, log_node, log_event, etc.
│   └── extensions/
│       ├── file-system.yaml          # 4 types: read_file, write_file, create_directory, delete_file
│       ├── git.yaml                  # 4 types: clone_repo, get_sha, git_pull, git_fetch
│       └── web.yaml                  # 2 types: web_fetch, cache_web_content
└── schema/
    └── consequence-definition.json   # JSON Schema for definition files
```

Each YAML definition includes:
- **Type identifier** and category
- **Parameters** with types, constraints, and possible values
- **Description** (brief + detailed + notes)
- **Payload** - effect pseudocode, tool calls, state mutations
- **Examples** for multi-shot LLM prompting
- **Related** consequence types

## Markdown Documentation (Legacy Reference)

The original markdown files remain for human-readable documentation:

```
consequences/
├── README.md              # This file - taxonomy and overview
├── core/                  # Intrinsic workflow engine (4 files)
│   ├── workflow.md        # State, evaluation, user interaction, control flow, skill, utility
│   ├── shared.md          # Common patterns: interpolation, parameters, failure handling
│   ├── intent-detection.md # 3VL routing system
│   └── logging.md         # Workflow execution logging
└── extensions/            # Generic domain extensions (3 files)
    ├── README.md          # Extension overview
    ├── file-system.md     # File operations
    ├── git.md             # Git source operations
    └── web.md             # Web source operations
```

## Core vs Extensions

| Category | Purpose | Characteristics |
|----------|---------|-----------------|
| **Core** | Fundamental workflow operations | Workflow-engine intrinsic, domain-agnostic |
| **Extensions** | Domain-specific operations | Generic, replaceable, composable |

---

## Quick Reference

### Core Consequences (30 types)

| Consequence Type | File | Description |
|------------------|------|-------------|
| `set_flag` | [core/workflow.md](core/workflow.md) | Set a boolean flag |
| `set_state` | [core/workflow.md](core/workflow.md) | Set any state field |
| `append_state` | [core/workflow.md](core/workflow.md) | Append to array field |
| `clear_state` | [core/workflow.md](core/workflow.md) | Reset field to null |
| `merge_state` | [core/workflow.md](core/workflow.md) | Merge object into field |
| `evaluate` | [core/workflow.md](core/workflow.md) | Evaluate expression to flag |
| `compute` | [core/workflow.md](core/workflow.md) | Compute and store result |
| `display_message` | [core/workflow.md](core/workflow.md) | Show message to user |
| `display_table` | [core/workflow.md](core/workflow.md) | Show tabular data |
| `create_checkpoint` | [core/workflow.md](core/workflow.md) | Save state snapshot |
| `rollback_checkpoint` | [core/workflow.md](core/workflow.md) | Restore from checkpoint |
| `spawn_agent` | [core/workflow.md](core/workflow.md) | Launch Task agent |
| `invoke_pattern` | [core/workflow.md](core/workflow.md) | Execute pattern document |
| `invoke_skill` | [core/workflow.md](core/workflow.md) | Invoke another skill |
| `set_timestamp` | [core/workflow.md](core/workflow.md) | Set ISO timestamp |
| `compute_hash` | [core/workflow.md](core/workflow.md) | Compute SHA-256 hash |
| `evaluate_keywords` | [core/intent-detection.md](core/intent-detection.md) | Match keywords to intent |
| `parse_intent_flags` | [core/intent-detection.md](core/intent-detection.md) | Parse 3VL flags |
| `match_3vl_rules` | [core/intent-detection.md](core/intent-detection.md) | Match flags to rules |
| `dynamic_route` | [core/intent-detection.md](core/intent-detection.md) | Dynamic node routing |
| `init_log` | [core/logging.md](core/logging.md) | Initialize log structure |
| `log_node` | [core/logging.md](core/logging.md) | Record node execution |
| `log_event` | [core/logging.md](core/logging.md) | Log domain-specific event |
| `log_warning` | [core/logging.md](core/logging.md) | Add warning to log |
| `log_error` | [core/logging.md](core/logging.md) | Add error with context |
| `log_session_snapshot` | [core/logging.md](core/logging.md) | Record mid-session checkpoint |
| `finalize_log` | [core/logging.md](core/logging.md) | Complete log with timing |
| `write_log` | [core/logging.md](core/logging.md) | Write log to file |
| `apply_log_retention` | [core/logging.md](core/logging.md) | Clean up old log files |
| `output_ci_summary` | [core/logging.md](core/logging.md) | Format output for CI

### Extension Consequences (13 types)

| Consequence Type | File | Description |
|------------------|------|-------------|
| `read_file` | [extensions/file-system.md](extensions/file-system.md) | Read arbitrary file |
| `write_file` | [extensions/file-system.md](extensions/file-system.md) | Write content to file |
| `create_directory` | [extensions/file-system.md](extensions/file-system.md) | Create directory |
| `delete_file` | [extensions/file-system.md](extensions/file-system.md) | Delete file |
| `clone_repo` | [extensions/git.md](extensions/git.md) | Clone git repository |
| `get_sha` | [extensions/git.md](extensions/git.md) | Get HEAD commit SHA |
| `git_pull` | [extensions/git.md](extensions/git.md) | Pull latest changes |
| `git_fetch` | [extensions/git.md](extensions/git.md) | Fetch remote refs |
| `web_fetch` | [extensions/web.md](extensions/web.md) | Fetch URL content |
| `cache_web_content` | [extensions/web.md](extensions/web.md) | Save fetched content |
| `run_script` | extensions/scripting.yaml | Execute script with auto-detected interpreter |
| `run_python` | extensions/scripting.yaml | Execute Python script |
| `run_bash` | extensions/scripting.yaml | Execute Bash script |

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - Workflow YAML structure
- **Preconditions:** `lib/workflow/preconditions/` - Boolean evaluations
- **Execution:** `lib/workflow/execution.md` - Turn loop
- **State:** `lib/workflow/state.md` - Runtime state structure
- **Intent Detection:** `lib/intent_detection/framework.md` - 3VL semantics
- **Extension Meta-Pattern:** `lib/blueprint/patterns/consequence-extensions.md`
