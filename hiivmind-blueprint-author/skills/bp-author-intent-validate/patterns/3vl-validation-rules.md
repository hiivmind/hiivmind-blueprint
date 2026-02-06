> **Used by:** `SKILL.md` Phase 5
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`

# 3VL Validation Rules

Complete three-valued logic (3VL) truth tables, ranking algorithm specification, and common semantic error patterns for intent-mapping.yaml validation.

---

## Overview

Intent mapping uses Kleene's strong three-valued logic (K3) to match user intent flags against routing rules. The three values are:

| Value | Meaning | In intent-mapping.yaml |
|-------|---------|----------------------|
| **T** (True) | Flag is positively detected | `flag_name: T` in rule condition |
| **F** (False) | Flag is explicitly absent / negated | `flag_name: F` in rule condition |
| **U** (Unknown) | Flag not evaluated / don't care | Flag omitted from rule condition |

---

## Truth Tables

### AND (Conjunction)

The AND operation determines if multiple conditions hold simultaneously. Used when a rule has multiple flag conditions -- all must be satisfied.

```
AND |  T  |  U  |  F
----+-----+-----+----
 T  |  T  |  U  |  F
 U  |  U  |  U  |  F
 F  |  F  |  F  |  F
```

Key properties:
- `T AND T = T` -- Both conditions confirmed, strong match
- `T AND U = U` -- One confirmed, one uncertain, result uncertain
- `T AND F = F` -- Contradiction, rule is excluded
- `U AND U = U` -- Both uncertain, match remains uncertain
- `F AND anything = F` -- Any contradiction kills the match

### OR (Disjunction)

The OR operation is used in the ranking tiebreaker -- if a candidate matches via any path:

```
OR  |  T  |  U  |  F
----+-----+-----+----
 T  |  T  |  T  |  T
 U  |  T  |  U  |  U
 F  |  T  |  U  |  F
```

Key properties:
- `T OR anything = T` -- One confirmed match is enough
- `U OR U = U` -- Both uncertain, remains uncertain
- `F OR F = F` -- Both excluded, stays excluded

### NOT (Negation)

The NOT operation inverts a condition value. Used for negative_keywords evaluation:

```
NOT T = F
NOT U = U
NOT F = T
```

Key property: `NOT U = U` -- Negating uncertainty produces uncertainty.

---

## Ranking Algorithm

When evaluating user input against the rule set, the 3VL ranker follows this algorithm:

### Step 1: Classify Each Condition Check

For a given input state (map of flag_name -> T/F/U) and a rule's conditions:

```
function classify_check(input_value, rule_value):
    """
    input_value: the detected state of the flag (T, F, or U)
    rule_value:  what the rule requires (T or F; omitted = U)
    """
    if rule_value is omitted (U):
        return "skip"         # Rule doesn't care about this flag

    if input_value == rule_value:
        return "hard_match"   # Definite agreement

    if input_value == "U":
        return "soft_match"   # Input uncertain, rule has opinion

    # input_value != rule_value and neither is U
    return "exclusion"        # Definite disagreement
```

Classification matrix:

```
              Rule: T       Rule: F       Rule: U (omitted)
Input: T      hard_match    exclusion     skip
Input: F      exclusion     hard_match    skip
Input: U      soft_match    soft_match    skip
```

### Step 2: Reject Excluded Candidates

Any rule with at least one exclusion is rejected:

```
function evaluate_rule(input_state, rule):
    hard_matches = 0
    soft_matches = 0
    effective_conditions = len(rule.condition)

    for flag, required_value in rule.condition.items():
        input_value = input_state.get(flag, "U")
        classification = classify_check(input_value, required_value)

        if classification == "exclusion":
            return {rejected: true}
        elif classification == "hard_match":
            hard_matches += 1
        elif classification == "soft_match":
            soft_matches += 1

    return {
        rejected: false,
        hard_matches: hard_matches,
        soft_matches: soft_matches,
        effective_conditions: effective_conditions,
        priority: rule.priority
    }
