# Workflow Execution Engine

This document specifies the abstract execution engine for workflow YAML files. The engine is LLM-native: the LLM interprets these patterns directly, enabling extensibility through new type definitions rather than engine modifications.

This is the **single comprehensive reference** for workflow execution. It consolidates:
- Execution semantics (formerly execution.md)
- YAML workflow structure (formerly schema.md)
- Runtime state structure (formerly state.md)

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      SKILL.md (Thin Loader)                     │
│  References engine.md, loads workflow.yaml                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    THIS DOCUMENT (engine.md)                    │
│  Abstract execution pattern (Phase 1-2-3 model)                 │
│  - Type resolution protocol (→ type-loader.md)                  │
│  - Node execution semantics                                     │
│  - State management                                             │
│  - Consequence dispatch                                         │
└─────────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        TypeRegistry     Dispatcher      StateManager
        (resolve)        (execute)       (interpolate)
```

---

## Core Principle: LLM-Native Execution

This workflow engine is NOT compiled code. It's a **pattern document** that the LLM interprets directly. This is intentional:

| Benefit | How It Works |
|---------|--------------|
| **Extensibility** | New types require only definition files, not engine changes |
| **Self-describing** | Type definitions fully specify behavior via pseudocode effects |
| **Natural handling** | The LLM naturally handles interpolation, error recovery, tool calls |
| **Zero deployment** | Updates to types or engine apply to all skills immediately |

---

## Workflow Schema

### File Structure

Each skill directory contains:

```
skills/hiivmind-corpus-{name}/
├── SKILL.md           # Thin loader with execution instructions
├── workflow.yaml      # Deterministic workflow graph
└── references/        # Complex procedure docs (optional)
    └── {topic}.md
```

### Workflow YAML Structure

```yaml
# Required: Workflow identity
name: "skill-name"                    # String: matches skill directory name
version: "1.0.0"                      # Semver: workflow version
description: "Trigger description"   # String: copied to SKILL.md frontmatter

# Optional: External type definitions (v2.1+)
definitions:
  source: hiivmind/hiivmind-blueprint-types@v1.0.0  # GitHub shorthand
  # OR: https://github.com/.../bundle.yaml          # Direct URL
  # OR: source: local + path: ./vendor/...         # Embedded
  fallback: embedded                  # Optional: error | warn | embedded
  extensions:                         # Optional: additional type sources
    - mycorp/custom-types@v1.0.0

# Required: Entry gate (all must pass to start)
entry_preconditions:
  - type: config_exists              # Precondition type
  - type: tool_available
    tool: git                        # Parameters for precondition

# Required: Initial runtime state
initial_state:
  phase: "start"                     # String: current phase label
  source_type: null                  # null | string: detected source type
  flags:                             # Boolean flags for routing
    config_found: false
    manifest_detected: false
    is_first_source: false
  computed: {}                       # Object: stores action outputs

# Required: Starting point
start_node: locate_corpus            # String: must exist in nodes

# Required: Workflow graph
nodes:
  node_name:                         # String: unique node identifier
    type: action                     # Node type (see Node Types below)
    # ... type-specific fields

# Required: Terminal states
endings:
  success:                           # Ending identifier
    type: success                    # success | error
    message: "Source added"          # Display message
  error_no_config:
    type: error
    message: "No config.yaml found"
    recovery: "hiivmind-corpus-init" # Optional: suggest recovery skill
```

### Definitions Block (v2.1+)

The `definitions` block specifies where to load type definitions from. See `type-loader.md` for full resolution protocol.

| Format | Example | Description |
|--------|---------|-------------|
| GitHub shorthand | `owner/repo@v1.0.0` | Fetches from GitHub releases |
| Direct URL | `https://example.com/bundle.yaml` | Fetches from URL |
| Local | `source: local` + `path: ./vendor/...` | Reads from local file |

**Fallback Strategies:**

| Value | Behavior |
|-------|----------|
| `error` | Fail immediately if fetch fails (default) |
| `warn` | Log warning, try cache, then embedded |
| `embedded` | Silently use embedded definitions |

**Extensions:** Load additional type sources:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-types@v1.0.0
  extensions:
    - mycorp/custom-types@v1.0.0
    - https://example.com/domain-types.yaml
