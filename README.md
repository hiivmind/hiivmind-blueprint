# hiivmind-blueprint-author

Authoring tools for converting Claude Code skills to deterministic YAML workflow patterns.

## Overview

This plugin provides tools for the full skill authoring lifecycle:

1. **Initialize** - Set up plugin for workflow support
2. **Discover** - Find existing skills and assess conversion status
3. **Analyze** - Deep structural analysis of prose skills
4. **Convert** - Transform analysis into workflow.yaml
5. **Generate** - Write skills and workflow files
6. **Gateway** - Create gateway commands for multi-skill plugins
7. **Visualize** - Generate Mermaid diagrams from workflows

## Installation

```bash
claude mcp add-skill-plugin hiivmind/hiivmind-blueprint-author
```

## Quick Start

```bash
# Initialize a plugin for workflow support
/hiivmind-blueprint-author init

# Discover skills in current plugin
/hiivmind-blueprint-author discover

# Analyze a specific skill
/hiivmind-blueprint-author analyze skills/my-skill/SKILL.md

# Convert to workflow format
/hiivmind-blueprint-author convert

# Generate workflow files
/hiivmind-blueprint-author generate
```

## Related Plugins

| Plugin | Purpose |
|--------|---------|
| [hiivmind-blueprint-ops](https://github.com/hiivmind/hiivmind-blueprint-ops) | Validation and maintenance |
| [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) | Core type definitions |

## License

MIT
