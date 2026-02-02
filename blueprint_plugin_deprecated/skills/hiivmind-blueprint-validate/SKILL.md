---
name: hiivmind-blueprint-validate
description: >
  This skill should be used when the user asks to "validate workflow", "check workflow YAML",
  "find workflow issues", "validate blueprint", "check for problems in workflow.yaml",
  "lint workflow", "verify workflow correctness", or wants to verify workflow structure.
  Triggers on "validate", "check workflow", "blueprint validate", "find issues", "lint",
  "verify workflow", or when user provides a workflow.yaml path for validation.
  Supports --mode=full|schema|graph|types|state to select validation scope.
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# Validate Workflow

Analyze workflow YAML files for consistency, completeness, and referential integrity.

**Invocation:**
- `/hiivmind-blueprint validate` - Full validation (all checks)
- `/hiivmind-blueprint validate schema` - JSON schema + yq structure validation only
- `/hiivmind-blueprint validate graph` - Reachability, cycles, dead ends
- `/hiivmind-blueprint validate types` - Precondition/consequence type validation
- `/hiivmind-blueprint validate state` - State variable validation
- `/hiivmind-blueprint validate --mode=full` - Explicit mode parameter

> **Pattern Documentation:**
> - Validation queries: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/legacy/validation-queries.md`
> - Report format: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/legacy/validation-report-format.md`
> - JSON Schemas: `${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema/workflow.json`, `${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema/intent-mapping.json`, `${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema/prompts-config.json`

---

## Overview

This skill validates workflow.yaml files against:
- **JSON Schema** - Validate against formal JSON Schema definitions (via check-jsonschema CLI)
- **Schema** - Required fields, node types, structure (yq-based)
- **Referential integrity** - Node references, transitions, endings
- **Graph** - Reachability, dead ends, cycles
- **Types** - Precondition/consequence type validity
- **State** - Variable references, unused state
- **User prompts** - Option handlers, header length, counts, mode configuration
- **Prompts configuration** - Mode, match strategy, other handler consistency
- **Endings** - Success/error types, message variables
- **Intent mapping** - Flag/rule validation (if intent-mapping.yaml present)

---

## Prerequisites

| Requirement | Check | Error Message |
|-------------|-------|---------------|
| yq installed | `which yq` | "yq is required. Install: https://github.com/mikefarah/yq" |
| check-jsonschema installed | `~/.rye/shims/check-jsonschema --version` | "check-jsonschema not found - JSON Schema validation will be skipped" |

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

### Step 2.0: Parse Mode Parameter

Check for explicit mode parameter or verb argument:

```
function parse_mode(args):
  # Check for verb argument (first positional arg)
  if args[0] in ["schema", "graph", "types", "state", "full"]:
    return args[0]

  # Check for --mode parameter
  if args.mode:
    return args.mode

  # Auto-detect from keywords in user input
  return detect_from_keywords(user_input)
```

### Step 2.1: Mode Definitions

| Mode | Description | Validation Phases |
|------|-------------|-------------------|
| `full` | Complete validation (default) | 3.0-3.9 (all) |
| `schema` | Structure validation | 3.0 (JSON Schema) + 3.1 (yq-based) |
| `graph` | Graph analysis | 3.3 (reachability, cycles, dead ends) |
| `types` | Type validation | 3.4 (precondition/consequence types) |
| `state` | State validation | 3.5 (variable references, unused state) |

### Step 2.2: Present Options (Interactive Mode)

If no mode specified and interactive:

```json
{
  "questions": [{
    "question": "What type of validation would you like?",
    "header": "Validation",
    "multiSelect": false,
    "options": [
      {"label": "Full validation (Recommended)", "description": "All checks: JSON Schema, references, graph, types, state"},
      {"label": "Schema only", "description": "JSON Schema + structure validation (yq-based)"},
      {"label": "Graph analysis", "description": "Find unreachable nodes, dead ends, cycles"},
      {"label": "Types", "description": "Validate precondition/consequence types"},
      {"label": "State", "description": "Validate state variables and references"}
    ]
  }]
}
```

### Step 2.3: Quick Command Detection

Detect validation mode from user input keywords:

| Keyword | Validation Mode |
|---------|-----------------|
| "validate workflow", "full validation", "full" | full |
| "check schema", "schema", "json schema" | schema |
| "find dead ends", "dead ends", "orphan", "graph" | graph |
| "check types", "type validation", "types" | types |
| "validate state", "state", "variables" | state |
| "check references", "references" | full (includes referential checks) |
| "check prompts", "user prompts" | full (includes prompt checks) |
| "validate intent", "intent mapping" | full (includes intent checks) |