```

Type collisions are resolved via namespace prefixes:

```yaml
actions:
  - type: clone_repo                          # Base type (unambiguous)
  - type: mycorp/custom-types:clone_repo      # Namespaced type
```

### Node Types

#### 1. Action Node

Executes one or more operations, then routes based on success/failure.

```yaml
node_name:
  type: action
  description: "Optional description for debugging"
  actions:
    - type: read_config              # Consequence type
      store_as: "config"             # Store result in state.computed
    - type: set_flag
      flag: config_found
      value: true
    - type: evaluate
      expression: "len(config.sources) == 0"
      set_flag: is_first_source
  on_success: next_node              # Route on all actions succeeding
  on_failure: error_node             # Route on any action failing
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"action"` |
| `description` | No | Human-readable purpose |
| `actions` | Yes | Array of consequence objects |
| `on_success` | Yes | Node/ending to route to on success |
| `on_failure` | Yes | Node/ending to route to on failure |

#### 2. Conditional Node

Branches based on a precondition evaluation.

```yaml
node_name:
  type: conditional
  description: "Route based on detected state"
  condition:
    type: flag_set                   # Precondition type
    flag: manifest_detected          # Precondition parameters
  branches:
    true: present_manifest_option    # Route when condition is true
    false: ask_source_type           # Route when condition is false
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"conditional"` |
| `description` | No | Human-readable purpose |
| `condition` | Yes | Single precondition object |
| `branches.true` | Yes | Node/ending when true |
| `branches.false` | Yes | Node/ending when false |

#### 3. User Prompt Node

Presents an AskUserQuestion and routes based on response.

```yaml
node_name:
  type: user_prompt
  prompt:
    question: "What type of source would you like to add?"
    header: "Source"                 # Max 12 chars
    options:
      - id: git
        label: "Git repository"
        description: "Clone repo with docs folder"
      - id: local
        label: "Local files"
        description: "Files on your machine"
      - id: web
        label: "Web pages"
        description: "Cache blog posts/articles"
  on_response:
    git:
      consequence:                   # Optional: apply before routing
        - type: set_state
          field: source_type
          value: git
      next_node: collect_git_url
    local:
      consequence:
        - type: set_state
          field: source_type
          value: local
      next_node: collect_local_info
    web:
      next_node: collect_web_urls    # Can route without consequence
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"user_prompt"` |
| `prompt.question` | Yes | Question text |
| `prompt.header` | Yes | Short label (max 12 chars) |
| `prompt.options` | Yes | Array of options (2-4) |
| `prompt.options[].id` | Yes | Unique identifier for routing |
| `prompt.options[].label` | Yes | Display text |
| `prompt.options[].description` | Yes | Explanation |
| `on_response` | Yes | Map of id → {consequence?, next_node} |

#### 4. Validation Gate Node

Runs multiple preconditions; all must pass to proceed.

```yaml
node_name:
  type: validation_gate
  description: "Validate before proceeding"
  validations:
    - type: file_exists
      path: "data/config.yaml"
      error_message: "Config file missing"
    - type: tool_available
      tool: git
      error_message: "Git is not installed"
  on_valid: proceed_node
  on_invalid: show_validation_errors
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"validation_gate"` |
| `description` | No | Human-readable purpose |
| `validations` | Yes | Array of preconditions with error_message |
| `on_valid` | Yes | Node/ending when all pass |
| `on_invalid` | Yes | Node/ending when any fail |

#### 5. Reference Node

Loads and executes a reference document section.

```yaml
node_name:
  type: reference
  doc: "lib/corpus/patterns/sources/git.md"
  section: "Clone Repository"        # Optional: specific section
  context:                           # Variables to pass to doc
    repo_url: "${computed.repo_url}"
    source_id: "${computed.source_id}"
  next_node: verify_clone
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | Must be `"reference"` |
| `doc` | Yes | Path to reference document |
| `section` | No | Section heading to execute |
| `context` | No | Variables available in doc |
| `next_node` | Yes | Node/ending after doc execution |

### Endings

Terminal states that stop workflow execution.

