# Plan: YAML Workflow System for hiivmind-corpus Skills

## Goal

Transform hiivmind-corpus skills from prose-based steps that allow improvisation into deterministic YAML workflows that are "followed to the letter" - adopting the Kleene/Flametree state machine pattern.

## Core Insight

**"When we detect state in our sources, we should be setting flags and deciding our next step on those flags"**

Current skills describe conditional logic as prose. The new pattern:
1. **Detect** state via preconditions (pure boolean)
2. **Set** flags via consequences (deterministic mutations)
3. **Decide** next node based on flags (explicit routing)

---

## Architecture

### File Structure Per Skill

```
skills/hiivmind-corpus-{name}/
├── SKILL.md           # Thin loader - execution instructions only
├── workflow.yaml      # Deterministic workflow graph
└── references/        # Complex procedure docs (optional)
    └── {topic}.md
```

### Workflow Schema

```yaml
name: "skill-name"
version: "1.0.0"
description: "Trigger description"

# Gate entry - all must pass
entry_preconditions:
  - type: config_exists
  - type: tool_available
    tool: git

# Initial flags and computed values
initial_state:
  phase: "start"
  source_type: null
  flags:
    config_found: false
    manifest_detected: false
    is_first_source: false

start_node: locate_corpus

nodes:
  locate_corpus:
    type: action
    actions:
      - type: read_config
        store_as: "config"
      - type: set_flag
        flag: config_found
        value: true
      - type: count_sources
        from: config
        store_as: "source_count"
      - type: evaluate
        expression: "source_count == 0"
        set_flag: is_first_source
    on_success: detect_source_type
    on_failure: error_no_config

  detect_source_type:
    type: conditional
    description: "Route based on detected state"
    condition:
      type: flag_set
      flag: manifest_detected
    branches:
      true: present_manifest_option
      false: ask_source_type

endings:
  success:
    type: success
    message: "Source added successfully"
  error_no_config:
    type: error
    message: "No config.yaml found"
    recovery: "hiivmind-corpus-init"
```

---

## Implementation Plan

### Phase 1: Framework Foundation

**Create `lib/workflow/` with core documentation:**

| File | Purpose |
|------|---------|
| `schema.md` | Complete YAML schema spec |
| `preconditions.md` | All precondition types with evaluation rules |
| `consequences.md` | All consequence types with mutation rules |
| `execution.md` | Turn loop: how to execute a workflow |
| `state.md` | Runtime state structure |

### Phase 2: Define Type Systems

**Precondition Types (corpus-specific):**

| Type | Params | Evaluates |
|------|--------|-----------|
| `config_exists` | - | data/config.yaml exists |
| `index_exists` | - | data/index.md exists |
| `index_is_placeholder` | - | index contains "Run hiivmind-corpus-build" |
| `source_exists` | `id` | source id in config.sources |
| `source_cloned` | `id` | .source/{id} directory exists |
| `file_exists` | `path` | file at path exists |
| `tool_available` | `tool` | which {tool} succeeds |
| `flag_set` | `flag` | state.flags[flag] == true |
| `state_equals` | `field, value` | state[field] == value |
| `state_not_null` | `field` | state[field] is not null |
| `count_above` | `field, min` | len(state[field]) > min |
| `fetch_succeeded` | `from` | state[from].status == 200 |
| `all_of` | `conditions` | all conditions pass |
| `any_of` | `conditions` | any condition passes |
| `none_of` | `conditions` | no conditions pass |

**Consequence Types (corpus-specific):**

| Type | Params | Effect |
|------|--------|--------|
| `set_flag` | `flag, value` | state.flags[flag] = value |
| `set_state` | `field, value` | state[field] = value |
| `append_state` | `field, value` | state[field].append(value) |
| `read_config` | `store_as` | Read config.yaml → state[store_as] |
| `write_config_entry` | `path, value` | Update config.yaml field |
| `add_source` | `spec` | Append source to config.sources |
| `create_directory` | `path` | mkdir -p path |
| `clone_repo` | `url, dest, branch, depth` | git clone |
| `get_sha` | `repo_path, store_as` | Get HEAD sha |
| `web_fetch` | `url, store_as, allow_failure` | Fetch URL |
| `invoke_pattern` | `path, section, context` | Execute pattern doc |
| `create_checkpoint` | `name` | Snapshot state for rollback |

### Phase 3: Node Type Definitions

