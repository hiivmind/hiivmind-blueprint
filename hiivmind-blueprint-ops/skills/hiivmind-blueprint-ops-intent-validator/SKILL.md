---
name: hiivmind-blueprint-ops-intent-validator
description: >
  Validate intent-mapping.yaml files for gaps, collisions, and semantic issues.
  Use when: "validate intent", "check intent mapping", "intent gaps", "intent collisions",
  "mapping coverage", "rule conflicts", "3VL validation", "flag coverage", "intent analysis",
  "find intent issues", "check rules", "validate flags", "rule overlap", "dead flags".
allowed-tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# Validate Intent Mapping

Analyze intent-mapping.yaml files for coverage gaps, rule collisions, and semantic issues.

**Invocation:**
- `/hiivmind-blueprint-ops intent-validator` - Full validation
- `/hiivmind-blueprint-ops validate-intent` - Alias
- `/hiivmind-blueprint-ops check intent mapping` - Natural language

---

## Overview

This skill validates intent-mapping.yaml files against 16 checks organized into 5 categories:

| Category | Checks |
|----------|--------|
| **Coverage Analysis** | Keyword uniqueness, overlap, negative coverage, dead flags |
| **Rule Collision Detection** | Identical conditions, subset conditions, mutual exclusivity, priority collisions |
| **Gap Detection** | Uncovered flag combinations, missing fallback, orphan rules |
| **3VL Semantics** | U-in-rule semantics, all-U conditions, soft match risk |
| **Cross-Reference** | Action targets, parameter consistency |

---

## Prerequisites

| Requirement | Check | Error Message |
|-------------|-------|---------------|
| yq installed | `which yq` | "yq is required. Install: https://github.com/mikefarah/yq" |
| jq installed | `which jq` | "jq is required for JSON processing" |

---

## Phase 1: Locate Intent Mapping

### Step 1.1: Determine Target

If user provided a path:
1. Validate the path exists
2. Read the intent-mapping.yaml file
3. Store path in `computed.intent_mapping_path`

If no path provided:
1. **Ask user** which intent mapping to validate:
   ```json
   {
     "questions": [{
       "question": "Which intent-mapping.yaml would you like to validate?",
       "header": "Target",
       "multiSelect": false,
       "options": [
         {"label": "Current plugin", "description": "Validate commands/*/intent-mapping.yaml in this plugin"},
         {"label": "Provide path", "description": "I'll give you the intent-mapping.yaml path"},
         {"label": "Search current directory", "description": "Find all intent-mapping.yaml files"}
       ]
     }]
   }
   ```

### Step 1.2: Load Intent Mapping

Read and parse the intent-mapping.yaml file:
```bash
yq -o=json '.' "$INTENT_MAPPING_PATH"
```

Store:
- `computed.flags` - Map of flag definitions
- `computed.rules` - Array of rule definitions
- `computed.version` - Schema version

---

## Phase 2: Coverage Analysis

### Check 1: Keyword Uniqueness

**Severity:** Warning

Detect when the same keyword appears in multiple flags.

```bash
# Extract all keywords into flag:keyword pairs
yq -r '.intent_flags | to_entries | .[] | .key as $flag | .value.keywords[]? | "\($flag):\(.)"' "$PATH" | sort | uniq -d
```

Report format:
```
WARN: Keyword "validate" appears in multiple flags:
  - has_validate
  - has_schema_mode (via "validate schema")
```

### Check 2: Keyword Overlap

**Severity:** Info

Detect substring overlap (e.g., "update" is substring of "update schema").

```bash
# For each keyword, check if it's a substring of another keyword in different flag
```

Report format:
```
INFO: Keyword overlap detected:
  - "update" (has_upgrade) is substring of "update schema" (has_schema_mode)
```

### Check 3: Negative Keyword Coverage

**Severity:** Info

Flags without negative_keywords may match too broadly.

```bash
yq -r '.intent_flags | to_entries | .[] | select(.value.negative_keywords == null or .value.negative_keywords == []) | .key' "$PATH"
```

Report format:
```
INFO: Flags without negative_keywords (may match broadly):
  - has_validate
  - has_lib_validation
```

### Check 4: Dead Flags

**Severity:** Error

Flags defined but never used in any rule condition.

```bash
# Extract flags used in conditions
USED_FLAGS=$(yq -r '.rules[].condition | keys[]' "$PATH" | sort -u)

# Compare with defined flags
DEFINED_FLAGS=$(yq -r '.intent_flags | keys[]' "$PATH" | sort -u)

# Find difference
comm -23 <(echo "$DEFINED_FLAGS") <(echo "$USED_FLAGS")
```

