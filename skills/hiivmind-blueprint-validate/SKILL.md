---
name: hiivmind-blueprint-validate
description: >
  This skill should be used when the user asks to "validate workflow", "check workflow YAML",
  "find workflow issues", "validate blueprint", "check for problems in workflow.yaml",
  "lint workflow", "verify workflow correctness", or wants to verify workflow structure.
  Triggers on "validate", "check workflow", "blueprint validate", "find issues", "lint",
  "verify workflow", or when user provides a workflow.yaml path for validation.
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# Validate Workflow

Analyze workflow YAML files for consistency, completeness, and referential integrity.

> **Pattern Documentation:**
> - Validation queries: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/validation-queries.md`
> - Report format: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/validation-report-format.md`
> - JSON Schemas: `${CLAUDE_PLUGIN_ROOT}/lib/schema/workflow-schema.json`, `${CLAUDE_PLUGIN_ROOT}/lib/schema/intent-mapping-schema.json`

---

## Overview

This skill validates workflow.yaml files against:
- **JSON Schema** - Validate against formal JSON Schema definitions
- **Schema** - Required fields, node types, structure (yq-based)
- **Referential integrity** - Node references, transitions, endings
- **Graph** - Reachability, dead ends, cycles
- **Types** - Precondition/consequence type validity
- **State** - Variable references, unused state
- **User prompts** - Option handlers, header length, counts
- **Endings** - Success/error types, message variables
- **Intent mapping** - Flag/rule validation (if intent-mapping.yaml present)

---

## Prerequisites

| Requirement | Check | Error Message |
|-------------|-------|---------------|
| yq installed | `which yq` | "yq is required. Install: https://github.com/mikefarah/yq" |
| python3 + jsonschema (optional) | `python3 -c "import jsonschema"` | "jsonschema not installed - JSON Schema validation will be skipped" |

---

## Phase 1: Locate Workflow

### Step 1.1: Determine Target Workflow

If user provided a path:
1. Validate the path exists
2. Read the workflow.yaml file
3. Store path in `computed.workflow_path`

If no path provided:
1. **Ask user** which workflow to validate:
   ```json
   {
     "questions": [{
       "question": "Which workflow would you like to validate?",
       "header": "Target",
       "multiSelect": false,
       "options": [
         {"label": "Provide path", "description": "I'll give you the workflow.yaml path"},
         {"label": "Search current directory", "description": "Look for workflow.yaml files here"},
         {"label": "Gateway command", "description": "Validate commands/*/workflow.yaml"}
       ]
     }]
   }
   ```
2. Based on response:
   - **Provide path**: Ask for the path, then read file
   - **Search current directory**: Glob for `**/workflow.yaml`, present list
   - **Gateway command**: Check `commands/*/workflow.yaml`

### Step 1.2: Check yq Availability

```bash
which yq
```

If not found, display error:
```
yq is required for workflow validation.

Install via:
  brew install yq          # macOS
  apt install yq           # Debian/Ubuntu
  snap install yq          # Snap
  go install github.com/mikefarah/yq/v4@latest  # Go
```

### Step 1.3: Check for Intent Mapping

Look for `intent-mapping.yaml` in same directory as workflow.yaml:
- If found, set flag `intent_mapping_present = true`
- Load content for intent validation phase

---

## Phase 2: Select Validation Mode

### Step 2.1: Present Validation Options

```json
{
  "questions": [{
    "question": "What type of validation would you like?",
    "header": "Validation",
    "multiSelect": false,
    "options": [
      {"label": "Full validation (Recommended)", "description": "All checks: JSON Schema, references, graph, types, state"},
      {"label": "JSON Schema only", "description": "Validate against formal JSON Schema definitions"},
      {"label": "Schema only", "description": "Check required fields and structure (yq-based)"},
      {"label": "Graph analysis", "description": "Find unreachable nodes, dead ends, cycles"}
    ]
  }]
}
```

### Step 2.2: Quick Command Detection

Detect validation type from user input keywords:

| Keyword | Validation Mode |
|---------|-----------------|
| "validate workflow", "full validation" | Full validation |
| "check schema", "schema" | Schema only |
| "find dead ends", "dead ends", "orphan" | Graph analysis |
| "check references", "references" | Referential integrity |
| "check types", "type validation" | Type validation |
| "validate state", "state" | State validation |
| "check prompts", "user prompts" | User prompt validation |
| "validate intent", "intent mapping" | Intent mapping |

---

## Phase 3: Run Validation

Execute validation checks based on selected mode. See `lib/workflow/validation-queries.md` for yq query patterns.

### 3.0: JSON Schema Validation (Optional)

