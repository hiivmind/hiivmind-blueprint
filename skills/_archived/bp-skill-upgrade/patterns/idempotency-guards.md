# Idempotency Guards

> **Used by:** `SKILL.md` Phase 2, Step 2.3 and Phase 3, Step 3.4
> **Guarantees:** Safe-to-rerun, no duplicate migrations, rollback support

This document defines the mechanisms that make the upgrade skill idempotent: running it
multiple times on the same workflow produces the same result as running it once.

---

## Content-Hash Backup Mechanism

Before any migration is applied, a backup is created with a content hash for deduplication.

### Backup Creation

```pseudocode
function create_guarded_backup(workflow_path):
  content = Read(workflow_path)
  content_hash = sha256(content)

  # Check if a backup with the same hash already exists
  existing_backups = Glob(workflow_path + ".backup.*")
  for backup in existing_backups:
    backup_content = Read(backup)
    if sha256(backup_content) == content_hash:
      # Identical backup already exists, reuse it
      computed.backup_path = backup
      computed.backup_reused = true
      return

  # Create new backup with timestamp
  timestamp = format_timestamp(now(), "YYYYMMDD_HHmmss")
  computed.backup_path = workflow_path + ".backup." + timestamp
  Write(computed.backup_path, content)
  computed.backup_reused = false
  computed.original_hash = content_hash
```

### Post-Migration Hash Check

After all migrations are applied, the result is hashed and compared to the original:

```pseudocode
function post_migration_hash_check(workflow_path):
  new_content = Read(workflow_path)
  computed.result_hash = sha256(new_content)

  if computed.result_hash == computed.original_hash:
    # No actual changes were made -- all migrations were no-ops
    computed.changes_made = false

    # Clean up unnecessary backup if we created one
    if NOT computed.backup_reused:
      # Optionally delete the backup since nothing changed
      computed.cleanup_backup = true
  else:
    computed.changes_made = true
    computed.cleanup_backup = false
```

---

## Migration Markers

Each migration step has structural indicators that reveal whether it has already been
applied. These markers allow the skill to detect partially upgraded workflows and skip
already-completed steps.

### Marker Detection Per Version Step

| Step | Already Applied If... | Not Yet Applied If... |
|------|----------------------|----------------------|
| 2.0 -> 2.1 | No `validation_gate` nodes exist in `nodes:` | Any node has `type: validation_gate` |
| 2.1 -> 2.2 | `initial_state.output.log_enabled` exists AND `initial_state.logging` does not exist | `initial_state.logging` exists as a separate block |
| 2.2 -> 2.3 | `initial_state.prompts` block exists | No `initial_state.prompts` block |
| 2.3 -> 2.4 | `initial_state.output` has all 9 required fields AND `initial_state.prompts` has all 4 required top-level fields | Any required field is missing from output or prompts |

### Detection Pseudocode

```pseudocode
function detect_applied_migrations(workflow):
  applied = {}

  # 2.0 -> 2.1: validation_gate removal
  has_gates = false
  for node_name, node in workflow.nodes:
    if node.type == "validation_gate":
      has_gates = true
      break
  applied["2.0->2.1"] = NOT has_gates

  # 2.1 -> 2.2: unified output config
  has_unified_output = (
    has_field(workflow, "initial_state.output") AND
    has_field(workflow, "initial_state.output.log_enabled")
  )
  has_separate_logging = has_field(workflow, "initial_state.logging")
  applied["2.1->2.2"] = has_unified_output AND NOT has_separate_logging

  # 2.2 -> 2.3: prompts config
  applied["2.2->2.3"] = has_field(workflow, "initial_state.prompts")

  # 2.3 -> 2.4: required complete configs
  REQUIRED_OUTPUT_FIELDS = [
    "level", "display_enabled", "batch_enabled", "batch_threshold",
    "use_icons", "log_enabled", "log_format", "log_location", "ci_mode"
  ]
  REQUIRED_PROMPTS_FIELDS = ["interface", "modes", "tabular", "autonomous"]

  output_complete = has_field(workflow, "initial_state.output") AND
    all(has_field(workflow.initial_state.output, f) for f in REQUIRED_OUTPUT_FIELDS)
  prompts_complete = has_field(workflow, "initial_state.prompts") AND
    all(has_field(workflow.initial_state.prompts, f) for f in REQUIRED_PROMPTS_FIELDS)
  applied["2.3->2.4"] = output_complete AND prompts_complete

  return applied
```