```yaml
endings:
  success:
    type: success
    message: "Source added successfully to corpus"
    summary:                         # Optional: structured result
      source_id: "${computed.source_id}"
      source_type: "${source_type}"
      files_count: "${computed.files_count}"

  error_no_config:
    type: error
    message: "No config.yaml found in current directory"
    recovery: "hiivmind-corpus-init" # Suggest recovery skill
    details: "Run from a corpus directory containing data/config.yaml"

  cancelled:
    type: error
    message: "Operation cancelled by user"
```

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `"success"` or `"error"` |
| `message` | Yes | Display to user |
| `recovery` | No | Skill to suggest on error |
| `details` | No | Additional context |
| `summary` | No | Structured output (success only) |

### Variable Interpolation

Within workflow YAML, use `${...}` for variable references:

```yaml
# Reference state fields
expression: "${source_type} == 'git'"

# Reference computed values
url: "${computed.repo_url}"

# Reference user responses
section: "${user_responses.select_sections}"

# Reference flags
condition: "${flags.manifest_detected}"
```

**Resolution order:**
1. `state.computed.{name}`
2. `state.flags.{name}`
3. `state.user_responses.{name}`
4. `state.{field}`

---

## Execution Model

### Phase 1: Initialization

```
FUNCTION initialize(workflow_path):
    # 1. Load workflow
    workflow = parse_yaml(read_file(workflow_path))

    # 2. Load type definitions
    types = load_types(workflow.definitions)  # See type-loader.md

    # 3. Validate
    validate_schema(workflow)
    validate_types_exist(workflow, types)
    validate_graph_connectivity(workflow)

    # 4. Check entry preconditions
    FOR each precondition IN workflow.entry_preconditions:
        result = evaluate_precondition(precondition, types)
        IF result == false:
            DISPLAY "Cannot start: {precondition.error_message or 'precondition failed'}"
            STOP

    # 5. Initialize state
    state = {
        workflow_name: workflow.name,
        workflow_version: workflow.version,
        current_node: workflow.start_node,
        previous_node: null,
        interface: detect_interface(),
        history: [],
        user_responses: {},
        computed: {},
        flags: copy(workflow.initial_state.flags or {}),
        checkpoints: {},
        ...workflow.initial_state  # Copy custom fields
    }

    RETURN { workflow, types, state }
```

### Phase 2: Execution Loop

```
FUNCTION execute(workflow, types, state):
    LOOP:
        node = workflow.nodes[state.current_node]

        # Check for ending
        IF state.current_node IN workflow.endings:
            ending = workflow.endings[state.current_node]
            GOTO Phase 3 (completion)

        # Execute node based on type
        outcome = execute_node(node, types, state)

        # Record in history
        state.history.append({
            node: state.current_node,
            outcome: outcome,
            timestamp: now()
        })

        # Update position
        state.previous_node = state.current_node
        state.current_node = outcome.next_node

    UNTIL ending
```

### Phase 3: Completion

```
FUNCTION complete(ending, state):
    message = interpolate(ending.message, state)

    IF ending.type == "success":
        DISPLAY message
        IF ending.summary:
            FOR each key, value IN ending.summary:
                DISPLAY "  {key}: {interpolate(value, state)}"

    ELSE IF ending.type == "error":
        DISPLAY "Error: " + message
        IF ending.details:
            DISPLAY interpolate(ending.details, state)
        IF ending.recovery:
            DISPLAY "Try running: /{ending.recovery}"

    RETURN ending.type
```

---

## Type Loading Protocol

Type definitions are loaded at workflow initialization. See `type-loader.md` for full details.

### Quick Reference

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-types@v1.0.0  # GitHub shorthand
  # OR
  source: https://github.com/.../bundle.yaml        # Direct URL
  # OR
  source: local                                     # Embedded
  path: ./vendor/blueprint-types/bundle.yaml
