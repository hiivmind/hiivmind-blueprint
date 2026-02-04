---
name: hiivmind-blueprint-author-visualize
description: >
  Generate Mermaid diagrams from workflow.yaml files. Use when you want to "visualize workflow",
  "show workflow graph", "generate diagram", "see workflow structure", "mermaid diagram".
  Triggers on "visualize", "diagram", "graph", "show workflow".
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Visualize Workflow

Generate Mermaid diagrams from workflow.yaml to visualize the workflow graph structure.

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Install |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | `brew install jq` / `apt install jq` |
| `yq` | **Mandatory** | `command -v yq` | `brew install yq` / [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |
| `mmdc` | Optional | `command -v mmdc` | `npm install -g @mermaid-js/mermaid-cli` |

If mandatory tools are missing, exit with error listing the install commands above.

---

## Workflow Graph Overview

```
┌─────────────────┐
│ prerequisites   │
└────────┬────────┘
         │
┌────────▼────────┐
│ load-workflow   │◄── subflow: locate + validate
└────────┬────────┘
         │
┌────────▼────────┐
│ extract nodes   │
│ & transitions   │
└────────┬────────┘
         │
┌────────▼────────┐
│ generate        │
│ mermaid         │
└────────┬────────┘
         │
┌────────▼────────┐
│   display       │
└─────────────────┘
```

---

## Usage

```
Skill(skill: "hiivmind-blueprint-author-visualize")
Skill(skill: "hiivmind-blueprint-author-visualize", args: "path/to/workflow.yaml")
```

Or via gateway routing:
```
/hiivmind-blueprint-author visualize
/hiivmind-blueprint-author visualize skills/my-skill/workflow.yaml
```

---

## Output Options

| Flag | Effect |
|------|--------|
| `--output file` | Write diagram to file (extension auto-determined by format) |
| `--format mmd` | Pure Mermaid file, no markdown wrapper |
| `--format md` | Markdown with embedded mermaid block (default) |
| `--format md-linked` | Markdown with PNG image link + PNG file (requires mermaid-cli) |
| `--format png` | PNG image only (requires mermaid-cli) |
| `--format svg` | SVG image only (requires mermaid-cli) |
| `--compact` | Simplified diagram without descriptions |

---

## Image Export (Optional)

When `--format png`, `--format svg`, or `--format md-linked` is specified and mermaid-cli is installed:

**CLI command:**
```
mmdc -i <input.mmd> -o <output.png|svg> -b transparent -p <puppeteer-config>
```

**Linux note:** AppArmor restrictions on Ubuntu 23.10+ require puppeteer args:
```json
{"args": ["--no-sandbox", "--disable-setuid-sandbox"]}
```

If mermaid-cli is not installed, fall back to markdown output with a note suggesting installation.

---

## Reference Documentation

- **Mermaid Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/mermaid-generation.md`

---

## Related Skills

- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
- Regenerate SKILL.md: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-regenerate/SKILL.md`