If `python3` with `jsonschema` module is available, validate against formal JSON Schema definitions first.

**Schema Files:**
- `${CLAUDE_PLUGIN_ROOT}/lib/schema/workflow-schema.json` - Workflow YAML structure
- `${CLAUDE_PLUGIN_ROOT}/lib/schema/intent-mapping-schema.json` - Intent mapping structure

**Validation Command:**

```python
#!/usr/bin/env python3
import json
import yaml
import jsonschema
import sys

# Load schema
with open('lib/schema/workflow-schema.json') as f:
    schema = json.load(f)

# Load workflow (YAML to dict)
with open(sys.argv[1]) as f:
    workflow = yaml.safe_load(f)

# Validate
try:
    jsonschema.validate(workflow, schema)
    print("Schema validation passed")
except jsonschema.ValidationError as e:
    print(f"Schema validation failed: {e.message}")
    print(f"Path: {'.'.join(str(p) for p in e.absolute_path)}")
    sys.exit(1)
```

**Inline validation via bash:**

```bash
python3 -c "
import json, yaml, sys
try:
    import jsonschema
except ImportError:
    print('jsonschema not installed - skipping')
    sys.exit(0)

with open('${CLAUDE_PLUGIN_ROOT}/lib/schema/workflow-schema.json') as f:
    schema = json.load(f)
with open('$WORKFLOW_PATH') as f:
    workflow = yaml.safe_load(f)
try:
    jsonschema.validate(workflow, schema)
    print('JSON Schema: PASS')
except jsonschema.ValidationError as e:
    print(f'JSON Schema: FAIL - {e.message}')
    print(f'  Path: {\".\".join(str(p) for p in e.absolute_path)}')
    sys.exit(1)
"
```

**JSON Schema Check Results:**

| Check | Severity |
|-------|----------|
| All required top-level fields present | Error |
| Node types match enum | Error |
| Node type-specific required fields present | Error |
| Precondition types match oneOf | Error |
| Consequence types match oneOf | Error |
| User prompt option count (2-4) | Error |
| Header max length (12 chars) | Error |
| Ending types match enum | Error |
| 3VL values match enum (T/F/U) | Error |

If jsonschema is not available, skip this phase and rely on yq-based validation below.

---

### 3.1: Schema Validation (yq-based)

| # | Check | yq Query | Severity |
|---|-------|----------|----------|
| 1 | `name` field present | `has("name")` | Error |
| 2 | `version` field present | `has("version")` | Error |
| 3 | `description` field present | `has("description")` | Warning |
| 4 | `start_node` field present | `has("start_node")` | Error |
| 5 | `nodes` object present | `has("nodes")` | Error |
| 6 | `nodes` is non-empty | `.nodes \| length > 0` | Error |
| 7 | `endings` object present | `has("endings")` | Error |
| 8 | `initial_state` object present | `has("initial_state")` | Warning |
| 9 | `entry_preconditions` array present | `has("entry_preconditions")` | Warning |
| 10 | Valid node types | See validation-queries.md | Error |

**Node type-specific required fields:**

| Node Type | Required Fields |
|-----------|----------------|
| action | `actions`, `on_success`, `on_failure` |
| conditional | `condition`, `branches.true`, `branches.false` |
| user_prompt | `prompt.question`, `prompt.header`, `prompt.options`, `on_response` |
| validation_gate | `validations`, `on_valid`, `on_invalid` |
| reference | `doc`, `next_node` |

### 3.2: Referential Integrity

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 11 | `start_node` exists | Must exist in `nodes` | Error |
| 12 | `on_success` targets exist | All must be nodes or endings | Error |
| 13 | `on_failure` targets exist | All must be nodes or endings | Error |
| 14 | `branches.true` targets exist | All must be nodes or endings | Error |
| 15 | `branches.false` targets exist | All must be nodes or endings | Error |
| 16 | `next_node` targets exist | All must be nodes or endings | Error |
| 17 | `on_response.*.next_node` targets exist | All must be nodes or endings | Error |
| 18 | Reference `doc` paths exist | File must exist | Warning |

### 3.3: Graph Analysis

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 19 | No orphan nodes | All nodes reachable from start | Warning |
| 20 | No dead ends | All paths lead to endings | Error |
| 21 | Cycle detection | Warn if cycles without user_prompt exit | Warning |
| 22 | Single-path detection | Warn if only one path through | Info |

**Reachability Algorithm:**

```
1. Initialize visited = {start_node}
2. Initialize queue = [start_node]
3. While queue not empty:
   a. Pop node from queue
   b. Get all destinations (on_success, on_failure, branches, on_response)
   c. For each destination not in visited and not an ending:
      - Add to visited
      - Add to queue
4. Orphan nodes = nodes - visited
```

