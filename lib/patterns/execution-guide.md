# Execution Guide

How to execute skills and workflow definitions for hiivmind-blueprint.

> **Related Patterns:**
> - Authoring Guide: `patterns/authoring-guide.md`
> - Node Mapping: `patterns/node-mapping.md`
> - Prompt Modes: `patterns/prompt-modes.md`

---

## 0. Skill Execution Model

Skills execute in a **phase-based model**. Each phase is either prose-driven or workflow-backed.

```
Step 1: Read SKILL.md
    Parse frontmatter (inputs, outputs, workflows)
    Identify phases and workflow references
    ↓
Step 2: Execute phases sequentially
    For each phase in the Execution section:
      If prose phase → follow prose instructions directly
      If workflow phase → run the 3-phase workflow model (below)
    ↓
Step 3: Return outputs
    Collect computed.* values matching declared outputs
    Return to caller
```

### Phase Types

| Phase Type | How It Executes |
|------------|-----------------|
| **Prose** | LLM follows instructions directly — tool calls, analysis, user interaction |
| **Workflow-backed** | LLM loads a workflow YAML and executes it using the 3-phase model below |

### State Handoff Between Phases

State flows through `computed.*` across all phases:

```
Phase 1 (prose)     → sets computed.target_files
Phase 2 (workflow)  → reads ${computed.target_files}, sets computed.validation_results
Phase 3 (prose)     → reads computed.validation_results, displays report
```

For workflow-backed phases:
1. Load type registry from `blueprint-types.md` (see [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib/blob/main/blueprint-types.md))
2. Read the workflow YAML file
3. Follow the 3-phase workflow execution model (Init → Execute → Complete)
4. After completion, `computed.*` values from the workflow are available to subsequent phases

---

## 1. Workflow Execution Overview

Individual workflows execute in a **3-phase model** using local definitions only:

```
Phase 1: Initialize
    Read definitions.yaml → build type registry
    Read workflow.yaml → validate types → initialize state
    Check entry preconditions
    ↓
Phase 2: Execute
    Main loop: dispatch current node → advance to next
    Repeat until an ending is reached
    ↓
Phase 3: Complete
    Display ending message and summary
    Return result type
```

All type definitions are loaded from `blueprint-types.md` in `hiivmind-blueprint-lib` — no remote fetching, no version resolution, no local `definitions.yaml` file required.

---

## 2. Phase 1: Initialize

```
FUNCTION initialize(workflow_path):
    # 1. Read local definitions
    definitions = load_blueprint_types("blueprint-types.md")  # from hiivmind-blueprint-lib
    types = {
        nodes: definitions.nodes,
        consequences: definitions.consequences,
        preconditions: definitions.preconditions
    }

    # 2. Read workflow
    workflow = parse_yaml(read_file(workflow_path))

    # 3. Validate all types used in workflow exist in definitions
    validate_workflow_types(workflow, types)

    # 4. Initialize state
    state = {
        current_node: workflow.start_node,
        previous_node: null,
        history: [],
        user_responses: {},
        computed: {},
        flags: copy(workflow.initial_state.flags OR {}),
        checkpoints: {},
        log: null,
        ...workflow.initial_state
    }

    # 5. Apply output config: defaults < workflow config < runtime flags
    state.output = resolve_output_config(workflow, runtime_flags)

    # 6. Check entry preconditions
    FOR each precondition IN workflow.entry_preconditions:
        IF NOT evaluate_precondition(precondition, types, state):
            DISPLAY precondition.error_message OR "Precondition failed"
            STOP

    RETURN { workflow, types, state }
```

### Type Validation

```
FUNCTION validate_workflow_types(workflow, types):
    FOR each node IN workflow.nodes:
        IF node.type == "action":
            FOR each action IN node.actions:
                IF action.type NOT IN types.consequences:
                    THROW "Unknown consequence type: {action.type}"
        IF node.type == "conditional":
            validate_precondition_types(node.condition, types)

FUNCTION validate_precondition_types(condition, types):
    IF condition.type NOT IN types.preconditions:
        THROW "Unknown precondition type: {condition.type}"
    IF condition.type == "composite":
        FOR each sub IN condition.conditions:
            validate_precondition_types(sub, types)
```

