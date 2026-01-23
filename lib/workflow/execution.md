# Workflow Execution

This document specifies how to execute a workflow YAML file. The execution logic is embedded in each SKILL.md as inline instructions.

---

## Execution Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                       SKILL.md Invoked                          │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: INITIALIZATION                                        │
│  1. Load workflow.yaml                                          │
│  2. Evaluate entry_preconditions                                │
│  3. Initialize runtime state                                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 2: EXECUTION LOOP                                        │
│  REPEAT:                                                        │
│    1. Get current node                                          │
│    2. Check for ending                                          │
│    3. Execute node by type                                      │
│    4. Update current_node based on outcome                      │
│    5. Record in history                                         │
│  UNTIL ending reached                                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 3: COMPLETION                                            │
│  1. Display ending message                                      │
│  2. Show summary (if success)                                   │
│  3. Suggest recovery (if error)                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Initialization

### Step 1.1: Load Workflow

```
workflow = parse_yaml(read_file("workflow.yaml"))
```

Validate:
- `workflow.name` matches skill directory name
- `workflow.start_node` exists in `workflow.nodes`
- All node transitions point to valid nodes or endings

### Step 1.2: Evaluate Entry Preconditions

```
FOR each precondition IN workflow.entry_preconditions:
    result = evaluate_precondition(precondition)
    IF result == false:
        DISPLAY "Cannot start: {precondition.error_message or default message}"
        STOP
```

All preconditions must pass. If any fails, workflow cannot start.

### Step 1.3: Initialize Runtime State

```yaml
state:
  workflow_name: "${workflow.name}"
  workflow_version: "${workflow.version}"
  current_node: "${workflow.start_node}"
  previous_node: null
  history: []
  user_responses: {}
  computed: {}
  flags: ${copy of workflow.initial_state.flags}
  checkpoints: {}
```

Copy all fields from `workflow.initial_state` into state.

---

## Phase 2: Execution Loop

### Main Loop

```
LOOP:
    node = workflow.nodes[state.current_node]

    # Check for ending
    IF state.current_node IN workflow.endings:
        ending = workflow.endings[state.current_node]
        GOTO Phase 3 (Completion)

    # Execute node
    outcome = execute_node(node)

    # Record history
    state.history.append({
        node: state.current_node,
        outcome: outcome,
        timestamp: now()
    })

    # Update position
    state.previous_node = state.current_node
    state.current_node = outcome.next_node

    CONTINUE LOOP
```

---

## Node Execution by Type

### Action Node

```
FUNCTION execute_action_node(node):
    TRY:
        FOR each action IN node.actions:
            execute_consequence(action)

        RETURN { success: true, next_node: node.on_success }

    CATCH error:
        RETURN { success: false, next_node: node.on_failure, error: error }
```

**Key points:**
- Actions execute sequentially
- First failure stops remaining actions
- State mutations may be partial on failure

### Conditional Node

```
FUNCTION execute_conditional_node(node):
    result = evaluate_precondition(node.condition)

    IF result == true:
        RETURN { next_node: node.branches.true }
    ELSE:
        RETURN { next_node: node.branches.false }
```

**Key points:**
- Pure evaluation, no side effects
- Always succeeds (routes to one branch)

### User Prompt Node

```
FUNCTION execute_user_prompt_node(node):
    # Build AskUserQuestion
    question = {
        questions: [{
            question: interpolate(node.prompt.question),
            header: node.prompt.header,
            multiSelect: false,
            options: node.prompt.options.map(opt => ({
                label: opt.label,
                description: opt.description
            }))
        }]
    }

    # Present to user
    response = AskUserQuestion(question)

    # Find matching handler
    response_id = find_response_id(response, node.prompt.options)
    handler = node.on_response[response_id]

    # Store response
    state.user_responses[state.current_node] = {
        id: response_id,
        raw: response
    }

    # Apply consequences (if any)
    IF handler.consequence:
        FOR each consequence IN handler.consequence:
            execute_consequence(consequence)

    RETURN { next_node: handler.next_node }
```

**Key points:**
- Blocks for user input
- Response stored in `state.user_responses`
- Consequences optional

### Validation Gate Node

