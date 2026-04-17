# Idempotency Guards

Mechanisms to ensure migrations are safe to re-run on partially upgraded workflows.

## Principle

Every migration function must be **idempotent** — applying it to a workflow that has
already been migrated must produce no changes and no errors.

## Pre-Migration Detection

Before applying a migration step, check whether it has already been applied:

```pseudocode
function is_already_applied(workflow, from_version, to_version):
    if from_version == "2.0" and to_version == "2.1":
        # Already applied if no validation_gate nodes exist
        return not any(node.type == "validation_gate" for node in workflow.nodes.values())

    elif from_version == "2.1" and to_version == "2.2":
        # Already applied if unified output exists and no separate logging/display
        has_unified = has_field(workflow, "initial_state.output.log_enabled")
        has_separate = has_field(workflow, "initial_state.logging")
        return has_unified and not has_separate

    elif from_version == "2.2" and to_version == "2.3":
        # Already applied if prompts config exists
        return has_field(workflow, "initial_state.prompts")

    elif from_version == "2.3" and to_version == "2.4":
        # Already applied if both configs are present with all required fields
        return has_all_required_output_fields(workflow) and
               has_all_required_prompts_fields(workflow)
```

## Content-Hash Backup Deduplication

After all migrations complete, compare the content hash of the result against the
original to detect no-op migrations:

```pseudocode
function check_deduplication(workflow_path, original_hash, backup_path):
    new_content = Read(workflow_path)
    result_hash = sha256(new_content)

    if result_hash == original_hash:
        # No actual changes were made
        display("No changes detected. Workflow was already at target state.")
        display("Removing unnecessary backup: " + backup_path)
        # Optionally delete the backup
        return false  # No changes made
    else:
        return true  # Changes were made
```

## Required Field Checks

### Output Config Required Fields (v2.4)

```pseudocode
function has_all_required_output_fields(workflow):
    required = [
        "level", "display_enabled", "batch_enabled", "batch_threshold",
        "use_icons", "log_enabled", "log_format", "log_location", "ci_mode"
    ]
    if not has_field(workflow, "initial_state.output"):
        return false
    output = workflow.initial_state.output
    return all(field in output for field in required)
```

### Prompts Config Required Fields (v2.4)

```pseudocode
function has_all_required_prompts_fields(workflow):
    if not has_field(workflow, "initial_state.prompts"):
        return false
    prompts = workflow.initial_state.prompts
    return ("interface" in prompts and
            "modes" in prompts and
            "tabular" in prompts and
            "autonomous" in prompts)
```

## Guard Pattern for Migration Functions

Every migration function should follow this pattern:

```pseudocode
function apply_migration_X_to_Y(workflow):
    # Guard: check if already applied
    if is_already_applied(workflow, "X", "Y"):
        return []  # No changes needed

    changes = []

    # ... perform migration ...

    return changes
```

This ensures that even if the version detection is slightly off, the migration
functions themselves protect against double-application.
