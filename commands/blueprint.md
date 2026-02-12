---
name: blueprint
description: >
  Unified entry point for hiivmind-blueprint operations - describe what you need
  in natural language or select from the menu. Authoring tools for converting prose-based
  skills to deterministic YAML workflows.
arguments:
  - name: request
    description: What you want to do (optional - shows menu if omitted)
    required: false
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

## Initial State - Paths

``` yaml
- paths:
  workflow_path: '${CLAUDE_PLUGIN_ROOT}/commands/blueprint/workflow.yaml'
  intent_mapping_path: '${CLAUDE_PLUGIN_ROOT}/commands/blueprint/intent-mapping.yaml'
```

---

## Usage

```
/blueprint                    # Show interactive menu
/blueprint [request]          # Route by natural language intent
/blueprint --help             # Show full help
/blueprint [flags] [request]  # With runtime flags
```

---

## Runtime Flags

Flags modify workflow execution. Per-invocation only (reset for each command).

| Flag | Effect |
|------|--------|
| `--verbose`, `-v` | Show all node details (level: verbose) |
| `--quiet`, `-q` | Only prompts and final result (level: quiet) |
| `--debug` | Full state dumps (level: debug) |
| `--no-log` | Disable file logging |
| `--no-display` | Silent mode (no terminal output) |
| `--ci` | CI mode: GitHub annotations |

---

## Help Commands

| Command | Description |
|---------|-------------|
| `/blueprint --help` | Show full command reference |
| `/blueprint -h` | Short form of --help |
| `/blueprint help` | Same as --help |
| `/blueprint help [skill]` | Help for specific skill |

### Configuration Help

| Command | Description |
|---------|-------------|
| `/blueprint help output` | Output levels and configuration |
| `/blueprint help prompts` | Prompt modes and match strategies |
| `/blueprint help flags` | Quick reference for runtime flags |

---

## Available Skills

### Skill Operations

| Skill | Purpose |
|-------|---------|
| **skill-create** | Create a new skill from scratch |
| **skill-analyze** | Analyze a workflow.yaml structure and quality |
| **skill-validate** | Validate a workflow.yaml for errors |
| **skill-refactor** | Refactor or restructure a workflow |
| **skill-upgrade** | Upgrade workflow schema version |
| **visualize** | Generate Mermaid diagram from workflow |

### Prose Conversion

| Skill | Purpose |
|-------|---------|
| **prose-analyze** | Analyze a prose SKILL.md before conversion |
| **prose-migrate** | Convert a prose SKILL.md to workflow.yaml |

### Gateway & Intent

| Skill | Purpose |
|-------|---------|
| **gateway-create** | Create a gateway command for multi-skill plugins |
| **gateway-validate** | Validate gateway routing and structure |
| **intent-create** | Create intent-mapping.yaml for a gateway |
| **intent-validate** | Validate intent mapping rules |

### Plugin Management

| Skill | Purpose |
|-------|---------|
| **plugin-discover** | Discover and inventory skills in a plugin |
| **plugin-analyze** | Analyze plugin health and cross-skill metrics |
| **plugin-batch** | Run operations across all skills in a plugin |

---

## Execution Protocol

**MANDATORY:** This gateway requires loading and following execution semantics from remote sources.

**See:** `.hiivmind/blueprint/engine_entrypoint.md` (Engine v1.0.0) for full protocol.

### Quick Summary

1. **Bootstrap:** Extract version from workflow.yaml
2. **Fetch Semantics:** Load execution rules from hiivmind-blueprint-lib
3. **Load Local Files:** Read workflow.yaml + intent-mapping.yaml
4. **Execute:** Run workflow per traversal semantics (initialize -> execute -> complete)
- When `invoke_skill` consequence fires: Use Skill tool to invoke matched skill


**Verification Checkpoint:**
Before proceeding to Phase 3, verify:
- `_semantics.bootstrap.phases` has 5 items ending with "execute"
- `_semantics.bootstrap.required_sections` has exactly 4 items
- `_semantics.traversal.phases` equals `["initialize", "execute", "complete"]`

If verification fails, retry fetch.

---


## Intent Detection

This gateway uses 3VL (3-valued logic) intent detection with **two-axis matching**:

| Value | Meaning | Example |
|-------|---------|---------|
| **T** (True) | Keyword matched | "create gateway" -> has_gateway: T, has_create: T |
| **F** (False) | Negative keyword matched | "not prose" -> has_prose: F |
| **U** (Unknown) | No match either way | (default state) |

### Two-Axis Resolution

Intent flags are split into **target** (what to operate on) and **action** (what to do):

- **Target flags:** `has_gateway`, `has_intent`, `has_plugin`, `has_prose`, `has_workflow`
- **Action flags:** `has_create`, `has_validate`, `has_analyze`, `has_migrate`, `has_upgrade`, `has_refactor`, `has_discover`, `has_batch`, `has_visualize`

Compound rules (target + action) have higher priority than single-action rules.

### How Intent Resolution Works

1. **Parse input** against flag keywords -> `computed.intent_flags`
2. **Match rules** in priority order -> `computed.intent_matches`
3. **Check for clear winner** (2+ point lead)
4. **Dynamic route** to `${computed.matched_action}` -> skill execution

This gateway uses O(1) dynamic routing instead of N conditional nodes.

If no clear winner, disambiguation is offered.

---

## Skill Dispatch Protocol

**CRITICAL:** Gateways are ROUTERS, not executors. When a skill is matched:

1. **DO NOT answer the user's request yourself** - Your job is routing, not answering
2. **DO NOT pre-validate or gather information** - Let the skill handle its own context
3. **IMMEDIATELY invoke the skill** using the Skill tool:

```
Skill(
  skill: "${computed.matched_skill}",
  args: "${arguments}"
)
```

4. **Let the skill take over** - It will load its own SKILL.md and execute its workflow

**Example:** If intent matches "convert prose", invoke `bp-prose-migrate`. Do not convert the skill yourself.

---

## Quick Examples

- `/blueprint create a new skill` -> Routes to bp-skill-create
- `/blueprint analyze this workflow` -> Routes to bp-skill-analyze
- `/blueprint convert prose to workflow` -> Routes to bp-prose-migrate
- `/blueprint validate gateway` -> Routes to bp-gateway-validate
- `/blueprint discover skills in plugin` -> Routes to bp-plugin-discover
- `/blueprint visualize` -> Routes to bp-visualize
- `/blueprint` -> Shows interactive menu

---

## Related Skills

- Skill creation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-create/SKILL.md`
- Workflow analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-analyze/SKILL.md`
- Workflow validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/SKILL.md`
- Workflow refactoring: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-refactor/SKILL.md`
- Workflow upgrade: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-upgrade/SKILL.md`
- Visualization: `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
- Prose analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-prose-analyze/SKILL.md`
- Prose migration: `${CLAUDE_PLUGIN_ROOT}/skills/bp-prose-migrate/SKILL.md`
- Gateway creation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-gateway-create/SKILL.md`
- Gateway validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-gateway-validate/SKILL.md`
- Intent creation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-intent-create/SKILL.md`
- Intent validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-intent-validate/SKILL.md`
- Plugin discovery: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-discover/SKILL.md`
- Plugin analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-analyze/SKILL.md`
- Batch operations: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-batch/SKILL.md`