---

## Phase 3: Run Validation

Execute validation checks based on selected mode. See `lib/workflow/legacy/validation-queries.md` for yq query patterns.

### 3.0: JSON Schema Validation (check-jsonschema CLI)

Validate against formal JSON Schema definitions using check-jsonschema CLI.

**Schema Files (from hiivmind-blueprint-lib):**
- `workflow.json` - Workflow YAML structure
- `intent-mapping.json` - Intent mapping structure
- `logging-config.json` - Logging configuration structure

**Validation Commands:**

```bash
# Set up schema paths
SCHEMA_DIR="${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema"
LIB_SCHEMA="file://${SCHEMA_DIR}/"

# Validate workflow.yaml
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  "$WORKFLOW_PATH"

# Validate intent-mapping.yaml (if present)
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/intent-mapping.json" \
  "$INTENT_MAPPING_PATH"

# Validate logging.yaml (if present)
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/logging-config.json" \
  "$LOGGING_CONFIG_PATH"
```

**JSON Schema Check Results:**

| Check | Severity |
|-------|----------|
| All required top-level fields present | Error |
| Node types match enum | Error |
| Node type-specific required fields present | Error |
| Precondition structure valid | Error |
| Consequence structure valid | Error |
| User prompt option count (2-4) | Error |
| Header max length (12 chars) | Error |
| Ending types match enum | Error |
| 3VL values match enum (T/F/U) | Error |

If check-jsonschema is not available, skip this phase and rely on yq-based validation below.

---

### 3.1: Schema Validation (yq-based)

| # | Check | yq Query | Severity |
|---|-------|----------|----------|
| 1 | `name` field present | `has("name")` | Error |
| 2 | `version` field present | `has("version")` | Error |
| 3 | `description` field present | `has("description")` | Warning |
| 4 | `start_node` field present | `has("start_node")` | Error |
| 5 | `nodes` object present | `has("nodes")` | Error |
| 6 | `nodes` is non-empty | `.nodes | length > 0` | Error |
| 7 | `endings` object present | `has("endings")` | Error |
| 8 | `initial_state` object present | `has("initial_state")` | Warning |
| 9 | `entry_preconditions` array present | `has("entry_preconditions")` | Warning |
| 10 | Valid node types | See validation-queries.md | Error |

**Node type-specific required fields:**

| Node Type | Required Fields |
|-----------|----------------|
| action | `actions`, `on_success`, `on_failure` |
| conditional | `condition`, `branches.on_true`, `branches.on_false` |
| user_prompt | `prompt.question`, `prompt.header`, `prompt.options`, `on_response` |
| validation_gate | `validations`, `on_valid`, `on_invalid` |
| reference | `doc`, `next_node` |

### 3.2: Referential Integrity

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 11 | `start_node` exists | Must exist in `nodes` | Error |
| 12 | `on_success` targets exist | All must be nodes or endings | Error |
| 13 | `on_failure` targets exist | All must be nodes or endings | Error |
| 14 | `branches.on_true` targets exist | All must be nodes or endings | Error |
| 15 | `branches.on_false` targets exist | All must be nodes or endings | Error |
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

Type validation uses an **extensible** approach:
- **Known types**: Validates required parameters ARE present (error if missing)
- **Unknown types**: Allows them through with warnings (preserves extensibility)

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 23 | Entry precondition types valid | Compare against type definitions | See below |
| 24 | Conditional condition types valid | Compare against type definitions | See below |
| 25 | Validation gate types valid | Compare against type definitions | See below |
| 26 | Action consequence types valid | Compare against type definitions | See below |
| 27a | Unknown precondition type | Type not in definitions | **Warning** |
| 27b | Unknown consequence type | Type not in definitions | **Warning** |
| 27c | Missing required precondition param | Known type, param missing | **Error** |
| 27d | Missing required consequence param | Known type, param missing | **Error** |
| 27e | Nested precondition params | Check params in all_of/any_of/xor_of/none_of | **Error** |
| 27f | Typo suggestions | Unknown type similar to known type | **Info** |

**Design Philosophy:**

| Type Status | Behavior |
|-------------|----------|
| Known type, all params present | ✅ Pass |
| Known type, missing required param | ❌ Error |
| Unknown type | ⚠️ Warning (allows extension) |
| Known type, extra params | ✅ Pass (forward-compatible) |

#### Step 3.4.1: Load Type Definitions

Load known types dynamically from hiivmind-blueprint-lib. Each YAML file is self-documenting with `type`, `description`, `parameters`, and evaluation/payload fields.

