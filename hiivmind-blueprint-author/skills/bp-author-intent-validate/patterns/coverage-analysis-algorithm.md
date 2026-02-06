> **Used by:** `SKILL.md` Phase 2
> **Supplements:** `patterns/3vl-validation-rules.md`

# Coverage Analysis Algorithm

Algorithm for computing skill coverage percentage, gap detection across flag combinations, collision set identification via pairwise rule comparison, and overlap visualization.

---

## Overview

Coverage analysis answers four questions:

1. **What percentage of declared skills are routable?** (coverage score)
2. **Which flag combinations have no matching rule?** (gap detection)
3. **Which rules overlap in ways that cause ambiguity?** (collision sets)
4. **How do the rules partition the input space?** (overlap visualization)

---

## Algorithm 1: Coverage Score Computation

The coverage score measures what fraction of available skills have at least one routing rule:

```
function compute_coverage_score(available_skills, rules):
    """
    Returns: float between 0.0 and 100.0

    A skill is "covered" if at least one rule has action == skill.name.
    Built-in actions (show_help, show_menu, etc.) are excluded from the denominator.
    """
    if len(available_skills) == 0:
        return 100.0  # vacuously true

    covered = 0
    for skill in available_skills:
        for rule in rules:
            if rule.action == skill.name:
                covered += 1
                break  # only need one matching rule

    return (covered / len(available_skills)) * 100.0
```

**Interpretation:**

| Score | Meaning | Action |
|-------|---------|--------|
| 100% | Every skill has routing | No coverage issues |
| 80-99% | Most skills routable | Review missing skills |
| 50-79% | Significant gaps | Many skills unreachable |
| < 50% | Severe coverage gap | Intent mapping is incomplete |

---

## Algorithm 2: Gap Detection (Flag Combination Enumeration)

Enumerates all possible flag state combinations and tests each against the rule set to find unhandled inputs.

### Exhaustive Enumeration

For N flags, there are 3^N possible combinations (each flag can be T, F, or U):

```
function enumerate_all_combinations(flag_names):
    """
    Generate every possible combination of T/F/U across all flags.

    For 7 flags: 3^7 = 2187 combinations (tractable).
    For 10 flags: 3^10 = 59049 combinations (still tractable but slow to display).
    For 15+ flags: consider sampling instead of exhaustive enumeration.
    """
    n = len(flag_names)

    if n > 12:
        return sample_combinations(flag_names)  # fallback to sampling

    combinations = []
    for values in product(["T", "F", "U"], repeat=n):
        state = dict(zip(flag_names, values))
        combinations.append(state)

    return combinations
```

### Testing Each Combination

For each combination, apply the 3VL matching algorithm to determine which rule (if any) would be selected:

```
function test_combination(state, rules, fallback):
    """
    Returns: the matching rule, or None if no rule matches and no fallback exists.
    """
    candidates = []

    for rule in rules:
        result = evaluate_rule(state, rule)  # from 3vl-validation-rules.md
        if not result.rejected:
            candidates.append((rule, result))

    if len(candidates) == 0:
        if fallback:
            return fallback
        return None  # GAP: this combination is unhandled

    # Rank candidates per 3VL ranking algorithm
    ranked = rank_candidates([c[1] for c in candidates])
    winning_index = ranked[0]  # best candidate
    return candidates[winning_index][0]  # return the rule
```

### Gap Collection

```
function find_gaps(flag_names, rules, fallback):
    """
    Returns: list of flag combinations that match no rule.
    If fallback exists, returns empty (fallback catches everything).
    """
    if fallback is not None:
        return []  # fallback covers all gaps by definition

    combinations = enumerate_all_combinations(flag_names)
    gaps = []

    for state in combinations:
        result = test_combination(state, rules, fallback=None)
        if result is None:
            gaps.append(state)

    return gaps
```

### Gap Categorization

Not all gaps are equal. Categorize by likelihood of occurrence:

```
function categorize_gap(gap_state):
    """
    Classify a gap based on how likely a real user input would produce this state.
    """
    t_count = sum(1 for v in gap_state.values() if v == "T")
    f_count = sum(1 for v in gap_state.values() if v == "F")
    u_count = sum(1 for v in gap_state.values() if v == "U")

    if t_count == 0:
        return "unlikely"    # No flags triggered -- user said nothing recognizable
    elif t_count == 1 and u_count == len(gap_state) - 1:
        return "common"      # Single flag with rest unknown -- normal single-intent input
    elif t_count >= 2:
        return "multi_intent" # Multiple flags triggered -- complex compound request
    else:
        return "edge_case"   # Mix of T and F -- unusual but possible
```