```

### Resolution Process

1. Parse `definitions.source` to determine source type
2. Check local cache (`~/.claude/cache/hiivmind/blueprint/types/`)
3. Fetch if not cached (WebFetch for URLs)
4. Validate against type schema
5. Build TypeRegistry with consequence and precondition definitions
6. Validate all types used in workflow exist in registry

### TypeRegistry Structure

```yaml
# In-memory registry (built from definitions)
type_registry:
  schema_version: "1.1"

  consequences:
    set_flag:
      category: core/state
      parameters: [...]
      payload: {...}
    clone_repo:
      category: extensions/git
      parameters: [...]
      payload: {...}
    # ... all 43 consequence types

  preconditions:
    file_exists:
      category: core/filesystem
      parameters: [...]
      evaluation: {...}
    flag_set:
      category: core/state
      parameters: [...]
      evaluation: {...}
    # ... all 27 precondition types
```

---

## Node Execution by Type

### Action Node

```
FUNCTION execute_action_node(node, types, state):
    TRY:
        FOR each action IN node.actions:
            execute_consequence(action, types, state)

        RETURN { success: true, next_node: node.on_success }

    CATCH error:
        IF node.checkpoint_rollback:
            rollback_checkpoint(node.checkpoint_rollback, state)
        RETURN { success: false, next_node: node.on_failure, error: error }
```

**Semantics:**
- Actions execute sequentially
- First failure stops remaining actions
- State mutations may be partial on failure (use checkpoints)

### Conditional Node

```
FUNCTION execute_conditional_node(node, types, state):
    result = evaluate_precondition(node.condition, types, state)

    IF result == true:
        RETURN { next_node: node.branches.true }
    ELSE:
        RETURN { next_node: node.branches.false }
```

**Semantics:**
- Pure evaluation, no side effects
- Always succeeds (routes to one branch)

### User Prompt Node

```
FUNCTION execute_user_prompt_node(node, types, state):
    # Present prompt based on detected interface
    IF state.interface == "claude_code":
        # CALL the AskUserQuestion tool
        response = CALL AskUserQuestion with build_ask_params(node, state)
    ELSE:
        # Claude.ai mode - display markdown, wait for chat response
        DISPLAY render_markdown_prompt(node, state)
        response = WAIT for user message

    # LLM interprets response and matches to handler
    handler = match_response_to_handler(response, node.on_response)

    # Store response
    state.user_responses[state.current_node] = {
        handler_id: handler.id,
        raw: response
    }

    # Apply handler consequences (if any)
    IF handler.consequence:
        FOR each consequence IN handler.consequence:
            execute_consequence(consequence, types, state)

    RETURN { next_node: handler.next_node }
