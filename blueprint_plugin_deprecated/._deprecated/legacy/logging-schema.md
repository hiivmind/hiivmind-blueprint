# Logging Schema

> **ARCHIVED:** This document is preserved for reference. The formal JSON Schema has been extracted to:
> - `lib/schema/logging-schema.json`

---

Defines the structure of workflow execution logs. This schema is domain-agnostic; plugins extend it with custom event types and domain-specific fields.

## Log Structure

```yaml
metadata:
  workflow_name: string
  workflow_version: string
  skill_name: string | null
  plugin_name: string | null
  execution_path: string
  session:
    id: string | null
    transcript_path: string | null
    invocation_index: number
    snapshot_points: []

parameters:
  key: value

execution:
  start_time: ISO8601
  end_time: ISO8601 | null
  duration_seconds: number | null
  outcome: OutcomeType | null
  ending_node: string | null

node_history:
  - node: string
    timestamp: ISO8601
    outcome: NodeOutcome
    details: object

events:
  - type: string
    timestamp: ISO8601
    data: object

warnings:
  - message: string
    timestamp: ISO8601
    node: string
    context: object

errors:
  - message: string
    error_type: string
    timestamp: ISO8601
    node: string
    context: object
    recoverable: boolean

summary: string | null
```

## OutcomeType Values

| Value | Meaning |
|-------|---------|
| `success` | All intended operations completed |
| `partial` | Some operations completed, some skipped/failed |
| `error` | Execution failed due to error |
| `cancelled` | User or system cancelled execution |

## NodeOutcome Values

| Value | Meaning |
|-------|---------|
| `success` | Node completed successfully |
| `skipped` | Node was skipped |
| `error` | Node failed with error |
| `blocked` | Node blocked by dependency |

---

## Related Documentation

- **JSON Schema:** `lib/schema/logging-schema.json`
- **Consequences:** `lib/consequences/definitions/core/logging.yaml`
