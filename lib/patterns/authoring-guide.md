# Authoring Guide

How to build skills and workflow definitions for hiivmind-blueprint.

> **Related Patterns:**
> - Node Mapping: `patterns/node-mapping.md`
> - Prompt Modes: `patterns/prompt-modes.md`
> - Execution Guide: `patterns/execution-guide.md`
> - Skill Analysis: `patterns/skill-analysis.md`

---

# Part 1: Authoring Skills

A **skill** is a prose orchestrator (SKILL.md) that optionally delegates specific phases to one or more workflow definitions. Skills are the unit of invocation — users invoke skills, not workflows.

---

## 1. Skill Directory Layout

```
skills/my-skill/
├── SKILL.md                    # Prose orchestrator (always present)
├── workflows/                  # Optional: workflow definitions
│   ├── validate.yaml          # Self-contained workflow for one phase
│   └── transform.yaml         # Self-contained workflow for another phase
└── patterns/                   # Optional: supporting pattern files
    └── *.md
```

**Single-workflow skills** use `workflows/workflow.yaml` — not a bare `workflow.yaml` at the skill root. All workflow files live under `workflows/`.

---

## 2. SKILL.md Frontmatter

```yaml
---
name: my-skill
description: >
  What this skill does, with trigger keywords for intent matching...
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
inputs:
  - name: target_path
    type: string
    required: true
    description: Path to process
  - name: format
    type: string
    required: false
    description: Output format (yaml, json, markdown)
outputs:
  - name: result
    type: object
    description: Structured analysis result
  - name: files_created
    type: array
    description: List of file paths created
workflows:                          # Optional: declared workflow files
  - workflows/validate.yaml
  - workflows/transform.yaml
---
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier in kebab-case |
| `description` | Yes | Trigger description with keywords (max 1024 chars) |
| `allowed-tools` | Yes | Comma-separated tool list |
| `inputs` | Yes | Array of input parameter definitions |
| `outputs` | Yes | Array of output definitions |
| `workflows` | No | Array of workflow file paths relative to skill directory |

### Input/Output Definitions

Each input and output has:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Parameter name in snake_case |
| `type` | Yes | `string`, `number`, `boolean`, `object`, `array` |
| `required` | Inputs only | Whether the input must be provided |
| `description` | Yes | What this parameter represents |

---

## 3. SKILL.md Body Structure

The body of a SKILL.md is organized into **phases**. Each phase is either prose-driven (tool calls, analysis, file reads) or workflow-backed (delegates to a workflow YAML file).

```markdown
# My Skill

[Overview paragraph — what this skill does and when to use it]

## Execution

### Phase 1: Discover
[Prose instructions — tool calls, file reads, analysis]

### Phase 2: Validate
Execute `workflows/validate.yaml` following the execution guide.
[Pre/post workflow prose if needed]

### Phase 3: Transform
Execute `workflows/transform.yaml` following the execution guide.

### Phase 4: Report
[Prose instructions — display results, offer next steps]
```

Each phase is either **prose** or **workflow-backed**. The SKILL.md is always the authority on overall flow.

---

## 4. Designing Phases

### Prose Phases

Prose phases contain direct instructions for the LLM:
- Tool calls (Read, Write, Glob, Grep, Bash)
- Analysis and computation (pseudocode blocks)
- User interaction (AskUserQuestion with JSON examples)
- State management (`computed.*` references)
- Display and reporting

### Workflow-Backed Phases

Workflow-backed phases delegate to a self-contained workflow YAML:

```markdown
### Phase 2: Validate

Execute `workflows/validate.yaml` following the execution guide (v2.0):

1. Load type registry from `blueprint-types.md` (see [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md))
2. Read `workflows/validate.yaml`
3. Follow `.hiivmind/blueprint/execution-guide.md` (Initialize → Execute → Complete)