### 3.4: Type Validation

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 23 | Entry precondition types known | Compare against preconditions.md | Error |
| 24 | Conditional condition types known | Compare against preconditions.md | Error |
| 25 | Validation gate types known | Compare against preconditions.md | Error |
| 26 | Action consequence types known | Compare against consequences.md | Error |
| 27 | Required parameters present | Type-specific parameter validation | Error |

**Known Precondition Types:**
```
config_exists, index_exists, index_is_placeholder, file_exists, directory_exists,
source_exists, source_cloned, source_has_updates, tool_available, python_module_available,
flag_set, flag_not_set, state_equals, state_not_null, state_is_null,
count_equals, count_above, count_below, fetch_succeeded, fetch_returned_content,
all_of, any_of, none_of, evaluate_expression
```

**Known Consequence Types:**
```
# Core: workflow.md
set_flag, set_state, append_state, clear_state, merge_state,
evaluate, compute, display_message, display_table,
invoke_pattern, create_checkpoint, rollback_checkpoint, spawn_agent,
set_timestamp, compute_hash, invoke_skill,
# Core: intent-detection.md
evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route,
# Core: logging.md
init_log, log_node, log_event, log_warning, log_error,
log_session_snapshot, finalize_log, write_log, apply_log_retention, output_ci_summary,
# Extensions
read_config, read_file, write_file, create_directory, delete_file,
write_config_entry, add_source, update_source, clone_repo, get_sha, git_pull, git_fetch,
web_fetch, cache_web_content, discover_installed_corpora
```

### 3.5: State/Variable Validation

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 28 | `${...}` syntax valid | Parseable variable references | Error |
| 29 | Initial state referenced | Fields in initial_state used somewhere | Warning |
| 30 | Flags balance | set_flag flags have matching flag_set checks | Info |
| 31 | store_as referenced | Stored values are used | Warning |
| 32 | Variable paths valid | No undefined nesting | Error |

### 3.6: User Prompt Validation

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 33 | All options have handlers | Each option.id in on_response | Error |
| 34 | No duplicate option IDs | Unique within each prompt | Error |
| 35 | Header max 12 chars | `prompt.header` length | Warning |
| 36 | 2-4 options per prompt | Option count in valid range | Warning |

### 3.7: Ending Validation

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 37 | At least one success ending | Must have success type | Error |
| 38 | Valid ending types | success or error only | Error |
| 39 | Message variable references | Variables in message resolvable | Warning |
| 40 | Recovery skill exists | If specified, skill should exist | Info |

### 3.8: Intent Mapping Validation (if present)

Only run if `intent-mapping.yaml` exists alongside workflow.yaml.

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 41 | All flags have keywords | intent_flags.*.keywords non-empty | Error |
| 42 | All rules reference valid flags | Rule conditions use defined flags | Error |
| 43 | All rule actions map to nodes | Action targets exist in workflow | Error |
| 44 | 3VL values valid | Only T, F, U in conditions | Error |

### 3.9: Logging Validation

Validate logging configuration and usage consistency. See `lib/workflow/validation-queries.md` for yq patterns.

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 45 | Config enabled but no init_log | logging.enabled=true but no init_log consequence | Warning |
| 46 | init_log without finalize_log | Incomplete logging lifecycle | Error |
| 47 | write_log without finalize_log | Writing unfinalized log | Error |
| 48 | Level mismatch | Config level doesn't permit used consequences | Warning |
| 49 | Retention without write_log | apply_log_retention but no write_log | Warning |
| 50 | Deprecated extensions/logging.md | Reference to old path | Warning |

**Check 45: Config Enabled Without init_log**

```bash
yq '
  (.initial_state.logging.enabled == true) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "init_log")] | length == 0)
' workflow.yaml
```

**Check 46: init_log Without finalize_log**

```bash
yq '
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "init_log")] | length > 0) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "finalize_log")] | length == 0)
' workflow.yaml
```

**Check 47: write_log Without finalize_log**

```bash
yq '
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "write_log")] | length > 0) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "finalize_log")] | length == 0)
' workflow.yaml
```

**Check 48: Level Mismatch**

```bash
# Check if log_event used with error/warn level config
yq '
  (.initial_state.logging.level == "error" or .initial_state.logging.level == "warn") and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "log_event")] | length > 0)
' workflow.yaml
```

**Check 49: Retention Without write_log**

```bash
yq '
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "apply_log_retention")] | length > 0) and
  ([.nodes | to_entries | .[] | .value.actions[]? | select(.type == "write_log")] | length == 0)
' workflow.yaml
```

