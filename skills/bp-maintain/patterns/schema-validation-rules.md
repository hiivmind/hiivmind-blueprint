# Schema Validation Rules

Rules for validating the structural correctness of a workflow.yaml file.

## Required Top-Level Sections

| Section | Required | Constraints |
|---------|----------|-------------|
| `name` | Yes | String, non-empty |
| `version` | No | Recommended; semver string |
| `description` | No | Recommended |
| `definitions` | No | Should have `source` if present |
| `definitions.source` | No | Format: `owner/repo@version` or local path |
| `entry_preconditions` | No | Array of precondition objects |
| `initial_state` | No | Map |
| `start_node` | Yes | Must reference a key in `nodes` |
| `nodes` | Yes | Map with at least 1 node |
| `endings` | Yes | Map with at least 1 ending |

## Node Type Validation

Every node must have a `type` field with one of these values:

- `action` — executes a sequence of consequence actions
- `conditional` — evaluates a precondition and branches
- `user_prompt` — presents a question to the user and routes based on response

## Transition Field Requirements

### Action Nodes

| Field | Required | Type |
|-------|----------|------|
| `actions` | Yes | Non-empty array of consequence objects |
| `on_success` | Yes | Target node ID or ending ID |
| `on_failure` | Yes | Target node ID or ending ID |
| `description` | No | String |

### Conditional Nodes

| Field | Required | Type |
|-------|----------|------|
| `condition` | Yes | Object with `type` field |
| `branches.on_true` | Yes | Target node ID or ending ID |
| `branches.on_false` | Yes | Target node ID or ending ID |
| `audit` | No | Object with `enabled` (boolean), `output` (string) |
| `description` | No | String |

### User Prompt Nodes

| Field | Required | Type |
|-------|----------|------|
| `prompt.question` | Yes | String |
| `prompt.header` | No | String |
| `prompt.options` | Yes* | Array of option objects |
| `prompt.options_from_state` | Yes* | String (state path) |
| `on_response` | Yes | Map with at least 1 handler |
| `description` | No | String |

*One of `prompt.options` or `prompt.options_from_state` is required.

Each `on_response` handler must have a `next_node` field.

## Target Validation

For every transition target (`on_success`, `on_failure`, `branches.on_true`,
`branches.on_false`, `on_response.*.next_node`):

1. If the target starts with `${` — dynamic target, log as **info**, cannot validate statically
2. Otherwise, verify the target exists as a key in `nodes` or `endings`
3. If not found — **error**

## Deprecated Pattern Detection

| Deprecated Pattern | Detection | Suggestion |
|-------------------|-----------|------------|
| `type: validation_gate` | Node type check | Use `type: conditional` with `audit.enabled: true` |
| Separate `output` and `logging` | Both at top level | Use unified `output` config (v2.4+) |
| `type: read_file` | Consequence type | Use `type: local_file_ops` with `operation: read` |
| `type: set_state` | Consequence type | Use `type: mutate_state` with `operation: set` |

Deprecated patterns are reported as **warnings**.
