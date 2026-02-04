---
name: hiivmind-blueprint-author-convert
description: >
  Convert a prose SKILL.md to workflow.yaml format. This is the unified conversion skill that
  analyzes, converts, and generates output files. Use when converting skills, "analyze and convert",
  "create workflow from skill", "transform skill to yaml". Triggers on "convert", "transform",
  "analyze skill", "generate workflow".
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion
---

# Convert Skill to Workflow

Unified skill that analyzes a prose SKILL.md, converts it to workflow structure, and generates
both workflow.yaml and a thin SKILL.md loader.

**This skill merges the functionality of:** analyze + convert + generate

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Install |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | `brew install jq` / `apt install jq` |
| `yq` | **Mandatory** | `command -v yq` | `brew install yq` / [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |
| `gh` | Recommended | `command -v gh` | `brew install gh` / `apt install gh` |

If mandatory tools are missing, exit with error listing the install commands above.

---

## Initial State - Paths

Detect and set path variables:

```pseudocode
workflow_path = "${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/workflow.yaml"

if file_exists(workflow_path):
    state.workflow_available = true
    state.workflow_path = workflow_path
else:
    state.workflow_available = false
    # ERROR: workflow.yaml is required
```

---

## Workflow Graph Overview

```
┌─────────────────┐
│ prerequisites   │
└────────┬────────┘
         │
┌────────▼────────┐
│  load-skill     │◄── subflow: locate + read + parse
└────────┬────────┘
         │
┌────────▼────────┐
│ structural      │
│ analysis        │
└────────┬────────┘
         │
┌────────▼────────┐
│ workflow        │
│ generation      │
└────────┬────────┘
         │
┌────────▼────────┐
│ safe-write      │◄── subflow: backup + write + validate
└────────┬────────┘
         │
┌────────▼────────┐
│   success       │
└─────────────────┘
```

---

## Usage

This skill is invoked via the Skill tool:

```
Skill(skill: "hiivmind-blueprint-author-convert")
Skill(skill: "hiivmind-blueprint-author-convert", args: "path/to/SKILL.md")
```

Or via gateway routing:
```
/hiivmind-blueprint-author convert
/hiivmind-blueprint-author convert skills/my-skill/SKILL.md
```

---

## Runtime Flags

Flags modify workflow execution. Per-invocation only (reset for each call).

| Flag | Effect |
|------|--------|
| `--verbose`, `-v` | Show all node details (level: verbose) |
| `--quiet`, `-q` | Only prompts and final result (level: quiet) |
| `--dry-run` | Show what would be generated without writing |
| `--force` | Overwrite existing files without prompting |

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
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`

---

## Related Skills

- Batch upgrade: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-upgrade/SKILL.md`
- Visualize workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-visualize/SKILL.md`
- Regenerate SKILL.md: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-regenerate/SKILL.md`
