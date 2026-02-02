---
name: hiivmind-blueprint-ops
description: >
  Unified entry point for hiivmind-blueprint-ops operations - describe what you need
  in natural language or select from the menu. Operations tools for validating and
  maintaining YAML workflow patterns.
arguments:
  - name: request
    description: What you want to do (optional - shows menu if omitted)
    required: false
---

# hiivmind-blueprint-ops Gateway

Execute this workflow for intelligent routing to the appropriate skill.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint-ops/workflow.yaml`
> **Intent Mapping:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint-ops/intent-mapping.yaml`

---

## Usage

```
/hiivmind-blueprint-ops                    # Show interactive menu
/hiivmind-blueprint-ops [request]          # Route by natural language intent
/hiivmind-blueprint-ops --help             # Show full help
```

## Quick Examples

### Validation

```
/hiivmind-blueprint-ops validate           # Full validation
/hiivmind-blueprint-ops validate schema    # JSON schema + structure only
/hiivmind-blueprint-ops validate graph     # Reachability analysis
/hiivmind-blueprint-ops validate types     # Type checking
/hiivmind-blueprint-ops validate state     # Variable validation
```

### Upgrades

```
/hiivmind-blueprint-ops upgrade            # Auto-detect target
/hiivmind-blueprint-ops upgrade skills     # Upgrade skill workflows
/hiivmind-blueprint-ops upgrade gateway    # Upgrade gateway workflows
```

### Library Validation

```
/hiivmind-blueprint-ops lib-validation     # Validate type definitions
```

---

## Available Skills

| Skill | Purpose | Verb Support |
|-------|---------|--------------|
| **validate** | Validate workflow.yaml structure and references | `schema`, `graph`, `types`, `state` |
| **upgrade** | Upgrade workflows to latest schema version | `skills`, `gateway` |
| **lib-validation** | Validate consequence/precondition definitions | - |

---

## Execution Reference

Execution semantics from [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib):

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/state.yaml) |
| Consequences | [consequence-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/consequence-dispatch.yaml) |
| Preconditions | [precondition-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/precondition-dispatch.yaml) |

---

## Related Skills

**This Plugin:**
- All skills listed in Available Skills table above

**Cross-Plugin (hiivmind-blueprint-author):**
- `/hiivmind-blueprint-author init` - Initialize projects
- `/hiivmind-blueprint-author analyze` - Analyze skills
- `/hiivmind-blueprint-author convert` - Convert to workflows
