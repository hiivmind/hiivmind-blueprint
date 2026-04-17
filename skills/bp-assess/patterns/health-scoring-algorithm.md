> **Used by:** `SKILL.md` Phase 6

# Health Scoring Algorithm

Weighted scoring formula for computing the overall plugin health score (0-100) from
four category dimensions: completeness, quality, consistency, and maintainability.

---

## Score Formula

```
overall = 0.30 * completeness + 0.25 * quality + 0.25 * consistency + 0.20 * maintainability
```

The overall score ranges from 0 (all categories at 0) to 100 (all categories at 100).

---

## Category Definitions

### Completeness (Weight: 0.30)

Measures how feature-complete the plugin is in terms of workflow adoption and gateway coverage.

| Factor | Contribution | Detection |
|--------|-------------|-----------|
| Workflow adoption | 60% of category | `(skills_with_workflows / total_skills) * 100` |
| Gateway coverage | 40% of category | `(routed_skills / total_skills) * 100` |

```pseudocode
function compute_completeness(inventory, intent_coverage):
  workflow_count = count(s for s in inventory if s.has_workflow)
  total = len(inventory)
  workflow_pct = (workflow_count / total * 100) if total > 0 else 0

  gateway_pct = 0
  IF intent_coverage.gateway_found:
    routed = len(intent_coverage.routed_skills)
    gateway_pct = (routed / total * 100) if total > 0 else 0

  return round(workflow_pct * 0.6 + gateway_pct * 0.4)
```

**Scoring examples:**
- 6/6 skills have workflows, 6/6 routed via gateway: `100 * 0.6 + 100 * 0.4 = 100`
- 4/6 skills have workflows, no gateway: `66.7 * 0.6 + 0 * 0.4 = 40`
- 6/6 skills have workflows, 3/6 routed: `100 * 0.6 + 50 * 0.4 = 80`

### Quality (Weight: 0.25)

Measures the average quality of workflow content across the plugin. Based on node
description coverage as the primary proxy metric.

```pseudocode
function compute_quality(workflows):
  coverage_scores = []
  FOR wf IN workflows:
    nodes = parse_nodes(wf.path)
    nodes_with_desc = count(n for n in nodes if "description" in n AND n.description != "")
    coverage = (nodes_with_desc / len(nodes) * 100) if len(nodes) > 0 else 100
    coverage_scores.append(coverage)

  IF len(coverage_scores) == 0:
    return 50  # No workflows to measure -- neutral score

  return round(average(coverage_scores))
```

**Scoring examples:**
- All nodes in all workflows have descriptions: 100
- Half the nodes are described on average: 50
- No workflows exist: 50 (neutral default)

### Consistency (Weight: 0.25)

Measures uniformity of versions, types, and naming conventions across the plugin.
Starts at 100 and applies deductions for each inconsistency found.

| Issue | Deduction | Cap |
|-------|-----------|-----|
| Lib version mismatch across workflows | -25 | once |
| Schema version mismatch across workflows | -15 | once |
| Each deprecated type usage | -5 | -30 max |
| Each keyword overlap in intent mapping | -5 | -15 max |

```pseudocode
function compute_consistency(version_consistency, intent_coverage):
  deductions = 0

  IF NOT version_consistency.lib_version_consistent:
    deductions += 25

  IF NOT version_consistency.schema_version_consistent:
    deductions += 15

  deprecated_penalty = min(version_consistency.deprecated_count * 5, 30)
  deductions += deprecated_penalty

  IF intent_coverage.gateway_found:
    overlap_penalty = min(intent_coverage.overlap_count * 5, 15)
    deductions += overlap_penalty

  return max(0, 100 - deductions)
```

**Scoring examples:**
- Everything aligned, no deprecated types: `100 - 0 = 100`
- Lib mismatch + 3 deprecated types: `100 - 25 - 15 = 60`
- All mismatches, 10 deprecated, 5 overlaps: `100 - 25 - 15 - 30 - 15 = 15`