**Before workflow:** Ensure `computed.target_files` is populated from Phase 1.
**After workflow:** Check `computed.validation_results` for any failures.
```

### When to Extract a Workflow

Extract a phase into a workflow when it has:

| Signal | Why Workflow |
|--------|-------------|
| High conditional density (5+ branches) | Deterministic routing prevents LLM drift |
| Finite state machine (FSM) pattern | Nodes + transitions map naturally to FSM |
| Loops with explicit break conditions | Workflow graph enforces loop termination |
| Multiple user prompts with branching | Response handlers route deterministically |
| Validation gates (multiple checks) | Audit mode evaluates ALL conditions |

Keep phases as prose when they involve:
- Open-ended analysis or reasoning
- Dynamic tool selection based on context
- Creative content generation
- Simple linear sequences of tool calls

---

## 5. Multi-Workflow Composition

A skill can orchestrate multiple workflows via prose:

```markdown
## Execution

### Phase 1: Gather (prose)
Read files, analyze structure, build computed state.

### Phase 2: Validate (workflow)
Execute `workflows/validate.yaml`

### Phase 3: Transform (workflow)
Execute `workflows/transform.yaml`

### Phase 4: Report (prose)
Display results from computed.* and offer next steps.
```

### State Handoff Between Phases

State flows between prose and workflow phases through `computed.*`:

- **Prose → Workflow:** Set `computed.*` values in prose, the workflow reads them via `${computed.*}` interpolation in its `initial_state` or node parameters.
- **Workflow → Prose:** Workflow consequences use `store_as` to write to `computed.*`. After the workflow completes, prose phases read these values.
- **Workflow → Workflow:** The same mechanism — first workflow writes to `computed.*`, second workflow reads from it.

### When to Split vs. One Large Workflow

| One Workflow | Multiple Workflows |
|-------------|-------------------|
| All phases are tightly coupled | Phases are logically independent |
| State flows linearly | State handoff has clear boundaries |
| < 15 nodes total | > 15 nodes if kept together |
| Single concern | Multiple distinct concerns |

---

## 6. Workflow Coverage Classification

Skills are classified by how much of their execution is workflow-backed:

| Coverage | Meaning | Example |
|----------|---------|---------|
| `none` | Pure prose skill, no workflow files | Analysis, reporting skills |
| `partial` | Mix of prose and workflow phases | Most hybrid skills |
| `full` | All substantive phases are workflow-backed | Fully formalized skills |

Coverage is not a quality judgment — pure prose skills may be entirely appropriate for their use case.

---

# Part 2: Authoring Workflows

Workflows are self-contained YAML definitions that live in a skill's `workflows/` directory. They define a graph of nodes that execute deterministically.

---

## 7. Workflow YAML Structure

A complete workflow contains these top-level fields:

```yaml
name: "validate"
version: "1.0.0"
description: >
  What this workflow does in 1-2 sentences.

entry_preconditions:      # Optional: conditions checked before execution starts
  - type: tool_check
    tool: git
    capability: available

initial_state:            # Starting state values
  phase: "start"
  flags: {}
  computed: {}
  output:
    level: "normal"
    log_enabled: true
  prompts:
    interface: "auto"

start_node: first_step    # Entry point into the node graph

nodes:                    # Map of node_id → node definition
  first_step:
    type: action
    actions:
      - type: display
        format: text
        content: "Starting workflow..."
    on_success: done

endings:                  # Map of ending_id → ending definition
  done:
    type: success
    message: "Workflow completed"
