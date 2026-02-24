---
name: bp-intent-validate
description: >
  This skill should be used when the user asks to "validate intent mapping", "check intent rules",
  "verify routing", "lint intent-mapping.yaml", "check 3VL logic", "find routing gaps",
  or needs to verify an intent-mapping.yaml is correct. Triggers on "validate intent",
  "check intent", "verify routing", "lint intent", "3VL validation", "routing gaps".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Validate Intent Mapping

Comprehensive read-only validation of an intent-mapping.yaml across 5 dimensions: coverage, collisions, gaps, 3VL semantics, and structural correctness. Reports all issues without modifying any files.

---

## Procedure Overview

```
+-----------------------+
| Phase 1: Load         |
|   Intent Mapping      |
|   + Available Skills  |
+----------+------------+
           |
+----------v------------+
| Phase 2: Coverage     |
|   Analysis            |
+----------+------------+
           |
+----------v------------+
| Phase 3: Collision    |
|   Detection           |
+----------+------------+
           |
+----------v------------+
| Phase 4: Gap          |
|   Detection           |
+----------+------------+
           |
+----------v------------+
| Phase 5: 3VL          |
|   Semantics           |
+----------+------------+
           |
+----------v------------+
| Phase 6: Report       |
+----------+------------+
```

---

## Phase 1: Load Intent Mapping and Available Skills

### Step 1.1: Path Resolution

Determine the intent-mapping.yaml to validate.

**If path was provided as argument:**

1. Read the file at the provided path.
2. If the file does not exist, report error and stop.
3. Store content in `computed.intent_mapping` and proceed.

**If no path was provided:**

Present an AskUserQuestion to determine the file:

```json
{
  "questions": [{
    "question": "Which intent-mapping.yaml should I validate?",
    "header": "Select how to locate the file",
    "options": [
      {
        "label": "I'll provide a path",
        "description": "Enter the path to an intent-mapping.yaml file"
      },
      {
        "label": "Search current directory",
        "description": "Glob for **/intent-mapping.yaml in the working directory"
      },
      {
        "label": "Search plugin root",
        "description": "Glob for **/intent-mapping.yaml under the plugin root"
      }
    ],
    "multiSelect": false
  }]
}
```

**Response handling:**

```pseudocode
user_choice = AskUserQuestion(questions_json).responses[0]

if user_choice == "I'll provide a path":
    path = AskUserQuestion("Enter the path to intent-mapping.yaml")
    computed.intent_mapping_path = path
    Read(path)
elif user_choice == "Search current directory":
    paths = Glob("**/intent-mapping.yaml", cwd)
    if len(paths) > 1:
        selected = AskUserQuestion(list_paths_as_options(paths))
        computed.intent_mapping_path = selected
    else:
        computed.intent_mapping_path = paths[0]
elif user_choice == "Search plugin root":
    paths = Glob("**/intent-mapping.yaml", CLAUDE_PLUGIN_ROOT)
    if len(paths) > 1:
        selected = AskUserQuestion(list_paths_as_options(paths))
        computed.intent_mapping_path = selected
    else:
        computed.intent_mapping_path = paths[0]
```

Store the resolved path in `computed.intent_mapping_path`.

### Step 1.2: Parse Intent Mapping

1. Read the file at `computed.intent_mapping_path`.
2. Parse the YAML content mentally. Store the parsed structure in `computed.intent_mapping`.
3. Verify basic structure exists:
   - Has `intent_flags` (map of flag definitions)
   - Has `rules` (array of rule objects)
   - Has `fallback` (object with `action`)
4. If any of these are missing, record as a fatal schema error and stop validation (the file is not a valid intent-mapping.yaml).

Extract from each flag definition: `keywords` (array), `negative_keywords` (array).
Extract from each rule: `name`, `condition` (map of flag->value), `action`, `priority`.

Store the parsed structure in `computed.intent_mapping`.

### Step 1.3: Discover Available Skills

Locate all skills the mapping should route to. Use Glob to find SKILL.md files in sibling skill directories:

```pseudocode
# Search for skills in the same plugin
skill_files = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
skill_files += Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
```