### Maintainability (Weight: 0.20)

Measures how easy the plugin's workflows are to understand and modify. Based on
average cyclomatic complexity as the primary indicator.

| Avg CC | Score | Interpretation |
|--------|-------|---------------|
| 1-3 | 100 | Simple, easy to maintain |
| 4-6 | 75 | Moderate, manageable |
| 7-10 | 50 | Complex, may need simplification |
| 11+ | 25 | Very complex, likely needs decomposition |

```pseudocode
function compute_maintainability(avg_complexity):
  IF avg_complexity <= 0:
    return 50  # No workflows to measure

  IF avg_complexity <= 3:
    return 100
  ELIF avg_complexity <= 6:
    return 75
  ELIF avg_complexity <= 10:
    return 50
  ELSE:
    return 25
```

---

## Traffic Light Thresholds

Applied to both the overall score and each category score:

| Score Range | Light | Meaning |
|-------------|-------|---------|
| 80-100 | Green | Healthy -- no urgent action needed |
| 50-79 | Yellow | Attention needed -- some issues to address |
| 0-49 | Red | Unhealthy -- significant issues require action |

---

## Worked Examples

### Example 1: Well-Maintained Plugin

```
Inventory: 6 skills, all with workflows, all routed via gateway
Quality: all nodes documented (100%)
Versions: all aligned, 0 deprecated types
Avg CC: 3.2

Completeness:    100 * 0.6 + 100 * 0.4 = 100
Quality:         100
Consistency:     100 - 0 = 100
Maintainability: 75 (CC 3.2 falls in 1-6 range, closer to boundary)

Overall = 100 * 0.30 + 100 * 0.25 + 100 * 0.25 + 75 * 0.20
        = 30 + 25 + 25 + 15
        = 95 [Green]
```

### Example 2: Plugin in Transition

```
Inventory: 8 skills, 4 with workflows, no gateway
Quality: 60% description coverage
Versions: lib mismatch in 2 workflows, 4 deprecated types
Avg CC: 5.1

Completeness:    50 * 0.6 + 0 * 0.4 = 30
Quality:         60
Consistency:     100 - 25 - 20 = 55
Maintainability: 75

Overall = 30 * 0.30 + 60 * 0.25 + 55 * 0.25 + 75 * 0.20
        = 9 + 15 + 13.75 + 15
        = 52.75 -> 53 [Yellow]
```

### Example 3: Neglected Plugin

```
Inventory: 10 skills, 2 with workflows, no gateway
Quality: 30% description coverage
Versions: multiple mismatches, 12 deprecated types
Avg CC: 8.5

Completeness:    20 * 0.6 + 0 * 0.4 = 12
Quality:         30
Consistency:     100 - 25 - 15 - 30 = 30
Maintainability: 50

Overall = 12 * 0.30 + 30 * 0.25 + 30 * 0.25 + 50 * 0.20
        = 3.6 + 7.5 + 7.5 + 10
        = 28.6 -> 29 [Red]
```

---

## Trend Tracking

When a previous analysis exists at `${CLAUDE_PLUGIN_ROOT}/.hiivmind/plugin-analysis-history.yaml`,
the current score is compared to produce a trend indicator:

| Delta | Direction | Display |
|-------|-----------|---------|
| > 0 | improved | "+N points since YYYY-MM-DD" |
| = 0 | unchanged | "unchanged since YYYY-MM-DD" |
| < 0 | regressed | "-N points since YYYY-MM-DD" |

The history file stores the most recent analysis timestamp and overall score. Each
run updates this file, enabling longitudinal tracking of plugin health.

---

## Related Documentation

- **Cross-Skill Metrics:** `patterns/cross-skill-metrics.md`
- **Classification Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/patterns/classification-algorithm.md`
- **Complexity Scoring (single skill):** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/patterns/complexity-scoring-algorithm.md`
