# Scaffold Placeholder Checklist

> **Used by:** `SKILL.md` Phase 3 and Phase 4
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`

---

## Overview

This document catalogs every `{{placeholder}}` value used in the SKILL.md and workflow.yaml
templates. During scaffold generation, each placeholder must be resolved to a concrete value
before the template is written to disk.

Placeholders fall into three categories:

| Category | Meaning | Example |
|----------|---------|---------|
| **User input** | Provided directly by the user during Phase 1 | `{{skill_name}}` |
| **Computed** | Derived from user input or detected context | `{{skill_short_name}}` |
| **Default** | Static value unless overridden | `{{allowed_tools}}` |

---

## SKILL.md Template Placeholders

These placeholders appear in `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`.

### Required Placeholders

| Placeholder | Source | Default | Description |
|------------|--------|---------|-------------|
| `{{skill_name}}` | User input | -- | The full kebab-case skill name. Used in frontmatter `name:` field and all invocation examples. Example: `bp-build` |
| `{{description}}` | Computed | -- | Frontmatter `description:` field. Auto-generated from skill name and features, or provided by user. Must include trigger keywords for Claude's skill matching. Max 1024 characters. |
| `{{allowed_tools}}` | Computed | `Read, Write, Glob, Bash, AskUserQuestion` | Comma-separated list of tools the skill may use. |
| `{{title}}` | Computed | -- | Human-readable title for the `# Heading` of the SKILL.md. Derived from skill name via title-casing. |
| `{{parent_plugin_name}}` | Computed | Directory name | The name of the parent plugin. Extracted from `.claude-plugin/plugin.json` if present, otherwise derived from the current directory basename. |
| `{{skill_short_name}}` | Computed | Last segment(s) | Short form used in help command examples. Derived from the last one or two segments of the skill name. |
| `{{skill_directory}}` | Computed | Same as `skill_name` | Directory name under `skills/` where this skill's files live. |
| `{{overview}}` | User input / Computed | -- | One-paragraph overview of what the skill does. Placed after the `# Title` heading. |

