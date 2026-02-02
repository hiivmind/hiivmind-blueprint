# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Plugin Overview

**hiivmind-blueprint-author** provides authoring tools for converting Claude Code skills to deterministic YAML workflow patterns. This plugin handles the creation and transformation of skills into workflow-based execution.

## Skills

| Skill | Purpose | Invocation |
|-------|---------|------------|
| init | Initialize plugin for workflow support | `/hiivmind-blueprint-author init` |
| discover | Find skills and show conversion status | `/hiivmind-blueprint-author discover` |
| analyze | Deep analysis of SKILL.md structure | `/hiivmind-blueprint-author analyze [path]` |
| convert | Transform analysis into workflow.yaml | `/hiivmind-blueprint-author convert` |
| generate | Write thin loader + workflow.yaml | `/hiivmind-blueprint-author generate` |
| gateway | Generate gateway command for multi-skill plugins | `/hiivmind-blueprint-author gateway` |
| visualize | Generate Mermaid diagrams from workflow.yaml | `/hiivmind-blueprint-author visualize` |
| lib-version | Update external hiivmind-blueprint-lib version | `/hiivmind-blueprint-author lib-version` |

## Version Management

The external `hiivmind-blueprint-lib` version is centralized in `BLUEPRINT_LIB_VERSION.yaml`.
Use `/hiivmind-blueprint-author lib-version` to update version references across the plugin.

## Directory Structure

```
hiivmind-blueprint-author/
├── .claude-plugin/plugin.json
├── skills/
│   ├── hiivmind-blueprint-author-init/SKILL.md
│   ├── hiivmind-blueprint-author-discover/SKILL.md
│   ├── hiivmind-blueprint-author-analyze/SKILL.md
│   ├── hiivmind-blueprint-author-convert/SKILL.md
│   ├── hiivmind-blueprint-author-generate/SKILL.md
│   ├── hiivmind-blueprint-author-gateway/SKILL.md
│   ├── hiivmind-blueprint-author-visualize/SKILL.md
│   └── hiivmind-blueprint-author-lib-version/SKILL.md
├── BLUEPRINT_LIB_VERSION.yaml  # External lib version config
├── commands/hiivmind-blueprint-author/
│   ├── hiivmind-blueprint-author.md
│   ├── workflow.yaml
│   └── intent-mapping.yaml
├── templates/           # Workflow and loader templates
├── references/          # Type definition examples
├── CLAUDE.md
└── README.md
```

## Related Plugins

- **hiivmind-blueprint-ops** - Validation and maintenance operations
- **hiivmind-blueprint-lib** - Core type definitions and execution semantics