For each discovered SKILL.md, extract the `name` from the YAML frontmatter:

```pseudocode
computed.available_skills = []
for skill_file in skill_files:
    content = Read(skill_file)
    frontmatter = parse_yaml_frontmatter(content)
    computed.available_skills.append({
        name: frontmatter.name,
        path: skill_file
    })
```

Also extract all unique action values from rules:

```pseudocode
computed.rule_actions = set()
for rule in computed.intent_mapping.rules:
    computed.rule_actions.add(rule.action)
if computed.intent_mapping.fallback:
    computed.rule_actions.add(computed.intent_mapping.fallback.action)
```

Store in `computed.available_skills` and `computed.rule_actions`.

---

## Phase 2: Coverage Analysis

> **Detail:** See `patterns/coverage-analysis-algorithm.md` for the complete algorithm with gap detection procedure and Venn diagram approach.

Initialize the issue collector:
```pseudocode
computed.validation.coverage_issues = []
```

### Step 2.1: All Skills Have Routing Rules

Check that each available skill name appears as an action target in at least one rule:

```pseudocode
for skill in computed.available_skills:
    matching_rules = [r for r in computed.intent_mapping.rules
                      if r.action == skill.name]
    if len(matching_rules) == 0:
        append to computed.validation.coverage_issues:
            severity: "warning"
            check: "skill_coverage"
            message: "Skill '${skill.name}' has no routing rule. Users cannot reach it via intent matching."
            fix: "Add a rule with action: ${skill.name} and appropriate flag conditions."
```

### Step 2.2: No Unreachable Skills

Verify every `action` value in the rules corresponds to a real skill or a known built-in action (e.g., `show_help`, `show_menu`):

```pseudocode
KNOWN_BUILTINS = ["show_help", "show_menu", "delegate_fallback"]

for rule in computed.intent_mapping.rules:
    skill_names = [s.name for s in computed.available_skills]
    if rule.action not in skill_names and rule.action not in KNOWN_BUILTINS:
        append to computed.validation.coverage_issues:
            severity: "error"
            check: "action_target"
            message: "Rule '${rule.name}' targets action '${rule.action}' which is not a known skill or built-in."
            fix: "Rename action to match an existing skill name, or create the missing skill."
```

### Step 2.3: Fallback Present

Verify that a fallback rule exists. The fallback should be a separate `fallback:` section or a rule with empty conditions `{}`:

```pseudocode
if "fallback" not in computed.intent_mapping or not computed.intent_mapping.fallback:
    # Check if any rule has empty conditions as a catch-all
    catch_all_rules = [r for r in computed.intent_mapping.rules
                       if len(r.condition) == 0]
    if len(catch_all_rules) == 0:
        append to computed.validation.coverage_issues:
            severity: "error"
            check: "fallback_present"
            message: "No fallback rule found. Requests matching no flags will have no routing target."
            fix: "Add a 'fallback:' section with an action, or add a rule with empty conditions {}."
```

### Step 2.4: Every Skill Reachable by Non-Fallback Rule

Verify each skill can be reached by at least one rule that is not the fallback. Skills only reachable via fallback are effectively hidden from intentional user requests:

```pseudocode
fallback_action = computed.intent_mapping.fallback.action if computed.intent_mapping.fallback else None

for skill in computed.available_skills:
    non_fallback_rules = [r for r in computed.intent_mapping.rules
                          if r.action == skill.name
                          and len(r.condition) > 0]
    if len(non_fallback_rules) == 0 and skill.name != fallback_action:
        append to computed.validation.coverage_issues:
            severity: "info"
            check: "non_fallback_reachability"
            message: "Skill '${skill.name}' is only reachable via fallback, not through any explicit intent rule."
            fix: "Add a rule with specific flag conditions that routes to ${skill.name}."
```

Compute coverage score:
```pseudocode
skills_with_rules = count(skill for skill in computed.available_skills
                          if any(r.action == skill.name for r in computed.intent_mapping.rules))
computed.validation.coverage_score = skills_with_rules / len(computed.available_skills) * 100
```