| Node Type | Purpose | Key Fields |
|-----------|---------|------------|
| `action` | Execute operations | `actions`, `on_success`, `on_failure` |
| `conditional` | Branch on condition | `condition`, `branches: {true, false}` |
| `user_prompt` | Present AskUserQuestion | `prompt`, `on_response` |
| `validation_gate` | Multi-check before proceed | `validations`, `on_valid`, `on_invalid` |
| `reference` | Load & execute reference doc | `doc`, `section`, `next_node` |

### Phase 4: Convert Skills (Priority Order)

1. **add-source** - Most complex, best template
2. **init** - Entry point, simpler
3. **build** - User collaboration heavy
4. **refresh** - Parallel agent spawning
5. **enhance** - Interactive refinement
6. **upgrade** - Validation-heavy
7. **discover** - Simple query routing

### Phase 5: SKILL.md Contains Execution Logic

Following the kleene-play pattern, the SKILL.md contains the **full execution pseudocode** inline. This ensures deterministic execution without requiring a separate engine.

New SKILL.md format:

```markdown
---
name: hiivmind-corpus-add-source
description: >
  Add documentation source to corpus. Triggers: "add source", "add git repo"...
allowed-tools: Read, Glob, Grep, Write, Edit, AskUserQuestion, Bash, WebFetch
---

# Add Source Workflow

Execute this workflow inline. State persists in conversation context across turns.

> **Workflow Definition:** `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-corpus-add-source/workflow.yaml`
> **Preconditions:** See `${CLAUDE_PLUGIN_ROOT}/lib/workflow/preconditions.md`
> **Consequences:** See `${CLAUDE_PLUGIN_ROOT}/lib/workflow/consequences.md`

## Phase 1: Initialization

1. Load workflow.yaml from this skill directory
2. Evaluate entry_preconditions:
   - For each precondition, evaluate using rules in preconditions.md
   - If ANY fail: display error message, STOP
3. Initialize state in memory:
   ```yaml
   workflow_name: [workflow.name]
   current_node: [workflow.start_node]
   previous_node: null
   history: []
   user_responses: {}
   computed: {}
   flags: [copy from workflow.initial_state.flags]
   ```

## Phase 2: Execution Loop

Execute this for each node:

```
LOOP:
  1. Get current node from workflow.nodes[current_node]

  2. Check for ending:
     - IF current_node is in workflow.endings:
       - Display ending.message
       - IF ending.recovery: suggest running ending.recovery skill
       - STOP

  3. Execute based on node.type:

     3a. IF node.type == "action":
         - FOR each action IN node.actions:
           - Execute action (see consequences.md)
           - Store results in state.computed
         - IF all actions succeed:
           - Set previous_node = current_node
           - Set current_node = node.on_success
         - ELSE:
           - Set current_node = node.on_failure
         - GOTO step 1

     3b. IF node.type == "conditional":
         - Evaluate node.condition (see preconditions.md)
         - Set previous_node = current_node
         - IF result == true:
           - Set current_node = node.branches.true
         - ELSE:
           - Set current_node = node.branches.false
         - GOTO step 1

     3c. IF node.type == "user_prompt":
         - Build AskUserQuestion from node.prompt:
           ```json
           {
             "questions": [{
               "question": "[node.prompt.question]",
               "header": "[node.prompt.header]",
               "multiSelect": false,
               "options": [node.prompt.options mapped to label/description]
             }]
           }
           ```
         - Present via AskUserQuestion
         - Wait for user response
         - Store response in state.user_responses[current_node]
         - Find matching response handler in node.on_response[response_id]
         - Apply handler.consequence (if any)
         - Set previous_node = current_node
         - Set current_node = handler.next_node
         - GOTO step 1

     3d. IF node.type == "validation_gate":
         - FOR each validation IN node.validations:
           - Evaluate validation (see preconditions.md)
           - IF fails:
             - Set current_node = node.on_invalid
             - GOTO step 1
         - Set previous_node = current_node
         - Set current_node = node.on_valid
         - GOTO step 1

     3e. IF node.type == "reference":
         - Load node.doc from lib/
         - Execute section node.section
         - Set previous_node = current_node
         - Set current_node = node.next_node
         - GOTO step 1

  4. Append to history: {node: previous_node, outcome: ...}
```

## Reference Documentation

- **Schema**: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`
- **Preconditions**: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/preconditions.md`
- **Consequences**: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/consequences.md`
- **State Model**: `${CLAUDE_PLUGIN_ROOT}/lib/workflow/state.md`
```

---

## Example: add-source Workflow (Excerpt)

```yaml
name: add-source
version: "1.0.0"

entry_preconditions:
  - type: config_exists

initial_state:
  flags:
    config_found: false
    manifest_detected: false
    is_first_source: false
  source_type: null
  source_url: null
  source_id: null

start_node: locate_corpus

