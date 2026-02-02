# Intent Detection Consequences

> **ARCHIVED:** This document is preserved for reference. The authoritative source is:
> - `lib/consequences/definitions/core/intent.yaml`

---

Consequences for 3-valued logic (3VL) intent detection and dynamic routing.

> **See also:** `lib/intent_detection/framework.md` for 3VL semantics and `lib/intent_detection/execution.md` for detailed algorithms.

---

## evaluate_keywords

Match user input against keyword sets to detect intent.

```yaml
- type: evaluate_keywords
  input: "${arguments}"
  keyword_sets:
    init:
      - "create"
      - "new"
      - "index"
    refresh:
      - "update"
      - "sync"
      - "check"
  store_as: computed.detected_intent
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `input` | string | Yes | User input to match against |
| `keyword_sets` | object | Yes | Map of intent names to keyword arrays |
| `store_as` | string | Yes | State field for matched intent |

---

## parse_intent_flags

Parse user input and set 3-valued logic (3VL) flags for intent detection.

```yaml
- type: parse_intent_flags
  input: "${arguments}"
  flag_definitions: "${intent_flags}"
  store_as: computed.intent_flags
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `input` | string | Yes | User input to parse |
| `flag_definitions` | object | Yes | Map of flag names to keyword definitions |
| `store_as` | string | Yes | State field for flag values |

**3VL Values:**
| Value | Meaning |
|-------|---------|
| `T` | True - positive keyword matched |
| `F` | False - negative keyword matched |
| `U` | Unknown - no keywords matched |

---

## match_3vl_rules

Match 3VL flags against rule table and rank candidates.

```yaml
- type: match_3vl_rules
  flags: "${computed.intent_flags}"
  rules: "${intent_rules}"
  store_as: computed.intent_matches
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `flags` | object | Yes | Map of flag names to 3VL values (T/F/U) |
| `rules` | array | Yes | Array of intent rules with conditions |
| `store_as` | string | Yes | State field for match results |

---

## dynamic_route

Execute a dynamically determined action (node transition).

```yaml
- type: dynamic_route
  action: "${computed.intent_matches.winner.action}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `action` | string | Yes | Node name to transition to (interpolated) |

---

## Related Documentation

- **Parent:** [../README.md](../README.md) - Consequence taxonomy
- **Core consequences:** [workflow.md](workflow.md) - State, evaluation, control flow
- **Framework:** `lib/intent_detection/framework.md` - 3VL theory and semantics
- **Execution:** `lib/intent_detection/execution.md` - Algorithm details