### Inputs/Outputs Placeholders

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{#inputs}}` ... `{{/inputs}}` | User input | Loop over declared input parameters |
| `{{name}}` (within inputs) | User input | Parameter name |
| `{{type}}` (within inputs) | Computed | Parameter type (string, number, boolean, object, array) |
| `{{required}}` (within inputs) | Computed | Whether parameter is required (true/false) |
| `{{description}}` (within inputs) | User input | Parameter description |
| `{{#outputs}}` ... `{{/outputs}}` | User input | Loop over declared output values |
| `{{name}}` (within outputs) | User input | Output name |
| `{{type}}` (within outputs) | Computed | Output type |
| `{{description}}` (within outputs) | User input | Output description |

### Workflows List Placeholders

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{#if_workflows}}` ... `{{/if_workflows}}` | Computed | Section included only when workflow-backed phases exist |
| `{{#workflows}}` ... `{{/workflows}}` | Computed | Loop over workflow file references |
| `{{filename}}` (within workflows) | Computed | Workflow filename (e.g., `validate.yaml`) |

### Phase Placeholders

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{#phases}}` ... `{{/phases}}` | Computed | Loop over all skill phases |
| `{{number}}` (within phases) | Computed | Phase number (1-based) |
| `{{title}}` (within phases) | User input | Phase title (e.g., "Gather", "Validate") |
| `{{#if_prose_phase}}` ... `{{/if_prose_phase}}` | Computed | Block included for prose phases |
| `{{prose_instructions}}` (within prose phase) | Computed | Prose instructions (initially TODO placeholder) |
| `{{#if_workflow_phase}}` ... `{{/if_workflow_phase}}` | Computed | Block included for workflow-backed phases |
| `{{workflow_file}}` (within workflow phase) | Computed | Workflow filename to execute |
| `{{#pre_workflow_prose}}` ... `{{/pre_workflow_prose}}` | User input | Optional prose before workflow execution |
| `{{#post_workflow_prose}}` ... `{{/post_workflow_prose}}` | User input | Optional prose after workflow execution |

### Conditional Section Placeholders

These control whether entire sections of the SKILL.md template are included or removed.

| Placeholder | Source | Default | Description |
|------------|--------|---------|-------------|
| `{{#if_runtime_flags}}` ... `{{/if_runtime_flags}}` | `computed.features.runtime_flags` | Excluded | Runtime Flags section with `--verbose`, `--quiet`, `--debug`, `--no-log`, `--no-display` flags. |
| `{{#if_intent_detection}}` ... `{{/if_intent_detection}}` | `computed.features.intent_detection` | Excluded | Intent Detection section with T/F/U flag semantics. |
| `{{#workflow_graph}}` ... `{{/workflow_graph}}` | `computed.features.visualization` | Excluded | ASCII art workflow graph overview. Requires `{{graph_ascii}}`. |
| `{{graph_ascii}}` | Computed | -- | ASCII art representation of the workflow graph. Only needed when `workflow_graph` section is enabled. |
| `{{#examples}}` ... `{{/examples}}` | Always enabled | Included | Quick Examples section. Contains `{{#items}}` loop. |
| `{{#related_skills}}` ... `{{/related_skills}}` | Always enabled | Included | Related Skills section. Contains `{{#skills}}` loop. |

---

## workflow.yaml Template Placeholders

These placeholders appear in `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`.

### Required Placeholders

| Placeholder | Source | Default | Description |
|------------|--------|---------|-------------|
| `{{workflow_id}}` | Computed | `{skill_name}-{phase_title}` | The workflow identity name. Used in the `name:` field. Each workflow has its own ID distinct from the skill name. Example: `bp-build-validate` |
| `{{description}}` | Computed | -- | Workflow description. Describes what this specific workflow phase does. |
| `{{state_variables}}` | Computed | `phase, flags, computed` | Comma-separated list documenting which state fields the workflow uses. |
| `{{start_node}}` | Computed | `start_{phase_title}` | The name of the first node to execute. Derived from phase title. |
| `{{success_message}}` | Computed | `{Phase title} completed successfully` | Message displayed when the workflow reaches its success ending. |

### Node Template Placeholders

These appear within the `{{#nodes}}` ... `{{/nodes}}` loop and are populated per-node
from the starter node definitions built in Phase 4.

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{id}}` | Computed | Node identifier in snake_case. Example: `start_validate` |
| `{{type}}` | Computed | Node type: `action`, `conditional`, or `user_prompt` |
| `{{description}}` | Computed | Human-readable description of what the node does |
| `{{#if_action}}` | Computed | Block included only for `type: action` nodes |
| `{{#actions}}` | Computed | Loop over the node's action list |
| `{{on_success}}` | Computed | Next node on successful action execution |
| `{{on_failure}}` | Computed | Next node on action failure |
| `{{#if_conditional}}` | Computed | Block included only for `type: conditional` nodes |
| `{{condition_type}}` | Computed | Precondition type (e.g., `state_check`, `path_check`) |
| `{{#condition_params}}` | Computed | Loop over condition parameters |
| `{{branch_true}}` | Computed | Next node when condition evaluates true |
| `{{branch_false}}` | Computed | Next node when condition evaluates false |
| `{{#if_user_prompt}}` | Computed | Block included only for `type: user_prompt` nodes |
| `{{question}}` | Computed | User prompt question text |
| `{{header}}` | Computed | User prompt header (max 12 characters) |
| `{{#options}}` | Computed | Loop over prompt options |
| `{{#responses}}` | Computed | Loop over response handlers |
| `{{#if_conditional_audit}}` | Computed | Block included only for conditional + audit mode nodes |

### Ending Placeholders

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{success_message}}` | Computed | Message for the success ending |
| `{{#success_summary}}` | Computed | Optional summary block with output variables |
| `{{#error_endings}}` | Computed | Loop over additional error endings beyond the defaults |
| `{{message}}` | Computed | Error ending message text |
| `{{recovery}}` | Computed | Optional recovery suggestion |
| `{{details}}` | Computed | Optional error details |

### Entry Precondition Placeholders

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{#entry_preconditions}}` | Computed | Loop over entry preconditions |
| `{{type}}` | Computed | Precondition type (e.g., `tool_check`, `path_check`) |
| `{{#params}}` | Computed | Loop over precondition parameters |

---

## Placeholder Resolution Order

Placeholders must be resolved in a specific order because some depend on others:

```
1. User input (Phase 1):
   skill_name  -->  skill_directory, skill_short_name, title, workflow_id
   description -->  frontmatter description
   inputs/outputs --> frontmatter arrays
   structure   -->  needs_gateway

2. Phase design (Phase 2):
   phases      -->  workflow_phases, coverage
   phases      -->  workflow filenames, workflow IDs

3. Context detection (Phase 3):
   has_plugin_manifest  -->  parent_plugin_name
   has_definitions      -->  whether to create definitions.yaml

4. Derived values (Phase 3/4):
   skill_name + features  -->  description (if auto-generated)
   features               -->  allowed_tools, conditional sections
   phases                 -->  phase content blocks
   workflow_phases        -->  start_node, state_variables per workflow
   skill_name + phase     -->  success_message per workflow
   nodes                  -->  graph_ascii (if visualization enabled)
```

---

## Validation Rules

After substitution, verify these conditions before writing files:

| Rule | Check | Error if Violated |
|------|-------|-------------------|
| No unresolved placeholders | `grep -c '{{' output_file` returns 0 | Template substitution incomplete |
| skill_name is valid kebab-case | Matches `/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/` | Invalid skill name format |
| description is under 1024 chars | `len(description) <= 1024` | Description too long for frontmatter |
| header values are under 12 chars | All `{{header}}` values `<= 12` chars | Header exceeds AskUserQuestion limit |
| start_node references valid node | `start_node IN nodes` | Start node not found in node list |
| All transitions reference valid targets | Every `on_success`, `on_failure`, `branches.*`, `next_node` points to a node or ending | Broken transition reference |
| workflow_id is unique per file | Each workflow file has a distinct workflow_id | Duplicate workflow identity |
| inputs have valid types | All input types are: string, number, boolean, object, array | Invalid input type |

---

## Examples

### Prose-Only Skill (no workflows, coverage: none)

```
skill_name:          "my-tool-run"
skill_directory:     "my-tool-run"
skill_short_name:    "run"
title:               "My Tool Run"
parent_plugin_name:  "my-tool"
description:         "This skill should be used when the user asks to \"run\". Triggers on \"run\"."
allowed_tools:       "Read, Write, Glob, Bash, AskUserQuestion"
inputs:              [{ name: "target", type: "string", required: true }]
outputs:             [{ name: "result", type: "object" }]
coverage:            "none"
phases:              [{ number: 1, title: "Execute", type: "prose" }]
workflow_phases:     []
```

Generated files:
- `skills/my-tool-run/SKILL.md`

### Hybrid Skill (coverage: partial)

```
skill_name:          "data-pipeline-setup"
skill_directory:     "data-pipeline-setup"
skill_short_name:    "setup"
title:               "Data Pipeline Setup"
parent_plugin_name:  "data-pipeline"
coverage:            "partial"
phases:
  - { number: 1, title: "Gather", type: "prose" }
  - { number: 2, title: "Validate", type: "workflow", workflow_file: "validate.yaml" }
  - { number: 3, title: "Transform", type: "workflow", workflow_file: "transform.yaml" }
  - { number: 4, title: "Report", type: "prose" }
workflow_phases:
  - { filename: "validate.yaml", workflow_id: "data-pipeline-setup-validate" }
  - { filename: "transform.yaml", workflow_id: "data-pipeline-setup-transform" }
```

Generated files:
- `skills/data-pipeline-setup/SKILL.md`
- `skills/data-pipeline-setup/workflows/validate.yaml`
- `skills/data-pipeline-setup/workflows/transform.yaml`

### Full-Workflow Skill (coverage: full)

```
skill_name:          "repo-audit"
skill_directory:     "repo-audit"
skill_short_name:    "audit"
title:               "Repo Audit"
parent_plugin_name:  "repo-tools"
coverage:            "full"
phases:
  - { number: 1, title: "Scan", type: "workflow", workflow_file: "scan.yaml" }
  - { number: 2, title: "Report", type: "workflow", workflow_file: "report.yaml" }
workflow_phases:
  - { filename: "scan.yaml", workflow_id: "repo-audit-scan" }
  - { filename: "report.yaml", workflow_id: "repo-audit-report" }
```

Generated files:
- `skills/repo-audit/SKILL.md`
- `skills/repo-audit/workflows/scan.yaml`
- `skills/repo-audit/workflows/report.yaml`
