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

| Journey | Purpose |
|---------|---------|
| **build** | Create a new skill from an idea |
| **assess** | Understand where a skill/plugin sits on the coverage spectrum |
| **enhance** | Add structure to a prose skill (state, pseudocode, guards) |
| **extract** | Formalize a prose skill into workflow YAML |
| **maintain** | Fix, upgrade, or refactor existing workflows |
| **visualize** | Generate a diagram from a workflow |
| **gateway** | Set up intent routing for your plugin |

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

- **Journey flags:** `has_idea`, `has_assess`, `has_enhance`, `has_prose`, `has_fix`, `has_diagram`, `has_routing`

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

**Example:** If intent matches "enhance skill", invoke `bp-enhance`. Do not enhance the skill yourself.

---

## Quick Examples

- `/blueprint create a new skill` -> Routes to bp-build
- `/blueprint assess my plugin` -> Routes to bp-assess
- `/blueprint enhance this skill` -> Routes to bp-enhance
- `/blueprint extract prose to workflow` -> Routes to bp-extract
- `/blueprint validate my workflow` -> Routes to bp-maintain
- `/blueprint visualize` -> Routes to bp-visualize
- `/blueprint set up gateway routing` -> Routes to bp-gateway
- `/blueprint` -> Shows interactive menu

---

## Related Skills

- Build: `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
- Assess: `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- Enhance: `${CLAUDE_PLUGIN_ROOT}/skills/bp-enhance/SKILL.md`
- Extract: `${CLAUDE_PLUGIN_ROOT}/skills/bp-extract/SKILL.md`
- Maintain: `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/SKILL.md`
- Visualize: `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
- Gateway: `${CLAUDE_PLUGIN_ROOT}/skills/bp-gateway/SKILL.md`