Store all issues in `computed.validation.coverage_issues`.

---

## Phase 3: Collision Detection

Initialize the issue collector:
```pseudocode
computed.validation.collision_issues = []
```

### Step 3.1: Overlapping Conditions

Find rules where one rule's conditions are a subset of another's. When a subset relationship exists, the more specific rule may be shadowed by the broader one depending on priority:

```pseudocode
function find_collisions(rules):
    collisions = []
    for i, rule_a in enumerate(rules):
        for rule_b in rules[i+1:]:
            overlap = compute_overlap(rule_a.condition, rule_b.condition)
            if overlap.is_subset:
                collisions.append({rules: [rule_a, rule_b], type: "subset"})
            elif overlap.ambiguous:
                collisions.append({rules: [rule_a, rule_b], type: "ambiguous"})
    return collisions

function compute_overlap(cond_a, cond_b):
    """
    Compare two condition maps for subset/superset/ambiguous relationships.

    A condition map is a dict of flag_name -> T/F.
    Omitted flags are implicitly U (unknown/don't care).

    Rule A is a SUBSET of Rule B if:
      - Every flag in A's conditions also appears in B's conditions with the same value
      - B may have additional flags that A does not specify

    Rules are AMBIGUOUS if:
      - They share some flags with same values but each has unique flags the other lacks
      - Both could match the same input with equal specificity
    """
    flags_a = set(cond_a.keys())
    flags_b = set(cond_b.keys())
    shared = flags_a & flags_b
    only_a = flags_a - flags_b
    only_b = flags_b - flags_a

    # Check agreement on shared flags
    agreement = all(cond_a[f] == cond_b[f] for f in shared)

    if not agreement:
        return {is_subset: false, ambiguous: false}  # Contradicting conditions, no overlap

    if len(only_a) == 0 and len(only_b) > 0:
        return {is_subset: true, narrower: "rule_a", broader: "rule_b"}
    if len(only_b) == 0 and len(only_a) > 0:
        return {is_subset: true, narrower: "rule_b", broader: "rule_a"}
    if len(only_a) == 0 and len(only_b) == 0:
        return {is_subset: true, narrower: "identical", broader: "identical"}
    if len(only_a) > 0 and len(only_b) > 0 and agreement:
        return {is_subset: false, ambiguous: true}

    return {is_subset: false, ambiguous: false}
```

For each collision found:
```pseudocode
for collision in collisions:
    if collision.type == "subset":
        append to computed.validation.collision_issues:
            severity: "warning"
            check: "subset_collision"
            message: "Rule '${collision.rules[0].name}' conditions are a subset of '${collision.rules[1].name}'. The broader rule may shadow the narrower one."
            fix: "Verify priority ordering. The more specific rule should have higher priority (lower number)."
    elif collision.type == "ambiguous":
        append to computed.validation.collision_issues:
            severity: "warning"
            check: "ambiguous_collision"
            message: "Rules '${collision.rules[0].name}' and '${collision.rules[1].name}' have overlapping conditions with equal specificity."
            fix: "Add distinguishing flag conditions to one rule, or assign different priorities."
```

### Step 3.2: Priority Conflicts

Detect rules with identical conditions but different actions and same priority:

```pseudocode
for i, rule_a in enumerate(computed.intent_mapping.rules):
    for rule_b in computed.intent_mapping.rules[i+1:]:
        if rule_a.condition == rule_b.condition:
            if rule_a.action != rule_b.action and rule_a.priority == rule_b.priority:
                append to computed.validation.collision_issues:
                    severity: "error"
                    check: "priority_conflict"
                    message: "Rules '${rule_a.name}' and '${rule_b.name}' have identical conditions, different actions ('${rule_a.action}' vs '${rule_b.action}'), and same priority ${rule_a.priority}. Routing is non-deterministic."
                    fix: "Assign different priorities, or merge the rules if they should route to the same skill."
            elif rule_a.action == rule_b.action:
                append to computed.validation.collision_issues:
                    severity: "info"
                    check: "duplicate_rule"
                    message: "Rules '${rule_a.name}' and '${rule_b.name}' have identical conditions and same action. One is redundant."
                    fix: "Remove the duplicate rule."
```