```

---

## 8. Type Definitions (v7.0.0)

As of v7.0.0, `hiivmind-blueprint-lib` ships a single consolidated file:

```
blueprint-types.md
```

See the complete type catalog at:
[https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md)

The catalog covers all **nodes**, **consequences**, and **preconditions** in a single Markdown document. The LLM reads this file directly — no `.hiivmind/blueprint/definitions.yaml` is required.

> **Note:** The `.hiivmind/blueprint/definitions.yaml` file is no longer needed. If you have one from a pre-v7.0.0 setup, it can be deleted — the skill loads `blueprint-types.md` automatically from the catalog.

### Which Types to Include

When authoring workflows, reference types from the catalog. When setting up your SKILL.md, instruct the LLM to load the catalog from `blueprint-types.md`. Scan your workflow YAML for:
- All `type:` values in action node `actions` arrays → consequence types needed
- All `type:` values in conditional node `condition` blocks → precondition types needed
- Recurse into `composite` conditions for nested precondition types
- All `type:` values used in `entry_preconditions`

---

## 9. Type Catalog Quick Reference

As of v7.0.0, the complete type catalog lives in a single file in `hiivmind-blueprint-lib`:

**[blueprint-types.md](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md)**

The catalog includes:
- **22 consequence types** — state mutations, control flow, display, intent detection, logging, and extensions
- **9 precondition types** — state checks, path checks, tool checks, network, git, and web
- **3 node types** — `action`, `conditional`, `user_prompt`
- **1 terminal node type** — `ending` (new in v8; see below)

Refer to `blueprint-types.md` for the authoritative list with full parameter definitions and pseudocode effects.

### Primitive Node Types

| Type | Purpose | Transition Slots |
|------|---------|-----------------|
| `action` | Execute a sequence of consequences | `on_success`, `on_failure` |
| `conditional` | Evaluate a precondition and branch | `branches.on_true`, `branches.on_false` |
| `user_prompt` | Present a question; route by response | `on_response.{handler_id}.next_node` |
| `ending` | Terminal state. Emit outcome; run consequences; apply behavior. | None — schema forbids `on_success`/`on_failure`/`on_true`/`on_false`/`on_unknown`/`on_response`. |

The `ending` node is the canonical termination point for a workflow run. Every path through the graph must reach an ending. Endings are defined under a top-level `endings:` map (not inside `nodes:`), with an `outcome` field (`success | failure | error | cancelled | indeterminate`), an optional `message`, optional `consequences[]`, and an optional `behavior` block. See Section 10 for full ending examples.

---

## 10. Building the Node Graph

### Node Ordering

1. Start node first
2. Happy path in execution order
3. Branch nodes after branching point
4. Error handler nodes at end

### Transition Connections

| Node Type | Connect Via |
|-----------|-------------|
| `action` | `on_success`, `on_failure` |
| `conditional` | `branches.on_true`, `branches.on_false` |
| `conditional` (audit) | Same + `audit.output` for collected results |
| `user_prompt` | `on_response.{handler_id}.next_node` |

### Endings

Every path through the graph must terminate at an ending. Endings define an **outcome type** and a **behavior**.

#### Outcome Types

| Type | Meaning |
|------|---------|
| `success` | Workflow completed successfully |
| `failure` | Workflow failed due to a known condition |
| `error` | Workflow failed due to an unexpected error |
| `cancelled` | User cancelled the workflow |
| `indeterminate` | Outcome is ambiguous or uncertain (maps to 3VL Unknown) |

#### Behaviors

Behavior controls what happens when an ending is reached. When `behavior:` is omitted, the ending defaults to **display** (show message/summary) — all existing endings work unchanged.

| Behavior | What It Does |
|----------|-------------|
| *(default)* display | Show message and summary to user |
| `delegate` | Hand off to another skill with context |
| `restart` | Loop back to a node in the workflow |
| `silent` | Complete with no output |

#### Consequences on Endings

Endings can execute consequences before completing. Consequence failures are logged but never prevent completion — endings are the termination point.

```yaml
endings:
  error_with_logging:
    type: error
    consequences:
      - type: log_entry
        level: "error"
        message: "workflow_error"
        context: { error: "${computed.last_error}" }
    message: "Operation failed"
    recovery: "Check logs for details"
```

#### Examples

```yaml
endings:
  # Display (default behavior — no behavior block needed)
  success:
    type: success
    message: "Completed: ${computed.summary}"
    summary:
      items_processed: "${computed.count}"

  # Delegate to another skill
  delegate_to_skill:
    type: success
    behavior:
      type: delegate
      skill: "corpus-init"
      args: "${computed.corpus_name}"
      context:
        source_type: "${computed.source_type}"

  # Restart (loop back to menu)
  back_to_menu:
    type: success
    message: "Returning to menu..."
    behavior:
      type: restart
      target_node: show_menu
      max_restarts: 10

  # Silent (gateway delegation — no output)
  delegated:
    type: success
    behavior:
      type: silent

  # Error with recovery guidance
  error_config:
    type: error
    category: configuration
    message: "Configuration file missing"
    recovery: "Run /init first"

  # Indeterminate outcome
  ambiguous_result:
    type: indeterminate
    message: "Analysis could not determine a definitive result"
    summary:
      confidence: "${computed.confidence_score}"

  # Cancelled
  cancelled:
    type: cancelled
    message: "Operation cancelled by user"
