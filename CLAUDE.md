# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Plugin Overview

**hiivmind-blueprint** provides journey-oriented tools for building, assessing, enhancing, extracting, maintaining, and visualizing Claude Code skills as deterministic YAML workflow patterns. This plugin handles the full skill lifecycle through 7 journey-oriented skills with a unified gateway.

## Architecture: Journey Model

This plugin uses a journey-oriented architecture where each skill represents a distinct phase of the skill authoring lifecycle. Users enter through the **gateway** skill, which routes to the appropriate journey skill based on intent.

### The 7 Journey Skills

| Skill | Journey Phase | Purpose |
|-------|--------------|---------|
| **bp-gateway** | Entry point | Routes user intent to the correct journey skill |
| **bp-build** | Creation | Build new skills from scratch with workflow patterns |
| **bp-assess** | Evaluation | Assess existing skills for quality, structure, and conversion readiness |
| **bp-enhance** | Improvement | Enhance existing skills with better patterns, error handling, and structure |
| **bp-extract** | Extraction | Extract workflow patterns from prose-based skills |
| **bp-maintain** | Maintenance | Maintain skills over time — validate, update, and repair |
| **bp-visualize** | Visualization | Generate Mermaid diagrams from workflow definitions |

### Archived Skills

The `skills/_archived/` directory contains old skills from the pre-journey architecture (bp-skill-create, bp-skill-analyze, bp-plugin-discover, etc.). These are retained for reference but are no longer active.

## Skills

| Skill | Purpose | Invocation |
|-------|---------|------------|
| **bp-gateway** | Route intent to journey skill | `/blueprint [request]` |
| **bp-build** | Build new skills from scratch | `/blueprint build [description]` |
| **bp-assess** | Assess skill quality and structure | `/blueprint assess [path]` |
| **bp-enhance** | Enhance existing skills | `/blueprint enhance [path]` |
| **bp-extract** | Extract workflows from prose skills | `/blueprint extract [path]` |
| **bp-maintain** | Validate and maintain skills | `/blueprint maintain [path]` |
| **bp-visualize** | Generate Mermaid diagrams | `/blueprint visualize [path]` |

## Version Management

The external `hiivmind-blueprint-lib` version is centralized in `.hiivmind/blueprint/config.yaml`.
Skills reference the version dynamically via `{computed.lib_version}` at runtime.

## Directory Structure

```
hiivmind-blueprint/
├── .claude-plugin/plugin.json
├── skills/
│   ├── bp-gateway/               # Entry point — intent routing
│   │   ├── SKILL.md
│   │   └── workflow.yaml
│   ├── bp-build/                 # Build new skills
│   │   ├── SKILL.md
│   │   └── patterns/
│   ├── bp-assess/                # Assess skill quality
│   │   └── SKILL.md
│   ├── bp-enhance/               # Enhance existing skills
│   │   └── SKILL.md
│   ├── bp-extract/               # Extract workflows from prose
│   │   └── SKILL.md
│   ├── bp-maintain/              # Validate and maintain
│   │   └── SKILL.md
│   ├── bp-visualize/             # Mermaid diagram generation
│   │   └── SKILL.md
│   └── _archived/                # Old pre-journey skills (reference only)
├── _archive/                     # Archived gateway versions
├── commands/
│   ├── blueprint.md
│   └── blueprint/
│       ├── workflow.yaml
│       └── intent-mapping.yaml
├── lib/patterns/                 # Pattern documentation
├── templates/                    # Workflow and skill templates
├── references/                   # Type definition examples
├── docs/releases/                # Release notes
├── CLAUDE.md
└── README.md
```

## Related Repositories

- **hiivmind-blueprint-lib** - Core type definitions and execution semantics
- **hiivmind-blueprint-central** - Governance and principles hub
