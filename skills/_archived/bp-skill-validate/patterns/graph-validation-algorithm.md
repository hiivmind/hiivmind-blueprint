> **Used by:** `SKILL.md` Phase 4

# Graph Validation Algorithm

Algorithms for validating the workflow graph: reachability, ending paths, cycle detection, and dead-end analysis.

---

## Overview

A workflow.yaml defines a directed graph where:
- **Nodes** are vertices
- **Transitions** (on_success, on_failure, branches, on_response, next_node) are edges
- **start_node** is the entry vertex
- **Endings** are terminal vertices (sinks)

Four graph properties must hold:

| Property | Meaning | Severity if violated |
|----------|---------|---------------------|
| Forward reachability | Every node reachable from start_node | Error (orphan nodes) |
| Ending reachability | Every node has a path to some ending | Warning (stranded nodes) |
| Bounded cycles | Every cycle has a break condition | Error (infinite loops) |
| No dead ends | Every node has at least one outgoing edge | Error (execution halts) |

---

## Transition Extraction

Before running any graph algorithm, extract all transition targets from a node.

```
function get_all_transition_targets(node_id, node):
    targets = []

    switch node.type:
        case "action":
            if "on_success" in node: targets.append(node.on_success)
            if "on_failure" in node: targets.append(node.on_failure)

        case "conditional":
            if "branches" in node:
                if "on_true" in node.branches: targets.append(node.branches.on_true)
                if "on_false" in node.branches: targets.append(node.branches.on_false)

        case "user_prompt":
            if "on_response" in node:
                for handler_id, handler in node.on_response:
                    if "next_node" in handler:
                        targets.append(handler.next_node)

        case "reference":
            if "next_node" in node: targets.append(node.next_node)

    return targets
```

**Dynamic targets:** Targets that contain `${...}` interpolation cannot be validated statically. Flag them as info-level observations and exclude from graph traversal.

```
function partition_targets(targets):
    static_targets = [t for t in targets if not t.startswith("${")]
    dynamic_targets = [t for t in targets if t.startswith("${")]
    return static_targets, dynamic_targets
```

---

## Algorithm 1: Forward Reachability (BFS)

Determine which nodes are reachable from `start_node`. Nodes not in the reachable set are orphans.

```
function bfs_forward(start_node, nodes, endings):
    """
    Returns: set of orphan node IDs

    Time complexity:  O(V + E) where V = |nodes|, E = total transitions
    Space complexity: O(V)
    """
    visited = set()
    queue = deque([start_node])

    while queue:
        current = queue.popleft()

        if current in visited:
            continue
        visited.add(current)

        // Only expand nodes (not endings)
        if current not in nodes:
            continue

        node = nodes[current]
        targets = get_all_transition_targets(current, node)
        static_targets, dynamic_targets = partition_targets(targets)

        for target in static_targets:
            if target not in visited:
                queue.append(target)

        // Log dynamic targets as info
        for target in dynamic_targets:
            report_info(
                node: current,
                message: "Dynamic target '${target}' cannot be validated statically"
            )

    // Orphans = declared nodes minus visited nodes
    all_node_ids = set(nodes.keys())
    orphans = all_node_ids - visited

    for orphan in orphans:
        report_error(
            node: orphan,
            message: "Orphan node '${orphan}' is not reachable from start_node '${start_node}'"
        )

    return orphans
```

---

## Algorithm 2: Ending Reachability (Reverse BFS)

Verify every node can eventually reach at least one ending. Build a reverse adjacency list, then BFS backward from all ending IDs.

```
function bfs_reverse(nodes, endings):
    """
    Returns: set of stranded node IDs (cannot reach any ending)

    Time complexity:  O(V + E)
    Space complexity: O(V + E) for reverse graph
    """
    // Phase 1: Build reverse adjacency list
    //   reverse_adj[target] = set of nodes that have a transition TO target
    reverse_adj = defaultdict(set)

    for node_id, node in nodes.items():
        targets = get_all_transition_targets(node_id, node)
        static_targets, _ = partition_targets(targets)

        for target in static_targets:
            reverse_adj[target].add(node_id)

    // Phase 2: BFS backward from all endings
    can_reach_ending = set()
    queue = deque(endings.keys())

    while queue:
        current = queue.popleft()

        if current in can_reach_ending:
            continue
        can_reach_ending.add(current)

        // Walk backward through predecessors
        for predecessor in reverse_adj.get(current, set()):
            if predecessor not in can_reach_ending:
                queue.append(predecessor)

    // Phase 3: Identify stranded nodes
    all_node_ids = set(nodes.keys())
    stranded = all_node_ids - can_reach_ending

    for node_id in stranded:
        report_warning(
            node: node_id,
            message: "Node '${node_id}' has no static path to any ending. "
                     "May be reachable via dynamic targets or may be a genuine issue."
        )

    return stranded
```

**Note on dynamic targets:** A node whose only path to an ending goes through a dynamic target (`${computed.dynamic_target}`) will appear as stranded. This is reported as a warning, not an error, because the dynamic target may resolve to a valid ending path at runtime.

