# hiivmind-blueprint-ops

Operations tools for validating and maintaining YAML workflow patterns.

## Overview

This plugin provides tools for workflow operations:

1. **Validate** - Check workflow correctness (schema, graph, types, state)
2. **Upgrade** - Migrate workflows to latest schema version
3. **Lib-validation** - Validate type definitions in blueprint-lib

## Installation

```bash
claude mcp add-skill-plugin hiivmind/hiivmind-blueprint-ops
```

## Quick Start

### Validation

```bash
# Full validation
/hiivmind-blueprint-ops validate

# Specific validation modes
/hiivmind-blueprint-ops validate schema    # Structure only
/hiivmind-blueprint-ops validate graph     # Reachability analysis
/hiivmind-blueprint-ops validate types     # Type checking
/hiivmind-blueprint-ops validate state     # Variable validation
```

### Upgrades

```bash
# Auto-detect and upgrade
/hiivmind-blueprint-ops upgrade

# Target specific workflow types
/hiivmind-blueprint-ops upgrade skills     # Upgrade skill workflows
/hiivmind-blueprint-ops upgrade gateway    # Upgrade gateway workflows
```

### Type Definition Validation

```bash
# Validate blueprint-lib definitions
/hiivmind-blueprint-ops lib-validation
```

## Related Plugins

| Plugin | Purpose |
|--------|---------|
| [hiivmind-blueprint-author](https://github.com/hiivmind/hiivmind-blueprint-author) | Skill authoring |
| [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) | Core type definitions |

## License

MIT