**Type Definitions Source:** `hiivmind/hiivmind-blueprint-lib@v2.0.0`

```bash
# Set schema directory (local development path - adjust as needed)
SCHEMA_DIR="${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib"

# Build precondition type lookup (type -> required params)
# Output: JSON object { "type_name": ["required_param1", "required_param2"], ... }
yq eval-all '
  [.preconditions[] | {
    "key": .type,
    "value": [.parameters[]? | select(.required == true) | .name]
  }] | from_entries
' "$SCHEMA_DIR"/preconditions/core/*.yaml "$SCHEMA_DIR"/preconditions/extensions/*.yaml \
  > /tmp/precondition_types.json

# Build consequence type lookup (type -> required params)
yq eval-all '
  [.consequences[] | {
    "key": .type,
    "value": [.parameters[]? | select(.required == true) | .name]
  }] | from_entries
' "$SCHEMA_DIR"/consequences/core/*.yaml "$SCHEMA_DIR"/consequences/extensions/*.yaml \
  > /tmp/consequence_types.json

# Get list of all known precondition type names
yq 'keys | .[]' /tmp/precondition_types.json > /tmp/known_preconditions.txt

# Get list of all known consequence type names
yq 'keys | .[]' /tmp/consequence_types.json > /tmp/known_consequences.txt
```

#### Step 3.4.2: Extract All Precondition Usages (Including Nested)

Preconditions can be nested in composites (`all_of`, `any_of`, `xor_of`, `none_of`). Extract from all locations:

```bash
# Extract precondition usages from workflow
# Returns: { "location": "...", "type": "file_exists", "params": ["path"] }

# 1. Entry preconditions (top-level)
yq '
  .entry_preconditions | to_entries | .[] |
  {
    "location": ("entry_preconditions[" + (.key | tostring) + "]"),
    "type": .value.type,
    "params": (.value | keys | map(select(. | test("^(type|conditions)$") | not)))
  }
' workflow.yaml > /tmp/used_preconditions.json

# 2. Conditional node conditions
yq '
  .nodes | to_entries | .[] |
  select(.value.type == "conditional") |
  {
    "location": ("nodes." + .key + ".condition"),
    "type": .value.condition.type,
    "params": (.value.condition | keys | map(select(. | test("^(type|conditions)$") | not)))
  }
' workflow.yaml >> /tmp/used_preconditions.json

# 3. Validation gate validations
yq '
  .nodes | to_entries | .[] |
  select(.value.type == "validation_gate") |
  .key as $node |
  .value.validations | to_entries | .[] |
  {
    "location": ("nodes." + $node + ".validations[" + (.key | tostring) + "]"),
    "type": .value.type,
    "params": (.value | keys | map(select(. | test("^(type|conditions)$") | not)))
  }
' workflow.yaml >> /tmp/used_preconditions.json

# 4. Extract nested preconditions in composites (recursively via .. operator)
yq '
  .. | select(type == "!!map" and has("conditions")) |
  .conditions[] | select(has("type")) |
  {
    "location": "nested_in_composite",
    "type": .type,
    "params": (keys | map(select(. | test("^(type|conditions)$") | not)))
  }
' workflow.yaml >> /tmp/used_preconditions.json
```

#### Step 3.4.3: Extract All Consequence Usages

```bash
# Extract all consequence usages from action nodes
# Returns: { "location": "nodes.action_id.actions[0]", "type": "clone_repo", "params": ["url", "dest"] }

# 1. From action node actions arrays
yq '
  .nodes | to_entries | .[] |
  select(.value.type == "action") |
  .key as $node_id |
  .value.actions | to_entries | .[] |
  {
    "location": ("nodes." + $node_id + ".actions[" + (.key | tostring) + "]"),
    "type": .value.type,
    "params": (.value | keys | map(select(. | test("^type$") | not)))
  }
' workflow.yaml > /tmp/used_consequences.json

# 2. From user_prompt on_response consequences
yq '
  .nodes | to_entries | .[] |
  select(.value.type == "user_prompt") |
  .key as $node_id |
  .value.on_response | to_entries | .[] |
  .key as $option_id |
  .value.consequence | to_entries | .[] |
  {
    "location": ("nodes." + $node_id + ".on_response." + $option_id + ".consequence[" + (.key | tostring) + "]"),
    "type": .value.type,
    "params": (.value | keys | map(select(. | test("^type$") | not)))
  }
' workflow.yaml >> /tmp/used_consequences.json
```

#### Step 3.4.4: Validate Precondition Types and Parameters