```

---

## 11. Graph Validation

Before finalizing a workflow, verify:

### Reachability

All nodes must be reachable from `start_node`:
1. Initialize visited = {start_node}
2. BFS through all transition targets
3. Orphan nodes = all_nodes - visited (should be empty)

### Path to Ending

All nodes must have a path to some ending. Reverse the graph and verify all nodes can reach the ending set.

### Transition Targets

Every `on_success`, `on_failure`, `branches.*`, and `on_response.*.next_node` must reference a valid node or ending.

| Error | Fix |
|-------|-----|
| Orphan node detected | Add transition to reach it or remove |
| Dead end node | Add on_success/on_failure |
| Invalid target "X" | Add X to nodes/endings or fix reference |

---

## 12. State and Interpolation

### `${...}` Syntax

Use `${...}` to reference state values in workflow YAML:

| Pattern | Example | Resolves From |
|---------|---------|--------------|
| `${field}` | `${source_type}` | Top-level state |
| `${computed.X}` | `${computed.repo_url}` | state.computed |
| `${flags.X}` | `${flags.config_found}` | state.flags |
| `${user_responses.node.field}` | `${user_responses.ask_type.handler_id}` | state.user_responses |
| `${array[N]}` | `${computed.sources[0].id}` | Array index |
| `${array[-1]}` | `${history[-1].node}` | Negative index (last) |

### `store_as`

Consequence results can be stored in state:

```yaml
- type: local_file_ops
  operation: read
  path: "config.yaml"
  store_as: config    # Result stored at state.computed.config
```

---

## 13. v8 Extensions: MCP Integration and Payload Types

### `mcp_tool_call` — invoke an external MCP tool

New in blueprint-lib v8 (BL1). Invokes a tool on a data-MCP server declared in the workflow's `data_mcps:` front-matter.

**Signature:**

```
mcp_tool_call(tool, params, params_type?, store_as?)
```

- `tool` — `"<alias>.<tool_name>"` where `<alias>` is a key declared in `data_mcps:`.
- `params` — map of literals + `${}` state interpolation.
- `params_type` — optional reference to a payload type declared in the workflow's `payload_types:` block (format: `name@version`).
- `store_as` — optional state field to receive the tool result.

**Minimal example:**

```yaml
data_mcps:
  eightball: "eightball-tools@^1"

nodes:
  shake:
    type: action
    consequences:
      - type: mcp_tool_call
        tool: eightball.shake
        params:
          question: "${computed.question}"
        store_as: computed.answer
    on_success: done
```

The catalog describes the *effect*. Topology (runtime-invokes vs LLM-invokes) is an execution concern — see `execution-guide.md`.

---

### Payload Types (`payload_types:` block)

New in v8 (BL2). Workflows declare data shapes at the top in a `payload_types:` block. Consequences reference shapes via `params_type: <name>@<version>`. No central catalog; shapes live per-workflow.

**Key pattern:** `^[a-z_][a-z0-9_]*@\d+$` (e.g. `shake_params@1`).

**Field descriptor forms:**

- **Scalar string:** `"string"`, `"integer (min=1, max=100)"`, `"array<string>"`, `"enum{a,b,c}"`.
- **Structured:** `{type: string, min_length: 1, optional: true}`.

**Example:**

```yaml
payload_types:
  shake_params@1:
    question: string (min_length=1)
    context:  string (optional)
```

Blueprint-lib's loader validates that each `params_type` reference resolves; it does NOT validate the shape of `params` itself — that is a runtime concern.

---

### Workflow-level declarations (v8)

Three new optional front-matter fields in v8:

- **`trust_mode`** (BL3) — enum `{stateless, gated}`, default `stateless`. Declarative metadata for runtimes; blueprint-lib validates the enum only.
- **`data_mcps`** (BL4) — map of `<alias>` → `"<name>@<semver-range>"`. Declares which MCP servers the workflow depends on; aliases are used as prefixes in `mcp_tool_call.tool` references.
- **`payload_types`** (BL2) — see Payload Types section above.

**Example front-matter:**

```yaml
name: my-workflow
version: "1.0.0"
trust_mode: stateless
data_mcps:
  docs: "docs-mcp@^2"
