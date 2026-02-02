---
name: hiivmind-blueprint-author
description: >
  Unified entry point for hiivmind-blueprint-author operations - describe what you need
  in natural language or select from the menu. Authoring tools for converting prose-based
  skills to deterministic YAML workflows.
arguments:
  - name: request
    description: What you want to do (optional - shows menu if omitted)
    required: false
---

# hiivmind-blueprint-author Gateway

Execute this workflow for intelligent routing to the appropriate skill.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint-author/workflow.yaml`
> **Intent Mapping:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint-author/intent-mapping.yaml`

---

## Usage

```
/hiivmind-blueprint-author                    # Show interactive menu
/hiivmind-blueprint-author [request]          # Route by natural language intent
/hiivmind-blueprint-author --help             # Show full help
```

## Quick Examples

- `/hiivmind-blueprint-author init` - Initialize blueprint project
- `/hiivmind-blueprint-author discover` - Find skills to convert
- `/hiivmind-blueprint-author analyze my-skill` - Analyze a skill
- `/hiivmind-blueprint-author convert` - Convert skill to workflow
- `/hiivmind-blueprint-author generate` - Write workflow files
- `/hiivmind-blueprint-author gateway` - Generate gateway command
- `/hiivmind-blueprint-author visualize` - Generate Mermaid diagram

---

## Available Skills

| Skill | Purpose |
|-------|---------|
| **init** | Initialize plugin for workflow support |
| **discover** | Find skills and show conversion status |
| **analyze** | Deep analysis of SKILL.md structure |
| **convert** | Transform analysis into workflow.yaml |
| **generate** | Write thin loader + workflow.yaml |
| **gateway** | Generate gateway command for multi-skill plugins |
| **visualize** | Generate Mermaid diagrams from workflow.yaml |

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

**Cross-Plugin (hiivmind-blueprint-ops):**
- `/hiivmind-blueprint-ops validate` - Validate workflows
- `/hiivmind-blueprint-ops upgrade` - Upgrade workflow schemas
