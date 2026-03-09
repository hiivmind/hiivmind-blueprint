# hiivmind-blueprint-author

Journey-oriented tools for building, assessing, enhancing, extracting, maintaining, and visualizing Claude Code skills as deterministic YAML workflow patterns.

## Overview

This plugin provides 7 journey-oriented skills covering the full skill authoring lifecycle:

1. **Gateway** - Entry point that routes user intent to the correct journey skill
2. **Build** - Create new skills from scratch with workflow patterns
3. **Assess** - Evaluate existing skills for quality, structure, and conversion readiness
4. **Enhance** - Improve existing skills with better patterns and error handling
5. **Extract** - Extract workflow patterns from prose-based skills
6. **Maintain** - Validate, update, and repair skills over time
7. **Visualize** - Generate Mermaid diagrams from workflow definitions

## Installation

```bash
claude mcp add-skill-plugin hiivmind/hiivmind-blueprint-author
```

## Quick Start

```bash
# Build a new skill from scratch
/hiivmind-blueprint-author build a validation skill for config files

# Assess an existing skill
/hiivmind-blueprint-author assess skills/my-skill/SKILL.md

# Enhance a skill with better patterns
/hiivmind-blueprint-author enhance skills/my-skill/SKILL.md

# Extract workflow from a prose skill
/hiivmind-blueprint-author extract skills/my-skill/SKILL.md

# Validate and maintain skills
/hiivmind-blueprint-author maintain

# Generate a Mermaid diagram
/hiivmind-blueprint-author visualize skills/my-skill/workflow.yaml
```

## Related Plugins

| Plugin | Purpose |
|--------|---------|
| [hiivmind-blueprint-ops](https://github.com/hiivmind/hiivmind-blueprint-ops) | Validation and maintenance |
| [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) | Core type definitions |

## License

MIT
