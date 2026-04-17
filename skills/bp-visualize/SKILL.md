---
name: bp-visualize
description: >
  This skill should be used when the user asks to "visualize workflow", "generate diagram",
  "show workflow flow", "mermaid diagram", "graph workflow", "render workflow",
  "see workflow structure", or needs to create visual representations of workflow.yaml files.
  Triggers on "visualize", "diagram", "mermaid", "show flow", "graph", "flowchart",
  "render workflow", "workflow diagram".
allowed-tools: Read, Glob, AskUserQuestion
---

# Visualize Workflow

Generate Mermaid diagrams from workflow.yaml files, supporting end-to-end flowcharts,
subflow diagrams, and state diagrams.

> **Diagram Element Mapping:** `patterns/diagram-element-mapping.md`
> **Mermaid Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/mermaid-generation.md`

---

## Overview

This skill generates Mermaid diagrams from workflow.yaml files:
- **End-to-end flowcharts** -- Complete workflow visualization
- **Subflow diagrams** -- Selected portions of the workflow
- **State diagrams** -- Alternative representation for state machines

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Purpose |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | JSON processing |
| `yq` | **Mandatory** | `command -v yq` | YAML processing |
| `gh` | Recommended | `command -v gh` | GitHub API access (private repos) |

If mandatory tools are missing, exit with error and installation guidance.

---

## Visualization Mappings

### Node Types to Mermaid Shapes

| Node Type | Mermaid Shape | Syntax |
|-----------|---------------|--------|
| action | Rectangle | `node[Action Name]` |
| conditional | Diamond | `node{Condition?}` |
| conditional (audit) | Diamond | `node{Validations?}` |
| user_prompt | Stadium | `node([User Prompt])` |
| ending (success) | Rounded | `node(Success)` |
| ending (error) | Rounded | `node(Error)` |

### Transitions to Edge Styles

| Transition | Style | Example |
|------------|-------|---------|
| on_success | Solid green | `A -->|success| B` |
| on_failure | Dashed red | `A -.->|failure| B` |
| branches.true | Solid | `A -->|true| B` |
| branches.false | Dashed | `A -.->|false| C` |
| on_response | Labeled | `A -->|option_id| B` |

---

## Phase 1: Mode Detection

Parse any flags provided by the user or calling skill to determine visualization mode upfront.

### Step 1.1: Parse Flags

Check for flags in the user's request or passed context:

| Flag | Effect | Example |
|------|--------|---------|
| `--format <type>` | Set diagram format | `--format flowchart`, `--format state`, `--format subflow` |
| `--output <path>` | Set file output path | `--output docs/workflow-diagram.md` |

Store parsed values:
```yaml
computed:
  mode:
    format: "flowchart"   # flowchart | state | subflow (null if not provided)
    output_path: null      # file path or null for display-only
```

### Step 1.2: Apply Mode or Prompt

- If `--format` provided: set `computed.mode.format` and skip the visualization mode prompt in Phase 3 (Step 3.3).
- If `--output` provided: set `computed.mode.output_path` and skip the file output prompt in Phase 5 (Step 5.2).
- If **no flags** provided: proceed normally -- the user will be prompted for format choice in Phase 3.

---

## Phase 2: Load Workflow

### Step 2.1: Determine Target Workflow

If user provided a path:
1. Validate the path exists
2. Read the workflow.yaml file
3. Store in `computed.workflow_content`

If no path provided:
1. Check if current directory has a workflow.yaml:
   - Glob for `**/workflow.yaml` in current directory
   - If found, ask user which one to visualize
2. If none found, **ask user** for the path:
   ```json
   {
     "questions": [{
       "question": "Which workflow would you like to visualize?",
       "header": "Target",
       "multiSelect": false,
       "options": [
         {"label": "Provide path", "description": "I'll give you the workflow.yaml path"},
         {"label": "Search current directory", "description": "Look for workflow.yaml files here"},
         {"label": "Use current skill", "description": "Visualize the skill I'm currently in"}
       ]
     }]
   }
   ```

### Step 2.2: Parse Workflow Structure

Extract from workflow.yaml:
- `name` -- Workflow identifier
- `start_node` -- Entry point
- `nodes` -- All workflow nodes with types and transitions
- `endings` -- Terminal states

Store in:
```yaml
computed:
  workflow_name: "extracted name"
  start_node: "check_arguments"
  nodes:
    - id: "node_id"
      type: "action|conditional|user_prompt|..."
      description: "Node description"
      transitions: {...}
  endings:
    - id: "success"
      type: "success|error"