### Handling Partial Application

A workflow may be in a state where some migrations have been applied but not others. For
example, a workflow at v2.2 that someone manually added a `prompts` block to (without
going through the v2.3 migration formally). The detection logic handles this:

```pseudocode
function determine_pending_steps(current_version, target_version, applied_markers):
  version_sequence = ["2.0", "2.1", "2.2", "2.3", "2.4"]
  current_idx = index_of(version_sequence, current_version)
  target_idx = index_of(version_sequence, target_version)

  pending = []
  skipped = []

  for i in range(current_idx, target_idx):
    from_ver = version_sequence[i]
    to_ver = version_sequence[i + 1]
    step_key = from_ver + "->" + to_ver

    if applied_markers.get(step_key, false):
      skipped.append({ from_version: from_ver, to_version: to_ver, reason: "already applied" })
    else:
      pending.append({ from_version: from_ver, to_version: to_ver })

  return { pending: pending, skipped: skipped }
```

---

## Safe-to-Rerun Guarantees

The upgrade skill provides three layers of safety:

### Layer 1: Pre-Migration Detection

Before any writes occur, the idempotency check in Phase 2 detects already-applied
migrations and filters them out of the pending list. If all migrations are already
applied, the skill exits with a "no changes needed" message.

### Layer 2: Per-Step Guards

Each migration function includes an internal guard that checks the structural precondition
before applying changes:

```pseudocode
function apply_migration_2_0_to_2_1(workflow):
  # Guard: only apply if validation_gate nodes actually exist
  gates = [n for n in workflow.nodes.values() if n.type == "validation_gate"]
  if len(gates) == 0:
    return []  # No changes needed, return empty changelist

  # ... proceed with migration ...
```

This means even if the outer idempotency check is bypassed (e.g., forced re-run), the
individual migration functions will not produce duplicate changes.

### Layer 3: Post-Migration Hash Check

After all migrations complete, the content hash comparison catches the case where
migrations ran but produced no actual changes (e.g., all defaults were already in place).
This prevents creating unnecessary backups and producing misleading "changes applied"
reports.

---

## Rollback Procedure

If migration fails or the user requests rollback at any point:

```pseudocode
function rollback(workflow_path, backup_path):
  # Verify backup exists and is readable
  if NOT file_exists(backup_path):
    DISPLAY "ERROR: Backup file not found at {backup_path}. Cannot rollback."
    return false

  # Read backup content
  backup_content = Read(backup_path)

  # Overwrite the workflow with backup content
  Write(workflow_path, backup_content)

  # Verify restoration
  restored_content = Read(workflow_path)
  restored_hash = sha256(restored_content)
  backup_hash = sha256(backup_content)

  if restored_hash == backup_hash:
    DISPLAY "Rollback successful. File restored to pre-migration state."
    DISPLAY "Backup preserved at: {backup_path}"
    return true
  else:
    DISPLAY "ERROR: Rollback verification failed. Manual intervention required."
    DISPLAY "Backup file: {backup_path}"
    DISPLAY "Workflow file: {workflow_path}"
    return false
```

### When Rollback is Offered

- Phase 4, Step 4.3: If validation fails after migration
- Phase 5, Step 5.4: As a final disposition option after reviewing the report

### Backup Lifecycle

| Event | Backup Action |
|-------|--------------|
| Migration starts | Backup created (or existing reused) |
| No changes detected | Backup optionally cleaned up |
| Migration succeeds, user accepts | Backup preserved (user can delete later) |
| User requests rollback | Backup content restored to workflow path |
| User requests "Delete backup" | Backup file removed |

---

## Related Documentation

- **Migration Table:** `patterns/migration-table.md`
- **SKILL.md Phase 2:** Idempotency check in Step 2.3
- **SKILL.md Phase 3:** Content-hash guard in Step 3.4