### Step 3.3: Ambiguous Matches

Flag input combinations that could match multiple rules with the same specificity (same number of effective conditions):

```pseudocode
function check_ambiguous_matches(rules):
    """
    For each pair of rules that are NOT in a subset relationship and NOT contradictory,
    check if there exists an input state that matches both with equal specificity.
    """
    for i, rule_a in enumerate(rules):
        for rule_b in rules[i+1:]:
            if rule_a.priority == rule_b.priority:
                effective_a = len(rule_a.condition)
                effective_b = len(rule_b.condition)
                if effective_a == effective_b:
                    # Check if a shared input can match both
                    overlap = compute_overlap(rule_a.condition, rule_b.condition)
                    if overlap.ambiguous:
                        append to computed.validation.collision_issues:
                            severity: "warning"
                            check: "ambiguous_match"
                            message: "Input matching both '${rule_a.name}' and '${rule_b.name}' would be ambiguous (same specificity ${effective_a}, same priority ${rule_a.priority})."
                            fix: "Differentiate by adding a flag condition to one rule or assigning different priorities."
```

Store all issues in `computed.validation.collision_issues`.

---

## Phase 4: Gap Detection

Initialize the issue collector:
```pseudocode
computed.validation.gap_issues = []
```

### Step 4.1: Keyword Coverage

Check that common user action verbs are covered by at least one flag's keyword list. Standard verbs that should typically be routable:

```pseudocode
STANDARD_VERBS = [
    "create", "new", "add", "make",
    "update", "edit", "modify", "change",
    "delete", "remove", "drop",
    "list", "show", "view", "display",
    "validate", "check", "verify", "lint",
    "convert", "transform", "migrate",
    "help", "?"
]

all_keywords = set()
for flag_name, flag_def in computed.intent_mapping.intent_flags:
    all_keywords.update(flag_def.keywords)

uncovered_verbs = [v for v in STANDARD_VERBS if v not in all_keywords]

if len(uncovered_verbs) > 0:
    append to computed.validation.gap_issues:
        severity: "info"
        check: "keyword_coverage"
        message: "Standard verbs not covered by any flag keyword: ${uncovered_verbs}"
        fix: "Consider adding these verbs to relevant flag keyword lists if users are likely to use them."
```

### Step 4.2: Unhandled Flag Combinations

Enumerate the possible T/F/U combinations for all declared flags and identify those that match no rule. For N flags, there are 3^N possible combinations, but in practice N is small (typically 3-8 flags):

```pseudocode
function enumerate_gaps(intent_flags, rules, fallback):
    flag_names = list(intent_flags.keys())
    n = len(flag_names)
    unhandled = []

    # For each possible combination of T/F/U across all flags
    for combo in product(["T", "F", "U"], repeat=n):
        state = dict(zip(flag_names, combo))

        # Check if any rule matches this state
        matched = false
        for rule in rules:
            if rule_matches_state(rule, state):
                matched = true
                break

        if not matched and fallback is None:
            unhandled.append(state)

    # Report only non-trivial gaps (not all-U which is the fallback case)
    meaningful_gaps = [g for g in unhandled if any(v != "U" for v in g.values())]

    if len(meaningful_gaps) > 0 and len(meaningful_gaps) <= 20:
        for gap in meaningful_gaps:
            append to computed.validation.gap_issues:
                severity: "warning"
                check: "unhandled_combination"
                message: "Flag combination ${gap} matches no rule and no fallback exists."
                fix: "Add a rule covering this combination or ensure a fallback is defined."
    elif len(meaningful_gaps) > 20:
        append to computed.validation.gap_issues:
            severity: "warning"
            check: "unhandled_combinations"
            message: "${len(meaningful_gaps)} flag combinations match no rule and no fallback exists. Too many to list individually."
            fix: "Define a fallback rule, or add broader rules with fewer conditions to catch more combinations."

function rule_matches_state(rule, state):
    """
    A rule matches a state if, for every flag in the rule's condition:
      - Rule says T and state says T -> match
      - Rule says T and state says U -> soft match (still matches, just uncertain)
      - Rule says T and state says F -> exclusion, no match
      - Rule says F and state says F -> match
      - Rule says F and state says U -> soft match
      - Rule says F and state says T -> exclusion, no match
    Omitted flags in the rule (implicit U) match any state value.
    """
    for flag, required_value in rule.condition.items():
        actual_value = state.get(flag, "U")
        if required_value == "T" and actual_value == "F":
            return false
        if required_value == "F" and actual_value == "T":
            return false
    return true
```