Report format:
```
ERROR: Dead flags (defined but never used in rules):
  - has_unused_flag
  - has_deprecated_mode
```

---

## Phase 3: Rule Collision Detection

### Check 5: Identical Conditions

**Severity:** Error

Two rules with exactly the same condition set.

```bash
# Hash each rule's conditions and find duplicates
yq -r '.rules[] | {name: .name, conditions: (.condition | to_entries | sort_by(.key))} | @json' "$PATH" | \
  jq -s 'group_by(.conditions) | map(select(length > 1))'
```

Report format:
```
ERROR: Rules with identical conditions:
  - validate_schema AND validate_full both have: {has_validate: T}
```

### Check 6: Subset Conditions

**Severity:** Warning

Rule A's conditions are a proper subset of Rule B's conditions.

Algorithm:
1. For each pair of rules (A, B)
2. If A.conditions ⊂ B.conditions (proper subset)
3. And A.priority >= B.priority (A would match first)
4. Report ambiguous priority

Report format:
```
WARN: Subset condition ambiguity:
  - validate_full (priority 100, {has_validate: T})
    is subset of validate_schema (priority 110, {has_validate: T, has_schema_mode: T})
  - Note: Higher priority on specific rule is correct behavior
```

### Check 7: Mutual Exclusivity

**Severity:** Info

Rules that can never both match (contradicting conditions).

Algorithm:
1. For each pair of rules (A, B)
2. If same condition key has T in A and F in B (or vice versa)
3. Rules are mutually exclusive

Report format:
```
INFO: Mutually exclusive rules (cannot both match):
  - upgrade_skills requires has_skills_target: T
  - upgrade_gateway requires has_gateway_target: T, has_skills_target: F
```

### Check 8: Priority Collisions

**Severity:** Warning

Same priority with overlapping conditions.

Algorithm:
1. Group rules by priority
2. For each group with >1 rule
3. Check if conditions can overlap (no contradiction)
4. Report potential tie

Report format:
```
WARN: Priority collision (priority 110):
  - validate_schema: {has_validate: T, has_schema_mode: T}
  - validate_graph: {has_validate: T, has_graph_mode: T}
  - These could tie if both has_schema_mode and has_graph_mode are T
```

---

## Phase 4: Gap Detection

### Check 9: Uncovered Flag Combinations

**Severity:** Warning

Valid flag combinations that match no rule.

Algorithm:
1. Enumerate flag combinations (for small flag sets)
2. For each combination, run match_3vl_rules logic
3. Report combinations with no matching rule

Note: For large flag sets (>8 flags), sample combinations or skip.

Report format:
```
WARN: Uncovered flag combinations:
  - {has_validate: F, has_upgrade: F, has_lib_validation: F, has_help: F}
    matches no rule (no fallback defined)
```

### Check 10: Missing Fallback

**Severity:** Error

No rule with empty conditions ({}) to catch unmatched inputs.

```bash
yq -r '.rules[] | select(.condition == {} or .condition == null) | .name' "$PATH"
```

Report format:
```
ERROR: No fallback rule defined
  - Add a rule with empty conditions {} as lowest priority
  - Example: {name: fallback, priority: 0, condition: {}, action: show_menu}
```

### Check 11: Orphan Rules

**Severity:** Error

Rules that can never match (all conditions are F, and no flag can be F by default).

Algorithm:
1. Find rules where all conditions are `F`
2. Check if any input could satisfy (flags default to U, not F)
3. Rules requiring all-F conditions are orphans

Report format:
```
ERROR: Orphan rules (can never match):
  - negative_only_rule requires all flags to be F, but flags default to U
```

---

## Phase 5: 3VL Semantics

### Check 12: U-in-Rule Semantics

**Severity:** Info

Verify rules using U in conditions understand it means "don't care".

```bash
yq -r '.rules[] | select(.condition | to_entries | .[] | select(.value == "U")) | .name' "$PATH"
```

Report format:
```
INFO: Rules using U in conditions (wildcard semantics):
  - flexible_validate: has_schema_mode: U means "matches regardless of schema mode"
```

### Check 13: All-U Conditions

**Severity:** Info

Rules with empty conditions or all-U conditions are equivalent fallbacks.

```bash
yq -r '.rules[] | select(
  .condition == {} or
  .condition == null or
  (.condition | to_entries | all(.value == "U"))
) | .name' "$PATH"
```

Report format:
```
INFO: Fallback-equivalent rules (empty or all-U conditions):
  - fallback_rule: {} (explicit fallback)
  - flexible_rule: {has_mode: U} (effectively fallback)
```

### Check 14: Soft Match Risk