---

## 3. Phase 2: Execute

```
FUNCTION execute(workflow, types, state):
    LOOP:
        # Multi-turn resume: if paused waiting for user input, resume
        IF state.awaiting_input:
            state.awaiting_input.user_input = get_user_input()
            state.current_node = state.awaiting_input.node_id

        node = workflow.nodes[state.current_node]

        # Check for ending
        IF state.current_node IN workflow.endings:
            GOTO Phase 3

        # Dispatch node by type
        outcome = dispatch_node(node, types, state)

        # Pause if node awaits user input (multi-turn)
        IF outcome.awaiting_input:
            PAUSE
            RETURN

        # Record and advance
        state.history.append({ node: state.current_node, outcome, timestamp: now() })
        state.previous_node = state.current_node
        state.current_node = outcome.next_node
    UNTIL ending
```

### Node Dispatch

```
FUNCTION dispatch_node(node, types, state):
    SWITCH node.type:
        CASE "action":      RETURN execute_action_node(node, types, state)
        CASE "conditional":  RETURN execute_conditional_node(node, types, state)
        CASE "user_prompt":  RETURN execute_user_prompt_node(node, types, state)
        DEFAULT:             THROW "Unknown node type: {node.type}"
```

### Action Nodes

Execute a sequence of consequences. All must succeed for on_success routing.

```
FUNCTION execute_action_node(node, types, state):
    TRY:
        FOR each action IN node.actions:
            execute_consequence(action, types, state)
        RETURN { success: true, next_node: resolve_target(node.on_success, state) }
    CATCH error:
        RETURN { success: false, next_node: resolve_target(node.on_failure, state), error }
```

### Conditional Nodes

Evaluate a precondition and branch.

```
FUNCTION execute_conditional_node(node, types, state):
    IF node.audit AND node.audit.enabled:
        # Audit mode: evaluate ALL conditions, collect results
        results = evaluate_all_conditions(node.condition, types, state)
        IF node.audit.output:
            set_nested(state.computed, node.audit.output, results)
        passed = results.passed
    ELSE:
        passed = evaluate_precondition(node.condition, types, state)

    IF passed:
        RETURN { next_node: resolve_target(node.branches.on_true, state) }
    ELSE:
        RETURN { next_node: resolve_target(node.branches.on_false, state) }
```

### User Prompt Nodes

Present a question to the user, route by response.

```
FUNCTION execute_user_prompt_node(node, types, state):
    # Build prompt (resolve dynamic options if options_from_state present)
    prompt = build_prompt(node.prompt, state)

    # Present to user and get response
    response = present_and_await(prompt)

    # Store response
    state.user_responses[node_id] = {
        handler_id: response.selected_id,
        raw: response
    }

    # Find matching handler
    handler = node.on_response[response.selected_id]

    # Execute handler consequences (if any)
    IF handler.consequence:
        FOR each action IN handler.consequence:
            execute_consequence(action, types, state)

    RETURN { next_node: resolve_target(handler.next_node, state) }
```

### Multi-Turn Pause/Resume

When a user_prompt node is reached in a multi-turn conversation:
1. The prompt is presented to the user
2. Execution **pauses** — state is preserved
3. When the user responds, execution **resumes** from the paused node
4. The response is processed and routing continues

---

## 4. Phase 3: Complete

