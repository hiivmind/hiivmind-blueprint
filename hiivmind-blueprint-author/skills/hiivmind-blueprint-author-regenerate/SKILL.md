---
name: hiivmind-blueprint-author-regenerate
description: >
  Regenerate a SKILL.md loader from an existing workflow.yaml. Use when you need to update
  the SKILL.md to match workflow changes, or when SKILL.md was accidentally modified.
  Triggers on "regenerate skill", "rebuild skill.md", "update skill loader", "sync skill".
allowed-tools: Read, Write, Bash, AskUserQuestion
---

# Regenerate SKILL.md

Rebuild the SKILL.md thin loader from an existing workflow.yaml file.

**Use case:** When workflow.yaml has been updated and SKILL.md needs to reflect those changes,
or when the SKILL.md loader template has been updated.

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Install |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | `brew install jq` / `apt install jq` |
| `yq` | **Mandatory** | `command -v yq` | `brew install yq` / [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |

If mandatory tools are missing, exit with error listing the install commands above.

---

## Workflow Graph Overview

```
┌─────────────────┐
│ prerequisites   │
└────────┬────────┘
         │
┌────────▼────────┐
│ load-workflow   │◄── subflow: locate + validate workflow
└────────┬────────┘
         │
┌────────▼────────┐
│ extract metadata│
└────────┬────────┘
         │
┌────────▼────────┐
│ generate SKILL  │
│ from template   │
└────────┬────────┘
         │
┌────────▼────────┐
│ safe-write      │
└────────┬────────┘
         │
┌────────▼────────┐
│   success       │
└─────────────────┘
```

---

## Usage

```
Skill(skill: "hiivmind-blueprint-author-regenerate")
Skill(skill: "hiivmind-blueprint-author-regenerate", args: "path/to/workflow.yaml")
```

Or via gateway routing:
```
/hiivmind-blueprint-author regenerate
/hiivmind-blueprint-author regenerate skills/my-skill/workflow.yaml
```

---

## Reference Documentation

- **SKILL.md Template:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`

---

## Related Skills

- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
- Visualize workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-visualize/SKILL.md`
