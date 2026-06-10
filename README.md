# hiivmind-blueprint

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

Install directly from GitHub (no cloning required):

```bash
claude --plugin-url https://github.com/hiivmind/hiivmind-blueprint/archive/refs/heads/main.zip
```

For local development, install from a cloned copy:

```bash
claude plugin add /path/to/hiivmind-blueprint
```

## Quick Start

```bash
# Build a new skill from scratch
/blueprint build a validation skill for config files

# Assess an existing skill
/blueprint assess skills/my-skill/SKILL.md

# Enhance a skill with better patterns
/blueprint enhance skills/my-skill/SKILL.md

# Extract workflow from a prose skill
/blueprint extract skills/my-skill/SKILL.md

# Validate and maintain skills
/blueprint maintain

# Generate a Mermaid diagram
/blueprint visualize skills/my-skill/workflow.yaml
```

## Related Repositories

| Repository | Purpose |
|------------|---------|
| [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) | Core type definitions and execution semantics |
| [hiivmind-blueprint-central](https://github.com/hiivmind/hiivmind-blueprint-central) | Governance and principles hub |

## License

MIT