```bash
# For each used precondition, validate:
# 1. Type is known (warn if not)
# 2. Required params are present (error if missing)

while IFS= read -r usage; do
  TYPE=$(echo "$usage" | yq '.type')
  LOCATION=$(echo "$usage" | yq '.location')
  PARAMS=$(echo "$usage" | yq '.params | .[]' 2>/dev/null)

  # Check if type is known
  if ! grep -qx "$TYPE" /tmp/known_preconditions.txt; then
    # Check for typo (Levenshtein-like suggestion)
    SIMILAR=$(grep -i "^${TYPE:0:3}" /tmp/known_preconditions.txt | head -1)
    if [ -n "$SIMILAR" ]; then
      echo "INFO: Unknown precondition type '$TYPE' at $LOCATION. Did you mean: $SIMILAR?"
    else
      echo "WARNING: Unknown precondition type '$TYPE' at $LOCATION (may be custom extension)"
    fi
    continue  # Can't validate params for unknown type
  fi

  # Get required params for this type
  REQUIRED=$(yq ".\"$TYPE\" | .[]" /tmp/precondition_types.json 2>/dev/null)

  # Check each required param is present
  for param in $REQUIRED; do
    if ! echo "$PARAMS" | grep -qx "$param"; then
      echo "ERROR: Precondition '$TYPE' at $LOCATION missing required param: $param"
    fi
  done
done < <(yq -c '.[]?' /tmp/used_preconditions.json 2>/dev/null)
```

#### Step 3.4.5: Validate Consequence Types and Parameters

```bash
# For each used consequence, validate:
# 1. Type is known (warn if not)
# 2. Required params are present (error if missing)

while IFS= read -r usage; do
  TYPE=$(echo "$usage" | yq '.type')
  LOCATION=$(echo "$usage" | yq '.location')
  PARAMS=$(echo "$usage" | yq '.params | .[]' 2>/dev/null)

  # Check if type is known
  if ! grep -qx "$TYPE" /tmp/known_consequences.txt; then
    # Check for typo (Levenshtein-like suggestion)
    SIMILAR=$(grep -i "^${TYPE:0:3}" /tmp/known_consequences.txt | head -1)
    if [ -n "$SIMILAR" ]; then
      echo "INFO: Unknown consequence type '$TYPE' at $LOCATION. Did you mean: $SIMILAR?"
    else
      echo "WARNING: Unknown consequence type '$TYPE' at $LOCATION (may be custom extension)"
    fi
    continue  # Can't validate params for unknown type
  fi

  # Get required params for this type
  REQUIRED=$(yq ".\"$TYPE\" | .[]" /tmp/consequence_types.json 2>/dev/null)

  # Check each required param is present
  for param in $REQUIRED; do
    if ! echo "$PARAMS" | grep -qx "$param"; then
      echo "ERROR: Consequence '$TYPE' at $LOCATION missing required param: $param"
    fi
  done
done < <(yq -c '.[]?' /tmp/used_consequences.json 2>/dev/null)
```

#### Step 3.4.6: Composite Precondition Special Handling

Composite types (`all_of`, `any_of`, `xor_of`, `none_of`) require special validation:
- They must have a `conditions` array
- Each condition in the array is validated recursively (already handled in Step 3.4.2)

```bash
# Check composite types have conditions array using recursive descent (..)
# This finds ALL composite types anywhere in the document
yq '
  .. | select(type == "!!map" and has("type")) |
  select(.type | test("^(all_of|any_of|xor_of|none_of)$")) |
  {
    "type": .type,
    "has_conditions": has("conditions"),
    "conditions_is_array": (if has("conditions") then (.conditions | type) == "!!seq" else false end),
    "conditions_count": (if has("conditions") and ((.conditions | type) == "!!seq") then (.conditions | length) else 0 end)
  } |
  if .has_conditions | not then
    {"severity": "error", "message": ("Composite type " + .type + " missing conditions array")}
  elif .conditions_is_array | not then
    {"severity": "error", "message": ("Composite type " + .type + ": conditions must be an array")}
  elif .conditions_count == 0 then
    {"severity": "warning", "message": ("Composite type " + .type + " has empty conditions array")}
  else empty end
' workflow.yaml
```

#### Example Validation Output

```
══════════════════════════════════════
  Blueprint Workflow Validation Report
══════════════════════════════════════

Errors (2)
──────────
✗ [Type] clone_repo at nodes.clone_source.actions[0] missing required param: url
  Required params: url, dest
  Found: dest, depth

✗ [Type] flag_set at entry_preconditions[1] missing required param: flag
  Required params: flag
  Found: (none)

Warnings (1)
────────────
⚠ [Type] Unknown precondition type 'my_custom_check' at nodes.verify.condition
  May be a custom extension - cannot validate parameters

Info (1)
────────
ℹ [Type] Unknown precondition type 'filexists' at entry_preconditions[0]
  Did you mean: file_exists?
```

