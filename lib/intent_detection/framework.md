# 3VL Intent Detection Framework

3-Valued Logic (3VL) for compound intent handling. This framework allows inputs like "help me initialize" to correctly route to the primary intent (init) rather than the modifier (help).

---

## Overview

Traditional keyword matching treats all keywords equally, causing ambiguity when multiple intents appear in one request. 3VL solves this by:

1. **Parsing flags** - Each keyword category becomes a flag with three values
2. **Matching rules** - Rules specify which flag combinations map to actions
3. **Scoring matches** - Rules are ranked by how well they match the input
4. **Winner selection** - Clear winners proceed; ties trigger disambiguation

---

## 3VL Values

| Value | Symbol | Meaning |
|-------|--------|---------|
| True | `T` | Positive keyword matched (user wants this) |
| False | `F` | Negative keyword matched (user explicitly doesn't want this) |
| Unknown | `U` | No keywords matched (user didn't mention this) |

**Key insight:** `U` (Unknown) is different from both `T` and `F`. It means "we don't know what the user wants regarding this category."

---

## Flag Definitions

Flags are defined with positive and optional negative keywords:

```yaml
intent_flags:
  has_init:
    keywords:
      - "create"
      - "new"
      - "initialize"
    negative_keywords:
      - "don't create"
      - "skip init"
    description: "User wants to create/initialize something"
```

**Resolution order:**
1. Check negative keywords first (they're more specific)
2. If no negative match, check positive keywords
3. If no match at all, value remains `U`

---

## Rule Conditions

Rules specify what flag values they expect:

```yaml
intent_rules:
  - name: "help_with_init"
    conditions:
      has_help: T    # Requires help flag to be True
      has_init: T    # Requires init flag to be True
      has_build: F   # Requires build flag to be False
    action: extract_project_for_init
    priority: 80
    description: "Help creating a corpus"
```

**Condition interpretation:**
| Rule Value | Meaning |
|------------|---------|
| `T` | This flag MUST be True |
| `F` | This flag MUST be False |
| `U` (or omitted) | Don't care about this flag |

---

## Scoring Semantics

Each flag comparison contributes to the rule's score:

| State | Rule | Score | Rationale |
|-------|------|-------|-----------|
| T | T | +2 | Hard match: requirement fully satisfied |
| F | F | +2 | Hard match: absence requirement confirmed |
| T | U | +1 | Soft match: state has info, rule doesn't care |
| U | T | +1 | Soft match: rule wants it, state is unknown |
| F | U | +1 | Soft match: state has info, rule doesn't care |
| U | F | +1 | Soft match: rule wants absence, state unknown |
| U | U | 0 | No contribution: neither specifies |
| F | T | **EXCLUDED** | Rule requires presence, state says absent |
| T | F | **EXCLUDED** | Rule requires absence, state says present |

**Exclusion:** If any condition causes exclusion, the rule is removed from consideration entirely.

---

## Winner Determination

After scoring all non-excluded rules:

### Step 1: Sort Candidates

```
candidates.sort(by: (-score, -priority))
```

Primary sort by score (descending), secondary by priority (descending).

### Step 2: Check for Clear Winner

```
IF candidates.length >= 2:
  clear_winner = (candidates[0].score >= candidates[1].score + 2)
ELSE IF candidates.length == 1:
  clear_winner = true
ELSE:
  clear_winner = false
```

A **clear winner** must beat the second-place candidate by at least 2 points. This margin ensures the winner is decisively better, not just slightly ahead.

### Step 3: Route or Disambiguate

- **Clear winner:** Execute the winning rule's action
- **No clear winner:** Present top candidates for user disambiguation
- **No candidates:** Fall back to default behavior (menu or error)

---

## Priority Tiers

Recommended priority levels for rule organization:

| Priority | Use Case |
|----------|----------|
| 100 | Pure single intents with explicit negation of others |
| 95 | Secondary pure intents |
| 90 | Standard single intents |
| 85 | Query/navigate with qualifiers |
| 80 | Compound intents (help + X) |
| 70 | Multi-step intents (init + build) |
| 60 | Fallback interpretations |
| 10 | Empty/default cases |

---

## Example Walkthrough

**Input:** "help me initialize a new corpus"

### Step 1: Parse Flags

```yaml
has_help: T    # "help" matched
has_init: T    # "initialize", "new" matched
has_build: U   # no build keywords
has_query: U   # no query keywords
# ... other flags remain U
```

### Step 2: Match Rules

**Rule: help_only** (priority 100)
- Conditions: has_help=T, has_init=F, ...
- has_init mismatch: state=T, rule=F → **EXCLUDED**

**Rule: init_only** (priority 90)
- Conditions: has_init=T, has_add_source=F, has_build=F
- has_init: T+T = +2
- has_add_source: U+F = +1
- has_build: U+F = +1
- **Score: 4**

**Rule: help_with_init** (priority 80)
- Conditions: has_help=T, has_init=T
- has_help: T+T = +2
- has_init: T+T = +2
- **Score: 4**

### Step 3: Winner Determination

- Top candidates: help_with_init (score 4), init_only (score 4)
- Score difference: 0 (less than 2)
- No clear winner → disambiguation menu

(In practice, priority might break the tie, or the disambiguation menu appears)

---

## Design Rationale

### Why 3 Values?

Two-valued logic (true/false) can't distinguish between:
- "User explicitly said no" (negation)
- "User didn't mention it" (unknown)

This distinction is critical for compound intents. "Help me init" shouldn't match "help_only" just because the user didn't explicitly negate init.

### Why +2/-1/0 Scoring?

- **+2 for hard matches** ensures explicit matches outweigh unknown states
- **+1 for soft matches** gives credit for having more information
- **Margin of 2** for clear winner prevents false confidence on marginal leads

### Why Priority as Tiebreaker?

Scores can be equal when rules have different focus areas. Priority allows defining which intent is more likely when scores don't distinguish.

---

## Related Documentation

- **Execution Algorithms:** `lib/intent_detection/execution.md`
- **Variable Interpolation:** `lib/intent_detection/variables.md`
- **Workflow Consequences:** `lib/workflow/consequences.md` (parse_intent_flags, match_3vl_rules)