```
FUNCTION complete(ending, workflow, types, state):
    # Step 1: Execute ending consequences (best-effort)
    IF ending.consequences:
        FOR each consequence IN ending.consequences:
            TRY:
                execute_consequence(consequence, types, state)
            CATCH error:
                LOG "Ending consequence failed: {error}" (continue — endings must not fail)

    # Step 2: Resolve behavior (default: display)
    behavior_type = ending.behavior.type IF ending.behavior ELSE "display"

    SWITCH behavior_type:
        CASE "display":  RETURN complete_display(ending, state)
        CASE "delegate": RETURN complete_delegate(ending, state)
        CASE "restart":  RETURN complete_restart(ending, workflow, types, state)
        CASE "silent":   RETURN ending.type


FUNCTION complete_display(ending, state):
    # Default behavior — backward compatible with all existing endings
    IF ending.message:
        DISPLAY interpolate(ending.message, state)

    IF ending.summary:
        FOR each key, value IN ending.summary:
            DISPLAY "  {key}: {interpolate(value, state)}"

    IF ending.type == "error" AND ending.recovery:
        DISPLAY "Recovery: {ending.recovery}"

    RETURN ending.type


FUNCTION complete_delegate(ending, state):
    # Hand off to another skill
    skill = interpolate(ending.behavior.skill, state)
    args = interpolate(ending.behavior.args, state) IF ending.behavior.args ELSE null
    context = interpolate_deep(ending.behavior.context, state) IF ending.behavior.context ELSE {}

    IF ending.message:
        DISPLAY interpolate(ending.message, state)

    INVOKE skill WITH args, context
    RETURN ending.type


FUNCTION complete_restart(ending, workflow, types, state):
    # Loop back to a node — with restart count safety
    state._restart_count = (state._restart_count OR 0) + 1
    max = ending.behavior.max_restarts OR 3

    IF state._restart_count > max:
        DISPLAY "Restart limit reached ({max}). Ending workflow."
        RETURN "failure"

    IF ending.behavior.reset_state:
        # Reset state but preserve _restart_count to prevent infinite loops
        restart_count = state._restart_count
        state = copy(workflow.initial_state) + engine_defaults
        state._restart_count = restart_count

    IF ending.message:
        DISPLAY interpolate(ending.message, state)

    # Re-enter Phase 2 from target node
    target = ending.behavior.target_node OR workflow.start_node
    state.current_node = target
    GOTO Phase 2 (execute loop)
```

---

## 5. Consequence Dispatch

Consequences modify state, call tools, compute values, or produce side effects.

```
FUNCTION execute_consequence(consequence, types, state):
    type_def = types.consequences[consequence.type]
    IF type_def == null:
        THROW "Unknown consequence type: {consequence.type}"

    # Check requirements (if any)
    IF type_def.payload.requires:
        check_requirements(type_def.payload.requires)

    # Interpolate parameters
    params = interpolate_params(consequence, type_def, state)

    # Route by payload kind
    SWITCH type_def.payload.kind:
        CASE "state_mutation":
            # Apply effect to state (set_flag, mutate_state, etc.)
            apply_effect(type_def.payload.effect, params, state)

        CASE "computation":
            # Evaluate expression, store result
            result = evaluate_expression(params.expression, state)
            IF consequence.store_as: set_nested(state.computed, consequence.store_as, result)
            IF consequence.set_flag: state.flags[consequence.set_flag] = result

        CASE "tool_call":
            # Build and execute Claude tool call
            result = CALL type_def.payload.tool with build_tool_call(type_def.payload.effect, params)
            IF consequence.store_as: set_nested(state.computed, consequence.store_as, result)

        CASE "side_effect":
            # Display output without modifying state
            apply_effect(type_def.payload.effect, params, state)

        DEFAULT:
            THROW "Unknown payload kind: {type_def.payload.kind}"
```

---

## 6. Precondition Dispatch

Preconditions are pure boolean evaluations that do not modify state.

```
FUNCTION evaluate_precondition(precondition, types, state):
    type_def = types.preconditions[precondition.type]
    IF type_def == null:
        THROW "Unknown precondition type: {precondition.type}"

    params = interpolate_params(precondition, type_def, state)
    RETURN evaluate_from_definition(type_def, params, state)
```

### Composite Preconditions

The `composite` type combines conditions with logical operators:

```
IF operator == "all":  RETURN all(evaluate(c) for c in conditions)
IF operator == "any":  RETURN any(evaluate(c) for c in conditions)
IF operator == "none": RETURN NOT any(evaluate(c) for c in conditions)
IF operator == "xor":  RETURN sum(evaluate(c) for c in conditions) == 1
```

### Audit Mode

