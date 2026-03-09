# Quality Indicators

> **Used by:** `SKILL.md` Phase 3
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

This document defines the complete quality indicator catalog, the scoring rubric for each
dimension, and the anti-pattern catalog with detection rules and severity levels.

---

## Quality Dimensions

Each dimension is scored independently on a 0-100 scale. Dimensions are combined into an
overall health score using weighted averaging.

### Dimension Weights

| Dimension | Weight | Rationale |
|-----------|--------|-----------|
| Description coverage | 0.20 | Self-documenting workflows are easier to maintain |
| Error handling coverage | 0.35 | Robust error handling prevents silent failures |
| Modularity (subflow usage) | 0.20 | Decomposition improves reuse and testability |
| Naming consistency | 0.10 | Consistent naming reduces cognitive load |
| Anti-pattern freedom | 0.15 | Absence of structural problems indicates sound design |

### Rating Scale

All dimensions use the same rating scale:

| Score Range | Rating | Interpretation |
|-------------|--------|----------------|
| 90-100 | `excellent` | No action needed |
| 70-89 | `good` | Minor improvements possible |
| 50-69 | `fair` | Noticeable gaps, should address |
| 0-49 | `poor` | Significant problems, must address |

---

## Scoring Rubric

### Description Coverage (0-100)

Measures the percentage of nodes that include a non-empty `description` field.

```pseudocode
score = (nodes_with_description / total_nodes) * 100
```

| Coverage | Score | Rating | Guidance |
|----------|-------|--------|----------|
| 100% | 100 | excellent | All nodes documented |
| 80-99% | 80-99 | good | A few nodes missing descriptions |
| 50-79% | 50-79 | fair | Many nodes lack context |
| 0-49% | 0-49 | poor | Most nodes undocumented |

**What counts as a description:**
- The `description` field must be present on the node
- The value must be a non-empty string (not `""`, not `null`)
- Ending nodes are excluded from the count (they have `message` instead)

**Common gaps:**
- Conditional nodes often lack descriptions because the condition itself seems self-documenting
- Reference nodes may omit descriptions when the `doc` field is considered sufficient
- Action nodes with a single `set_state` action are frequently left undescribed

### Error Handling Coverage (0-100)

Measures how comprehensively action nodes handle failure scenarios.

**Two-tier scoring:**

| Tier | Weight | What It Measures |
|------|--------|-----------------|
| Basic | 0.60 | Does the action node have an `on_failure` field at all? |
| Meaningful | 0.40 | Does `on_failure` point to a specific error ending (not just `cancelled`)? |

```pseudocode
basic_pct = (nodes_with_on_failure / total_action_nodes) * 100
meaningful_pct = (nodes_with_specific_error_ending / total_action_nodes) * 100
score = round(basic_pct * 0.6 + meaningful_pct * 0.4)
```

**What counts as meaningful error handling:**
- `on_failure` points to a named error ending (e.g., `error_load`, `error_parse`)
- The error ending has a descriptive `message` and optionally a `recovery` suggestion
- `on_failure: cancelled` does NOT count as meaningful (it is a generic catch-all)
- `on_failure` pointing to another action node (retry pattern) counts as meaningful

**Scoring examples:**

| Scenario | Basic | Meaningful | Score |
|----------|-------|------------|-------|
| 10/10 have on_failure, 10/10 specific | 100% | 100% | 100 |
| 10/10 have on_failure, 5/10 specific | 100% | 50% | 80 |
| 7/10 have on_failure, 7/10 specific | 70% | 70% | 70 |
| 5/10 have on_failure, 0/10 specific | 50% | 0% | 30 |
| 0/10 have on_failure | 0% | 0% | 0 |

### Modularity / Subflow Usage (0-100)

Measures whether the workflow delegates to subflows via `reference` nodes.

**Size-adjusted scoring:**

| Workflow Size | Reference Count | Score | Rating |
|---------------|----------------|-------|--------|
| <= 5 nodes | Any | 100 | n/a (too small) |
| 6-15 nodes | 0 | 60 | fair |
| 6-15 nodes | 1-2 | 70 | good |
| 6-15 nodes | 3+ | 100 | excellent |
| 16+ nodes | 0 | 30 | poor |
| 16+ nodes | 1-2 | 70 | good |
| 16+ nodes | 3+ or >= 20% of nodes | 100 | excellent |

**What counts as a subflow reference:**
- A node with `type: reference` that points to a `doc` path
- The `doc` path should resolve to a valid pattern or subflow file
- Self-referencing nodes (pointing to the same workflow) are loops, not subflows

### Naming Consistency (0-100)

Measures adherence to naming conventions for node IDs.

**Two-factor scoring:**

| Factor | Weight | Pattern |
|--------|--------|---------|
| snake_case compliance | 0.70 | `/^[a-z][a-z0-9]*(_[a-z0-9]+)*$/` |
| Type-prefix convention | 0.30 | Node ID starts with a prefix that matches its type |

```pseudocode
score = round(snake_case_pct * 0.7 + prefix_pct * 0.3)
```

**Type-prefix conventions:**

