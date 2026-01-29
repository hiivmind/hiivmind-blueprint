# hiivmind-blueprint

**Transform prose-based Claude Code skills into deterministic YAML workflows.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Schema Version](https://img.shields.io/badge/Schema-v2.2-green.svg)](https://github.com/hiivmind/hiivmind-blueprint-lib)

---

## Overview

**hiivmind-blueprint** is a meta-plugin for Claude Code that converts existing prose-based skills into declarative YAML workflows. Instead of relying on LLM interpretation of natural language instructions, workflows provide:

- **Predictable execution** - Same inputs produce same outputs
- **Testable behavior** - Validate workflow graph structure and state transitions
- **Analyzable logic** - Explicit branching, preconditions, and consequences
- **Upgradeable schemas** - Migrate workflows when the schema evolves

The core insight: Claude interprets the YAML workflow at runtime (LLM-native execution), but the workflow structure itself is deterministic and verifiable.

---

## Quick Start

### Installation

```bash
# Add the marketplace
/plugin marketplace add hiivmind/hiivmind-blueprint

# Install the plugin
/plugin install hiivmind-blueprint@hiivmind
```

Or use `/plugin` to browse and install interactively.

**Local development:**

```bash
# Clone for local development
git clone https://github.com/hiivmind/hiivmind-blueprint.git

# Add local path to settings (~/.claude/settings.json)
{
  "plugins": [
    "/path/to/hiivmind-blueprint"
  ]
}
```

### Basic Workflow

Convert an existing skill to a workflow:

```bash
# 1. Initialize blueprint support in your plugin
/hiivmind-blueprint init

# 2. Analyze an existing SKILL.md
/hiivmind-blueprint analyze skills/my-skill/SKILL.md

# 3. Convert analysis to workflow.yaml
/hiivmind-blueprint convert

# 4. Generate files to destination
/hiivmind-blueprint generate

# 5. Validate the generated workflow
/hiivmind-blueprint validate skills/my-skill/workflow.yaml
```

Or use the gateway for natural language:

```
/hiivmind-blueprint convert my-skill to workflow format
/hiivmind-blueprint what skills need conversion?
```

---

## Core Skills

| Skill | Purpose |
|-------|---------|
| **init** | Initialize plugin for workflow support (creates `.hiivmind/blueprint/`) |
| **analyze** | Deep analysis of SKILL.md structure (phases, conditionals, state) |
| **convert** | Transform analysis into workflow.yaml |
| **generate** | Write thin loader + workflow.yaml to skill directory |
| **gateway** | Generate gateway command for multi-skill plugins (3VL intent detection) |
| **discover** | Find skills in plugin, show conversion status |
| **validate** | Validate workflow.yaml (schema, references, graph structure) |
| **upgrade** | Update existing workflows to latest schema version |

### Skill Lifecycle

```
         /hiivmind-blueprint (gateway)
                    │
        hiivmind-blueprint-discover ← shows conversion status
                    │
                    ▼
init → analyze → convert → generate → validate
(once)     │         │          │          │
           │         │          │          └── Check correctness
           │         │          └── Write files
           │         └── Create workflow.yaml
           └── Extract structure from prose
```

---

## Architecture

### Workflow Execution Model

Workflows are **LLM-native**: Claude reads the YAML and executes it step-by-step, maintaining state in conversation context. There's no compilation step—the workflow is interpreted at runtime.

```yaml
# workflow.yaml structure
name: "my-skill"
version: "1.0.0"

definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

initial_state:
  phase: "start"
  flags:
    initialized: false
  computed: {}

start_node: validate_input

nodes:
  validate_input:
    type: action
    actions:
      - type: file_exists
        path: "${computed.target_path}"
    on_success: process_file
    on_failure: error_missing_file

endings:
  success:
    type: success
    message: "Operation completed"
```

### Node Types

| Type | Purpose | Example Use |
|------|---------|-------------|
| `action` | Execute tool calls, record consequences | Read file, run command |
| `conditional` | Branch based on state or preconditions | Check if flag set |
| `user_prompt` | Get user input via AskUserQuestion | Select option, confirm action |
| `reference` | Include another workflow | Reuse intent detection |

> Note: `validation_gate` is deprecated in v2.0. Use `conditional` with `audit: { enabled: true }` instead.

### State Interpolation

Workflows use `${...}` syntax for runtime interpolation:

| Namespace | Source | Example |
|-----------|--------|---------|
| `${computed.*}` | Calculated values from actions | `${computed.file_count}` |
| `${flags.*}` | Boolean flags | `${flags.initialized}` |
| `${user_responses.*}` | User input | `${user_responses.selected_option}` |
| `${arguments}` | Raw skill arguments | `${arguments}` |

---

## External Type Definitions

Consequences and preconditions are defined in a separate versioned library:

**Repository:** [hiivmind/hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib)

### Type Inventory

| Category | Count | Examples |
|----------|-------|----------|
| Consequences | 44 | `set_state`, `clone_repo`, `web_fetch`, `parse_intent_flags` |
| Preconditions | 32 | `file_exists`, `flag_set`, `all_of`, `evaluate_expression` |
| Workflows | 1 | `intent-detection` (reusable 3VL routing) |
| Node Types | 5 | `action`, `conditional`, `user_prompt`, `reference`, `validation_gate` |

### Version Pinning

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0  # Exact version
  # source: hiivmind/hiivmind-blueprint-lib@v2.0  # Latest patch
  # source: hiivmind/hiivmind-blueprint-lib@v2    # Latest minor
```

---

## Plugin Structure

When generating workflows, Blueprint creates this structure:

```
{your_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── logging.yaml      # Plugin-wide logging defaults
│       └── display.yaml      # Plugin-wide display settings
├── skills/
│   └── my-skill/
│       ├── SKILL.md          # Thin loader (links to workflow)
│       └── workflow.yaml     # The actual workflow
└── commands/
    └── my-plugin/            # Gateway command (for multi-skill plugins)
        ├── my-plugin.md
        ├── workflow.yaml
        └── intent-mapping.yaml
```

### Thin Loader Pattern

Generated SKILL.md files are minimal—they reference the workflow and execution semantics from the lib:

```markdown
---
name: my-skill
description: Does something useful
allowed-tools: Read, Edit, Bash
---

# My Skill

Execute this workflow deterministically.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/my-skill/workflow.yaml`

## Execution Reference

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/execution/state.yaml) |
```

---

## Key Patterns

### 3VL Intent Detection

Gateway commands use three-valued logic for O(1) skill routing:

```yaml
# intent-mapping.yaml
skills:
  - id: analyze
    triggers: ["analyze", "examine", "inspect"]
    flags: [analyze]
  - id: convert
    triggers: ["convert", "transform", "generate workflow"]
    flags: [convert]

intent_rules:
  - rule: [analyze]
    target: hiivmind-blueprint-analyze
  - rule: [convert]
    target: hiivmind-blueprint-convert
```

Instead of O(N) LLM calls to match skills, parse flags once and route in constant time.

### Dynamic Routing

Workflows support dynamic `next_node` via state interpolation:

```yaml
execute_skill:
  type: reference
  workflow: "${computed.target_skill}"
  next_node: finalize
```

### 4-Tier Configuration Hierarchy

Logging, display, and prompts follow a priority hierarchy:

```
1. Runtime flags (--log-level=debug)        ← Highest
2. Workflow initial_state.logging           ← Skill-specific
3. Plugin .hiivmind/blueprint/logging.yaml  ← Plugin-wide
4. Remote defaults from lib                 ← Framework defaults
```

### Safety Endings

All workflows should include a safety ending for Claude's built-in harm detection:

```yaml
endings:
  error_safety:
    type: error
    category: safety
    message: "I can't help with that request."
    recovery:
      suggestion: "Please rephrase your request."
```

---

## Validation

### Schema Validation

Use `check-jsonschema` to validate against JSON Schema:

```bash
LIB_SCHEMA="file:///path/to/hiivmind-blueprint-lib/schema/"
SCHEMA_DIR="/path/to/hiivmind-blueprint-lib/schema"

# Validate workflow
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  skills/my-skill/workflow.yaml

# Validate intent mapping
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/intent-mapping.json" \
  commands/my-plugin/intent-mapping.yaml
```

### Graph Validation

The `validate` skill checks:

- All nodes reachable from start
- All paths lead to endings
- No orphan nodes
- Valid type references
- Correct state interpolation

---

## Documentation

| Document | Location | Purpose |
|----------|----------|---------|
| Execution Reference | `lib/workflow/engine.md` | Complete workflow execution semantics |
| Type Loader | `lib/workflow/type-loader.md` | External definition resolution |
| Workflow Loader | `lib/workflow/workflow-loader.md` | Remote workflow resolution |
| Logging Config | `lib/workflow/logging-config-loader.md` | 4-tier logging hierarchy |
| Display Config | `lib/workflow/display-config-loader.md` | Terminal output configuration |
| Prompts Config | `lib/workflow/prompts-config-loader.md` | User input modes |

### Patterns

| Pattern | Location | Purpose |
|---------|----------|---------|
| Skill Analysis | `lib/blueprint/patterns/skill-analysis.md` | How to analyze SKILL.md |
| Node Mapping | `lib/blueprint/patterns/node-mapping.md` | Prose → workflow nodes |
| Intent Composition | `lib/blueprint/patterns/intent-composition.md` | 3VL intent detection |
| Plugin Structure | `lib/blueprint/patterns/plugin-structure.md` | Generated plugin layout |

---

## Self-Dogfooding

This plugin uses its own patterns:

- The `/hiivmind-blueprint` gateway command has its own `workflow.yaml` + `intent-mapping.yaml`
- Each skill follows the thin loader pattern it generates
- The gateway uses 3VL intent detection to route requests

```
commands/hiivmind-blueprint/
├── workflow.yaml              # Gateway workflow
└── intent-mapping.yaml        # 3VL skill routing
```

---

## License

MIT