```

**Semantics:**
- Blocks for user input
- Interface-aware: Claude Code uses AskUserQuestion tool, Claude.ai uses markdown
- Response stored in `state.user_responses`
- Handler consequences are optional

**Interface-aware presentation:**

For Claude Code (`state.interface == "claude_code"`):
```
FUNCTION build_ask_params(node, state):
    RETURN {
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
```

For Claude.ai (`state.interface == "claude_ai"`):
```
FUNCTION render_markdown_prompt(node, state):
    md = "**{node.prompt.header}**\n\n"
    md += "{interpolate(node.prompt.question)}\n\n"
    md += "| # | Option | Description |\n"
    md += "|---|--------|-------------|\n"
    FOR i, opt IN enumerate(node.prompt.options):
        md += "| {i+1} | {opt.label} | {opt.description} |\n"
    md += "\n*Reply with a number to select, or describe what you want.*"
    RETURN md
```

### Validation Gate Node

```
FUNCTION execute_validation_gate_node(node, types, state):
    errors = []

    # Non-short-circuit: evaluate ALL validations
    FOR each validation IN node.validations:
        result = evaluate_precondition(validation, types, state)
        IF result == false:
            errors.append(validation.error_message)

    IF errors.length > 0:
        state.computed.validation_errors = errors
        RETURN { next_node: node.on_invalid }
    ELSE:
        RETURN { next_node: node.on_valid }
```

**Semantics:**
- All validations evaluated (collects all errors)
- Errors stored in `state.computed.validation_errors`
- Routes to single invalid/valid target

### Reference Node

```
FUNCTION execute_reference_node(node, types, state):
    # Load document
    doc = read_file(node.doc)

    # Extract section if specified
    IF node.section:
        doc = extract_section(doc, node.section)

    # Build context with interpolation
    context = {}
    FOR each key, value IN node.context:
        context[key] = interpolate(value, state)

    # Execute document with context
    # Note: Reference execution shares state (unlike invoke_skill)
    execute_document(doc, context, state)

    RETURN { next_node: node.next_node }
```

**Semantics:**
- Document executed as sub-procedure
- Context variables passed to document
- State is SHARED (not isolated like `invoke_skill`)
- Always routes to `next_node`

---

## Consequence Dispatch

Consequences are executed based on their type definition from the TypeRegistry.

### Dispatch Algorithm

```
FUNCTION execute_consequence(consequence, types, state):
    # 1. Resolve type definition
    type_def = types.consequences[consequence.type]
    IF type_def == null:
        THROW "Unknown consequence type: {consequence.type}"

    # 2. Check requirements
    IF type_def.payload.requires:
        check_requirements(type_def.payload.requires)

    # 3. Dispatch based on payload.kind
    SWITCH type_def.payload.kind:
        CASE "state_mutation":
            execute_state_mutation(consequence, type_def, state)

        CASE "computation":
            execute_computation(consequence, type_def, state)

        CASE "tool_call":
            execute_tool_call(consequence, type_def, state)

        CASE "composite":
            execute_composite(consequence, type_def, types, state)

        CASE "side_effect":
            execute_side_effect(consequence, type_def, state)
```

### Kind: state_mutation

Direct state modifications (set_flag, set_state, append_state, etc.)

```
FUNCTION execute_state_mutation(consequence, type_def, state):
    # Interpolate parameter values
    params = interpolate_params(consequence, type_def, state)

    # Apply effect to state
    # The LLM interprets type_def.payload.effect and applies it
    apply_effect(type_def.payload.effect, params, state)
```

### Kind: computation

Expression evaluation and result storage (evaluate, compute)

```
FUNCTION execute_computation(consequence, type_def, state):
    params = interpolate_params(consequence, type_def, state)

    # Evaluate expression
    result = evaluate_expression(params.expression, state)

    # Store result
    IF consequence.store_as:
        set_nested(state, consequence.store_as, result)
    IF consequence.set_flag:
        state.flags[consequence.set_flag] = result
```

### Kind: tool_call

Execute a Claude Code tool (Bash, Read, Write, WebFetch, etc.)

```
FUNCTION execute_tool_call(consequence, type_def, state):
    params = interpolate_params(consequence, type_def, state)

    # Check tool availability
    IF NOT tool_available(type_def.payload.tool):
        # Try alternatives
        FOR each alt IN type_def.payload.alternatives:
            IF evaluate_condition(alt.condition, state):
                CALL tool with alt.effect
                RETURN
        IF type_def.payload.alternatives.fallback:
            THROW type_def.payload.alternatives.fallback.error

    # Build tool call from effect
    tool_call = build_tool_call(type_def.payload.effect, params)

    # Execute tool
    result = CALL type_def.payload.tool with tool_call

    # Store result if specified
    IF consequence.store_as:
        set_nested(state.computed, consequence.store_as, result)
```

### Kind: composite

Multiple sub-consequences (for complex operations)

```
FUNCTION execute_composite(consequence, type_def, types, state):
    FOR each sub_consequence IN type_def.payload.consequences:
        execute_consequence(sub_consequence, types, state)
```

### Kind: side_effect

Display or output without state mutation

```
FUNCTION execute_side_effect(consequence, type_def, state):
    params = interpolate_params(consequence, type_def, state)

    SWITCH type_def.type:
        CASE "display_message":
            DISPLAY interpolate(params.message, state)
        CASE "display_table":
            DISPLAY render_table(params.data, params.columns)
```

---

## Precondition Evaluation

Preconditions are boolean evaluations that don't modify state.

```
FUNCTION evaluate_precondition(precondition, types, state):
    # 1. Resolve type definition
    type_def = types.preconditions[precondition.type]
    IF type_def == null:
        THROW "Unknown precondition type: {precondition.type}"

    # 2. Interpolate parameters
    params = interpolate_params(precondition, type_def, state)

    # 3. Evaluate based on type
    SWITCH precondition.type:
        # Filesystem
        CASE "file_exists":
            RETURN file_exists(params.path)
        CASE "directory_exists":
            RETURN directory_exists(params.path)
        CASE "config_exists":
            RETURN file_exists("data/config.yaml")

        # State
        CASE "flag_set":
            RETURN state.flags[params.flag] == true
        CASE "flag_not_set":
            RETURN state.flags[params.flag] != true
        CASE "state_equals":
            RETURN get_nested(state, params.field) == params.value
        CASE "state_not_null":
            RETURN get_nested(state, params.field) != null
        CASE "state_is_null":
            RETURN get_nested(state, params.field) == null

        # Composite
        CASE "all_of":
            FOR each cond IN params.conditions:
                IF NOT evaluate_precondition(cond, types, state):
                    RETURN false
            RETURN true
        CASE "any_of":
            FOR each cond IN params.conditions:
                IF evaluate_precondition(cond, types, state):
                    RETURN true
            RETURN false
        CASE "none_of":
            FOR each cond IN params.conditions:
                IF evaluate_precondition(cond, types, state):
                    RETURN false
            RETURN true

        # Expression
        CASE "evaluate_expression":
            RETURN evaluate_expression(params.expression, state)

        # Tool
        CASE "tool_available":
            RETURN check_tool_available(params.tool)

        DEFAULT:
            # Fall back to type definition evaluation
            RETURN evaluate_from_definition(type_def, params, state)
```

---

## State Management

### State Structure

```yaml
# Runtime state maintained by executor
state:
  # Identity (from workflow)
  workflow_name: "add-source"
  workflow_version: "1.0.0"

  # Position (execution tracking)
  current_node: "ask_source_type"
  previous_node: "check_url_provided"

  # Runtime detection
  interface: "claude_code"  # or "claude_ai"

  # Execution history
  history:
    - node: "locate_corpus"
      outcome: { success: true }
      timestamp: "2026-01-27T10:30:00Z"
    - node: "check_url_provided"
      outcome: { branch: "false" }
      timestamp: "2026-01-27T10:30:01Z"

  # User interaction results
  user_responses:
    ask_source_type:
      handler_id: "git"
      raw: { selected: "Git repository" }
    collect_git_url:
      handler_id: "other"
      raw: { text: "https://github.com/pola-rs/polars" }

  # Computed values from consequences
  computed:
    config:
      schema_version: 2
      corpus:
        name: "polars"
      sources: []
    source_id: "polars"
    repo_url: "https://github.com/pola-rs/polars"
    sha: "abc123def456"
    files_count: 42

  # Boolean routing flags
  flags:
    config_found: true
    manifest_detected: false
    is_first_source: true
    clone_succeeded: true

  # Rollback snapshots
  checkpoints:
    before_clone:
      # Full state snapshot at checkpoint creation
      current_node: "execute_clone"
      flags: { ... }
      computed: { ... }

  # Custom fields from initial_state
  phase: "setup"
  source_type: "git"
  source_url: "https://github.com/pola-rs/polars"
```

### Field Reference

#### Identity Fields

| Field | Type | Description |
|-------|------|-------------|
| `workflow_name` | string | Name from workflow.yaml |
| `workflow_version` | string | Version from workflow.yaml |

#### Position Fields

| Field | Type | Description |
|-------|------|-------------|
| `current_node` | string | Node currently being executed |
| `previous_node` | string | Last executed node |

#### Runtime Fields

| Field | Type | Description |
|-------|------|-------------|
| `interface` | string | Detected interface: `"claude_code"` or `"claude_ai"` |

#### History

Array of executed node records:

```yaml
history:
  - node: "locate_corpus"           # Node name
    outcome:                        # Execution result
      success: true                 # For action nodes
      # OR
      branch: "true"                # For conditional nodes
      # OR
      response: "git"               # For user_prompt nodes
    timestamp: "2026-01-27T10:30:00Z"
```

**Use cases:**
- Debugging execution path
- Detecting loops
- Audit trail

#### User Responses

Results from user_prompt nodes, keyed by node name:

```yaml
user_responses:
  ask_source_type:
    handler_id: "git"               # Option id selected
    raw:                            # Raw AskUserQuestion response
      selected: "Git repository"
  collect_git_url:
    handler_id: "other"             # "other" for custom input
    raw:
      text: "https://github.com/..."
```

**Accessing in expressions:**
```yaml
expression: "user_responses.ask_source_type.handler_id == 'git'"
```

#### Computed Values

Results from action consequences, organized hierarchically:

```yaml
computed:
  # From read_config
  config:
    schema_version: 2
    corpus: { name: "polars" }
    sources: []

  # From compute/evaluate
  source_id: "polars"
  repo_name: "polars"
  repo_owner: "pola-rs"

  # From web_fetch
  manifest_check:
    status: 200
    content: "# Polars\n..."
    url: "https://..."

  # From get_sha
  sha: "abc123def456"

  # Nested structures
  source_config:
    type: "git"
    branch: "main"
    docs_root: "docs"
```

**Accessing in expressions:**
```yaml
expression: "computed.config.sources.length == 0"
value: "${computed.source_id}"
```

#### Flags

Boolean values for routing decisions:

```yaml
flags:
  config_found: true
  manifest_detected: false
  is_first_source: true
  clone_succeeded: true
  user_confirmed: false
```

**Setting flags:**
```yaml
- type: set_flag
  flag: manifest_detected
  value: true

- type: evaluate
  expression: "len(computed.config.sources) == 0"
  set_flag: is_first_source
```

**Checking flags:**
```yaml
condition:
  type: flag_set
  flag: manifest_detected
```

#### Checkpoints

State snapshots for rollback:

```yaml
checkpoints:
  before_clone:
    current_node: "execute_clone"
    previous_node: "collect_git_details"
    flags:
      config_found: true
      manifest_detected: false
    computed:
      config: { ... }
      source_id: "polars"
    # ... full state copy
```

**Creating:**
```yaml
- type: create_checkpoint
  name: "before_clone"
```

**Restoring:**
```yaml
- type: rollback_checkpoint
  name: "before_clone"
```

### State Access Patterns

**Dot notation** for nested fields:
```yaml
field: computed.config.corpus.name
```

**Array access** with brackets:
```yaml
field: computed.config.sources[0].id
field: history[-1].node  # Last entry
```

**Variable interpolation** with `${...}`:
```yaml
path: ".source/${computed.source_id}/docs"
message: "Found ${computed.files_count} files in ${source_type} source"
```

### Variable Interpolation Functions

```
FUNCTION interpolate(template, state):
    # Replace ${...} patterns with values from state
    RETURN template.replace(/\$\{([^}]+)\}/g, (match, path) => {
        RETURN resolve_path(path, state)
    })