When `audit.enabled` is true on a conditional node:
- Evaluate ALL conditions (no short-circuit)
- Collect individual results with pass/fail status
- Store at `audit.output` path (default: `computed.audit_results`)
- Result structure: `{ passed, total, passed_count, failed_count, results: [...] }`

---

## 7. Interpolation

### `${...}` Resolution

```
FUNCTION interpolate(template, state):
    FOR each match IN template.match_all(/\$\{([^}]+)\}/):
        path = match.group(1)
        value = resolve_path(state, path)
        IF value == null: THROW "Unresolved variable: ${path}"
        template = template.replace(match.full, to_string(value))
    RETURN template

FUNCTION resolve_path(state, path):
    IF path.startsWith("computed."):       RETURN get_nested(state.computed, path[9:])
    IF path.startsWith("flags."):          RETURN get_nested(state.flags, path[6:])
    IF path.startsWith("user_responses."): RETURN get_nested(state.user_responses, path[15:])
    RETURN get_nested(state, path)
```

### Deep Interpolation

Interpolation recurses into nested objects and arrays so that consequence parameters like `{ url: "${computed.repo_url}" }` are resolved at all nesting levels before execution.

### Path Resolution

```
FUNCTION get_nested(obj, path):
    FOR each part IN parse_path(path):  # Handles dots and [N] brackets
        IF obj == null: RETURN null
        IF part.is_index:
            index = part.index < 0 ? obj.length + part.index : part.index
            obj = obj[index]
        ELSE:
            obj = obj[part.key]
    RETURN obj
```

---

## 8. Dynamic Routing and Checkpoints

### Dynamic Routing

Any routing field (`on_success`, `on_failure`, `branches.*`) can contain `${...}` references:

```
FUNCTION resolve_target(target, state):
    IF target.includes("${"):
        resolved = interpolate(target, state)
        IF resolved == null OR resolved == "":
            THROW "Dynamic target resolved to null: {target}"
        RETURN resolved
    RETURN target
```

### Checkpoints

Save and restore state snapshots:

```
# Create checkpoint before risky operation
FUNCTION create_checkpoint(name, state):
    state.checkpoints[name] = deep_copy(state)

# Rollback on failure
FUNCTION rollback_checkpoint(name, state):
    snapshot = state.checkpoints[name]
    state.current_node = snapshot.current_node
    state.computed = snapshot.computed
    state.flags = snapshot.flags
    state.user_responses = snapshot.user_responses
    state.history = snapshot.history
```

---

## 9. State Structure and Lifecycle

```yaml
state:
  # Position tracking
  current_node: string       # Node being executed
  previous_node: string      # Last executed node
  history: []                # Array of { node, outcome, timestamp }

  # User interaction results
  user_responses: {}         # Keyed by node name: { handler_id, raw }

  # Computed values from consequences
  computed: {}               # Results from consequences (store_as targets)

  # Boolean routing flags
  flags: {}                  # Set via set_flag or evaluate consequences

  # Rollback snapshots
  checkpoints: {}            # Named state snapshots

  # Output configuration
  output:
    level: string            # silent|quiet|normal|verbose|debug
    log_enabled: boolean     # Whether to write log files
```

### Lifecycle

1. **Initialize:** State created from `workflow.initial_state` + engine defaults
2. **Execute:** State mutated by consequences, extended by user responses
3. **Complete:** Final state available for ending message interpolation

---

## 10. Output and Logging

### Output Levels

| Level | Shows |
|-------|-------|
| `silent` | User prompts and final result only |
| `quiet` | Adds warnings |
| `normal` | Adds node transitions (default) |
| `verbose` | Adds condition evaluations, branch decisions |
| `debug` | Adds full state dumps, interpolation traces |

### Runtime Flags

| Flag | Effect |
|------|--------|
| `--verbose`, `-v` | Set level to verbose |
| `--quiet`, `-q` | Set level to quiet |
| `--debug` | Set level to debug |
| `--no-log` | Disable log file writing |

### Configuration Precedence

```
hardcoded defaults < workflow.initial_state.output < runtime flags
```

Default values (used when not configured):
- `level: "normal"`
- `log_enabled: true`
- `log_format: "yaml"`
- `log_location: ".logs/"`