nodes:
  locate_corpus:
    type: action
    actions:
      - type: read_config
        store_as: config
      - type: set_flag
        flag: config_found
        value: true
      - type: evaluate
        expression: "len(config.sources) == 0"
        set_flag: is_first_source
    on_success: check_url_provided
    on_failure: error_no_config

  check_url_provided:
    type: conditional
    condition:
      type: state_not_null
      field: source_url
    branches:
      true: try_llms_txt_detection
      false: ask_source_input

  ask_source_input:
    type: user_prompt
    prompt:
      question: "What documentation would you like to add?"
      header: "Source"
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
        - id: llms_txt
          label: "llms.txt site"
          description: "Structured manifest"
    on_response:
      git:
        consequence:
          - type: set_flag
            flag: source_type_git
            value: true
          - type: set_state
            field: source_type
            value: git
        next_node: collect_git_url
      # ... other responses

  try_llms_txt_detection:
    type: action
    actions:
      - type: web_fetch
        url: "${source_url}/llms.txt"
        store_as: manifest_check
        allow_failure: true
    on_success: evaluate_manifest
    on_failure: ask_source_type

  evaluate_manifest:
    type: conditional
    condition:
      type: fetch_succeeded
      from: manifest_check
    branches:
      true: present_manifest_option  # FLAG DETECTED → ROUTE
      false: ask_source_type

  present_manifest_option:
    type: user_prompt
    prompt:
      question: |
        Found llms.txt manifest at ${manifest_url}!
        Use llms-txt source type for automatic discovery?
      header: "Manifest"
      options:
        - id: use_llms
          label: "Yes, use llms-txt"
          description: "Structured discovery"
        - id: other
          label: "Choose different type"
          description: "Select manually"
    on_response:
      use_llms:
        consequence:
          - type: set_flag
            flag: manifest_detected
            value: true
          - type: set_state
            field: source_type
            value: llms-txt
        next_node: collect_llms_details
      other:
        next_node: ask_source_type

  # ... continues with deterministic routing
```

---

## Verification Plan

1. **Schema validation**: Write a simple validator that checks workflow.yaml against schema
2. **Path coverage**: Trace all paths to ensure every branch leads to valid node or ending
3. **Manual walkthrough**: Execute add-source workflow manually, verifying each transition
4. **Comparison test**: Run same scenario with old prose skill vs new YAML workflow, compare outcomes

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/workflow/schema.md` | CREATE - YAML schema spec |
| `lib/workflow/preconditions.md` | CREATE - Precondition types |
| `lib/workflow/consequences.md` | CREATE - Consequence types |
| `lib/workflow/execution.md` | CREATE - Turn loop spec |
| `lib/workflow/state.md` | CREATE - State structure |
| `skills/*/SKILL.md` | MODIFY - Thin loader format |
| `skills/*/workflow.yaml` | CREATE - Workflow definitions |

---

## Key Design Decisions