FUNCTION resolve_path(path, state):
    # Resolution order:
    # 1. computed.{name}
    # 2. flags.{name}
    # 3. user_responses.{name}
    # 4. top-level state.{field}

    IF path.startsWith("computed."):
        RETURN get_nested(state.computed, path.substring(9))
    IF path.startsWith("flags."):
        RETURN state.flags[path.substring(6)]
    IF path.startsWith("user_responses."):
        RETURN get_nested(state.user_responses, path.substring(15))
    RETURN get_nested(state, path)
```

### Checkpoint Operations

```
FUNCTION create_checkpoint(name, state):
    state.checkpoints[name] = deep_copy(state)

FUNCTION rollback_checkpoint(name, state):
    IF name NOT IN state.checkpoints:
        THROW "Checkpoint not found: {name}"

    checkpoint = state.checkpoints[name]

    # Restore all state except checkpoints themselves
    state.current_node = checkpoint.current_node
    state.previous_node = checkpoint.previous_node
    state.computed = checkpoint.computed
    state.flags = checkpoint.flags
    state.user_responses = checkpoint.user_responses
    state.history = checkpoint.history
    # ... other fields
```

### State Lifecycle

**Initialization:**
```
1. Load workflow.yaml
2. Create empty state structure
3. Copy workflow.initial_state fields
4. Copy workflow.initial_state.flags
5. Set current_node = workflow.start_node
6. Detect interface
```

**During Execution:**
```
For each node:
1. Execute node (may modify computed, flags, user_responses)
2. Append to history
3. Update previous_node, current_node
```

**On Error:**
```
If action fails:
1. State may be partially modified
2. If checkpoint exists, can rollback
3. Route to on_failure node
```

**On Completion:**
```
When ending reached:
1. State is final
2. History contains full execution path
3. Summary can reference final computed values
```

### State Persistence

State exists in conversation context and persists across turns:

**Turn 1:**
```
User invokes skill
→ Initialize state
→ Execute nodes until user_prompt
→ Present AskUserQuestion
→ State persists...
```

**Turn 2:**
```
User responds
→ Resume from user_prompt node
→ Store response in state.user_responses
→ Continue execution
→ State persists...
```

**Turn N:**
```
Workflow reaches ending
→ Display result
→ State complete
```

---

## Interface Detection

```
FUNCTION detect_interface():
    # Claude Code: AskUserQuestion tool is available
    # Claude.ai: No tool access, conversational mode
    IF tool_available("AskUserQuestion"):
        RETURN "claude_code"
    ELSE:
        RETURN "claude_ai"
