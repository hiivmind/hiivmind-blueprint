# Abstract Workflow Executor with Type Loader

## Context

We've externalized type definitions to `hiivmind/hiivmind-blueprint-lib` (43 consequences, 27 preconditions). The workflow schema v2.1 supports external type references via `definitions` block.

**Current state:** No executor implementation exists. Execution is "LLM-native" - prose instructions embedded in each SKILL.md that the LLM interprets.

**Goal:** Design and document an abstract workflow engine that:
1. Loads type definitions from external sourcesC
2. Executes ANY workflow without domain-specific code
3. Supports composition (workflows calling workflows)
4. Is extensible via new types, not engine modifications

---

## Architecture Design

### Core Principle: LLM-Native Execution

The workflow engine is NOT compiled code. It's a **pattern document** that the LLM interprets. This is intentional:
- Type definitions fully specify behavior via pseudocode effects
- New types require only definition files, not engine changes
- The LLM naturally handles interpolation, error handling, tool calls

### Key Components

```
┌─────────────────────────────────────────────────────────────┐
│                      SKILL.md (Thin Loader)                 │
│  References engine.md, loads workflow.yaml                  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   lib/workflow/engine.md                    │
│  Abstract execution pattern (Phase 1-2-3 model)             │
│  - Type resolution protocol                                 │
│  - Node execution semantics                                 │
│  - State management                                         │
│  - Consequence dispatch                                     │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        TypeLoader      Dispatcher       StateManager
        (resolve)       (execute)        (interpolate)
```

---

## Implementation Plan

### Phase 1: Create `lib/workflow/engine.md`

**File:** `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/workflow/engine.md`

A comprehensive pattern document that describes:

#### 1.1 Type Loader Protocol

```markdown
## Type Loading

### Resolution Order
1. Check workflow.definitions.source
2. If URL → fetch bundle.yaml (cache in memory)
3. If local → read from path
4. If missing → use embedded lib/types/

### TypeRegistry
- Load consequence definitions into registry
- Load precondition definitions into registry
- Validate all types used in workflow exist
```

#### 1.2 Execution Loop

```markdown
## Execution Model

### Phase 1: Initialization
1. Load workflow.yaml
2. Load type definitions (per definitions block)
3. Validate: schema, type existence, graph connectivity
4. Evaluate entry_preconditions (all must pass)
5. Initialize state from workflow.initial_state

### Phase 2: Main Loop
REPEAT:
  node = nodes[current_node]
  IF current_node IN endings: GOTO Phase 3
  outcome = execute_node(node)
  history.append({node, outcome, timestamp})
  current_node = outcome.next_node
UNTIL ending

### Phase 3: Completion
Display ending message, summary, or recovery suggestion
```

#### 1.3 Node Execution Patterns

```markdown
## Node Types

### action
1. For each consequence in actions:
   - Resolve type definition
   - Check payload.requires
   - Execute payload.effect (may involve tool calls)
   - If failure: stop, route to on_failure
2. Route to on_success

### conditional
1. Evaluate precondition
2. Route to branches.true or branches.false

### user_prompt
1. IF interface == "claude_code": CALL AskUserQuestion
   ELSE: Display markdown choices
2. Match response to handler
3. Execute handler.consequence (if any)
4. Route to handler.next_node

### validation_gate
1. Evaluate all validations (non-short-circuit)
2. Collect error_messages for failures
3. Route to on_valid or on_invalid

### reference
1. Load doc at path
2. Extract section if specified
3. Merge context into state
4. Execute document
5. Route to next_node
```

#### 1.4 Consequence Dispatch

```markdown
## Consequence Execution

Based on payload.kind:

| Kind | Action |
|------|--------|
| state_mutation | Execute effect against state |
| computation | Evaluate expression, store result |
| tool_call | CALL tool with interpolated parameters |
| composite | Execute multiple sub-actions |
| side_effect | Display to user |

### Tool Call Translation
1. Resolve type definition
2. Check payload.requires (tools, network, etc.)
3. Select alternative if primary unavailable
4. Interpolate parameters into effect
5. Generate and execute tool call
```

#### 1.5 State Management

```markdown
## State

### Structure
- workflow_name, workflow_version (identity)
- current_node, previous_node (position)
- flags: Record<string, boolean>
- computed: Record<string, any>
- user_responses: Record<node_id, response>
- history: [{node, outcome, timestamp}]
- checkpoints: Record<name, state_snapshot>

### Interpolation
${path} resolved in order:
1. computed.{name}
2. flags.{name}
3. user_responses.{name}
4. top-level state.{field}
```

---

### Phase 2: Create Type Loader Pattern

**File:** `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/workflow/type-loader.md`

Details the loading protocol including:
- URL fetch with WebFetch tool
- Local file read with Read tool
- Caching strategy (session-level)
- Validation against type schemas

---

### Phase 3: Update Existing Documentation

Update these files to reference the new engine:
- `lib/workflow/execution.md` - Add reference to engine.md
- `lib/workflow/schema.md` - Document definitions block usage
- `lib/blueprint/patterns/type-resolution.md` - Already exists, verify consistency

---

### Phase 4: Create Thin Loader Template

**File:** `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/templates/skill-with-executor.md.template`

```markdown
---
name: {{skill_name}}
description: {{description}}
allowed-tools: Read, Write, Bash, AskUserQuestion, Glob, Grep, Task
---

# {{skill_name}}

Execute workflow using the abstract engine.

**Workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/{{skill_name}}/workflow.yaml`
**Engine:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`

## Execution

Load and execute the workflow following the engine pattern.

1. Read workflow.yaml
2. Load type definitions per definitions block
3. Execute using lib/workflow/engine.md semantics
4. State persists in conversation context
```

---

### Phase 5: Bundle Embedded Types (Fallback)

**Directory:** `/home/nathanielramm/git/hiivmind/hiivmind-blueprint/lib/types/`

Copy from hiivmind-blueprint-lib as fallback for offline/airgapped scenarios:
- `index.yaml`
- `consequences/`
- `preconditions/`

---

## Files to Create/Modify

| Action | File | Description |
|--------|------|-------------|
| CREATE | `lib/workflow/engine.md` | Abstract execution engine pattern |
| CREATE | `lib/workflow/type-loader.md` | Type loading protocol |
| CREATE | `templates/skill-with-executor.md.template` | Thin SKILL.md template |
| CREATE | `lib/types/` (directory) | Embedded type definitions fallback |
| MODIFY | `lib/workflow/execution.md` | Reference engine.md |
| MODIFY | `lib/workflow/schema.md` | Document definitions block |

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Executor location | Pattern document (`engine.md`) | LLM-native, updates apply to all skills |
| Type loading | Lazy with session cache | Bundle fetched once, no network for embedded |
| Consequence execution | LLM interprets pseudocode | No imperative code, fully extensible |
| State isolation | `invoke_skill`=isolated, `reference`=shared | Clean boundaries for skills, shared context for patterns |
| Interface detection | Check AskUserQuestion availability | Claude Code vs Claude.ai adaptation |

---

## Verification

After implementation, verify by:

1. **Type Resolution Test**
   - Create a test workflow with `definitions.source` pointing to bundle URL
   - Verify types resolve correctly

2. **Node Execution Test**
   - Create workflow with all 5 node types
   - Verify each executes correctly

3. **Composition Test**
   - Workflow A invokes Workflow B via `invoke_skill`
   - Verify state isolation

4. **Fallback Test**
   - Remove network, verify embedded types work

5. **Self-Dogfooding**
   - Update one hiivmind-blueprint skill to use thin loader
   - Verify identical behavior
