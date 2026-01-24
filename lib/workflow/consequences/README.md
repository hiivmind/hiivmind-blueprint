# Workflow Consequences

Consequences are operations that mutate state or perform actions during workflow execution. This directory organizes consequences into **core** (intrinsic workflow engine) and **extension** (domain-specific) modules.

## Directory Structure

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

### Extension Consequences (10 types)

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

---

## Domain Files

### Core

| File | Category | Consequence Count |
|------|----------|-------------------|
| [core/workflow.md](core/workflow.md) | Fundamental Operations | 16 |
| [core/intent-detection.md](core/intent-detection.md) | 3VL Intent Detection | 4 |
| [core/logging.md](core/logging.md) | Workflow Logging | 10 |
| [core/shared.md](core/shared.md) | Common Patterns | - |

### Extensions

| File | Category | Consequence Count |
|------|----------|-------------------|
| [extensions/file-system.md](extensions/file-system.md) | File Operations | 4 |
| [extensions/git.md](extensions/git.md) | Git Operations | 4 |
| [extensions/web.md](extensions/web.md) | Web Operations | 2 |

---

## Usage Context

Consequences are used in:
- **Action nodes** - Execute operations and store results
- **User prompt responses** - Apply changes before routing

All consequences either succeed or fail. Failures trigger `on_failure` routing.

## Execution Semantics

Consequences in an action node execute **sequentially**:

```yaml
actions:
  - type: read_file              # 1. Execute first
    path: "config.yaml"
    store_as: config
  - type: set_flag               # 2. Execute second
    flag: config_found
    value: true
  - type: evaluate               # 3. Execute third
    expression: "len(config.sources) == 0"
    set_flag: is_first_source
```

**On failure:**
- If any consequence fails, remaining consequences are skipped
- Action node routes to `on_failure`
- State mutations from failed action may be partial (use checkpoints for safety)

## Common Patterns

See [core/shared.md](core/shared.md) for:
- Parameter interpolation syntax (`${field}`)
- Standard parameter types (`store_as`, `from`, `field`, `path`)
- Failure handling conventions
- Cross-cutting concerns

---

## Extensibility

### Adding to Core

Core consequences should be generic and workflow-agnostic. To add:
1. Add to appropriate section in `core/workflow.md` or create new section
2. Update this README's Quick Reference

### Adding Extensions

To add a new extension domain:
1. **Create domain file** - `extensions/{domain}.md`
2. **Follow template** - Header, consequence sections, related documentation
3. **Update extensions/README.md** - Add to tables
4. **Update this README** - Add to Quick Reference

### Custom Plugin Extensions

Plugins converted by hiivmind-blueprint may define their own domain-specific extensions. See `lib/blueprint/patterns/consequence-extensions.md` for guidance.

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - Workflow YAML structure
- **Preconditions:** `lib/workflow/preconditions/` - Boolean evaluations
- **Execution:** `lib/workflow/execution.md` - Turn loop
- **State:** `lib/workflow/state.md` - Runtime state structure
- **Intent Detection:** `lib/intent_detection/framework.md` - 3VL semantics
- **Extension Meta-Pattern:** `lib/blueprint/patterns/consequence-extensions.md`
