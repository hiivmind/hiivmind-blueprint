# Intent Detection Consequences

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

**Effect:**
```
FOR each keyword_set IN keyword_sets:
  FOR each keyword IN keyword_set.keywords:
    IF input.toLowerCase().includes(keyword.toLowerCase()):
      set_state_value(store_as, keyword_set.name)
      RETURN success
set_state_value(store_as, null)
RETURN success
```

Matches the **first** keyword set that contains a phrase found in the input (case-insensitive). Returns null if no match found.

> **Note:** For compound intent handling, use `parse_intent_flags` + `match_3vl_rules` instead.

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

**Flag Definition Structure:**
```yaml
intent_flags:
  has_help:
    keywords: ["help", "how do i", "?"]
    negative_keywords: ["don't help"]  # Optional
    description: "User is asking for help"
```

**3VL Values:**
| Value | Meaning |
|-------|---------|
| `T` | True - positive keyword matched |
| `F` | False - negative keyword matched |
| `U` | Unknown - no keywords matched |

**Effect:**
```
flags = {}
FOR each flag_name, definition IN flag_definitions:
  flags[flag_name] = U  # Default: Unknown

  # Check negative keywords first (more specific)
  IF definition.negative_keywords:
    FOR each keyword IN definition.negative_keywords:
      IF input.toLowerCase().includes(keyword.toLowerCase()):
        flags[flag_name] = F  # False
        BREAK

  # Check positive keywords (if not already F)
  IF flags[flag_name] != F:
    FOR each keyword IN definition.keywords:
      IF input.toLowerCase().includes(keyword.toLowerCase()):
        flags[flag_name] = T  # True
        BREAK

set_state_value(store_as, flags)
RETURN success
```

**Example Result:**
```yaml
computed.intent_flags:
  has_help: T
  has_init: T
  has_modify: U
  has_query: U
```

---

## match_3vl_rules

Match 3VL flags against rule table and rank candidates.

> **See also:** `lib/intent_detection/framework.md` for scoring semantics and winner determination.

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

**Rule Structure:**
```yaml
intent_rules:
  - name: "help_with_init"
    conditions:
      has_help: T
      has_init: T
    action: delegate_init
    priority: 80
    description: "Help me initialize..."
```

**3VL Matching Semantics:**

| State | Rule | Result | Rationale |
|-------|------|--------|-----------|
| T | T | +2 (hard match) | Requirement fully satisfied |
| F | F | +2 (hard match) | Absence requirement confirmed |
| T | U | +1 (soft match) | State has info, rule doesn't care |
| U | T | +1 (soft match) | Rule wants it, state is unknown |
| F | U | +1 (soft match) | State has info, rule doesn't care |
| U | F | +1 (soft match) | Rule wants absence, state is unknown |
| U | U | 0 (no score) | Neither specifies |
| F | T | **EXCLUDED** | Rule requires presence, state says absent |
| T | F | **EXCLUDED** | Rule requires absence, state says present |

**Effect:**
```
candidates = []
FOR each rule IN rules:
  score = 0
  excluded = false

  FOR each condition_key, rule_val IN rule.conditions:
    state_val = flags[condition_key] || U  # Default to Unknown

    IF (state_val == T AND rule_val == T) OR (state_val == F AND rule_val == F):
      score += 2  # Hard match
    ELSE IF (state_val == T AND rule_val == F) OR (state_val == F AND rule_val == T):
      excluded = true  # Exclusion
      BREAK
    ELSE IF state_val == U AND rule_val == U:
      score += 0  # No contribution
    ELSE:
      score += 1  # Soft match (any other combination)

  IF NOT excluded:
    candidates.append({ rule: rule, score: score })

# Sort by score (descending), then priority (descending)
candidates.sort(by: (-score, -priority))

# Determine if clear winner
IF candidates.length >= 2:
  clear_winner = (candidates[0].score >= candidates[1].score + 2)
ELSE IF candidates.length == 1:
  clear_winner = true
ELSE:
  clear_winner = false

result = {
  clear_winner: clear_winner,
  winner: candidates[0].rule if clear_winner else null,
  top_candidates: candidates[0..2],  # Top 3 for disambiguation
  all_candidates: candidates
}

set_state_value(store_as, result)
RETURN success
```

**Example Result:**
```yaml
computed.intent_matches:
  clear_winner: true
  winner:
    name: "help_with_init"
    action: delegate_init
    priority: 80
  top_candidates:
    - rule: { name: "help_with_init", ... }
      score: 4
    - rule: { name: "init_only", ... }
      score: 3
```

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

**Effect:**
```
target_node = interpolate(action)
# The workflow engine uses this as the next node
set_state_value("computed.dynamic_target", target_node)
RETURN success
```

The workflow engine should check for `computed.dynamic_target` after this consequence and use it as the next node if `on_success` is not explicitly set.

**Note:** This consequence enables rule-based routing where the target node is determined at runtime from state values.

---

## Common Patterns

### Full Intent Detection Pipeline

```yaml
nodes:
  parse_intent:
    type: action
    actions:
      - type: parse_intent_flags
        input: "${arguments}"
        flag_definitions:
          has_create: { keywords: ["create", "new", "init"] }
          has_update: { keywords: ["update", "refresh", "sync"] }
          has_query: { keywords: ["find", "search", "where"] }
        store_as: computed.flags
    on_success: match_rules

  match_rules:
    type: action
    actions:
      - type: match_3vl_rules
        flags: "${computed.flags}"
        rules:
          - name: create_workflow
            conditions: { has_create: T, has_query: F }
            action: delegate_init
          - name: refresh_workflow
            conditions: { has_update: T }
            action: delegate_refresh
          - name: query_workflow
            conditions: { has_query: T }
            action: delegate_navigate
        store_as: computed.matches
    on_success: check_winner

  check_winner:
    type: decision
    conditions:
      - condition:
          evaluate_expression: "computed.matches.clear_winner"
        goto: route_winner
      - goto: disambiguate

  route_winner:
    type: action
    actions:
      - type: dynamic_route
        action: "${computed.matches.winner.action}"
```

### Simple Keyword Matching

```yaml
- type: evaluate_keywords
  input: "${arguments}"
  keyword_sets:
    analyze: ["analyze", "examine", "inspect"]
    convert: ["convert", "transform", "generate"]
    validate: ["validate", "check", "verify"]
  store_as: computed.intent
```

---

## Related Documentation

- **Parent:** [../README.md](../README.md) - Consequence taxonomy
- **Core consequences:** [workflow.md](workflow.md) - State, evaluation, control flow
- **Framework:** `lib/intent_detection/framework.md` - 3VL theory and semantics
- **Execution:** `lib/intent_detection/execution.md` - Algorithm details
