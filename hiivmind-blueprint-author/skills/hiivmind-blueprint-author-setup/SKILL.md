---
name: hiivmind-blueprint-author-setup
description: >
  Initialize a plugin for workflow support. Use when setting up a new plugin or adding
  workflow infrastructure to an existing plugin. Triggers on "init blueprint", "setup workflows",
  "blueprint init", "initialize plugin", "add workflow support".
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# Setup Blueprint Infrastructure

Set up a plugin for deterministic workflow patterns by creating the engine entrypoint,
version configuration, and required directory structure.

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Install |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | `brew install jq` / `apt install jq` |
| `yq` | **Mandatory** | `command -v yq` | `brew install yq` / [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |

If mandatory tools are missing, exit with error listing the install commands above.

---

## Initial State - Paths

Detect and set path variables:

```pseudocode
workflow_path = "${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-setup/workflow.yaml"

if file_exists(workflow_path):
    state.workflow_available = true
    state.workflow_path = workflow_path
else:
    state.workflow_available = false
    # ERROR: workflow.yaml is required
```

---

## Usage

This skill is invoked via the Skill tool:

```
Skill(skill: "hiivmind-blueprint-author-setup")
```

Or via gateway routing:
```
/hiivmind-blueprint-author setup
/hiivmind-blueprint-author init
```

---

## Execution Protocol

**See:** `.hiivmind/blueprint/engine_entrypoint.md` (Engine v1.0.0) for full protocol.

### Quick Summary

1. **Bootstrap:** Extract `v3.0.0` from workflow.yaml
2. **Fetch Semantics:** Load execution rules from hiivmind-blueprint-lib@v3.0.0
3. **Load Local Files:** Read and validate workflow.yaml
4. **Execute:** Run workflow per traversal semantics (initialize → execute → complete)

---

## Reference Documentation

- **Type Definitions:** [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib/tree/v3.0.0)

---

## Related Skills

- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-upgrade/SKILL.md`
- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
