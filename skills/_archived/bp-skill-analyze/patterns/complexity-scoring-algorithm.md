# Complexity Scoring Algorithm

> **Used by:** `SKILL.md` Phase 2, Step 2.4
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

This document defines the full cyclomatic complexity formula for workflow graphs, the
weighted overall complexity score, and threshold definitions for classification.

---

## Cyclomatic Complexity for Workflow Graphs

Cyclomatic complexity measures the number of linearly independent paths through a directed
graph. For workflow.yaml files, the formula adapts the standard McCabe metric to account
for workflow-specific node types.

### Formula

```
M = E - N + 2P
```

Where:

| Symbol | Meaning | Workflow Mapping |
|--------|---------|-----------------|
| `M` | Cyclomatic complexity | Number of independent paths through the workflow |
| `E` | Number of edges | Count of all transitions (on_success, on_failure, branches, on_response) |
| `N` | Number of nodes | Count of all nodes + all endings |
| `P` | Connected components | Typically 1 for a well-formed workflow (no orphan subgraphs) |

### Edge Counting Rules

Each node type contributes edges differently:

| Node Type | Edges Contributed | Detail |
|-----------|------------------|--------|
| `action` (with on_failure) | 2 | `on_success` + `on_failure` |
| `action` (without on_failure) | 1 | `on_success` only |
| `conditional` | 2 | `on_true` + `on_false` |
| `conditional` (audit, multi-condition) | 2 | Still 2 edges regardless of condition count |
| `user_prompt` | N | One edge per option in `on_response` |
| `reference` | 1 | `next_node` |
| `ending` | 0 | Terminal node, no outgoing edges |

### Pseudocode

```pseudocode
function cyclomatic_complexity(workflow):
  edges = 0

  FOR node IN workflow.nodes:
    SWITCH node.type:
      CASE "action":
        edges += 1                        # on_success
        IF node.on_failure is defined:
          edges += 1                      # on_failure
      CASE "conditional":
        edges += 2                        # on_true + on_false
      CASE "user_prompt":
        edges += len(node.on_response)    # one per option
      CASE "reference":
        edges += 1                        # next_node

  total_nodes = len(workflow.nodes) + len(workflow.endings)
  connected_components = count_connected_components(workflow)  # Usually 1

  RETURN edges - total_nodes + 2 * connected_components
```

### Connected Components

A well-formed workflow has exactly 1 connected component (all nodes reachable from
`start_node`). If orphan nodes exist, they form additional components:

```pseudocode
function count_connected_components(workflow):
  reachable = BFS(workflow.start_node)
  all_nodes = set(workflow.nodes.keys()) | set(workflow.endings.keys())
  unreachable = all_nodes - reachable

  IF len(unreachable) == 0:
    RETURN 1

  # Count disconnected subgraphs among unreachable nodes
  components = 1
  remaining = set(unreachable)
  WHILE remaining:
    start = remaining.pop()
    subgraph = BFS(start, scope=unreachable)
    remaining -= subgraph
    components += 1

  RETURN components
```

---

## Weighted Overall Complexity Score

The cyclomatic complexity alone does not capture all dimensions of workflow complexity.
The weighted overall score combines multiple metrics into a single number.

### Input Metrics

| Metric | Symbol | Source |
|--------|--------|--------|
| Total node count | `N_total` | `computed.metrics.nodes.total` |
| Cyclomatic complexity | `CC` | `computed.metrics.cyclomatic_complexity` |
| Max branch depth | `D_max` | `computed.metrics.max_branch_depth` |
| State variable count (declared) | `S_decl` | `computed.metrics.state_variables.declared` |
| State variable count (mutated) | `S_mut` | `computed.metrics.state_variables.mutated` |
| User prompt count | `P_user` | `computed.metrics.nodes.user_prompt` |

### Weighted Formula

