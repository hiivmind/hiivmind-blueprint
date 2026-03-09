> **Used by:** `SKILL.md` Phase 3

# Complexity Scoring

Weighted scoring formula for classifying prose skill complexity as Low, Medium, or High.

---

## Metrics and Weights

Each metric contributes to the overall complexity score according to its assigned weight. Weights reflect the relative impact of each metric on conversion difficulty.

| Metric | Weight | Rationale |
|--------|--------|-----------|
| `phase_count` | 0.15 | More phases means more workflow nodes, but phases are straightforward to map |
| `conditional_count` | 0.25 | Conditionals are the hardest to convert correctly; highest weight |
| `branching_depth` | 0.20 | Nested conditionals compound conversion difficulty exponentially |
| `tool_variety` | 0.10 | More tools means more node types, but each is independently simple |
| `user_interactions` | 0.15 | User prompts require careful state handling and response routing |
| `state_variables` | 0.15 | More state means more data flow mapping between nodes |

**Sum of weights:** 1.00

---

## Normalization

Each metric is normalized to a 1-3 integer scale using the threshold ranges defined in the metrics table.

| Metric | Low (= 1) | Medium (= 2) | High (= 3) |
|--------|-----------|---------------|-------------|
| `phase_count` | 1-3 | 4-6 | 7+ |
| `conditional_count` | 0-1 | 2-4 | 5+ |
| `branching_depth` | 1 (linear) | 2 levels | 3+ levels |
| `tool_variety` | 1-2 tools | 3-4 tools | 5+ tools |
| `user_interactions` | 0-1 | 2-3 | 4+ |
| `state_variables` | 1-3 | 4-7 | 8+ |

Normalization pseudocode:
```
function normalize(value, low_max, med_max):
  if value <= low_max:
    return 1
  elif value <= med_max:
    return 2
  else:
    return 3

phase_count_norm       = normalize(phase_count, 3, 6)
conditional_count_norm = normalize(conditional_count, 1, 4)
branching_depth_norm   = normalize(branching_depth, 1, 2)
tool_variety_norm      = normalize(tool_variety, 2, 4)
user_interactions_norm = normalize(user_interactions, 1, 3)
state_variables_norm   = normalize(state_variables, 3, 7)
```

---

## Scoring Formula

```
score = (phase_count_norm       * 0.15) +
        (conditional_count_norm * 0.25) +
        (branching_depth_norm   * 0.20) +
        (tool_variety_norm      * 0.10) +
        (user_interactions_norm * 0.15) +
        (state_variables_norm   * 0.15)
```

The score ranges from 1.00 (all metrics Low) to 3.00 (all metrics High).

---

## Classification Thresholds

| Score Range | Classification | Description |
|-------------|----------------|-------------|
| < 1.5 | **Low** | Simple linear workflow. Direct conversion with minimal conditionals. Single action chain. |
| 1.5 - 2.5 | **Medium** | Standard workflow with branching. May benefit from subflow extraction. Conditional routing needed. |
| > 2.5 | **High** | Complex workflow requiring manual review. Consider decomposition into multiple skills or subflows. |

---

## Worked Examples

### Example 1: Simple Validation Skill (Low)

```
Metrics:
  phase_count: 2       → norm: 1
  conditional_count: 1  → norm: 1
  branching_depth: 1    → norm: 1
  tool_variety: 2       → norm: 1
  user_interactions: 0  → norm: 1
  state_variables: 2    → norm: 1

Score = (1 * 0.15) + (1 * 0.25) + (1 * 0.20) + (1 * 0.10) + (1 * 0.15) + (1 * 0.15)
      = 0.15 + 0.25 + 0.20 + 0.10 + 0.15 + 0.15
      = 1.00

Classification: Low
```

### Example 2: Standard Conversion Skill (Medium)

```
Metrics:
  phase_count: 5       → norm: 2
  conditional_count: 3  → norm: 2
  branching_depth: 2    → norm: 2
  tool_variety: 4       → norm: 2
  user_interactions: 2  → norm: 2
  state_variables: 6    → norm: 2

Score = (2 * 0.15) + (2 * 0.25) + (2 * 0.20) + (2 * 0.10) + (2 * 0.15) + (2 * 0.15)
      = 0.30 + 0.50 + 0.40 + 0.20 + 0.30 + 0.30
      = 2.00

Classification: Medium
```

### Example 3: Complex Multi-Phase Skill (High)

```
Metrics:
  phase_count: 8       → norm: 3
  conditional_count: 6  → norm: 3
  branching_depth: 3    → norm: 3
  tool_variety: 6       → norm: 3
  user_interactions: 4  → norm: 3
  state_variables: 10   → norm: 3

Score = (3 * 0.15) + (3 * 0.25) + (3 * 0.20) + (3 * 0.10) + (3 * 0.15) + (3 * 0.15)
      = 0.45 + 0.75 + 0.60 + 0.30 + 0.45 + 0.45
      = 3.00

Classification: High
```

### Example 4: Mixed Metrics (Medium-High Boundary)

```
Metrics:
  phase_count: 4       → norm: 2
  conditional_count: 5  → norm: 3
  branching_depth: 3    → norm: 3
  tool_variety: 3       → norm: 2
  user_interactions: 1  → norm: 1
  state_variables: 3    → norm: 1

Score = (2 * 0.15) + (3 * 0.25) + (3 * 0.20) + (2 * 0.10) + (1 * 0.15) + (1 * 0.15)
      = 0.30 + 0.75 + 0.60 + 0.20 + 0.15 + 0.15
      = 2.15

Classification: Medium
```

This example shows how heavy conditional/branching complexity is moderated by low user interactions and state variables, resulting in a medium classification despite two metrics scoring high.

---

## Conversion Approach Mapping

| Classification | Approach | Node Estimate Formula |
|----------------|----------|----------------------|
| Low | `simple_linear` | `phase_count * 2 + conditional_count` |
| Medium | `standard_workflow` | `phase_count * 3 + conditional_count * 2 + user_interactions` |
| High | `complex_with_subflows` | `phase_count * 4 + conditional_count * 3 + user_interactions * 2` |

The node estimate provides a rough upper bound for planning purposes. Actual node counts may be lower after optimization (merging sequential action nodes, collapsing trivial conditionals).