**Severity:** Warning

Rules likely to soft-match ambiguously (many conditions, none required hard).

Algorithm:
1. For rules with >2 conditions
2. Check if conditions have overlapping keywords
3. High risk of soft-match ties

Report format:
```
WARN: Soft match risk (multiple conditions may match partially):
  - compound_rule: {has_a: T, has_b: T, has_c: T}
    If only has_a is T and others are U, soft matches with score 1
    May tie with simpler rules
```

---

## Phase 6: Cross-Reference

### Check 15: Action Targets

**Severity:** Error

Rule actions reference valid nodes/skills.

```bash
# Extract action targets
ACTIONS=$(yq -r '.rules[].action' "$PATH" | sort -u)

# For each action, verify:
# 1. If starts with "hiivmind-", check skill exists
# 2. If simple name, check it's a valid workflow node
```

Report format:
```
ERROR: Invalid action targets:
  - validate_full references "hiivmind-blueprint-ops-validate" (exists: yes)
  - broken_rule references "nonexistent-skill" (exists: no)
```

### Check 16: Parameter Consistency

**Severity:** Warning

Rules with params should match expected schema.

```bash
# Extract rules with params
yq -r '.rules[] | select(.params != null) | {name: .name, action: .action, params: .params} | @json' "$PATH"
```

Cross-reference with skill's expected parameters.

Report format:
```
WARN: Parameter consistency issues:
  - validate_schema passes {mode: "schema"} to hiivmind-blueprint-ops-validate
    Skill expects: mode (valid values: full, schema, graph, types, state)
    Status: valid
```

---

## Phase 7: Generate Report

### Summary Format

```markdown
# Intent Mapping Validation Report

**File:** commands/hiivmind-blueprint-ops/intent-mapping.yaml
**Flags:** 10 defined
**Rules:** 12 defined

## Summary

| Severity | Count |
|----------|-------|
| Error    | 2     |
| Warning  | 4     |
| Info     | 3     |

## Errors (must fix)

1. **Dead flags**: has_unused_flag (Check 4)
2. **Missing fallback**: No rule catches unmatched input (Check 10)

## Warnings (should fix)

1. **Priority collision**: validate_schema, validate_graph at priority 110 (Check 8)
2. **Subset ambiguity**: validate_full vs validate_schema (Check 6)
3. **Soft match risk**: compound_rule (Check 14)
4. **Keyword uniqueness**: "validate" in multiple flags (Check 1)

## Info (consider)

1. **Negative keyword coverage**: 5 flags without negative_keywords (Check 3)
2. **U-in-rule semantics**: 0 rules use U wildcards (Check 12)
3. **Mutually exclusive**: 2 rule pairs (Check 7)

## Recommendations

1. Add fallback rule with empty conditions
2. Remove or use dead flag has_unused_flag
3. Consider adding negative_keywords to improve precision
```

---

## Validation Script

For automated validation, use this combined check:

```bash
#!/bin/bash
# Intent mapping validator

INTENT_PATH="${1:-commands/*/intent-mapping.yaml}"

echo "=== Intent Mapping Validation ==="

# Check 4: Dead flags
echo -e "\n## Dead Flags"
DEFINED=$(yq -r '.intent_flags | keys[]' "$INTENT_PATH" | sort)
USED=$(yq -r '.rules[].condition | keys[]' "$INTENT_PATH" 2>/dev/null | sort -u)
DEAD=$(comm -23 <(echo "$DEFINED") <(echo "$USED"))
if [ -n "$DEAD" ]; then
  echo "ERROR: Dead flags found:"
  echo "$DEAD" | sed 's/^/  - /'
else
  echo "OK: All flags are used"
fi

# Check 10: Missing fallback
echo -e "\n## Fallback Rule"
FALLBACK=$(yq -r '.rules[] | select(.condition == {} or .condition == null) | .name' "$INTENT_PATH")
if [ -z "$FALLBACK" ]; then
  echo "ERROR: No fallback rule defined"
else
  echo "OK: Fallback rule: $FALLBACK"
fi

# Check 5: Identical conditions
echo -e "\n## Duplicate Conditions"
yq -r '.rules[] | {name: .name, cond: (.condition | to_entries | sort_by(.key) | from_entries)} | @json' "$INTENT_PATH" | \
  jq -s 'group_by(.cond) | map(select(length > 1) | map(.name))' | \
  jq -r '.[] | "ERROR: Duplicate conditions: " + (. | join(", "))'

echo -e "\n=== Validation Complete ==="
```

---

## Examples

### Example 1: Full Validation

```
User: validate intent mapping for blueprint-ops