payload_types:
  query@1: { text: "string (min_length=1)" }
```

---

## 14. Entry Preconditions

Check requirements before the workflow starts:

```yaml
entry_preconditions:
  - type: tool_check
    tool: git
    capability: available
  - type: path_check
    path: "data/config.yaml"
    check: is_file
```

If any entry precondition fails, the workflow stops with an error before executing any nodes.

---

## 15. User Prompts and Conditional Audit Mode

### User Prompt Nodes

```yaml
ask_source:
  type: user_prompt
  prompt:
    question: "What type of source?"
    header: "Source"
    options:
      - id: git
        label: "Git repository"
        description: "Clone a repository"
      - id: local
        label: "Local files"
        description: "Files on your machine"
  on_response:
    git:
      consequence:
        - type: mutate_state
          operation: set
          field: source_type
          value: git
      next_node: configure_git
    local:
      next_node: configure_local
```

### Dynamic Options From State

When options come from a computed array:

```yaml
show_candidates:
  type: user_prompt
  prompt:
    question: "Which did you mean?"
    header: "Clarify"
    options_from_state: computed.intent_matches.top_candidates
    options:
      id: rule.name
      label: rule.name
      description: rule.description
  on_response:
    selected:
      next_node: execute_matched
```

### Audit Mode (Validation)

For collecting all validation errors instead of short-circuiting:

```yaml
validate_env:
  type: conditional
  condition:
    type: composite
    operator: all
    conditions:
      - type: tool_check
        tool: git
        capability: available
      - type: path_check
        path: "config.yaml"
        check: is_file
  audit:
    enabled: true
    output: computed.validation_errors
    messages:
      tool_check: "Git is required"
      path_check: "Config file missing"
  branches:
    on_true: proceed
    on_false: show_errors
```

---

## 16. Output Configuration

Configure display verbosity and logging:

```yaml
initial_state:
  output:
    level: "normal"       # silent|quiet|normal|verbose|debug
    log_enabled: true
  prompts:
    interface: "auto"     # auto-detect execution environment
```

Levels control what's displayed:
- **silent:** User prompts and final result only
- **quiet:** Adds warnings
- **normal:** Adds node transitions (default)
- **verbose:** Adds condition evaluations, branch decisions
- **debug:** Adds full state dumps

---

## Appendix: Migration Guide

### Migrating from Remote Definitions (v5.0 → v6.0)

If migrating from the old `definitions.source` model:

**Before (v5.0 and earlier):**

```yaml
# In workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v5.0.0

# Types fetched from GitHub at runtime
```

**After (v6.0):**

```yaml
# workflow.yaml — no definitions block needed

# Types loaded from local definitions at runtime
```

Steps:
1. Remove the `definitions:` block from all workflow YAML files
2. Update SKILL.md templates to load from the local definitions file

### Migrating from Local Definitions File (v6.0 → v7.0.0)

If migrating from the v6.0 local definitions model:

**Before (v6.0):**
- Type definitions stored in `.hiivmind/blueprint/definitions.yaml` per repo
- SKILL.md instructed the LLM to read that file first

**After (v7.0.0):**
- `.hiivmind/blueprint/definitions.yaml` is **no longer required**
- The skill loads the type catalog from `blueprint-types.md` in `hiivmind-blueprint-lib` automatically
- See [blueprint-types.md](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md) for the complete catalog

Steps:
1. Delete `.hiivmind/blueprint/definitions.yaml` from your repo (if present)
2. Update your SKILL.md templates to reference `blueprint-types.md` instead of `definitions.yaml`

---

## Related Documentation

- **Skill Analysis:** `patterns/skill-analysis.md`
- **Execution Guide:** `patterns/execution-guide.md`
- **Type Catalog:** [blueprint-types.md](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md) in `hiivmind-blueprint-lib`
- **Prompts Config:** `references/prompts-config-examples.md`
