# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Plugin Overview

**hiivmind-blueprint-ops** provides operations tools for validating and maintaining YAML workflow patterns. This plugin handles validation, schema upgrades, and type definition management.

## Skills

| Skill | Purpose | Invocation |
|-------|---------|------------|
| validate | Validate workflow.yaml structure and references | `/hiivmind-blueprint-ops validate [mode]` |
| upgrade | Upgrade workflows to latest schema version | `/hiivmind-blueprint-ops upgrade [target]` |
| lib-validation | Validate consequence/precondition definitions | `/hiivmind-blueprint-ops lib-validation` |

### Validate Modes

```
/hiivmind-blueprint-ops validate           # Full validation (all checks)
/hiivmind-blueprint-ops validate schema    # JSON schema + structure only
/hiivmind-blueprint-ops validate graph     # Reachability, cycles, dead ends
/hiivmind-blueprint-ops validate types     # Precondition/consequence types
/hiivmind-blueprint-ops validate state     # State variable validation
```

### Upgrade Targets

```
/hiivmind-blueprint-ops upgrade            # Auto-detect (ask if both found)
/hiivmind-blueprint-ops upgrade skills     # Upgrade skill workflows
/hiivmind-blueprint-ops upgrade gateway    # Upgrade gateway workflows
```

## Version Management

The external `hiivmind-blueprint-lib` version is centralized in `BLUEPRINT_LIB_VERSION.yaml`.
This ensures all workflows and documentation reference the same lib version.

## Directory Structure

```
hiivmind-blueprint-ops/
├── .claude-plugin/plugin.json
├── BLUEPRINT_LIB_VERSION.yaml  # External lib version config
├── skills/
│   ├── hiivmind-blueprint-ops-validate/SKILL.md
│   ├── hiivmind-blueprint-ops-upgrade/SKILL.md
│   ├── hiivmind-blueprint-ops-lib-validation/SKILL.md
│   └── hiivmind-blueprint-ops-intent-validator/SKILL.md
├── commands/hiivmind-blueprint-ops/
│   ├── hiivmind-blueprint-ops.md
│   ├── workflow.yaml
│   └── intent-mapping.yaml
├── lib/workflow/legacy/     # Validation reference documentation
├── CLAUDE.md
└── README.md
```

## Related Plugins

- **hiivmind-blueprint-author** - Skill authoring and conversion
- **hiivmind-blueprint-lib** - Core type definitions and execution semantics