Display priority: `common` gaps first, then `multi_intent`, then `edge_case`, then `unlikely`.

---

## Algorithm 3: Collision Set Identification

Pairwise comparison of all rules to find overlapping condition sets.

### Pairwise Comparison

```
function identify_collision_sets(rules):
    """
    Compare every pair of rules for condition overlap.

    Time complexity: O(R^2 * F) where R = number of rules, F = number of flags.
    For typical intent mappings (R < 20, F < 10), this is negligible.
    """
    collisions = []

    for i in range(len(rules)):
        for j in range(i + 1, len(rules)):
            rule_a = rules[i]
            rule_b = rules[j]
            relationship = classify_relationship(rule_a.condition, rule_b.condition)

            if relationship.type != "disjoint":
                collisions.append({
                    rule_a: rule_a,
                    rule_b: rule_b,
                    relationship: relationship
                })

    return collisions
```

### Relationship Classification

```
function classify_relationship(cond_a, cond_b):
    """
    Classify the relationship between two condition maps.

    Returns one of:
      - identical: same flags, same values
      - subset_ab: A is a subset of B (A is broader, B is more specific)
      - subset_ba: B is a subset of A (B is broader, A is more specific)
      - overlapping: shared flags agree but each has unique flags
      - disjoint: at least one shared flag contradicts
    """
    flags_a = set(cond_a.keys())
    flags_b = set(cond_b.keys())
    shared = flags_a & flags_b
    only_a = flags_a - flags_b
    only_b = flags_b - flags_a

    # Check for contradiction on any shared flag
    for flag in shared:
        if cond_a[flag] != cond_b[flag]:
            return {type: "disjoint", contradicting_flag: flag}

    # No contradictions -- determine relationship type
    if flags_a == flags_b:
        return {type: "identical"}
    elif len(only_a) == 0:
        # A has no unique flags; A's conditions are a subset of B's
        # A is BROADER (fewer constraints), B is MORE SPECIFIC
        return {type: "subset_ab", broader: "a", specific: "b"}
    elif len(only_b) == 0:
        # B has no unique flags; B's conditions are a subset of A's
        return {type: "subset_ba", broader: "b", specific: "a"}
    else:
        # Both have unique flags, shared flags agree
        return {type: "overlapping", shared_flags: list(shared),
                unique_a: list(only_a), unique_b: list(only_b)}
```

### Collision Severity Assessment

```
function assess_collision_severity(collision):
    """
    Determine whether a collision is problematic based on the
    relationship type and the rules' priorities and actions.
    """
    rel = collision.relationship
    rule_a = collision.rule_a
    rule_b = collision.rule_b

    if rel.type == "identical":
        if rule_a.action == rule_b.action:
            return {severity: "info", reason: "duplicate"}
        elif rule_a.priority == rule_b.priority:
            return {severity: "error", reason: "non_deterministic"}
        else:
            return {severity: "warning", reason: "shadowed"}

    if rel.type in ("subset_ab", "subset_ba"):
        broader = rule_a if rel.broader == "a" else rule_b
        specific = rule_a if rel.specific == "a" else rule_b

        if broader.priority <= specific.priority:
            # Broader rule has equal or higher priority -- swallows specific
            return {severity: "warning", reason: "swallowed"}
        else:
            # Specific rule has higher priority -- correct ordering
            return {severity: "info", reason: "correctly_ordered"}

    if rel.type == "overlapping":
        if rule_a.priority == rule_b.priority:
            return {severity: "warning", reason: "ambiguous_overlap"}
        else:
            return {severity: "info", reason: "priority_resolved"}

    return {severity: "info", reason: "disjoint"}
```

---

## Visualizing Overlap: Venn Diagram Approach

For human understanding, represent rule overlaps as a Venn-style partition of the flag space.

### Text-Based Venn Diagram

For up to 3 rules with overlapping conditions, render an ASCII representation:

```
function render_overlap_diagram(collision_set):
    """
    Produce a text-based visualization of which rules cover which
    parts of the input space.
    """
    # Collect all involved rules
    rules = set()
    for collision in collision_set:
        rules.add(collision.rule_a.name)
        rules.add(collision.rule_b.name)

    if len(rules) <= 3:
        render_venn_text(rules, collision_set)
    else:
        render_matrix(rules, collision_set)
```

Example Venn output for 2 overlapping rules:

```
Flag Space Overlap:

  +-- setup_action ------+
  |                      |
  | has_setup: T         |
  | (only setup)         |
  |          +-----------+-- convert_action --+
  |          |           |                    |
  |          | OVERLAP   |  has_convert: T    |
  |          | setup+    |  (only convert)    |
  |          | convert   |                    |
  +----------+-----------+--------------------+

  OVERLAP zone: has_setup: T AND has_convert: T
  Resolution: Both match, priority determines winner.
```

### Overlap Matrix

For larger rule sets, display a matrix showing each rule pair's relationship:

```
function render_matrix(rules, collisions):
    """
    Produce a matrix showing relationships between all rule pairs.
    """
    # Header
    print("Collision Matrix:")
    print("")
    print("| Rule |", " | ".join(rule_names), "|")
    print("|------|", " | ".join(["---"] * len(rule_names)), "|")

    for rule_a in rule_names:
        row = [rule_a]
        for rule_b in rule_names:
            if rule_a == rule_b:
                row.append("-")
            else:
                rel = find_relationship(rule_a, rule_b, collisions)
                row.append(rel.type[0].upper())  # I=identical, S=subset, O=overlap, D=disjoint
        print("| " + " | ".join(row) + " |")
```

Example matrix output:

```
Collision Matrix:

| Rule       | setup | convert | upgrade | gateway | regen | visual | help |
|------------|-------|---------|---------|---------|-------|--------|------|
| setup      |   -   |    D    |    D    |    D    |   D   |   D    |  D   |
| convert    |   D   |    -    |    D    |    D    |   D   |   D    |  D   |
| upgrade    |   D   |    D    |    -    |    D    |   D   |   D    |  D   |
| gateway    |   D   |    D    |    D    |    -    |   D   |   D    |  D   |
| regen      |   D   |    D    |    D    |    D    |   -   |   D    |  D   |
| visual     |   D   |    D    |    D    |    D    |   D   |   -    |  D   |
| help       |   D   |    D    |    D    |    D    |   D   |   D    |  -   |

Legend: I=Identical, S=Subset, O=Overlapping, D=Disjoint
```

All D (disjoint) is the ideal state -- each rule occupies a distinct region of the flag space.

---

## Edge Cases

### Zero Rules

If the intent-mapping has no rules at all, report:
- Coverage: 0%
- Gaps: all non-fallback combinations
- Collisions: none (no rules to collide)

### Single Rule

If only one rule exists:
- Collisions: none (no pair to compare)
- Coverage: 1 / N skills
- Gaps: all combinations not matching the single rule

### Flags With Empty Keywords

A flag with `keywords: []` can never be set to T by keyword evaluation. All rules requiring `flag: T` for that flag are unreachable. Flag this as part of coverage analysis.

### Very Large Flag Count (N > 12)

If the number of flags exceeds 12, exhaustive enumeration of 3^N combinations becomes impractical (3^13 = 1,594,323). In this case:

```
function sample_combinations(flag_names, sample_size=10000):
    """
    Random sampling of the flag space for large N.
    Prioritize 'common' patterns: single-T, all-U, pairwise-T.
    """
    samples = []

    # Always include: all-U state
    samples.append({f: "U" for f in flag_names})

    # Always include: each single-flag-T state
    for flag in flag_names:
        state = {f: "U" for f in flag_names}
        state[flag] = "T"
        samples.append(state)

    # Always include: each pairwise-T combination
    for i, flag_a in enumerate(flag_names):
        for flag_b in flag_names[i+1:]:
            state = {f: "U" for f in flag_names}
            state[flag_a] = "T"
            state[flag_b] = "T"
            samples.append(state)

    # Fill remaining with random samples
    import random
    while len(samples) < sample_size:
        state = {f: random.choice(["T", "F", "U"]) for f in flag_names}
        samples.append(state)

    return deduplicate(samples)
```

Report that sampling was used instead of exhaustive enumeration, and note the coverage may be approximate.

---

## Related Documentation

- **3VL Validation Rules:** `patterns/3vl-validation-rules.md`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
