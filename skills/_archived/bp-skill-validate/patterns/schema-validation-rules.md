> **Used by:** `SKILL.md` Phase 3
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

# Schema Validation Rules

Complete field requirements and valid values for workflow.yaml schema validation.

---

## Top-Level Structure

| Field | Required | Type | Validation |
|-------|----------|------|------------|
| `name` | Yes | string | Non-empty, typically matches skill ID |
| `version` | Recommended | string | Semver format (e.g., `"1.0.0"`) |
| `description` | Recommended | string | Non-empty |
| `definitions` | Recommended | map | Should contain `source` |
| `definitions.source` | If definitions present | string | `owner/repo@version` or `./` or absolute path |
| `entry_preconditions` | No | array | Array of precondition objects |
| `initial_state` | Recommended | map | Arbitrary key-value structure |
| `start_node` | Yes | string | Must be a key in `nodes` |
| `nodes` | Yes | map | At least 1 node |
| `endings` | Yes | map | At least 1 ending |

---

## Node Field Requirements

### action

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `type` | Yes | string | Must be `"action"` |
| `description` | No | string | Human-readable purpose |
| `actions` | Yes | array | Non-empty; each element is a consequence object |
| `on_success` | Yes | string | Valid node ID or ending ID |
| `on_failure` | Yes | string | Valid node ID or ending ID |

Each consequence in `actions` must have:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `type` | Yes | string | Must be a valid consequence type |
| (varies) | Varies | - | Depends on consequence type |
| `store_as` | No | string | State path to store result |

### conditional

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `type` | Yes | string | Must be `"conditional"` |
| `description` | No | string | Human-readable purpose |
| `condition` | Yes | map | Must have `type` field |
| `condition.type` | Yes | string | Valid precondition type |
| `branches` | Yes | map | Must have `on_true` and `on_false` |
| `branches.on_true` | Yes | string | Valid node ID or ending ID |
| `branches.on_false` | Yes | string | Valid node ID or ending ID |
| `audit` | No | map | Optional audit mode configuration |

Audit mode fields (when `audit` is present):

| Field | Required | Default | Constraints |
|-------|----------|---------|-------------|
| `audit.enabled` | No | `false` | Boolean |
| `audit.output` | No | `computed.audit_results` | String state path |
| `audit.messages` | No | - | Map of type-to-message strings |

### user_prompt

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `type` | Yes | string | Must be `"user_prompt"` |
| `description` | No | string | Human-readable purpose |
| `prompt` | Yes | map | Contains question configuration |
| `prompt.question` | Yes | string | Non-empty question text |
| `prompt.header` | Yes | string | Max 12 characters |
| `prompt.options` | Yes* | array | Static option definitions |
| `prompt.options_from_state` | Yes* | string | State path for dynamic options |
| `prompt.option_mapping` | If dynamic | map | Transform fields: `id`, `label`, `description` |
| `on_response` | Yes | map | At least 1 handler |

*One of `options` or `options_from_state` is required.

Each static option must have:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `id` | Yes | string | Unique within options, matches handler key |
| `label` | Yes | string | Display label |
| `description` | No | string | Optional description |

Each response handler must have:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `next_node` | Yes | string | Valid node ID or ending ID |
| `consequence` | No | array | Optional array of consequences |

### reference

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `type` | Yes | string | Must be `"reference"` |
| `doc` | Yes* | string | Local document path |
| `workflow` | Yes* | string | Remote ref: `owner/repo@version:workflow-name` |
| `section` | No | string | Section heading (doc mode only) |
| `context` | No | map | Variables passed to sub-execution |
| `next_node` | Yes | string | Valid node ID or ending ID |

*One of `doc` or `workflow` is required.

---

## Ending Structure

Each ending must have:

| Field | Required | Type | Constraints |
|-------|----------|------|-------------|
| `type` | Yes | string | `"success"` or `"error"` |
| `message` | Yes | string | Human-readable outcome description |
| `summary` | No | map | Key-value pairs (success endings) |
| `category` | No | string | Error category (error endings) |
| `recovery` | No | string or map | Recovery instructions (error endings) |
| `details` | No | string | Additional context (error endings) |

---

## Valid Enum Values

### Node Types

```
["action", "conditional", "user_prompt", "reference"]
```

### Ending Types

```
["success", "error"]
```

### Output Levels (initial_state.output.level)

```
["silent", "quiet", "normal", "verbose", "debug"]
```

### Prompt Interfaces (initial_state.prompts.interface)

```
["auto", "claude_code", "web", "api", "agent"]
```

### Prompt Modes

```
["interactive", "tabular", "forms", "structured", "autonomous"]
```

### Tabular Match Strategies

```
["exact", "prefix", "fuzzy"]
```

### Tabular Other Handlers

```
["prompt", "route", "fail"]
```

### Autonomous Strategies

```
["best_match", "first_match", "weighted"]
```

---

## Version Compatibility Matrix

| Feature | Minimum Version | Notes |
|---------|----------------|-------|
| Basic workflow | v1.0.0 | name, nodes, endings, start_node |
| `definitions.source` | v1.0.0 | External type definitions |
| `entry_preconditions` | v1.0.0 | Pre-execution guards |
| Audit mode on conditional | v2.0.0 | Replaces `validation_gate` |
| Remote workflow references | v2.1.0 | `workflow` field on reference nodes |
| Unified output config | v2.4.0 | Single `output` replaces separate `logging` + `display` |
| Prompts config | v2.4.0 | Multi-modal prompt support |
| Consolidated types ({computed.lib_version}) | {computed.lib_version} | `local_file_ops`, `git_ops_local`, `web_ops`, etc. |

### Detecting Version from Content

```
function infer_workflow_version(workflow):
    if has_consolidated_types(workflow):      // local_file_ops, git_ops_local, etc.
        return "{computed.lib_version}"
    if has_prompts_config(workflow):          // initial_state.prompts
        return "v2.4.0"
    if has_remote_references(workflow):       // workflow field on reference nodes
        return "v2.1.0"
    if has_audit_mode(workflow):              // audit on conditional nodes
        return "v2.0.0"
    return "v1.0.0"
```

---

## Common Schema Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `start_node references unknown node` | Typo or missing node | Check spelling, add node if needed |
| `Node missing type` | Incomplete node definition | Add `type: action\|conditional\|user_prompt\|reference` |
| `Invalid node type` | Typo or deprecated type | Use one of the 4 valid types |
| `Missing on_success` | Incomplete action node | Add `on_success: <target>` |
| `Missing on_failure` | Incomplete action node | Add `on_failure: <error_ending>` |
| `Missing branches` | Incomplete conditional | Add `branches: { on_true: ..., on_false: ... }` |
| `Missing on_response` | Incomplete user_prompt | Add `on_response:` with at least 1 handler |
| `Empty actions array` | Action node with no consequences | Add at least 1 consequence to `actions` |
| `Handler missing next_node` | Incomplete response handler | Add `next_node: <target>` to handler |
| `Missing prompt.question` | Incomplete user_prompt | Add `question:` to prompt |
| `Header too long` | Exceeds 12 chars | Shorten `prompt.header` to 12 chars max |

---

## Related Documentation

- **Node Features:** `${CLAUDE_PLUGIN_ROOT}/references/node-features.md`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