```pseudocode
function weighted_complexity(metrics):
  # Normalize each metric to a 0-10 scale
  n_score = min(10, metrics.nodes.total / 3)         # 30 nodes = max 10
  cc_score = min(10, metrics.cyclomatic_complexity / 2)  # CC of 20 = max 10
  d_score = min(10, metrics.max_branch_depth * 2)     # depth 5 = max 10
  s_score = min(10, (metrics.state_variables.declared + metrics.state_variables.mutated) / 3)
  p_score = min(10, metrics.nodes.user_prompt * 2)    # 5 prompts = max 10

  # Apply weights
  weights = {
    node_count:   0.15,
    cyclomatic:   0.35,
    branch_depth: 0.25,
    state_vars:   0.15,
    user_prompts: 0.10
  }

  weighted = (
    n_score  * weights.node_count
    + cc_score * weights.cyclomatic
    + d_score  * weights.branch_depth
    + s_score  * weights.state_vars
    + p_score  * weights.user_prompts
  )

  RETURN round(weighted, 1)
```

---

## Threshold Definitions

The weighted complexity score maps to four classification levels:

| Level | Score Range | Characteristics | Maintenance Implication |
|-------|------------|-----------------|------------------------|
| `simple` | 0.0 - 2.0 | Few nodes, linear flow, minimal branching | Easy to understand and modify |
| `moderate` | 2.1 - 4.5 | Multiple paths, some conditionals, manageable state | Standard maintenance effort |
| `complex` | 4.6 - 7.0 | Many branches, deep nesting, significant state management | Requires careful review |
| `very_complex` | 7.1 - 10.0 | Highly branched, deep nesting, extensive state, many prompts | Consider decomposing into subflows |

### Pseudocode

```pseudocode
function classify_complexity(weighted_score):
  IF weighted_score <= 2.0:
    RETURN "simple"
  ELIF weighted_score <= 4.5:
    RETURN "moderate"
  ELIF weighted_score <= 7.0:
    RETURN "complex"
  ELSE:
    RETURN "very_complex"
```

### Metric-Level Thresholds

Individual metrics also have standalone thresholds for quick assessment:

| Metric | Simple | Moderate | Complex | Very Complex |
|--------|--------|----------|---------|--------------|
| Node count | 1-5 | 6-15 | 16-25 | 26+ |
| Cyclomatic complexity | 1-3 | 4-8 | 9-15 | 16+ |
| Max branch depth | 0-1 | 2-3 | 4-5 | 6+ |
| State variables (declared) | 0-3 | 4-8 | 9-15 | 16+ |
| State variables (mutated) | 0-2 | 3-5 | 6-10 | 11+ |
| User prompts | 0-1 | 2-3 | 4-5 | 6+ |

### Usage in Reports

When reporting complexity, present both the overall classification and the individual
metric breakdown so users can identify which dimension drives the complexity:

```
Complexity: moderate (score: 3.8/10)
  - Node count: 12 (moderate)
  - Cyclomatic complexity: 6 (moderate)
  - Branch depth: 3 (moderate)
  - State variables: 5 declared, 3 mutated (moderate)
  - User prompts: 2 (moderate)
```

If any single metric is two levels above the overall classification, flag it as a
complexity hotspot:

```pseudocode
function find_hotspots(metrics, overall_level):
  hotspots = []
  level_order = ["simple", "moderate", "complex", "very_complex"]
  overall_idx = level_order.index(overall_level)

  FOR metric_name, metric_level IN individual_levels:
    metric_idx = level_order.index(metric_level)
    IF metric_idx >= overall_idx + 2:
      hotspots.append({
        metric: metric_name,
        level: metric_level,
        message: "{metric_name} is {metric_level} while overall is {overall_level}"
      })

  RETURN hotspots
```

---

## Related Documentation

- **Quality Indicators:** `patterns/quality-indicators.md`
- **SKILL.md Phase 2:** Parent skill, Step 2.4 (cyclomatic complexity)
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