```

### Step 3: Rank Remaining Candidates

Candidates that pass (no exclusions) are ranked by the following criteria in order:

1. **Priority** (ascending -- lower number = higher priority)
2. **Hard matches** (descending -- more definite agreement = better)
3. **Soft matches** (ascending -- fewer uncertain matches = more confident)
4. **Effective conditions** (ascending -- simpler rules preferred as tiebreaker)

```
function rank_candidates(candidates):
    return sorted(candidates, key=lambda c: (
        c.priority,              # lower is better
        -c.hard_matches,         # more is better (negated for ascending sort)
        c.soft_matches,          # fewer is better
        c.effective_conditions   # fewer is better (tiebreaker)
    ))
```

The top-ranked candidate is the selected rule.

---

## Validation Checks

### Check 1: Valid Condition Values

Every condition value in a rule must be `T` or `F`. The value `U` should not appear explicitly -- it is represented by omission:

```
INVALID if rule has:
    condition:
      has_setup: U    # WRONG: omit the flag instead

VALID:
    condition:
      has_setup: T    # Requires flag to be true
```

### Check 2: Declared Flag References

Every flag referenced in a rule's condition must be declared in the `intent_flags` section:

```
INVALID if rule references 'has_deploy' but intent_flags has no 'has_deploy' entry.
```

### Check 3: Ranking Determinism

No two rules should produce identical ranking tuples for any plausible input:

```
INVALID:
  - name: rule_a
    condition: { has_setup: T }
    priority: 10
  - name: rule_b
    condition: { has_setup: T }
    priority: 10
    # Same conditions, same priority -> ranking tie
```

### Check 4: No Empty Catch-Alls in Rules

A rule with zero conditions matches everything. This belongs in the `fallback:` section, not in `rules`:

```
INVALID in rules[]:
  - name: catch_all
    condition: {}        # Matches every input
    action: show_menu
    priority: 100

VALID as fallback:
  fallback:
    action: show_menu
```

---

## Common Semantic Errors

### Error: All-U Rule Not Marked as Fallback

**Symptom:** A rule in the `rules` array has no conditions (or all flags omitted).

**Problem:** This rule will match every input and, depending on priority, may shadow all other rules.

**Example:**
```yaml
rules:
  - name: catch_everything
    condition: {}
    action: show_menu
    priority: 50
  - name: setup_action
    condition:
      has_setup: T
    action: run_setup
    priority: 10
```

**Fix:** Move the catch-all to the `fallback:` section. The setup rule above is safe because it has higher priority (10 < 50), but this pattern is fragile.

### Error: Contradictory Rules

**Symptom:** Two rules with identical conditions route to different actions.

**Problem:** If they have the same priority, the ranker cannot choose between them. If they have different priorities, the lower-priority rule is dead code.

**Example:**
```yaml
rules:
  - name: convert_v1
    condition: { has_convert: T }
    action: skill_convert_v1
    priority: 10
  - name: convert_v2
    condition: { has_convert: T }
    action: skill_convert_v2
    priority: 10
```

**Fix:** Either merge into one rule, differentiate by adding a flag condition (e.g., `has_legacy: T` for v1), or assign different priorities if one should take precedence.

### Error: Broad Rule Swallows Specific Rule

**Symptom:** A rule with fewer conditions has equal or higher priority than a more specific rule whose conditions are a superset.

**Problem:** The broad rule matches everything the specific rule matches (and more), and is preferred by the ranker.

**Example:**
```yaml
rules:
  - name: generic_convert
    condition: { has_convert: T }
    action: convert_generic
    priority: 10
  - name: convert_with_validate
    condition: { has_convert: T, has_validate: T }
    action: convert_validated
    priority: 10
```

**Fix:** Give `convert_with_validate` a higher priority (lower number, e.g., priority 5) so it is preferred when both flags are set. Or rely on the hard_matches ranking (the specific rule gets 2 hard matches vs 1), but explicit priority is clearer.

### Error: Flag Without Keywords

**Symptom:** A flag is declared in `intent_flags` with an empty `keywords` array.

**Problem:** This flag can never be set to T by the keyword evaluation phase, making any rule that requires `flag: T` unreachable.

**Example:**
```yaml
intent_flags:
  has_deploy:
    keywords: []
    negative_keywords: []
```

**Fix:** Add at least one keyword that would trigger this flag.

---

## Related Documentation

- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Coverage Analysis Algorithm:** `patterns/coverage-analysis-algorithm.md`