| Node Type | Accepted Prefixes | Examples |
|-----------|------------------|----------|
| `action` | `do_`, `run_`, `exec_`, `perform_`, `set_`, `save_`, `load_`, `write_`, `read_` | `load_config`, `write_output` |
| `conditional` | `check_`, `is_`, `has_`, `validate_`, `verify_`, `if_` | `check_prerequisites`, `is_valid` |
| `user_prompt` | `prompt_`, `ask_`, `select_`, `choose_`, `confirm_` | `prompt_scope`, `ask_format` |
| `reference` | `ref_`, `sub_`, `call_`, `invoke_` | `ref_load_skill`, `sub_validate` |

**Common violations:**
- camelCase IDs (`loadConfig` instead of `load_config`)
- UPPER_CASE IDs (`LOAD_CONFIG`)
- Numeric-only suffixes without meaning (`step1`, `step2`)
- Mismatched type prefix (`check_` on an action node)

---

## Anti-Pattern Catalog

Anti-patterns are structural problems detected in Phase 4. Each has a severity level
that determines its impact on the overall health score.

### Severity Levels

| Severity | Score Deduction | Meaning |
|----------|----------------|---------|
| `error` | -15 per occurrence | Must fix -- workflow may malfunction or stall |
| `warning` | -10 per occurrence | Should fix -- reduces maintainability or clarity |

The anti-pattern freedom score starts at 100 and deducts per finding:

```pseudocode
anti_pattern_score = max(0, 100 - sum(deductions))
```

### Anti-Pattern: Deep Nesting

| Property | Value |
|----------|-------|
| Severity | `warning` |
| Deduction | -10 |
| Threshold | Max branch depth > 4 |
| Detection | DFS from start_node, track conditional depth |

**Why it matters:** Deeply nested branches create exponentially many paths, making the
workflow difficult to reason about and test exhaustively.

**Remediation:** Extract nested branches into subflows via `reference` nodes. Each
subflow encapsulates a decision subtree with its own endings that map back to the
parent workflow.

### Anti-Pattern: God Nodes

| Property | Value |
|----------|-------|
| Severity | `warning` |
| Deduction | -10 per node |
| Threshold | Action node with > 5 actions |
| Detection | Count actions array length per action node |

**Why it matters:** Nodes with many actions are doing too much. If any single action
fails, the entire node fails, making error recovery coarse-grained.

**Remediation:** Split into a chain of focused action nodes, each with 1-3 actions
and its own error handling.

### Anti-Pattern: Missing Error Paths

| Property | Value |
|----------|-------|
| Severity | `error` |
| Deduction | -15 per node |
| Threshold | Action node without `on_failure` |
| Detection | Check for absence of `on_failure` field on action nodes |

**Why it matters:** Without `on_failure`, a failed action has undefined behavior.
The engine may halt, retry implicitly, or silently continue -- none of which are
desirable in a deterministic workflow.

**Remediation:** Add an explicit `on_failure` transition pointing to either:
- A specific error ending with a descriptive message
- A retry/recovery node
- A user_prompt node that asks how to proceed

### Anti-Pattern: Orphan Nodes

| Property | Value |
|----------|-------|
| Severity | `error` |
| Deduction | -15 per node |
| Threshold | Node unreachable from start_node |
| Detection | BFS from start_node; nodes not in reachable set are orphans |

**Why it matters:** Orphan nodes are dead code. They consume cognitive load during
review but never execute. They may also indicate a broken transition that was supposed
to reach them.

**Remediation:** Either:
- Remove the orphan node entirely
- Fix the broken transition that should reference it
- If the node is intentionally dormant, add a comment explaining why

### Anti-Pattern: Dead-End Nodes

| Property | Value |
|----------|-------|
| Severity | `warning` |
| Deduction | -10 per node |
| Threshold | Non-ending node with no outgoing transitions |
| Detection | Check each node type for its expected outgoing fields |

**Expected outgoing fields by type:**

| Node Type | Required Outgoing | Detection Rule |
|-----------|------------------|----------------|
| `action` | `on_success` | `on_success` must be defined |
| `conditional` | `branches.on_true` AND `branches.on_false` | Both must be defined |
| `user_prompt` | `on_response` with at least one entry | `len(on_response) > 0` |
| `reference` | `next_node` | `next_node` must be defined |

**Why it matters:** Dead-end nodes cause the workflow to stall at runtime with no
indication of what went wrong.

**Remediation:** Add the missing transition to route to the next node or an ending.

---

## Overall Health Score

The overall health score is a weighted combination of all quality dimension scores:

```pseudocode
function compute_overall_health():
  anti_pattern_count = count_all_anti_pattern_findings()
  anti_pattern_score = max(0, 100 - (anti_pattern_count * deduction_per_finding))

  overall = round(
    description_score * 0.20
    + error_handling_score * 0.35
    + modularity_score * 0.20
    + naming_score * 0.10
    + anti_pattern_score * 0.15
  )

  RETURN overall
```

### Interpretation

| Overall Score | Health | Action |
|---------------|--------|--------|
| 90-100 | Excellent | Workflow is well-structured and maintainable |
| 70-89 | Good | Minor improvements recommended |
| 50-69 | Fair | Several areas need attention |
| 0-49 | Poor | Significant rework needed before production use |

---

## Related Documentation

- **Complexity Scoring:** `patterns/complexity-scoring-algorithm.md`
- **SKILL.md Phase 3:** Parent skill, quality assessment
- **SKILL.md Phase 4:** Parent skill, anti-pattern detection