### Step 4.3: Missing Negative Keywords

Check for flags with overlapping keywords that lack negative keywords for disambiguation:

```pseudocode
function check_negative_keywords(intent_flags):
    # Build a reverse index: keyword -> list of flags that claim it
    keyword_to_flags = {}
    for flag_name, flag_def in intent_flags:
        for keyword in flag_def.keywords:
            keyword_to_flags.setdefault(keyword, []).append(flag_name)

    # Find keywords claimed by multiple flags
    shared_keywords = {k: flags for k, flags in keyword_to_flags.items()
                       if len(flags) > 1}

    for keyword, flags in shared_keywords.items():
        # Check if any of these flags have negative keywords to disambiguate
        for flag_name in flags:
            flag_def = intent_flags[flag_name]
            other_flags = [f for f in flags if f != flag_name]
            has_disambiguation = any(
                neg_kw in intent_flags[other].keywords
                for other in other_flags
                for neg_kw in flag_def.negative_keywords
            )
            if not has_disambiguation and len(flag_def.negative_keywords) == 0:
                append to computed.validation.gap_issues:
                    severity: "info"
                    check: "missing_negative_keywords"
                    message: "Keyword '${keyword}' is shared by flags [${flags}]. Flag '${flag_name}' has no negative_keywords to disambiguate."
                    fix: "Add negative_keywords to '${flag_name}' that exclude keywords unique to ${other_flags}."
```

Store all issues in `computed.validation.gap_issues`.

---

## Phase 5: 3VL Semantics Validation

> **Detail:** See `patterns/3vl-validation-rules.md` for complete truth tables and the ranking algorithm specification.

Initialize the issue collector:
```pseudocode
computed.validation.threevl_issues = []
```

### Step 5.1: Proper T/F/U Usage

Verify each rule's condition values use valid 3VL values. In intent-mapping.yaml, conditions map flags to explicit `T` or `F`. Omitted flags are implicitly `U` (unknown / don't care):

```pseudocode
VALID_CONDITION_VALUES = ["T", "F"]

for rule in computed.intent_mapping.rules:
    for flag_name, value in rule.condition.items():
        # Check value is valid
        if value not in VALID_CONDITION_VALUES:
            append to computed.validation.threevl_issues:
                severity: "error"
                check: "invalid_condition_value"
                message: "Rule '${rule.name}' has condition '${flag_name}: ${value}'. Expected T or F (omit for U)."
                fix: "Change to T (true), F (false), or remove the flag from conditions for U (unknown)."

        # Check flag is declared
        if flag_name not in computed.intent_mapping.intent_flags:
            append to computed.validation.threevl_issues:
                severity: "error"
                check: "undeclared_flag"
                message: "Rule '${rule.name}' references flag '${flag_name}' which is not declared in intent_flags."
                fix: "Add '${flag_name}' to the intent_flags section with keywords, or remove it from this rule."
```

### Step 5.2: Kleene Logic Correctness

Verify the ranking algorithm semantics are properly implementable with the current rule set. The 3VL ranking works as follows:

1. For each rule, given an input state, classify each condition check:
   - **Hard match**: state value and rule value agree (both T or both F)
   - **Soft match**: state value is U (unknown) and rule specifies T or F
   - **Exclusion**: state value contradicts rule value (T vs F or F vs T)

2. If any exclusion exists, the rule is rejected as a candidate.

3. Remaining candidates are ranked by:
   - Primary: most hard matches (descending)
   - Secondary: fewest soft matches (ascending)
   - Tertiary: fewest effective conditions (ascending -- prefer simpler rules as tiebreaker)