```

---

## Phase 3: Analyze & Choose Mode

### Step 3.1: Detect Decision Nodes

Identify nodes that create branching:
- **conditional** nodes -- `branches.true` and `branches.false`
- **conditional (audit)** nodes -- Same as conditional but validates all conditions
- **user_prompt** nodes -- Multiple `on_response` handlers

Count and classify:
```yaml
computed:
  decision_nodes:
    - id: "check_arguments"
      type: "conditional"
      branch_count: 2
    - id: "show_main_menu"
      type: "user_prompt"
      branch_count: 4
```

### Step 3.2: Identify Subflow Boundaries

Trace workflow paths to detect natural segments:

1. **Trace from start**: Follow paths from start_node to endings
2. **Identify clusters**: Group nodes that form logical units
3. **Name subflows**: Use node descriptions or infer from purpose

Algorithm:
```pseudocode
For each decision node:
  1. Trace forward to next decision or ending
  2. Collect all nodes in this segment
  3. Name based on entry node description
  4. Count nodes in segment
```

Example detected subflows:
```yaml
computed:
  subflows:
    - name: "Intent Parsing Flow"
      entry: "check_arguments"
      nodes: ["check_arguments", "parse_intent", "check_clear_winner"]
      exit_to: ["execute_matched_intent", "show_disambiguation"]
    - name: "Menu Flow"
      entry: "show_main_menu"
      nodes: ["show_main_menu", "delegate_init", "delegate_discover"]
      exit_to: ["success", "error_delegation"]
```

### Step 3.3: Present Visualization Options

Ask user which visualization mode:

```json
{
  "questions": [{
    "question": "How would you like to visualize the workflow?",
    "header": "Mode",
    "multiSelect": false,
    "options": [
      {"label": "Full diagram (Recommended)", "description": "Complete end-to-end workflow visualization"},
      {"label": "Subflows", "description": "Choose specific portions to visualize"},
      {"label": "State diagram", "description": "Alternative stateDiagram representation"}
    ]
  }]
}
```

If **Subflows** selected, present detected subflows:

```json
{
  "questions": [{
    "question": "Which subflows would you like to visualize?",
    "header": "Subflows",
    "multiSelect": true,
    "options": [
      {"label": "Intent Parsing", "description": "check_arguments -> check_clear_winner (3 nodes)"},
      {"label": "Menu Flow", "description": "show_main_menu -> delegations (8 nodes)"},
      {"label": "Disambiguation", "description": "show_disambiguation -> delegations (5 nodes)"},
      {"label": "Error Handling", "description": "All error paths (2 nodes)"}
    ]
  }]
}
```

Store `computed.diagram_mode` ("flowchart" or "state"), `computed.selected_nodes`,
and `computed.orientation` ("TD" or "LR") based on selection. Use TD for deep
workflows (4+ decision nodes), LR for shallow workflows or subflow views.

---

## Phase 4: Generate Diagram

### Step 4.1: Build Node Definitions

For each node in the selected scope, generate Mermaid syntax:

```pseudocode
For each node:
  shape = get_shape(node.type)
  label = sanitize(node.description or node.id)
  output: "{node.id}{shape_open}{label}{shape_close}"