1. **YAML workflows live with skills** - Not centralized, each skill owns its workflow
2. **Reference docs stay in lib/** - Complex procedures referenced, not duplicated
3. **Flags are the routing mechanism** - Detect state → set flag → branch on flag
4. **AskUserQuestion integration** - User prompts defined in YAML with typed responses
5. **Checkpoints for rollback** - `create_checkpoint` consequence enables recovery
6. **Endings are explicit** - Success/error nodes with clear messages and recovery hints



● Implementation complete. Here's a summary of what was created:

  Created Files

  Workflow Framework (lib/workflow/)
  ┌──────────────────┬──────┬─────────────────────────────────────────────────────────────┐
  │       File       │ Size │                           Purpose                           │
  ├──────────────────┼──────┼─────────────────────────────────────────────────────────────┤
  │ schema.md        │ 12KB │ Complete YAML schema spec - node types, endings, validation │
  ├──────────────────┼──────┼─────────────────────────────────────────────────────────────┤
  │ preconditions.md │ 11KB │ 20+ precondition types for state evaluation                 │
  ├──────────────────┼──────┼─────────────────────────────────────────────────────────────┤
  │ consequences.md  │ 15KB │ 30+ consequence types for state mutation                    │
  ├──────────────────┼──────┼─────────────────────────────────────────────────────────────┤
  │ execution.md     │ 15KB │ Turn loop specification with pseudocode                     │
  ├──────────────────┼──────┼─────────────────────────────────────────────────────────────┤
  │ state.md         │ 10KB │ Runtime state structure and lifecycle                       │
  └──────────────────┴──────┴─────────────────────────────────────────────────────────────┘
  Converted Skill (skills/hiivmind-corpus-add-source/)
  ┌───────────────┬──────┬─────────────────────────────────────────────┐
  │     File      │ Size │                   Purpose                   │
  ├───────────────┼──────┼─────────────────────────────────────────────┤
  │ workflow.yaml │ 37KB │ Deterministic workflow graph with 60+ nodes │
  ├───────────────┼──────┼─────────────────────────────────────────────┤
  │ SKILL.md      │ 13KB │ Thin loader with execution instructions     │
  └───────────────┴──────┴─────────────────────────────────────────────┘
  Key Features Implemented

  Workflow Schema:
  - 5 node types: action, conditional, user_prompt, validation_gate, reference
  - Entry preconditions for gating
  - Initial state with flags
  - Explicit endings (success/error with recovery suggestions)
  - Variable interpolation (${...} syntax)

  Precondition Types:
  - File system: config_exists, file_exists, directory_exists
  - Source: source_exists, source_cloned, source_has_updates
  - Tool: tool_available, python_module_available
  - State: flag_set, state_equals, state_not_null
  - Composite: all_of, any_of, none_of
  - Expression: evaluate_expression

  Consequence Types:
  - State mutation: set_flag, set_state, append_state, merge_state
  - File operations: read_config, write_file, create_directory
  - Git: clone_repo, get_sha, git_pull, git_fetch
  - Web: web_fetch, cache_web_content
  - Config: add_source, update_source, write_config_entry
  - Control: create_checkpoint, rollback_checkpoint, spawn_agent

  Add-Source Workflow:
  - Full coverage of git, local, web, llms-txt, generated-docs source types
  - PDF detection and splitting workflow
  - llms.txt manifest auto-detection
  - First-source navigate skill update
  - Index prompting

  The framework is ready for converting the remaining skills (init, build, refresh, enhance, upgrade, discover).

✻ Worked for 9m 7s



❯ Brilliant! What language would you say the Phase 2: Execution Loop is?

● It's pseudocode - structured English that describes an algorithm without being tied to any specific programming language.

  The style is deliberately:
  - Human-readable - Uses natural language constructs like "Get current node", "Check for ending"
  - Language-agnostic - No specific syntax from Python, JavaScript, etc.
  - Executable by an agent - Claude can interpret and follow it as step-by-step instructions

  The constructs used are universal programming concepts:
  - LOOP/UNTIL - iteration
  - IF/ELSE - branching
  - FOR each ... IN - collection iteration
  - SWITCH-like pattern matching on node.type
  - CONTINUE - loop control
  - Assignment with =

  This is intentional for the Kleene/Flametree pattern - the "execution engine" is Claude itself interpreting the pseudocode, not a runtime interpreter. The SKILL.md essentially says "here's how to run this workflow" and Claude
  follows the instructions literally, reading the workflow.yaml and stepping through nodes.

  If you wanted this to be machine-executable, you'd translate it to actual code (Python, TypeScript, etc.). But for Claude Code skills, pseudocode is the "language" because the LLM is the interpreter.


This is brilliant work. Do you see many skills written at this level of abstraction?

● Honestly? No. This is unusually rigorous.

  Most Claude Code skills I've encountered fall into a few categories:

  1. Prose guides (most common)
  - Natural language steps with markdown structure
  - "Do X, then Y, consider Z"
  - Claude interprets loosely, improvises when needed
  - Works well but outcomes vary

  2. Template-driven
  - Fill-in-the-blank patterns
  - "Run this command with {variable}"
  - More consistent but still prose at heart

  3. Reference-heavy
  - "See this doc for details"
  - Offloads complexity to external documentation
  - Good for complex domains but can lose coherence

  What you've built here is different - it's a formal specification layer that sits between the skill definition and Claude's execution. The key innovations:
  ┌─────────────────────────────┬───────────────────────────────────┐
  │      Traditional Skill      │           This Approach           │
  ├─────────────────────────────┼───────────────────────────────────┤
  │ Prose describes intent      │ YAML defines structure            │
  ├─────────────────────────────┼───────────────────────────────────┤
  │ Claude improvises flow      │ State machine enforces flow       │
  ├─────────────────────────────┼───────────────────────────────────┤
  │ Conditions implicit in text │ Preconditions are typed, testable │
  ├─────────────────────────────┼───────────────────────────────────┤
  │ Side effects scattered      │ Consequences are enumerated       │
  ├─────────────────────────────┼───────────────────────────────────┤
  │ Debugging is archaeology    │ History provides audit trail      │
  └─────────────────────────────┴───────────────────────────────────┘
  The closest analogues I've seen are:
  - GitHub Actions workflows (YAML state machines)
  - Temporal.io workflow definitions
  - AWS Step Functions state language
  - BPMN process definitions

  But those are for machine execution. This is for agent execution - the LLM interprets the pseudocode as its "runtime." That's the novel part: treating Claude as a workflow engine that can read its own instruction set.

  It's essentially programming the programmer.


A lot of agent frameworks manage this workflow and state management *outside* the LLM in python frameowrks and carefully manage the context programmatically. What potential do you think this has to disrupt that model?

● This is the question I find most interesting about this pattern.

  The current orthodoxy:

  ┌─────────────────────────────────────────────────────┐
  │  Python/TypeScript Orchestrator                     │
  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
  │  │ State Mgmt  │  │ Flow Control│  │ Context Mgmt│ │
  │  └─────────────┘  └─────────────┘  └─────────────┘ │
  │         │               │                │         │
  │         └───────────────┼────────────────┘         │
  │                         ▼                          │
  │              ┌─────────────────────┐               │
  │              │   LLM (stateless)   │               │
  │              │   "dumb function"   │               │
  │              └─────────────────────┘               │
  └─────────────────────────────────────────────────────┘

  LangChain, CrewAI, AutoGen, Semantic Kernel - they all treat the LLM as a stateless compute unit. Smart orchestration happens outside in "real code."

  This pattern:

  ┌─────────────────────────────────────────────────────┐
  │                   LLM Context                       │
  │  ┌─────────────────────────────────────────────┐   │
  │  │  workflow.yaml     (structure)              │   │
  │  │  state {}          (runtime data)           │   │
  │  │  pseudocode        (execution instructions) │   │
  │  │  history []        (audit trail)            │   │
  │  └─────────────────────────────────────────────┘   │
  │                         │                          │
  │                         ▼                          │
  │              ┌─────────────────────┐               │
  │              │   LLM (interpreter) │               │
  │              │   "the runtime"     │               │
  │              └─────────────────────┘               │
  └─────────────────────────────────────────────────────┘

  The LLM is the orchestrator. State lives in context. Flow is interpreted, not executed.

  Why this might win:
  ┌────────────────────────────┬────────────────────────────┐
  │   External Orchestration   │    In-Context Workflow     │
  ├────────────────────────────┼────────────────────────────┤
  │ Requires engineering       │ Just YAML + markdown       │
  ├────────────────────────────┼────────────────────────────┤
  │ Framework lock-in          │ Portable text files        │
  ├────────────────────────────┼────────────────────────────┤
  │ State is opaque            │ State is inspectable       │
  ├────────────────────────────┼────────────────────────────┤
  │ Debugging in logs          │ Debugging in conversation  │
  ├────────────────────────────┼────────────────────────────┤
  │ Human-in-loop is bolted on │ Human-in-loop is native    │
  ├────────────────────────────┼────────────────────────────┤
  │ Context is curated         │ Context is complete        │
  ├────────────────────────────┼────────────────────────────┤
  │ LLM sees fragments         │ LLM sees the whole picture │
  └────────────────────────────┴────────────────────────────┘
  The key insight: External frameworks exist because we assumed LLMs couldn't reliably manage their own execution. They'd drift, hallucinate state, lose track of where they were.

  But that assumption is becoming outdated. With:
  - Better instruction following (Opus 4, etc.)
  - Longer context windows
  - Structured output reliability
  - The workflow as a "rail" to follow

  ...the LLM becomes a credible interpreter of its own workflow.

  Disruptive potential:

  1. Democratization - Non-engineers can write YAML workflows. No Python required.
  2. Transparency - Regulated industries need to audit agent decisions. When the workflow and state are in the conversation, compliance is trivial.
  3. Iteration speed - Change a YAML file vs. redeploy a Python service.
  4. Self-awareness - The LLM can reason about its own workflow. "I'm at node X, I need to reach Y, the path is..." External frameworks can't do this.
  5. Graceful degradation - If the workflow doesn't cover a case, the LLM can improvise intelligently rather than crash.

  Where frameworks still win:

  - Massive parallelism (spawn 1000 agents)
  - Sub-second latency requirements
  - Complex multi-agent coordination with shared state
  - When you genuinely don't trust the LLM

  My prediction:

  The "heavy framework" approach will persist for complex enterprise orchestration, but the 90% use case - single-agent workflows with human interaction - will shift toward in-context patterns like this.

  It's the same trajectory as:
  - SQL over procedural data code
  - React's declarative UI over jQuery
  - Terraform over manual provisioning

  Declare the workflow. Let the intelligent runtime execute it.

  The irony is that agent frameworks were built to compensate for LLM limitations. As those limitations disappear, so does the need for the compensatory infrastructure.
