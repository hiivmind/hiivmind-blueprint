# Graph Validation Algorithm

Validates the directed graph structure of a workflow.yaml by checking reachability,
cycles, dead ends, and ending paths.

## BFS Reachability from Start Node

Forward BFS from `start_node` through all transition targets. Nodes not visited are
orphans — unreachable from the workflow entry point.

```pseudocode
function bfs_reachability(start_node, nodes):
    visited = {start_node}
    queue = [start_node]
    while queue is not empty:
        current = queue.pop_front()
        if current not in nodes: continue
        for target in get_all_transition_targets(current, nodes[current]):
            if target starts with "${": continue  # Dynamic target, skip
            if target not in visited:
                visited.add(target)
                if target in nodes: queue.append(target)
    orphans = set(nodes.keys()) - visited
    return orphans
```

Each orphan is reported as an **error** — it cannot be reached during execution.

## Ending Reachability (Reverse BFS)

Build a reverse adjacency list (target -> set of predecessors), then BFS backward from
all ending IDs. Nodes not reached from any ending are "stranded" — they exist on a path
that never terminates.

```pseudocode
function reverse_reachability(nodes, endings):
    reverse_graph = {}
    for node_id, node in nodes:
        for target in get_all_transition_targets(node_id, node):
            if target starts with "${": continue
            if target not in reverse_graph:
                reverse_graph[target] = set()
            reverse_graph[target].add(node_id)

    # BFS from all ending IDs through the reverse graph
    can_reach_ending = set(endings.keys())
    queue = list(endings.keys())
    while queue:
        current = queue.pop(0)
        if current in reverse_graph:
            for predecessor in reverse_graph[current]:
                if predecessor not in can_reach_ending:
                    can_reach_ending.add(predecessor)
                    queue.append(predecessor)

    stranded = set(nodes.keys()) - can_reach_ending
    return stranded
```

Each stranded node is reported as a **warning** — it may indicate an incomplete path.

## Cycle Detection (DFS 3-Color)

Uses DFS with 3-color marking to detect back edges indicating cycles:

- **WHITE (0)**: unvisited
- **GRAY (1)**: currently in the DFS stack (being explored)
- **BLACK (2)**: fully explored

A back edge to a GRAY node indicates a cycle.

```pseudocode
function detect_cycles(nodes, start_node):
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {node_id: WHITE for node_id in nodes}
    cycles = []

    function dfs(node_id, path):
        color[node_id] = GRAY
        path.append(node_id)

        if node_id in nodes:
            for target in get_all_transition_targets(node_id, nodes[node_id]):
                if target starts with "${": continue
                if target in nodes:
                    if color[target] == GRAY:
                        cycle_start = path.index(target)
                        cycles.append(path[cycle_start:])
                    elif color[target] == WHITE:
                        dfs(target, path)

        color[node_id] = BLACK
        path.pop()

    for node_id in nodes:
        if color[node_id] == WHITE:
            dfs(node_id, [])

    return cycles
```

### Break Condition Analysis

For each detected cycle, check whether it has a break condition:

- A cycle has a **break** if any node in the cycle has a transition target outside the cycle
- `user_prompt` nodes and `conditional` nodes are typical break points
- Cycle **without** break -> **error** (infinite loop)
- Cycle **with** break -> **info** (bounded loop, intentional retry pattern)

## Dead-End Detection

Nodes with zero valid outgoing transitions after filtering nulls and empty strings:

```pseudocode
function find_dead_ends(nodes):
    dead_ends = []
    for node_id, node in nodes:
        targets = get_all_transition_targets(node_id, node)
        valid = [t for t in targets if t is not null and t != ""]
        if len(valid) == 0:
            dead_ends.append(node_id)
    return dead_ends
```

Each dead-end is reported as an **error** — the workflow will stall at this node.

## Transition Target Extraction

Helper function used by all graph algorithms:

```pseudocode
function get_all_transition_targets(node_id, node):
    targets = []
    if node.type == "action":
        targets = [node.on_success, node.on_failure]
    elif node.type == "conditional":
        targets = [node.branches.on_true, node.branches.on_false]
    elif node.type == "user_prompt":
        targets = [handler.next_node for handler in node.on_response.values()]
    return [t for t in targets if t is not null]
```