```

**Interface capabilities:**

| Interface | Structured Prompts | Freetext Input | Multi-select |
|-----------|-------------------|----------------|--------------|
| Claude Code | AskUserQuestion tool | Via "Other" option | Supported |
| Claude.ai | Markdown table | Chat field | Single response |

---

## Skill Composition

### invoke_skill (Isolated Execution)

Used for calling another skill with state isolation:

```
FUNCTION invoke_skill(skill_path, input_params, output_mapping, state):
    # Create isolated state for child skill
    child_state = {
        # Only copy input parameters
        ...input_params
    }

    # Load and execute child workflow
    child_workflow = load_workflow(skill_path)
    child_result = execute_workflow(child_workflow, child_state)

    # Map outputs back to parent state
    FOR each output IN output_mapping:
        parent_field = output.to
        child_field = output.from
        value = get_nested(child_result.state, child_field)
        set_nested(state, parent_field, value)

    RETURN child_result
```

### Reference Node (Shared State)

In contrast, reference nodes SHARE state with the parent workflow:

```
FUNCTION execute_reference_node(node, state):
    # Same state object, context variables just added
    doc = read_file(node.doc)
    context = interpolate_context(node.context, state)

    # Document can read and write to state directly
    execute_document(doc, context, state)
```

| Composition Type | State Handling | Use Case |
|------------------|----------------|----------|
| `invoke_skill` | Isolated | Reusable skills, clean boundaries |
| `reference` | Shared | Pattern libraries, documentation |

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

### Partial State Warning

Without checkpoints, failed actions may leave partial state:

```yaml
# If clone succeeds but get_sha fails:
actions:
  - type: clone_repo        # ✓ Succeeded (directory created)
    dest: ".source/polars"
  - type: get_sha           # ✗ Failed
    store_as: computed.sha
  - type: add_source        # Skipped
    spec: {...}