Verify the rule set produces deterministic rankings:

```pseudocode
function verify_ranking_determinism(rules):
    """
    Check that no two rules would produce identical ranking scores
    for any plausible input state. If two rules have identical
    condition sets (same flags, same values), they will always
    tie in the ranking algorithm.
    """
    for i, rule_a in enumerate(rules):
        for rule_b in rules[i+1:]:
            if rule_a.condition == rule_b.condition:
                if rule_a.priority == rule_b.priority:
                    append to computed.validation.threevl_issues:
                        severity: "error"
                        check: "ranking_tie"
                        message: "Rules '${rule_a.name}' and '${rule_b.name}' have identical conditions and priority. The 3VL ranker cannot distinguish them."
                        fix: "Assign different priorities or differentiate conditions."
                elif rule_a.action == rule_b.action:
                    append to computed.validation.threevl_issues:
                        severity: "info"
                        check: "redundant_rules"
                        message: "Rules '${rule_a.name}' and '${rule_b.name}' are functionally identical (same conditions, same action). One can be removed."
```

### Step 5.3: Common Semantic Errors

Detect well-known anti-patterns in 3VL rule design:

**Error 1: Rule with all conditions omitted (all U)**

A rule with zero conditions is equivalent to a catch-all. If it is not the designated fallback, it swallows every input:

```pseudocode
for rule in computed.intent_mapping.rules:
    if len(rule.condition) == 0:
        append to computed.validation.threevl_issues:
            severity: "warning"
            check: "empty_conditions"
            message: "Rule '${rule.name}' has no conditions (all flags implicitly U). It matches every input and acts as a catch-all."
            fix: "If this is intentional, move it to the fallback: section. Otherwise, add at least one flag condition."
```

**Error 2: Contradictory rules**

Two rules with identical conditions but different actions and different priorities. The lower-priority rule is unreachable:

```pseudocode
for i, rule_a in enumerate(computed.intent_mapping.rules):
    for rule_b in computed.intent_mapping.rules[i+1:]:
        if rule_a.condition == rule_b.condition and rule_a.action != rule_b.action:
            if rule_a.priority != rule_b.priority:
                lower = rule_a if rule_a.priority > rule_b.priority else rule_b
                higher = rule_b if rule_a.priority > rule_b.priority else rule_a
                append to computed.validation.threevl_issues:
                    severity: "warning"
                    check: "shadowed_rule"
                    message: "Rule '${lower.name}' is shadowed by '${higher.name}' (identical conditions, higher priority). '${lower.name}' will never be selected."
                    fix: "Remove '${lower.name}' or add distinguishing conditions."
```

**Error 3: Overly broad rule swallows specific ones**

A rule with fewer conditions (more U values) at equal or higher priority than a more specific rule. The broad rule matches every input the specific rule would, plus more:

```pseudocode
for i, rule_a in enumerate(computed.intent_mapping.rules):
    for rule_b in computed.intent_mapping.rules[i+1:]:
        overlap = compute_overlap(rule_a.condition, rule_b.condition)
        if overlap.is_subset:
            # Identify the narrower (more specific) and broader (fewer conditions) rule
            if len(rule_a.condition) < len(rule_b.condition):
                broad, specific = rule_a, rule_b
            else:
                broad, specific = rule_b, rule_a

            # Broad rule should NOT have equal or better priority than specific
            if broad.priority <= specific.priority:
                append to computed.validation.threevl_issues:
                    severity: "warning"
                    check: "broad_swallows_specific"
                    message: "Broad rule '${broad.name}' (${len(broad.condition)} conditions, priority ${broad.priority}) swallows specific rule '${specific.name}' (${len(specific.condition)} conditions, priority ${specific.priority})."
                    fix: "Give '${specific.name}' a higher priority (lower number) than '${broad.name}', or remove the broad rule."
```

Store all issues in `computed.validation.threevl_issues`.

---

## Phase 6: Report

### Step 6.1: Per-Check Summary

For each validation dimension, produce a pass/fail summary:

