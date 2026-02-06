---
name: bp-author-skill-upgrade
description: >
  This skill should be used when the user asks to "upgrade workflow", "migrate workflow version",
  "update schema version", "fix deprecated types", "upgrade workflow.yaml", "modernize workflow",
  or needs to update a workflow.yaml from an older schema to v2.4+. Triggers on "upgrade",
  "migrate version", "update schema", "deprecated types", "modernize", "schema upgrade".
allowed-tools: Read, Write, Edit, Glob, AskUserQuestion
---

# Upgrade Workflow Schema Version

Guides the user through upgrading a workflow.yaml from an older schema version to the latest
(v2.4+). Detects the current version from structure and fields, builds a step-by-step migration
plan, applies migrations in order with backup and idempotency, and verifies the result.

> **Migration Table:** `patterns/migration-table.md`
> **Idempotency Guards:** `patterns/idempotency-guards.md`
> **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`

---

## Overview

This skill performs a versioned, incremental upgrade of a single workflow.yaml file. Migrations
are applied one version step at a time (2.0 -> 2.1 -> 2.2 -> 2.3 -> 2.4), with each step
making specific structural changes. The skill:

- Detects current schema version from structural indicators (no version field required)
- Builds a migration plan showing all changes per version step
- Creates a timestamped backup before modifying anything
- Applies migrations idempotently (safe to re-run)
- Validates the upgraded workflow using `bp-author-skill-validate` logic
- Reports all changes with before/after details

**Target schema version:** 2.4 (required output + prompts configs, unified output config)

---

## Phase 1: Load & Detect Version

### Step 1.1: Path Resolution

If the user provided a path in the invocation arguments:

1. Validate the path exists using Read
2. Confirm the file is a YAML file containing `nodes:` and `start_node:` (minimal workflow indicators)
3. Store the full content in `computed.workflow_content`
4. Store the resolved absolute path in `computed.workflow_path`

If no path was provided, use AskUserQuestion to determine the target:

```json
{
  "questions": [{
    "question": "Which workflow.yaml would you like to upgrade?",
    "header": "Target",
    "multiSelect": false,
    "options": [
      {"label": "Provide path", "description": "I'll give you the workflow.yaml path"},
      {"label": "Search current directory", "description": "Find workflow.yaml files in this repo"},
      {"label": "Search plugin skills", "description": "Look in skills/ and skills-prose/ directories"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PATH_RESPONSE(response):
  SWITCH response:
    CASE "Provide path":
      # Ask follow-up for the path, then Read the file
      # If file does not exist or lacks workflow indicators, report error and re-prompt
      computed.workflow_path = user_provided_path
    CASE "Search current directory":
      files = Glob("**/workflow.yaml")
      # Exclude node_modules, .hiivmind, backup directories
      files = filter(files, not contains("node_modules", ".hiivmind", "backup"))
      # Present numbered list to user via AskUserQuestion
      computed.workflow_path = selected_file
    CASE "Search plugin skills":
      files = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/workflow.yaml")
      files += Glob("${CLAUDE_PLUGIN_ROOT}/skills-prose/*/workflow.yaml")
      # Present numbered list to user via AskUserQuestion
      computed.workflow_path = selected_file
```

Read the selected file and store content in `computed.workflow_content`.

### Step 1.2: Detect Schema Version

Read the workflow.yaml and detect the schema version from its structure and fields.
There is no explicit version field for the schema -- version is inferred from structural
indicators.

```pseudocode
function detect_version(workflow):
  has_output_config = has_field(workflow, "initial_state.output")
  has_prompts_config = has_field(workflow, "initial_state.prompts")
  has_validation_gate_nodes = any(node.type == "validation_gate" for node in workflow.nodes)
  has_unified_output = has_output_config AND has_field(workflow, "initial_state.output.log_enabled")
  has_separate_logging = has_field(workflow, "initial_state.logging") AND NOT has_unified_output

  # Version 2.4: Both output and prompts are present and required
  if has_output_config AND has_prompts_config:
    # Check if output config is unified (has log_enabled field)
    if has_unified_output:
      return "2.4"
    else:
      return "2.3"

  # Version 2.3: prompts config present but output may be missing or separate
  elif has_prompts_config:
    return "2.3"

  # Version 2.2: unified output config present but no prompts
  elif has_unified_output:
    return "2.2"

  # Version 2.1: no validation_gate nodes, but no unified output
  elif NOT has_validation_gate_nodes AND has_separate_logging:
    return "2.1"

  # Version 2.1: no validation_gate nodes, no logging config either
  elif NOT has_validation_gate_nodes:
    return "2.1"

  # Version 2.0: has validation_gate nodes (deprecated type still present)
  elif has_validation_gate_nodes:
    return "2.0"

  # Fallback: assume oldest supported version
  else:
    return "2.0"
```

Store in:

```yaml
computed:
  current_version: "2.X"  # detected version
  target_version: "2.4"   # always the latest
```

### Step 1.3: Display Version Status

Present the detected version to the user:

```
## Workflow Schema Version Detection

**File:** {computed.workflow_path}
**Current version:** {computed.current_version}
**Target version:** {computed.target_version}

{if computed.current_version == computed.target_version}
This workflow is already at the latest schema version. No migration needed.
{else}
Migration path: {computed.current_version} -> ... -> {computed.target_version}
{computed.migration_steps_count} migration step(s) required.
{/if}
```

If `computed.current_version == computed.target_version`, display the message and exit.
No further phases needed.

---

## Phase 2: Build Migration Plan

### Step 2.1: Determine Migration Steps

Build the ordered list of version transitions needed:

```pseudocode
function build_migration_path(current, target):
  version_sequence = ["2.0", "2.1", "2.2", "2.3", "2.4"]
  current_idx = index_of(version_sequence, current)
  target_idx = index_of(version_sequence, target)

  computed.migration_steps = []
  for i in range(current_idx, target_idx):
    from_ver = version_sequence[i]
    to_ver = version_sequence[i + 1]
    computed.migration_steps.append({
      from_version: from_ver,
      to_version: to_ver,
      changes: get_changes_for_step(from_ver, to_ver)
    })

  computed.migration_steps_count = len(computed.migration_steps)
```

### Step 2.2: List Changes Per Version Step

For each migration step, enumerate the specific structural changes. The full before/after
YAML examples for each change are documented in `patterns/migration-table.md`.

| From | To | Changes |
|------|----|---------|
| 2.0 | 2.1 | Remove `validation_gate` nodes, replace with `conditional` nodes using `audit` config. Map `validations` array to `condition.conditions` array. Add `audit.enabled: true` and `audit.output` field. |
| 2.1 | 2.2 | Unify separate `logging` and `display` configs into single `output` config under `initial_state.output`. Merge `logging.enabled` -> `output.log_enabled`, `logging.format` -> `output.log_format`, `logging.location` -> `output.log_location`. Merge `display.enabled` -> `output.display_enabled`, `display.batch` -> `output.batch_enabled`. |
| 2.2 | 2.3 | Add `prompts` configuration under `initial_state.prompts` for multi-modal support. Set interface to `auto`, configure mode defaults for `claude_code`, `web`, `api`, `agent`. |
| 2.3 | 2.4 | Make `output` and `prompts` configs required (not optional). If `output` is present but incomplete, fill in default values for missing fields. If `prompts` is present but incomplete, fill in default values. |

> **Detail:** See `patterns/migration-table.md` for complete before/after YAML examples for every change.

### Step 2.3: Check Already-Applied Migrations (Idempotency)

Before presenting the plan, check which migrations have already been applied. This makes
the skill safe to re-run on partially upgraded workflows.

```pseudocode
function check_idempotency(workflow, migration_steps):
  for step in migration_steps:
    step.already_applied = false

    if step.from_version == "2.0" AND step.to_version == "2.1":
      # Check if any validation_gate nodes still exist
      has_gates = any(node.type == "validation_gate" for node in workflow.nodes)
      step.already_applied = NOT has_gates

    elif step.from_version == "2.1" AND step.to_version == "2.2":
      # Check if unified output config exists and separate logging/display are gone
      has_unified = has_field(workflow, "initial_state.output.log_enabled")
      has_separate = has_field(workflow, "initial_state.logging")
      step.already_applied = has_unified AND NOT has_separate

    elif step.from_version == "2.2" AND step.to_version == "2.3":
      # Check if prompts config exists
      step.already_applied = has_field(workflow, "initial_state.prompts")

    elif step.from_version == "2.3" AND step.to_version == "2.4":
      # Check if both configs are present with all required fields
      output_complete = has_all_required_output_fields(workflow)
      prompts_complete = has_all_required_prompts_fields(workflow)
      step.already_applied = output_complete AND prompts_complete

  # Filter out already-applied steps
  computed.pending_steps = [s for s in migration_steps if NOT s.already_applied]
  computed.skipped_steps = [s for s in migration_steps if s.already_applied]
```

> **Detail:** See `patterns/idempotency-guards.md` for the full detection logic and content-hash
> backup mechanism.

### Step 2.4: Present Migration Plan for Confirmation

Display the plan and ask for confirmation:

```
## Migration Plan

**File:** {computed.workflow_path}
**Path:** {computed.current_version} -> {computed.target_version}
**Steps:** {len(computed.pending_steps)} pending, {len(computed.skipped_steps)} already applied

{for step in computed.migration_steps}
### {step.from_version} -> {step.to_version} {" [SKIP - already applied]" if step.already_applied else ""}
{for change in step.changes}
- {change.description}
{/for}
{/for}
```

Use AskUserQuestion to confirm:

```json
{
  "questions": [{
    "question": "Proceed with the migration plan above?",
    "header": "Confirm",
    "multiSelect": false,
    "options": [
      {"label": "Apply all pending migrations", "description": "Upgrade from {current} to {target}"},
      {"label": "Apply step-by-step", "description": "Confirm each migration step individually"},
      {"label": "Cancel", "description": "Do not modify the workflow"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_CONFIRM(response):
  SWITCH response:
    CASE "Apply all pending migrations":
      computed.apply_mode = "batch"
      GOTO Phase 3
    CASE "Apply step-by-step":
      computed.apply_mode = "interactive"
      GOTO Phase 3
    CASE "Cancel":
      DISPLAY "Migration cancelled. No changes made."
      EXIT
```

---

## Phase 3: Apply Migrations

### Step 3.1: Create Backup

Before modifying anything, create a timestamped backup of the original file:

```pseudocode
function create_backup(workflow_path):
  timestamp = format_timestamp(now(), "YYYYMMDD_HHmmss")
  computed.backup_path = workflow_path + ".backup." + timestamp

  # Read original content
  original = Read(workflow_path)

  # Write backup
  Write(computed.backup_path, original)

  # Compute content hash for deduplication guard
  computed.original_hash = sha256(original)

  DISPLAY "Backup created: {computed.backup_path}"
```

Store `computed.backup_path` and `computed.original_hash` for rollback and deduplication.

### Step 3.2: Apply Migrations in Order

Iterate through `computed.pending_steps` and apply each migration sequentially.

```pseudocode
function apply_all_migrations(workflow, pending_steps):
  computed.applied_changes = []

  for step in pending_steps:
    if computed.apply_mode == "interactive":
      # Ask user before each step
      confirmed = AskUserQuestion({
        "questions": [{
          "question": "Apply migration {step.from_version} -> {step.to_version}?",
          "header": "Step",
          "multiSelect": false,
          "options": [
            {"label": "Apply", "description": "Apply this migration step"},
            {"label": "Skip", "description": "Skip this step and continue"},
            {"label": "Stop", "description": "Stop here, keep changes so far"}
          ]
        }]
      })
      if confirmed == "Skip":
        continue
      if confirmed == "Stop":
        break

    changes = apply_migration(workflow, step.from_version, step.to_version)
    computed.applied_changes.extend(changes)

  # Write the modified workflow
  Write(computed.workflow_path, serialize_yaml(workflow))
```

**Migration functions by version step:**

```pseudocode
function apply_migration(workflow, from_version, to_version):
  changes = []

  if from_version == "2.0" AND to_version == "2.1":
    # ---- Remove validation_gate nodes, replace with conditional + audit ----
    for node_name, node in workflow.nodes:
      if node.type == "validation_gate":
        # Build replacement conditional node
        new_node = {
          type: "conditional",
          description: node.description,
          condition: {
            type: "all_of",
            conditions: []
          },
          audit: {
            enabled: true,
            output: "computed.validation_errors",
            messages: {}
          },
          branches: {
            on_true: node.on_valid,    # Map old field name
            on_false: node.on_invalid  # Map old field name
          }
        }

        # Map each validation to a condition entry
        for validation in node.validations:
          new_node.condition.conditions.append({
            type: validation.type,
            # Copy all params from the validation
            **validation.params
          })
          # Add audit message
          new_node.audit.messages[validation.type] = validation.error_message or
            "Validation failed: " + validation.type

        workflow.nodes[node_name] = new_node
        changes.append("Replaced validation_gate '{node_name}' with conditional + audit")

  elif from_version == "2.1" AND to_version == "2.2":
    # ---- Unify separate logging/display configs into output config ----
    old_logging = workflow.initial_state.get("logging", {})
    old_display = workflow.initial_state.get("display", {})

    unified_output = {
      level: old_logging.get("level", "normal"),
      display_enabled: old_display.get("enabled", true),
      batch_enabled: old_display.get("batch", {}).get("enabled", true),
      batch_threshold: old_display.get("batch", {}).get("threshold", 3),
      use_icons: old_display.get("use_icons", true),
      log_enabled: old_logging.get("enabled", true),
      log_format: old_logging.get("format", "yaml"),
      log_location: old_logging.get("location", ".logs/"),
      ci_mode: old_logging.get("ci_mode", false)
    }

    workflow.initial_state.output = unified_output

    # Remove old separate configs
    delete workflow.initial_state.logging
    delete workflow.initial_state.display

    changes.append("Unified logging + display configs into initial_state.output")
    if old_logging:
      changes.append("Migrated logging.enabled -> output.log_enabled")
      changes.append("Migrated logging.format -> output.log_format")
      changes.append("Migrated logging.location -> output.log_location")
    if old_display:
      changes.append("Migrated display.enabled -> output.display_enabled")
      changes.append("Migrated display.batch -> output.batch_enabled + batch_threshold")

  elif from_version == "2.2" AND to_version == "2.3":
    # ---- Add prompts configuration for multi-modal support ----
    workflow.initial_state.prompts = {
      interface: "auto",
      modes: {
        claude_code: "interactive",
        web: "forms",
        api: "structured",
        agent: "autonomous"
      },
      tabular: {
        match_strategy: "prefix",
        other_handler: "prompt"
      },
      autonomous: {
        strategy: "best_match",
        confidence_threshold: 0.7
      }
    }
    changes.append("Added initial_state.prompts config with multi-modal defaults")

  elif from_version == "2.3" AND to_version == "2.4":
    # ---- Make output and prompts required, fill missing defaults ----
    OUTPUT_DEFAULTS = {
      level: "normal", display_enabled: true, batch_enabled: true,
      batch_threshold: 3, use_icons: true, log_enabled: true,
      log_format: "yaml", log_location: ".logs/", ci_mode: false
    }
    PROMPTS_DEFAULTS = {
      interface: "auto",
      modes: { claude_code: "interactive", web: "forms", api: "structured", agent: "autonomous" },
      tabular: { match_strategy: "prefix", other_handler: "prompt" },
      autonomous: { strategy: "best_match", confidence_threshold: 0.7 }
    }

    # Ensure output config exists and is complete
    if NOT has_field(workflow, "initial_state.output"):
      workflow.initial_state.output = OUTPUT_DEFAULTS
      changes.append("Added missing required output config with defaults")
    else:
      for field, default in OUTPUT_DEFAULTS:
        if NOT has_field(workflow.initial_state.output, field):
          workflow.initial_state.output[field] = default
          changes.append("Added missing output field: {field} = {default}")

    # Ensure prompts config exists and is complete
    if NOT has_field(workflow, "initial_state.prompts"):
      workflow.initial_state.prompts = PROMPTS_DEFAULTS
      changes.append("Added missing required prompts config with defaults")
    else:
      for field, default in PROMPTS_DEFAULTS:
        if NOT has_field(workflow.initial_state.prompts, field):
          workflow.initial_state.prompts[field] = default
          changes.append("Added missing prompts field: {field}")

  return changes
```

### Step 3.3: Type Consolidation (v2.x to v3.0.0)

After schema migrations, detect and replace deprecated v2.x consequence and precondition
types with their consolidated v3.0.0 equivalents. This runs as a separate pass over all
nodes regardless of which schema migrations were applied.

**Consequence type consolidation:**

| Old v2.x Type | New v3.0.0 Type | Operation Parameter |
|----------------|-----------------|---------------------|
| `read_file` | `local_file_ops` | `operation: read` |
| `write_file` | `local_file_ops` | `operation: write` |
| `create_directory` | `local_file_ops` | `operation: mkdir` |
| `delete_file` | `local_file_ops` | `operation: delete` |
| `clone_repo` | `git_ops_local` | `operation: clone` |
| `git_pull` | `git_ops_local` | `operation: pull` |
| `git_fetch` | `git_ops_local` | `operation: fetch` |
| `get_sha` | `git_ops_local` | `operation: get-sha` |
| `web_fetch` | `web_ops` | `operation: fetch` |
| `cache_web_content` | `web_ops` | `operation: cache` |
| `run_script` | `run_command` | `interpreter: auto` |
| `run_python` | `run_command` | `interpreter: python` |
| `run_bash` | `run_command` | `interpreter: bash` |
| `set_state` | `mutate_state` | `operation: set` |
| `append_state` | `mutate_state` | `operation: append` |
| `clear_state` | `mutate_state` | `operation: clear` |
| `merge_state` | `mutate_state` | `operation: merge` |
| `log_event` | `log_entry` | `level: info` |
| `log_warning` | `log_entry` | `level: warning` |
| `log_error` | `log_entry` | `level: error` |
| `display_message` | `display` | `format: text` |
| `display_table` | `display` | `format: table` |

**Precondition type consolidation:**

| Old v2.x Type | New v3.0.0 Type | Parameter |
|----------------|-----------------|-----------|
| `flag_set` | `state_check` | `operator: true` |
| `flag_not_set` | `state_check` | `operator: false` |
| `state_equals` | `state_check` | `operator: equals` |
| `state_not_null` | `state_check` | `operator: not_null` |
| `state_is_null` | `state_check` | `operator: null` |
| `file_exists` | `path_check` | `check: exists` |
| `directory_exists` | `path_check` | `check: is_directory` |
| `config_exists` | `path_check` | `check: exists` |
| `tool_available` | `tool_check` | `capability: available` |
| `tool_version_gte` | `tool_check` | `capability: version_gte` |
| `tool_authenticated` | `tool_check` | `capability: authenticated` |
| `count_equals` | `evaluate_expression` | expression form |
| `count_above` | `evaluate_expression` | expression form |
| `count_below` | `evaluate_expression` | expression form |

```pseudocode
function consolidate_types(workflow):
  type_changes = []

  for node_name, node in workflow.nodes:
    # Consolidate consequence types in action nodes
    if node.type == "action" AND has_field(node, "actions"):
      for action in node.actions:
        old_type = action.type
        consolidated = CONSEQUENCE_MAP.get(old_type)
        if consolidated:
          action.type = consolidated.new_type
          action.operation = consolidated.operation_param
          type_changes.append(
            "Node '{node_name}': {old_type} -> {consolidated.new_type} (operation: {consolidated.operation_param})"
          )

    # Consolidate precondition types in conditional nodes
    if node.type == "conditional" AND has_field(node, "condition"):
      consolidate_condition(node.condition, node_name, type_changes)

    # Consolidate types in user_prompt on_response consequences
    if node.type == "user_prompt" AND has_field(node, "on_response"):
      for response_id, response in node.on_response:
        if has_field(response, "consequence"):
          for action in response.consequence:
            old_type = action.type
            consolidated = CONSEQUENCE_MAP.get(old_type)
            if consolidated:
              action.type = consolidated.new_type
              action.operation = consolidated.operation_param
              type_changes.append(
                "Node '{node_name}' response '{response_id}': {old_type} -> {consolidated.new_type}"
              )

  computed.type_changes = type_changes
  return type_changes
```

### Step 3.4: Content-Hash Deduplication Guards

After all migrations, compute the content hash of the result and compare against
`computed.original_hash` to detect no-op migrations:

```pseudocode
function check_deduplication():
  new_content = Read(computed.workflow_path)
  computed.result_hash = sha256(new_content)

  if computed.result_hash == computed.original_hash:
    DISPLAY "No changes detected. The workflow was already at the target state."
    DISPLAY "Removing unnecessary backup: {computed.backup_path}"
    # Delete the backup since no changes were made
    computed.changes_made = false
  else:
    computed.changes_made = true
```

> **Detail:** See `patterns/idempotency-guards.md` for the full content-hash and migration
> marker mechanisms.

---

## Phase 4: Verify Upgrade

### Step 4.1: Run Validation

Apply the same validation logic used by `bp-author-skill-validate` on the upgraded workflow.
Read the upgraded file and check across all four dimensions:

```pseudocode
function validate_upgraded_workflow(workflow_path):
  content = Read(workflow_path)
  computed.validation_results = {
    schema: validate_schema(content),
    graph: validate_graph(content),
    types: validate_types(content),
    state: validate_state(content)
  }
```

**Validation dimensions (summary):**

| Dimension | Checks |
|-----------|--------|
| Schema | Required top-level fields present, initial_state has output + prompts (v2.4), definitions.source set |
| Graph | All nodes reachable from start_node, all transitions target valid nodes/endings, no orphans |
| Types | All consequence types are valid v3.0.0 types, all precondition types are valid, no deprecated types remain |
| State | All `${field}` references resolve to declared state, no undefined computed.* references |

For the full validation procedure, defer to the `bp-author-skill-validate` skill documentation.

### Step 4.2: Confirm Migrations Applied

Cross-reference the changes recorded in `computed.applied_changes` and `computed.type_changes`
against the validation results:

```pseudocode
function confirm_migrations():
  computed.verification = {
    all_migrations_applied: len(computed.pending_steps) == len(computed.applied_steps),
    no_deprecated_types: computed.validation_results.types.deprecated_count == 0,
    schema_valid: computed.validation_results.schema.passed,
    graph_valid: computed.validation_results.graph.passed,
    overall: "pass" if all above else "fail"
  }
```

### Step 4.3: Handle Validation Failures

If validation fails, present the errors and ask the user how to proceed:

```json
{
  "questions": [{
    "question": "Validation found {error_count} issue(s) after migration. How would you like to proceed?",
    "header": "Issues",
    "multiSelect": false,
    "options": [
      {"label": "Review errors", "description": "Show detailed validation errors for manual review"},
      {"label": "Rollback", "description": "Restore the original file from backup"},
      {"label": "Continue anyway", "description": "Keep the upgraded file despite validation issues"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_VALIDATION_FAILURE(response):
  SWITCH response:
    CASE "Review errors":
      # Display all validation errors grouped by dimension
      for dimension in ["schema", "graph", "types", "state"]:
        errors = computed.validation_results[dimension].errors
        if errors:
          DISPLAY "### {dimension} errors ({len(errors)})"
          for error in errors:
            DISPLAY "- {error.message} (at {error.location})"
      # After review, ask again: rollback / continue / done
      GOTO Step 4.3  # Re-prompt after review

    CASE "Rollback":
      # Restore from backup
      backup_content = Read(computed.backup_path)
      Write(computed.workflow_path, backup_content)
      DISPLAY "Rolled back to original. Backup preserved at {computed.backup_path}."
      computed.final_status = "rolled_back"
      GOTO Phase 5

    CASE "Continue anyway":
      computed.final_status = "completed_with_warnings"
      GOTO Phase 5
```

If validation passes, set `computed.final_status = "completed"` and proceed to Phase 5.

---

## Phase 5: Report

### Step 5.1: Version Summary

Display the before and after version:

```
## Upgrade Report

**File:** {computed.workflow_path}
**Status:** {computed.final_status}

| | Version |
|--|---------|
| Before | {computed.current_version} |
| After | {computed.target_version} |
```

### Step 5.2: Changes Made

List all changes grouped by migration step:

```
### Changes Applied

{for step in computed.migration_steps where NOT step.already_applied}
#### {step.from_version} -> {step.to_version}
{for change in computed.applied_changes where change belongs to step}
- {change}
{/for}
{/for}

{if computed.type_changes}
#### Type Consolidation (v2.x -> v3.0.0)
{for change in computed.type_changes}
- {change}
{/for}
{/if}

{if computed.skipped_steps}
#### Skipped (already applied)
{for step in computed.skipped_steps}
- {step.from_version} -> {step.to_version}: already at target state
{/for}
{/if}
```

### Step 5.3: Verification Results

Display validation results per dimension:

```
### Verification

| Dimension | Status | Details |
|-----------|--------|---------|
| Schema | {pass/fail} | {computed.validation_results.schema.summary} |
| Graph | {pass/fail} | {computed.validation_results.graph.summary} |
| Types | {pass/fail} | {computed.validation_results.types.summary} |
| State | {pass/fail} | {computed.validation_results.state.summary} |

**Overall:** {computed.verification.overall}
**Backup:** {computed.backup_path}
```

### Step 5.4: Final Action

Ask the user for final disposition:

```json
{
  "questions": [{
    "question": "Upgrade complete. What would you like to do?",
    "header": "Done",
    "multiSelect": false,
    "options": [
      {"label": "Done", "description": "Accept the upgrade and finish"},
      {"label": "Show diff", "description": "Display a before/after diff of the workflow"},
      {"label": "Rollback", "description": "Restore the original file from backup"},
      {"label": "Delete backup", "description": "Remove the backup file (changes are final)"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_FINAL(response):
  SWITCH response:
    CASE "Done":
      DISPLAY "Upgrade complete. Backup preserved at {computed.backup_path}."
      EXIT

    CASE "Show diff":
      original = Read(computed.backup_path)
      upgraded = Read(computed.workflow_path)
      # Display a section-by-section comparison
      DISPLAY "### Diff: {computed.workflow_path}"
      DISPLAY diff(original, upgraded)
      # After showing diff, re-prompt with same options
      GOTO Step 5.4

    CASE "Rollback":
      backup_content = Read(computed.backup_path)
      Write(computed.workflow_path, backup_content)
      DISPLAY "Rolled back to original. Backup preserved at {computed.backup_path}."
      EXIT

    CASE "Delete backup":
      # Remove backup file
      DISPLAY "Backup deleted. Upgrade is final."
      EXIT
```

---

## State Flow

```
Phase 1                    Phase 2                       Phase 3                    Phase 4             Phase 5
──────────────────────────────────────────────────────────────────────────────────────────────────────────────
computed.workflow_path   -> computed.migration_steps   -> computed.backup_path    -> computed.validation -> Report
computed.workflow_content   computed.pending_steps        computed.applied_changes    _results             (assembled)
computed.current_version    computed.skipped_steps        computed.type_changes      computed.verification
computed.target_version     computed.apply_mode           computed.original_hash     computed.final_status
                                                          computed.result_hash
                                                          computed.changes_made
```

---

## Reference Documentation

- **Migration Table:** `patterns/migration-table.md` (local to this skill)
- **Idempotency Guards:** `patterns/idempotency-guards.md` (local to this skill)
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Type Definitions:** [hiivmind-blueprint-lib v3.0.0](https://github.com/hiivmind/hiivmind-blueprint-lib/tree/v3.0.0)
- **Blueprint Lib Version:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`

---

## Related Skills

- **Validate workflow:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/SKILL.md`
- **Create new skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-create/SKILL.md`
- **Analyze skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-analyze/SKILL.md`
- **Refactor skill:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-refactor/SKILL.md`
- **Discover plugin skills:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/SKILL.md`
