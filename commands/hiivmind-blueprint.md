---
name: hiivmind-blueprint
description: >
  Unified entry point for hiivmind-blueprint operations - describe what you need
  in natural language or select from the menu. Converts prose-based skills to
  deterministic YAML workflows.
arguments:
  - name: request
    description: What you want to do (optional - shows menu if omitted)
    required: false
---

# hiivmind-blueprint Gateway

Execute this workflow for intelligent routing to the appropriate skill.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/workflow.yaml`
> **Intent Mapping:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/intent-mapping.yaml`

---

## Usage

```
/hiivmind-blueprint                    # Show interactive menu
/hiivmind-blueprint [request]          # Route by natural language intent
```

## Quick Examples

- `/hiivmind-blueprint init` → Initialize blueprint project
- `/hiivmind-blueprint discover` → Find skills to convert
- `/hiivmind-blueprint analyze my-skill` → Analyze a skill
- `/hiivmind-blueprint convert` → Convert skill to workflow
- `/hiivmind-blueprint generate` → Write workflow files
- `/hiivmind-blueprint gateway` → Generate gateway command
- `/hiivmind-blueprint upgrade` → Upgrade existing workflows
- `/hiivmind-blueprint visualize` → Generate Mermaid diagram

---

## Available Operations

### Initialize (`init`)

Set up a plugin for deterministic workflow conversion by copying required libraries and creating the directory structure.

**Trigger phrases:** "initialize", "init", "setup", "prepare", "copy libs"

### Discover (`discover`)

Scan a plugin for skills and report their conversion status (prose, workflow, or complex).

**Trigger phrases:** "discover", "find skills", "list skills", "show status", "what needs conversion"

### Analyze (`analyze`)

Perform deep analysis of a prose SKILL.md to extract phases, actions, conditionals, and state variables.

**Trigger phrases:** "analyze", "examine", "inspect", "understand", "breakdown"

### Convert (`convert`)

Transform an analyzed skill into a deterministic workflow.yaml structure.

**Trigger phrases:** "convert", "transform", "translate", "make workflow"

### Generate (`generate`)

Write the workflow.yaml and thin loader SKILL.md to the skill directory.

**Trigger phrases:** "generate", "write", "output", "save", "create files"

### Gateway (`gateway`)

Create a gateway command with 3VL intent detection for routing user requests.

**Trigger phrases:** "gateway", "create command", "intent detection", "routing"

### Upgrade (`upgrade`)

Migrate existing workflow.yaml files to the latest schema version.

**Trigger phrases:** "upgrade", "migrate", "update schema", "fix deprecated"

### Visualize (`visualize`)

Generate Mermaid diagrams from workflow.yaml files for documentation and understanding.

**Trigger phrases:** "visualize", "diagram", "mermaid", "show flow", "graph", "flowchart"

---

## Intent Detection

This gateway uses 3VL (3-valued logic) intent detection:

| Value | Meaning | Example |
|-------|---------|---------|
| **T** (True) | Keyword matched | "init" → has_init: T |
| **F** (False) | Negative keyword matched | "don't init" → has_init: F |
| **U** (Unknown) | No match either way | (default state) |

---

## Execution Instructions

### Phase 1: Initialize

1. **Load workflow.yaml** from this command directory:
   Read: `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/workflow.yaml`

2. **Load intent-mapping.yaml**:
   Read: `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/intent-mapping.yaml`

3. **Initialize runtime state**:
   ```yaml
   workflow_name: hiivmind-blueprint-gateway
   current_node: check_arguments
   arguments: "${request}"
   intent: null
   flags:
     has_arguments: ${request != null}
   computed: {}
   ```

---

### Phase 2: Execution Loop

Execute nodes until an ending is reached:

```
LOOP:
  1. Get current node from workflow.nodes[current_node]

  2. Check for ending:
     - IF current_node is in workflow.endings:
       - Display ending.message
       - STOP

  3. Execute by node.type:

     ACTION (parse_intent):
     - Parse user input against intent_flags
     - Evaluate intent_rules in priority order
     - Store matches in computed.intent_matches
     - Route via on_success or on_failure

     CONDITIONAL (check_arguments, check_clear_winner):
     - Evaluate condition
     - Route via branches.true or branches.false

     USER_PROMPT (show_main_menu, show_disambiguation):
     - Present AskUserQuestion
     - Store response, route via handler

     DYNAMIC_ROUTE (execute_matched_intent):
     - Get action from computed.intent_matches.winner
     - Invoke corresponding skill

  4. Record in history and continue

UNTIL ending reached
```

---

## Reference Documentation

- **Workflow Engine:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`
- **Intent Composition:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/intent-composition.md`

---

## Related Skills

- Initialize: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
- Discover: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Analyze: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Generate: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
- Gateway: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-gateway/SKILL.md`
- Upgrade: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-upgrade/SKILL.md`
- Visualize: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-visualize/SKILL.md`
