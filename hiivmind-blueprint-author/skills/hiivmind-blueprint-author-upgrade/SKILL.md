---
name: hiivmind-blueprint-author-upgrade
description: >
  Batch upgrade/convert all prose skills in a plugin to workflow format. Use when you want to
  "upgrade all skills", "batch convert", "convert everything", "brownfield upgrade",
  "discover and convert all". Triggers on "upgrade", "batch", "convert all", "discover skills".
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion
---

# Upgrade All Skills

Discover all skills in a plugin, classify them, and batch convert prose skills to workflow format.

**This skill combines:** discover + convert (batch mode)

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
workflow_path = "${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-upgrade/workflow.yaml"

if file_exists(workflow_path):
    state.workflow_available = true
    state.workflow_path = workflow_path
```

---

## Workflow Graph Overview

```
┌─────────────────┐
│ prerequisites   │
└────────┬────────┘
         │
┌────────▼────────┐
│ discover-all    │◄── subflow: find + classify all skills
└────────┬────────┘
         │
┌────────▼────────┐
│ show summary    │
│ & confirm       │
└────────┬────────┘
         │
┌────────▼────────┐
│ batch convert   │◄── loop: convert each prose skill
│ (loop)          │
└────────┬────────┘
         │
┌────────▼────────┐
│   report        │
└─────────────────┘
```

---

## Usage

This skill is invoked via the Skill tool:

```
Skill(skill: "hiivmind-blueprint-author-upgrade")
Skill(skill: "hiivmind-blueprint-author-upgrade", args: "--dry-run")
```

Or via gateway routing:
```
/hiivmind-blueprint-author upgrade
/hiivmind-blueprint-author discover
```

---

## Runtime Flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Show what would be converted without making changes |
| `--force` | Convert all without confirmation prompts |
| `--include-deprecated` | Include skills in *_deprecated directories |

---

## Execution Protocol

**See:** `.hiivmind/blueprint/engine_entrypoint.md` (Engine v1.0.0) for full protocol.

---

## Reference Documentation

- **Type Definitions:** [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib/tree/v3.0.0)

---

## Related Skills

- Convert single skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
- Setup infrastructure: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-setup/SKILL.md`
- Generate gateway: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-gateway/SKILL.md`