```

Shape mapping:
```
action         -> [Label]
conditional    -> {Label?}
user_prompt    -> ([Label])
ending.success -> (Success)
ending.error   -> (Error)
```

### Step 4.2: Build Edges

For each node, generate transition edges:

**Action nodes:**
```mermaid
{node_id} -->|success| {on_success}
{node_id} -.->|failure| {on_failure}
```

**Conditional nodes:**
```mermaid
{node_id} -->|true| {branches.true}
{node_id} -.->|false| {branches.false}
```

**User prompt nodes:**
```mermaid
{node_id} -->|{option_id}| {on_response.{option_id}.next_node}
```

Only emit edges whose targets are within `computed.selected_nodes` or ending IDs.

### Step 4.3: Apply Styling

Add class definitions for visual distinction:

```mermaid
classDef success fill:#90EE90,stroke:#228B22,color:#000
classDef error fill:#FFB6C1,stroke:#DC143C,color:#000
classDef conditional fill:#87CEEB,stroke:#4682B4,color:#000
classDef userPrompt fill:#DDA0DD,stroke:#9932CC,color:#000
```

Apply classes to nodes:
- Endings with `type: success` -- `:::success`
- Endings with `type: error` -- `:::error`
- Conditional nodes -- `:::conditional`
- User prompt nodes -- `:::userPrompt`

### Step 4.4: Assemble Complete Diagram

Combine into final output:

For **flowchart** mode: header (`flowchart TD|LR`), classDefs, start connector
(`start([Start]) --> {start_node}`), node definitions, edges.

For **state** mode: header (`stateDiagram-v2`), start transition (`[*] --> {start_node}`),
state transitions with colon-labeled edges, terminal transitions (`{success} --> [*]`).

Store assembled output in `computed.diagram_output`.

---

## Phase 5: Output

### Step 5.1: Display Diagram

Output the Mermaid diagram in a code block:

~~~markdown
```mermaid
flowchart TD
    classDef success fill:#90EE90,stroke:#228B22,color:#000
    classDef error fill:#FFB6C1,stroke:#DC143C,color:#000
    classDef conditional fill:#87CEEB,stroke:#4682B4,color:#000
    classDef userPrompt fill:#DDA0DD,stroke:#9932CC,color:#000

    start([Start]) --> check_arguments{has_arguments?}
    check_arguments -->|true| parse_intent[Parse Intent]
    check_arguments -->|false| show_menu([Show Menu])
    ...
```
~~~

### Step 5.2: Offer File Output

Ask if user wants to save:

```json
{
  "questions": [{
    "question": "Would you like to save this diagram to a file?",
    "header": "Save",
    "multiSelect": false,
    "options": [
      {"label": "Display only", "description": "Just show it here"},
      {"label": "Save to docs/", "description": "Write to docs/workflow-diagram.md"},
      {"label": "Save to README", "description": "Append to README.md"}
    ]
  }]
}
```

If saving:
1. Wrap diagram in appropriate markdown
2. Write to specified location
3. Confirm save path

---

## Output Examples

### End-to-End Flowchart

```mermaid
flowchart TD
    classDef success fill:#90EE90,stroke:#228B22,color:#000
    classDef error fill:#FFB6C1,stroke:#DC143C,color:#000
    classDef conditional fill:#87CEEB,stroke:#4682B4,color:#000
    classDef userPrompt fill:#DDA0DD,stroke:#9932CC,color:#000

    start([Start]) --> check_arguments{has_arguments?}:::conditional
    check_arguments -->|true| parse_intent[Parse Intent]
    check_arguments -->|false| show_menu([Show Menu]):::userPrompt
    parse_intent --> check_winner{clear_winner?}:::conditional
    check_winner -->|true| execute[Execute Intent]
    check_winner -->|false| disambiguate([Disambiguate]):::userPrompt
    execute --> success_end(Success):::success
    show_menu --> delegate[Delegate to Skill]
    delegate --> success_end
    delegate -.->|failure| error_end(Error):::error
```

### Subflow (Selected Nodes Only)

```mermaid
flowchart LR
    parse_intent[Parse Intent] --> check_winner{clear_winner?}:::conditional
    check_winner -->|true| execute[Execute Intent]
    check_winner -->|false| disambiguate([Disambiguate]):::userPrompt
```

### State Diagram (Alternative)

```mermaid
stateDiagram-v2
    [*] --> check_arguments
    check_arguments --> parse_intent: has arguments
    check_arguments --> show_main_menu: no arguments
    parse_intent --> check_clear_winner
    check_clear_winner --> execute_matched_intent: clear winner
    check_clear_winner --> show_disambiguation: ambiguous
    execute_matched_intent --> success
    show_main_menu --> delegate_init: init
    show_main_menu --> delegate_discover: discover
    delegate_init --> success
    delegate_discover --> success
    success --> [*]
```

---

## Reference Documentation

- **Diagram Element Mapping:** `patterns/diagram-element-mapping.md`
- **Mermaid Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/mermaid-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`

---

## Related Skills

- Skill assessment: `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- Workflow extraction: `${CLAUDE_PLUGIN_ROOT}/skills/bp-extract/SKILL.md`
- Skill building: `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
- Skill maintenance: `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/SKILL.md`