```

**Recovery options:**
1. Manual cleanup
2. Retry from beginning
3. Use checkpoints in workflow design (recommended)

---

## Validation Rules

### Structural Validation

| Rule | Error |
|------|-------|
| `name` must match skill directory | "Workflow name mismatch" |
| `start_node` must exist in `nodes` | "Start node not found" |
| All `on_success`/`on_failure` must exist | "Invalid transition target" |
| All `branches` targets must exist | "Invalid branch target" |
| All `next_node` must exist | "Invalid next_node target" |
| `on_response` must cover all option ids | "Missing response handler" |

### Runtime Validation

| Rule | Error |
|------|-------|
| Entry preconditions must pass | "Entry gate failed: {message}" |
| Precondition types must be known | "Unknown precondition type" |
| Consequence types must be known | "Unknown consequence type" |
| Variable references must resolve | "Unresolved variable: ${name}" |

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
  interface: claude_code
  flags:
    config_found: true
    manifest_detected: false
    is_first_source: true
  computed:
    config: { sources: [] }
  history:
    - { node: locate_corpus, outcome: { success: true } }
    - { node: check_url_provided, outcome: { branch: false } }
```

---

## Related Documentation

- **Type Loader:** `lib/workflow/type-loader.md` - Type resolution protocol
- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - External type sources
- **Type Definitions:** `lib/consequences/definitions/` and `lib/preconditions/definitions/`
- **JSON Schema:** `lib/schema/workflow-schema.json` - Formal schema definition
