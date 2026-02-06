> **Used by:** `SKILL.md` Phase 2

# Cross-Skill Metrics

Algorithms for detecting shared patterns, duplicate nodes, and constructing dependency
graphs across all workflows in a plugin.

---

## Shared Pattern Detection

Identifies structural patterns (node signatures) that recur across multiple workflows.
Shared patterns are candidates for extraction into reusable subflows.

### Node Signature Construction

Each node is reduced to a structural signature string that captures its type, shape,
and complexity without binding to specific field values:

```pseudocode
function build_signature(node):
  SWITCH node.type:
    CASE "action":
      action_count = len(node.actions)
      action_types = sorted([a.type for a in node.actions])
      has_failure = "f" if node.on_failure is defined else ""
      return f"action:{action_count}:{','.join(action_types)}:s{has_failure}"

    CASE "conditional":
      cond_type = node.condition.type
      has_audit = "+audit" if hasattr(node, "audit") AND node.audit.enabled else ""
      return f"conditional:{cond_type}{has_audit}:t+f"

    CASE "user_prompt":
      option_count = len(node.on_response)
      has_multi = "+multi" if node.prompt.multiSelect else ""
      return f"user_prompt:{option_count}{has_multi}"

    CASE "reference":
      ref_type = "doc" if hasattr(node, "doc") else "workflow"
      return f"reference:{ref_type}"
```

**Signature examples:**
- `action:3:display,mutate_state,set_flag:sf` -- 3-action node with failure path
- `conditional:state_check:t+f` -- state check conditional
- `user_prompt:4` -- 4-option user prompt
- `reference:doc` -- document reference node

### Frequency Mapping

Build a map from signature to list of occurrences, then filter to signatures appearing
in 2+ distinct workflows:

```pseudocode
function detect_shared_patterns(workflows):
  signature_map = {}  # signature -> [{workflow, node_id}, ...]

  FOR workflow IN workflows:
    nodes = parse_nodes(workflow.path)
    FOR node_id, node IN nodes:
      sig = build_signature(node)
      IF sig NOT IN signature_map:
        signature_map[sig] = []
      signature_map[sig].append({
        workflow: workflow.name,
        node_id:  node_id
      })

  # Filter: shared means appearing in 2+ DIFFERENT workflows
  shared = {}
  FOR sig, occurrences IN signature_map:
    unique_workflows = set(o.workflow for o in occurrences)
    IF len(unique_workflows) >= 2:
      shared[sig] = {
        signature:  sig,
        count:      len(occurrences),
        workflows:  list(unique_workflows),
        instances:  occurrences
      }

  return shared
```

### Interpreting Shared Patterns

| Pattern Type | Extraction Candidate | Rationale |
|-------------|---------------------|-----------|
| `action:N:types:sf` in 3+ workflows | Strong | Identical multi-action sequences are prime subflow candidates |
| `conditional:type:t+f` in 2+ workflows | Medium | Guard clauses may be worth sharing if the condition is reusable |
| `user_prompt:N` in 2+ workflows | Weak | User prompts are typically context-specific |
| `reference:doc` in 2+ workflows | Informational | Shared references indicate documentation dependencies |

---

## Duplicate Node Identification

Detects nodes across workflows with structural similarity exceeding 80%. Unlike shared
pattern detection (exact signature match), this uses fuzzy comparison to catch near-duplicates.

### Structural Fingerprinting

Each node produces a fingerprint object with typed fields for comparison:

```pseudocode
function build_fingerprint(node):
  return {
    type:           node.type,
    action_count:   len(node.actions) if node.type == "action" else 0,
    action_types:   sorted([a.type for a in node.actions]) if node.type == "action" else [],
    condition_type: node.condition.type if node.type == "conditional" else null,
    option_count:   len(node.on_response) if node.type == "user_prompt" else 0,
    has_failure:    node.on_failure is defined if node.type == "action" else false,
    has_audit:      hasattr(node, "audit") AND node.audit.enabled if node.type == "conditional" else false,
    description_len: len(node.description) if hasattr(node, "description") else 0
  }
```

### Similarity Scoring

Compare two fingerprints field-by-field. Each field contributes a weighted match score:

```pseudocode
function compute_similarity(fp_a, fp_b):
  # Type must match for any similarity
  IF fp_a.type != fp_b.type:
    return 0.0

  score = 0.0
  max_score = 0.0

  # Type match (mandatory gate, not counted in score)

  # Action count similarity (weight: 0.25)
  IF fp_a.type == "action":
    max_score += 0.25
    IF fp_a.action_count == fp_b.action_count:
      score += 0.25
    ELIF abs(fp_a.action_count - fp_b.action_count) == 1:
      score += 0.15  # Off by one

  # Action type overlap (weight: 0.30)
  IF fp_a.type == "action" AND fp_a.action_count > 0:
    max_score += 0.30
    set_a = set(fp_a.action_types)
    set_b = set(fp_b.action_types)
    IF len(set_a | set_b) > 0:
      jaccard = len(set_a & set_b) / len(set_a | set_b)
      score += 0.30 * jaccard

  # Condition type match (weight: 0.30)
  IF fp_a.type == "conditional":
    max_score += 0.30
    IF fp_a.condition_type == fp_b.condition_type:
      score += 0.30

  # Option count match (weight: 0.25)
  IF fp_a.type == "user_prompt":
    max_score += 0.25
    IF fp_a.option_count == fp_b.option_count:
      score += 0.25
    ELIF abs(fp_a.option_count - fp_b.option_count) == 1:
      score += 0.15

  # Failure path match (weight: 0.15)
  IF fp_a.type == "action":
    max_score += 0.15
    IF fp_a.has_failure == fp_b.has_failure:
      score += 0.15

  # Audit match (weight: 0.10)
  IF fp_a.type == "conditional":
    max_score += 0.10
    IF fp_a.has_audit == fp_b.has_audit:
      score += 0.10

  # Normalize to 0.0-1.0
  IF max_score == 0:
    return 0.0
  return score / max_score
```

**Similarity thresholds:**

| Similarity | Classification | Action |
|-----------|---------------|--------|
| >= 0.95 | Near-identical | Strong extraction candidate |
| 0.80 - 0.94 | Very similar | Review for possible extraction |
| 0.60 - 0.79 | Somewhat similar | Note but do not flag |
| < 0.60 | Distinct | Ignore |

Only cross-workflow pairs with similarity >= 0.80 are reported as duplicates.

---

## Dependency Graph Construction

Build an adjacency list representation of skill-to-skill dependencies from reference
nodes and `invoke_skill` actions.

### Graph Structure

```pseudocode
# Adjacency list: source_skill -> [target_skills]
dependency_graph = {
  "skill-a": ["skill-b", "skill-c"],
  "skill-b": ["skill-c"],
  "skill-c": []
}
```

### Edge Detection

Two types of edges connect skills:

**Type 1: Reference nodes (subflow composition)**

A `reference` node in workflow A that points to a path containing workflow B's directory
creates a directed edge from A to B.

```pseudocode
function extract_reference_edges(workflow, nodes):
  edges = []
  FOR node_id, node IN nodes:
    IF node.type == "reference":
      target_path = node.doc if hasattr(node, "doc") else node.workflow
      target_skill = extract_skill_name(target_path)
      IF target_skill:
        edges.append({
          source: workflow.name,
          target: target_skill,
          type:   "subflow_reference",
          node:   node_id
        })
  return edges
```

**Type 2: Invoke_skill actions (horizontal delegation)**

An `invoke_skill` consequence in any action node creates a directed edge.

```pseudocode
function extract_invoke_edges(workflow, nodes):
  edges = []
  FOR node_id, node IN nodes:
    IF node.type == "action":
      FOR action IN node.actions:
        IF action.type == "invoke_skill":
          edges.append({
            source: workflow.name,
            target: action.skill,
            type:   "invoke_skill",
            node:   node_id
          })
  return edges
```

### Cycle Detection in Dependencies

After building the graph, check for circular dependencies using DFS coloring:

```pseudocode
function detect_dependency_cycles(graph):
  WHITE, GRAY, BLACK = 0, 1, 2
  color = {skill: WHITE for skill in graph}
  cycles = []

  function dfs(skill, path):
    color[skill] = GRAY
    path.append(skill)

    FOR dep IN graph.get(skill, []):
      IF color.get(dep) == GRAY:
        # Cycle detected
        cycle_start = path.index(dep)
        cycles.append(path[cycle_start:] + [dep])
      ELIF color.get(dep) == WHITE:
        dfs(dep, path)

    path.pop()
    color[skill] = BLACK

  FOR skill IN graph:
    IF color[skill] == WHITE:
      dfs(skill, [])

  return cycles
```

Circular dependencies between skills are reported as warnings since they may
indicate tight coupling that should be refactored.

---

## Related Documentation

- **Health Scoring Algorithm:** `patterns/health-scoring-algorithm.md`
- **Classification Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/patterns/classification-algorithm.md`
- **Graph Validation Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/patterns/graph-validation-algorithm.md`