**Check 50: Deprecated Path Reference**

```bash
# Check SKILL.md or workflow.yaml for old path
grep -l "extensions/logging.md" *.md *.yaml 2>/dev/null
```

---

## Phase 4: Generate Report

### Step 4.1: Aggregate Results

Collect all check results:

```yaml
computed:
  results:
    schema:
      passed: 9
      failed: 1
      warnings: 0
      checks:
        - id: 1
          name: "name field present"
          status: "passed"
        - id: 5
          name: "nodes object present"
          status: "failed"
          message: "nodes is missing"
          line: null
    referential:
      passed: 7
      failed: 1
      warnings: 0
      checks: [...]
    # ... other categories
```

### Step 4.2: Format Report

See `lib/workflow/validation-report-format.md` for complete format specification.

**Report Structure:**

```
══════════════════════════════════════
  Blueprint Workflow Validation Report
══════════════════════════════════════

Workflow: {workflow_name}
Version: {version}
Path: {workflow_path}

Summary
───────
{for each category}
{status_icon} {category}: {passed}/{total} checks passed
{/for}

{if errors}
Errors ({count})
────────────────
{for each error}
✗ [{category}] {check_name} (line {line})
  {description}
  Suggested fix: {fix}
{/for}
{/if}

{if warnings}
Warnings ({count})
──────────────────
{for each warning}
⚠ [{category}] {check_name} (line {line})
  {description}
  Suggested fix: {fix}
{/for}
{/if}

{if info}
Info ({count})
──────────────
{for each info}
ℹ [{category}] {check_name}
  {description}
{/for}
{/if}

Passed Checks: {total_passed}/{total_checks}
```

**Status Icons:**
- `✓` - All checks passed
- `⚠` - Warnings present (no errors)
- `✗` - Errors present

### Step 4.3: Display Report

Output the formatted report directly to the user.

---

## Validation Results Structure

Each check produces a result object:

```yaml
check_result:
  id: 11                    # Check number
  category: "referential"   # Validation category
  name: "start_node exists" # Human-readable name
  status: "failed"          # passed | failed | warning | info
  severity: "error"         # error | warning | info
  message: "start_node 'init' not found in nodes"
  line: 12                  # Line number in YAML (if available)
  suggested_fix: "Add 'init' to nodes or change start_node"
```

---

## yq Query Examples

Quick reference for common validation queries. Full patterns in `lib/workflow/validation-queries.md`.

### Check required fields

```bash
yq 'has("name") and has("version") and has("start_node") and has("nodes") and has("endings")' workflow.yaml
```

### Get all valid targets

```bash
yq '(.nodes | keys) + (.endings | keys) | .[]' workflow.yaml
```

### Find invalid node types

```bash
yq '[.nodes | to_entries | .[] | .value.type] | unique | .[] | select(. != "action" and . != "conditional" and . != "user_prompt" and . != "validation_gate" and . != "reference")' workflow.yaml
```

### Find orphan nodes

```bash
# Get start_node and all destinations
yq '[.start_node, (.nodes | to_entries | .[] | [.value.on_success, .value.on_failure, .value.branches.true, .value.branches.false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null))] | unique | .[]' workflow.yaml
```

### Check user prompt headers

```bash
yq '.nodes | to_entries | .[] | select(.value.type == "user_prompt" and (.value.prompt.header | length) > 12) | {node: .key, header: .value.prompt.header, length: (.value.prompt.header | length)}' workflow.yaml
```

---

## Error Messages and Fixes

### Common Errors

| Error | Suggested Fix |
|-------|---------------|
| `start_node not found in nodes` | Add the node to `nodes:` or correct `start_node` |
| `Invalid transition target: X` | Add X to nodes/endings or fix the reference |
| `Unknown precondition type: X` | Use a known type from preconditions.md |
| `Orphan node: X` | Add transition to reach X or remove it |
| `Dead end: X` | Add on_success/on_failure or next_node |
| `Missing on_response handler for: X` | Add handler in on_response for option ID |
| `Header exceeds 12 chars` | Shorten prompt.header to 12 characters |

---

## Reference Documentation

- **Validation Queries:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/validation-queries.md`
- **Report Format:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/validation-report-format.md`
- **Workflow JSON Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/schema/workflow-schema.json`
- **Intent Mapping JSON Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/schema/intent-mapping-schema.json`
- **Workflow Schema (docs):** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`
- **Preconditions:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/preconditions.md`
- **Consequences:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/consequences.md`

---

## Related Skills

- Analyze skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Visualize workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-visualize/SKILL.md`
- Upgrade workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-upgrade/SKILL.md`
- Discover workflows: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