```pseudocode
function dimension_summary(dimension_name, issues):
    errors = [i for i in issues if i.severity == "error"]
    warnings = [i for i in issues if i.severity == "warning"]
    infos = [i for i in issues if i.severity == "info"]

    if len(errors) > 0:
        status = "FAIL"
    elif len(warnings) > 0:
        status = "WARN"
    else:
        status = "PASS"

    return {
        dimension: dimension_name,
        status: status,
        errors: len(errors),
        warnings: len(warnings),
        info: len(infos),
        issues: issues
    }
```

Display the summary table:

```
| Dimension      | Status | Errors | Warnings | Info |
|----------------|--------|--------|----------|------|
| Coverage       | PASS   | 0      | 1        | 0    |
| Collisions     | FAIL   | 1      | 2        | 0    |
| Gaps           | WARN   | 0      | 3        | 2    |
| 3VL Semantics  | PASS   | 0      | 0        | 1    |
```

### Step 6.2: Coverage Score

Display the overall coverage metric computed in Phase 2:

```
Coverage: ${computed.validation.coverage_score}% of skills have routing rules
  - ${skills_with_rules} of ${total_skills} skills covered
  - Fallback: ${fallback_present ? "present" : "MISSING"}
```

### Step 6.3: Collision Summary

Display collision count and details:

```
Collisions: ${len(computed.validation.collision_issues)} found
  - Subset collisions: ${count_subset}
  - Priority conflicts: ${count_priority}
  - Ambiguous matches: ${count_ambiguous}
  - Duplicate rules: ${count_duplicate}
```

For each collision, show the involved rules and the nature of the overlap.

### Step 6.4: 3VL Correctness Assessment

Summarize the 3VL validation results:

```
3VL Semantics: ${status}
  - Invalid values: ${count_invalid_values}
  - Undeclared flags: ${count_undeclared}
  - Ranking ties: ${count_ties}
  - Shadowed rules: ${count_shadowed}
  - Empty-condition rules: ${count_empty}
```

### Step 6.5: Fix Suggestions

For each issue found across all dimensions, display grouped by severity (errors first, then warnings, then info):

```
### Errors (must fix)

[ERROR] ${dimension}: ${message}
  Fix: ${fix_suggestion}

### Warnings (should fix)

[WARN] ${dimension}: ${message}
  Fix: ${fix_suggestion}

### Info (observations)

[INFO] ${dimension}: ${message}
  Note: ${fix_suggestion}
```

### Step 6.6: Next Steps

Present the user with options for what to do with the validation results:

```json
{
  "questions": [{
    "question": "Validation complete. What would you like to do?",
    "header": "Next steps",
    "options": [
      {
        "label": "Fix issues",
        "description": "Apply suggested fixes to the intent-mapping.yaml (will invoke bp-intent-create)"
      },
      {
        "label": "Re-validate",
        "description": "Run validation again (after manual edits)"
      },
      {
        "label": "Done",
        "description": "Validation review complete"
      }
    ],
    "multiSelect": false
  }]
}
```

**Response handling:**

```pseudocode
user_choice = AskUserQuestion(questions_json).responses[0]

if user_choice == "Fix issues":
    # Hand off to bp-intent-create with computed.validation as context
    # The create skill can use the issue list to guide targeted fixes
    invoke_skill("bp-intent-create", context=computed.validation)
elif user_choice == "Re-validate":
    # Return to Phase 1, Step 1.2 (re-read the file)
    # Clear all computed.validation.* state and re-run Phases 2-6
    clear(computed.validation)
    goto Step_1_2
elif user_choice == "Done":
    # Display final summary line and exit
    print("Validation complete.")
```

---

## Reference Documentation

- **3VL Validation Rules:** `patterns/3vl-validation-rules.md` (local to this skill)
- **Coverage Analysis Algorithm:** `patterns/coverage-analysis-algorithm.md` (local to this skill)
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`

---

## Related Skills

- **Create intent mapping:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-intent-create/SKILL.md`
- **Validate workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/SKILL.md`
- **Validate gateway command:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-gateway-validate/SKILL.md`
- **Discover plugin skills:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-discover/SKILL.md`
