# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Plugin Overview

**hiivmind-blueprint-author** provides authoring tools for converting Claude Code skills to deterministic YAML workflow patterns. This plugin handles the creation and transformation of skills into workflow-based execution.

## Architecture: Composable Subflows

This plugin uses a 3-layer composable architecture:

### Layer 0: Atomic Subflows (subflows/)
Smallest reusable units that cannot be further decomposed:
- `prerequisites-check.yaml` - jq/yq/gh availability checks
- `locate-file-by-type.yaml` - Path provided → Read | Glob → Ask user
- `existing-file-handler.yaml` - Skip/Overwrite/Backup+Replace/Cancel
- `iterate-files.yaml` - Glob pattern + for-each loop
- `validate-yaml-structure.yaml` - Parse YAML + validate sections
- `template-render.yaml` - Load template, substitute vars, output

### Layer 1: Composite Subflows (subflows/)
Combine atomic subflows for common compound operations:
- `load-skill.yaml` - prerequisites-check → locate-file(SKILL.md) → validate
- `load-workflow.yaml` - prerequisites-check → locate-file(workflow.yaml) → validate
- `safe-write-files.yaml` - existing-file-handler → template-render → validate-output
- `classify-skill.yaml` - Read SKILL.md → detect indicators → classify
- `discover-all-skills.yaml` - iterate-files(SKILL.md) → classify-skill (each)

### Layer 2: User-Facing Skills (skills/)
The 6 skills users invoke directly via slash commands.

## Skills

| Skill | Purpose | Invocation |
|-------|---------|------------|
| **setup** | Initialize plugin for workflow support | `/hiivmind-blueprint-author setup` |
| **convert** | Analyze + convert + generate (unified) | `/hiivmind-blueprint-author convert [path]` |
| **upgrade** | Batch convert all prose skills | `/hiivmind-blueprint-author upgrade` |
| **gateway** | Generate gateway command for multi-skill plugins | `/hiivmind-blueprint-author gateway` |
| **regenerate** | Rebuild SKILL.md from workflow.yaml | `/hiivmind-blueprint-author regenerate [path]` |
| **visualize** | Generate Mermaid diagrams from workflow.yaml | `/hiivmind-blueprint-author visualize [path]` |

### Skill Consolidation (vs. Previous Version)

| Previous (7 skills) | New (6 skills) | Change |
|---------------------|----------------|--------|
| init | **setup** | Simplified, infrastructure only |
| analyze | — | Merged into convert |
| convert | **convert** | Merged: analyze + convert + generate |
| generate | — | Merged into convert |
| discover | **upgrade** | Merged: discover + batch convert |
| gateway | **gateway** | Unchanged |
| visualize | **visualize** | Unchanged |
| — | **regenerate** | NEW: rebuild SKILL.md from workflow |

## Version Management

The external `hiivmind-blueprint-lib` version is centralized in `.hiivmind/blueprint/config.yaml`.
Skills reference the version dynamically via `{computed.lib_version}` at runtime.

## Directory Structure

```
hiivmind-blueprint-author/
├── .claude-plugin/plugin.json
├── subflows/                    # Composable subflow definitions
│   ├── prerequisites-check.yaml
│   ├── locate-file-by-type.yaml
│   ├── existing-file-handler.yaml
│   ├── iterate-files.yaml
│   ├── validate-yaml-structure.yaml
│   ├── template-render.yaml
│   ├── load-skill.yaml
│   ├── load-workflow.yaml
│   ├── safe-write-files.yaml
│   ├── classify-skill.yaml
│   └── discover-all-skills.yaml
├── skills/
│   ├── hiivmind-blueprint-author-setup/
│   │   ├── SKILL.md
│   │   └── workflow.yaml
│   ├── hiivmind-blueprint-author-convert/
│   │   ├── SKILL.md
│   │   └── workflow.yaml
│   ├── hiivmind-blueprint-author-upgrade/
│   │   ├── SKILL.md
│   │   └── workflow.yaml
│   ├── hiivmind-blueprint-author-gateway/
│   │   ├── SKILL.md
│   │   └── workflow.yaml
│   ├── hiivmind-blueprint-author-regenerate/
│   │   ├── SKILL.md
│   │   └── workflow.yaml
│   └── hiivmind-blueprint-author-visualize/
│       ├── SKILL.md
│       └── workflow.yaml
├── commands/hiivmind-blueprint-author/
│   ├── hiivmind-blueprint-author.md
│   ├── workflow.yaml
│   └── intent-mapping.yaml
├── lib/patterns/                # Pattern documentation
├── templates/                   # Workflow and skill templates
├── references/                  # Type definition examples
├── templates/config.yaml.template
├── CLAUDE.md
└── README.md
```

## Subflow Composition (Future)

The subflows are designed for composition via `type: reference` nodes:

```yaml
start_analyze:
  type: reference
  workflow: subflows/load-skill.yaml
  input:
    skill_path: ${args.path}
  output_mapping:
    state.loaded.content: output.skill_content
  transitions:
    on_success: structural_analysis
    on_failure: error_load
```

Until hiivmind-blueprint-lib supports subflow composition, subflow logic is inlined in the parent workflows. The subflows exist as standalone, testable workflows and documentation of the intended interface.

See `docs/subflow-composition-spec.md` for the full specification.

## Related Plugins

- **hiivmind-blueprint-ops** - Validation and maintenance operations
- **hiivmind-blueprint-lib** - Core type definitions and execution semantics


<claude-mem-context>
# Recent Activity

<!-- This section is auto-generated by claude-mem. Edit content outside the tags. -->

*No recent activity*
</claude-mem-context>