```
FUNCTION execute_validation_gate_node(node):
    errors = []

    FOR each validation IN node.validations:
        result = evaluate_precondition(validation)
        IF result == false:
            errors.append(validation.error_message)

    IF errors.length > 0:
        state.computed.validation_errors = errors
        RETURN { next_node: node.on_invalid }
    ELSE:
        RETURN { next_node: node.on_valid }
```

**Key points:**
- All validations evaluated (not short-circuit)
- Errors collected for display
- Routes to single invalid/valid target

### Reference Node

```
FUNCTION execute_reference_node(node):
    # Load document
    doc = read_file(node.doc)

    # Extract section if specified
    IF node.section:
        doc = extract_section(doc, node.section)

    # Build context
    context = {}
    FOR each key, value IN node.context:
        context[key] = interpolate(value)

    # Execute document instructions
    execute_document(doc, context)

    RETURN { next_node: node.next_node }
```

**Key points:**
- Document executed as sub-procedure
- Context variables available in document
- Always routes to `next_node`

---

## Variable Interpolation

The `interpolate(template)` function resolves `${...}` references.

```
FUNCTION interpolate(template):
    RETURN template.replace(/\$\{([^}]+)\}/g, (match, path) => {
        RETURN resolve_path(path)
    })

FUNCTION resolve_path(path):
    # Try computed first
    IF path.startsWith("computed."):
        RETURN get_nested(state.computed, path.substring(9))

    # Try flags
    IF path.startsWith("flags."):
        RETURN state.flags[path.substring(6)]

    # Try user_responses
    IF path.startsWith("user_responses."):
        RETURN get_nested(state.user_responses, path.substring(15))

    # Try top-level state
    RETURN state[path]
```

**Resolution order:**
1. `state.computed.{name}`
2. `state.flags.{name}`
3. `state.user_responses.{name}`
4. `state.{field}`

---

## Consequence Execution

```
FUNCTION execute_consequence(consequence):
    SWITCH consequence.type:
        CASE "set_flag":
            state.flags[consequence.flag] = consequence.value

        CASE "set_state":
            value = interpolate_if_string(consequence.value)
            set_nested(state, consequence.field, value)

        CASE "read_config":
            content = read_file("data/config.yaml")
            parsed = parse_yaml(content)
            state.computed[consequence.store_as] = parsed

        CASE "web_fetch":
            result = WebFetch(
                url: interpolate(consequence.url),
                prompt: consequence.prompt or "Extract content"
            )
            state.computed[consequence.store_as] = {
                status: result.status,
                content: result.content,
                url: consequence.url
            }
            IF NOT consequence.allow_failure AND result.status >= 400:
                THROW "Fetch failed: " + result.status

        # ... other consequence types per consequences.md
```

---

## Precondition Evaluation

```
FUNCTION evaluate_precondition(precondition):
    SWITCH precondition.type:
        CASE "config_exists":
            RETURN file_exists("data/config.yaml")

        CASE "file_exists":
            path = interpolate(precondition.path)
            RETURN file_exists(path)

        CASE "flag_set":
            RETURN state.flags[precondition.flag] == true

        CASE "state_equals":
            value = get_nested(state, precondition.field)
            RETURN value == precondition.value

        CASE "all_of":
            FOR each cond IN precondition.conditions:
                IF NOT evaluate_precondition(cond):
                    RETURN false
            RETURN true

        CASE "any_of":
            FOR each cond IN precondition.conditions:
                IF evaluate_precondition(cond):
                    RETURN true
            RETURN false

        # ... other precondition types per preconditions.md
```

---

## Phase 3: Completion

### Success Ending

```
IF ending.type == "success":
    message = interpolate(ending.message)
    DISPLAY message

    IF ending.summary:
        FOR each key, value IN ending.summary:
            DISPLAY "  {key}: {interpolate(value)}"
```

### Error Ending

```
IF ending.type == "error":
    message = interpolate(ending.message)
    DISPLAY "Error: " + message

    IF ending.details:
        DISPLAY interpolate(ending.details)

    IF ending.recovery:
        DISPLAY "Try running: /" + ending.recovery
```

---

## SKILL.md Template

Each skill's SKILL.md should contain this execution logic:

```markdown
---
name: hiivmind-corpus-{name}
description: >
  {trigger description from workflow}
allowed-tools: Read, Glob, Grep, Write, Edit, AskUserQuestion, Bash, WebFetch
---

# {Skill Name} Workflow

Execute this workflow inline. State persists in conversation context.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/{skill}/workflow.yaml`

## Execution Instructions

### Phase 1: Initialize

1. **Load workflow.yaml** from this skill directory
2. **Check entry preconditions** (see `lib/workflow/preconditions.md`):
   - Evaluate each precondition in `entry_preconditions`
   - If ANY fails: display error, STOP
3. **Initialize state**:
   ```yaml
   current_node: {workflow.start_node}
   previous_node: null
   history: []
   user_responses: {}
   computed: {}
   flags: {copy from workflow.initial_state.flags}
   ```

### Phase 2: Execute Loop

```
REPEAT for each node:

1. Get node: workflow.nodes[current_node]

2. If current_node is an ending:
   - Display ending.message
   - If error with recovery: suggest recovery skill
   - STOP

3. Execute by node.type:

   ACTION:
   - Execute each action in node.actions
   - If all succeed: current_node = node.on_success
   - If any fail: current_node = node.on_failure

   CONDITIONAL:
   - Evaluate node.condition
   - If true: current_node = node.branches.true
   - If false: current_node = node.branches.false

   USER_PROMPT:
   - Present AskUserQuestion from node.prompt
   - Store response in state.user_responses[current_node]
   - Apply handler.consequence if present
   - current_node = handler.next_node

   VALIDATION_GATE:
   - Evaluate all node.validations
   - If all pass: current_node = node.on_valid
   - If any fail: current_node = node.on_invalid

   REFERENCE:
   - Load node.doc, extract node.section if specified
   - Execute with node.context
   - current_node = node.next_node

4. Append to history

UNTIL ending reached
```

## Reference

- **Workflow Schema:** `lib/workflow/schema.md`
- **Preconditions:** `lib/workflow/preconditions.md`
- **Consequences:** `lib/workflow/consequences.md`
- **State Model:** `lib/workflow/state.md`
```

---

## Debugging

### Trace Mode

For debugging, log each node transition:

```
[WORKFLOW] Node: locate_corpus (action)
[WORKFLOW]   Action: read_config → computed.config
[WORKFLOW]   Action: set_flag config_found = true
[WORKFLOW]   Action: evaluate "len(config.sources) == 0" → is_first_source = true
[WORKFLOW]   → on_success: check_url_provided

[WORKFLOW] Node: check_url_provided (conditional)
[WORKFLOW]   Condition: state_not_null(source_url) = false
[WORKFLOW]   → branches.false: ask_source_type
```

### State Inspection

At any point, display current state:

```yaml
state:
  current_node: ask_source_type
  previous_node: check_url_provided
  flags:
    config_found: true
    manifest_detected: false
    is_first_source: true
  computed:
    config: {...}
  history:
    - node: locate_corpus
      outcome: {success: true}
    - node: check_url_provided
      outcome: {branch: false}
```

---

## Error Recovery

### Checkpoint Restoration

```
IF action fails AND checkpoint exists:
    DISPLAY "Error: {error}"
    DISPLAY "Rolling back to checkpoint: {checkpoint_name}"
    rollback_checkpoint(checkpoint_name)
    ROUTE to on_failure
```

### Partial State

Without checkpoints, failed actions may leave partial state:

```yaml
actions:
  - type: clone_repo        # ✓ Succeeded
    dest: ".source/polars"
  - type: get_sha           # ✗ Failed (repo corrupt?)
    store_as: computed.sha
  - type: add_source        # Skipped
    spec: {...}
```

**Recovery options:**
1. Manual cleanup of `.source/polars`
2. Retry from beginning
3. Use checkpoints in workflow design

---

## Related Documentation

- **Schema:** `lib/workflow/schema.md` - YAML structure
- **Preconditions:** `lib/workflow/preconditions.md` - Boolean evaluations
- **Consequences:** `lib/workflow/consequences.md` - State mutations
- **State:** `lib/workflow/state.md` - Runtime state structure