This approach:
- **Errors** on known types with missing params (blocks if found)
- **Warns** on unknown types (allows extensibility)
- **Suggests** typo fixes for close matches

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

### 3.6.1: Prompts Configuration Validation

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 36a | Valid prompt mode | Mode is "interactive" or "tabular" | Error |
| 36b | Valid match strategy | Strategy is "exact", "prefix", or "fuzzy" | Error |
| 36c | Valid other handler | Handler is "prompt", "route", or "fail" | Error |
| 36d | Other handler route requires on_response.other | If other_handler: "route", all user_prompt nodes must have on_response.other | Error |
| 36e | Fuzzy threshold in range | fuzzy_threshold between 0.0 and 1.0 | Error |
| 36f | Tabular config without tabular mode | tabular block present but mode != "tabular" | Warning |

**Check 36a-c: Valid Enum Values**

```bash
# Check prompts mode
yq '
  if .initial_state.prompts.mode then
    .initial_state.prompts.mode | select(. != "interactive" and . != "tabular")
  else empty end
' workflow.yaml

# Check match strategy
yq '
  if .initial_state.prompts.tabular.match_strategy then
    .initial_state.prompts.tabular.match_strategy |
    select(. != "exact" and . != "prefix" and . != "fuzzy")
  else empty end
' workflow.yaml

# Check other handler
yq '
  if .initial_state.prompts.tabular.other_handler then
    .initial_state.prompts.tabular.other_handler |
    select(. != "prompt" and . != "route" and . != "fail")
  else empty end
' workflow.yaml
```

**Check 36d: Other Handler Route Requires on_response.other**

```bash
# If other_handler is "route", check all user_prompt nodes have on_response.other
yq '
  if (.initial_state.prompts.tabular.other_handler == "route") then
    .nodes | to_entries | .[] |
    select(.value.type == "user_prompt") |
    select(.value.on_response.other == null) |
    .key
  else empty end
' workflow.yaml
```

If this returns any node names, emit error:
```
ERROR: other_handler is "route" but node "{node_name}" missing on_response.other
```

**Check 36e: Fuzzy Threshold Range**

```bash
yq '
  if .initial_state.prompts.tabular.fuzzy_threshold then
    .initial_state.prompts.tabular.fuzzy_threshold |
    select(. < 0 or . > 1)
  else empty end
' workflow.yaml
```

**Check 36f: Unused Tabular Config**

```bash
yq '
  if (.initial_state.prompts.tabular != null) and
     (.initial_state.prompts.mode != "tabular") then
    "tabular config present but mode is not tabular"
  else empty end
' workflow.yaml
```

### 3.7: Ending Validation

| # | Check | Description | Severity |
|---|-------|-------------|----------|
| 37 | At least one success ending | Must have success type | Error |
| 38 | Valid ending types | success, failure, error, or cancelled only | Error |
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

Validate logging configuration and usage consistency. See `lib/workflow/legacy/validation-queries.md` for yq patterns.

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

See `lib/workflow/legacy/validation-report-format.md` for complete format specification.

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

Quick reference for common validation queries. Full patterns in `lib/workflow/legacy/validation-queries.md`.

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
yq '[.start_node, (.nodes | to_entries | .[] | [.value.on_success, .value.on_failure, .value.branches.on_true, .value.branches.on_false, .value.next_node, (.value.on_response | .[]? | .next_node)] | .[] | select(. != null))] | unique | .[]' workflow.yaml
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
| `Unknown precondition type: X` | Use a known type from type definitions |
| `Orphan node: X` | Add transition to reach X or remove it |
| `Dead end: X` | Add on_success/on_failure or next_node |
| `Missing on_response handler for: X` | Add handler in on_response for option ID |
| `Header exceeds 12 chars` | Shorten prompt.header to 12 characters |

---

## Reference Documentation

- **Validation Queries:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/legacy/validation-queries.md`
- **Report Format:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/legacy/validation-report-format.md`
- **Workflow JSON Schema:** `${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema/workflow.json`
- **Intent Mapping JSON Schema:** `${CLAUDE_PLUGIN_ROOT}/../hiivmind-blueprint-lib/schema/intent-mapping.json`
- **Workflow Schema (docs):** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`

---

## Related Skills

- Analyze skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Upgrade workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-upgrade/SKILL.md`
- Discover workflows: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Validate lib types: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-lib-validation/SKILL.md`