---

## Algorithm 3: Cycle Detection (DFS with Coloring)

Detect cycles and check whether each cycle has a break condition.

```
function detect_cycles(start_node, nodes):
    """
    Returns: list of cycle descriptions

    Uses 3-color DFS:
      WHITE (0) = unvisited
      GRAY  (1) = in current DFS path (on recursion stack)
      BLACK (2) = fully processed

    Time complexity:  O(V + E)
    Space complexity: O(V) for color + parent arrays
    """
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {nid: WHITE for nid in nodes}
    parent = {}
    cycles = []

    function dfs(node_id):
        color[node_id] = GRAY

        targets = get_all_transition_targets(node_id, nodes[node_id])
        static_targets, _ = partition_targets(targets)

        for target in static_targets:
            if target not in nodes:
                continue  // target is an ending, not a cycle risk

            if color[target] == GRAY:
                // Back edge found - reconstruct cycle
                cycle = reconstruct_cycle(node_id, target, parent)
                cycles.append(cycle)

            elif color[target] == WHITE:
                parent[target] = node_id
                dfs(target)

        color[node_id] = BLACK

    // Start DFS from start_node
    if start_node in nodes:
        dfs(start_node)

    // Also check any remaining unvisited nodes (in case of disconnected subgraphs)
    for node_id in nodes:
        if color[node_id] == WHITE:
            dfs(node_id)

    return cycles


function reconstruct_cycle(from_node, to_node, parent):
    """
    Reconstruct the cycle path from to_node back to to_node
    via the DFS parent chain.
    """
    path = [from_node]
    current = from_node
    while current != to_node:
        current = parent[current]
        path.append(current)
    path.reverse()
    return path
```

### Break Condition Analysis

A cycle is considered "safe" if it contains at least one node that can route execution out of the cycle:

```
function has_break_condition(cycle, nodes):
    """
    A cycle has a break condition if at least one node in the cycle
    has a transition target OUTSIDE the cycle.

    Break conditions typically come from:
    - user_prompt: user can choose an option that exits the cycle
    - conditional: one branch exits the cycle
    """
    cycle_set = set(cycle)

    for node_id in cycle:
        node = nodes[node_id]
        targets = get_all_transition_targets(node_id, node)
        static_targets, dynamic_targets = partition_targets(targets)

        // Dynamic targets are potential break conditions
        if len(dynamic_targets) > 0:
            return true  // dynamic target could exit the cycle

        // Check if any static target exits the cycle
        for target in static_targets:
            if target not in cycle_set:
                return true  // this transition exits the cycle

    return false


function classify_cycles(cycles, nodes):
    for cycle in cycles:
        if has_break_condition(cycle, nodes):
            report_info(
                message: "Cycle detected: ${cycle}. Has break condition (can exit)."
            )
        else:
            report_error(
                message: "Infinite cycle detected: ${cycle}. "
                         "No node in the cycle has a transition outside it. "
                         "Add a conditional or user_prompt with an exit path."
            )
```

---

## Algorithm 4: Dead-End Detection

A dead-end node has no outgoing transitions. This is distinct from schema validation (which checks field presence) because a node could have fields present but with empty or null values.

```
function detect_dead_ends(nodes):
    """
    Returns: list of dead-end node IDs

    Time complexity: O(V) where V = |nodes|
    """
    dead_ends = []

    for node_id, node in nodes.items():
        targets = get_all_transition_targets(node_id, node)

        // Filter out null/empty targets
        valid_targets = [t for t in targets if t is not None and t != ""]

        if len(valid_targets) == 0:
            report_error(
                node: node_id,
                message: "Dead-end node '${node_id}' (type: ${node.type}) has no "
                         "valid outgoing transitions. Execution would halt here."
            )
            dead_ends.append(node_id)

    return dead_ends
```

---

## Complexity Summary

| Algorithm | Time | Space | Purpose |
|-----------|------|-------|---------|
| Forward BFS | O(V + E) | O(V) | Orphan detection |
| Reverse BFS | O(V + E) | O(V + E) | Ending reachability |
| Cycle DFS | O(V + E) | O(V) | Cycle detection |
| Dead-end scan | O(V) | O(1) | Dead-end detection |
| **Total** | **O(V + E)** | **O(V + E)** | All graph checks |

Where V = number of nodes, E = total number of transitions across all nodes.

For typical workflows: V < 50, E < 100. All algorithms complete in negligible time.

---

## Edge Cases

| Scenario | Handling |
|----------|----------|
| Single node workflow | Valid if node transitions to an ending |
| All dynamic targets | No static graph to validate; report info that validation is limited |
| Self-loop (node targets itself) | Detected as cycle; check for break condition |
| Multiple start candidates | Only `start_node` is the entry; other nodes may be orphans |
| Ending referenced by no node | Not an error (endings are declared, not required to be reached) |

---

## Related Documentation

- **Workflow Generation (graph section):** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Node Features (transition types):** `${CLAUDE_PLUGIN_ROOT}/references/node-features.md`
