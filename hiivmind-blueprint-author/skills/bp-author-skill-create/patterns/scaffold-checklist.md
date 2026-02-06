# Scaffold Placeholder Checklist

> **Used by:** `SKILL.md` Phase 4, Step 4.2 and Phase 5, Step 5.2
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
| **Default** | Static value unless overridden | `{{lib_version}}` |

---

## SKILL.md Template Placeholders

These placeholders appear in `${CLAUDE_PLUGIN_ROOT}/templates/SKILL.md.template`.

### Required Placeholders

| Placeholder | Source | Default | Description |
|------------|--------|---------|-------------|
| `{{skill_name}}` | User input | -- | The full kebab-case skill name. Used in frontmatter `name:` field and all invocation examples. Example: `bp-author-skill-create` |
| `{{description}}` | Computed | -- | Frontmatter `description:` field. Auto-generated from skill name and features, or provided by user. Must include trigger keywords for Claude's skill matching. Max 1024 characters. Example: `This skill should be used when the user asks to "create a new skill"...` |
| `{{allowed_tools}}` | Computed | `Read, Write, Glob, Bash, AskUserQuestion` | Comma-separated list of tools the skill may use. Base set is always included; additional tools added based on features. |
| `{{title}}` | Computed | -- | Human-readable title for the `# Heading` of the SKILL.md. Derived from skill name via title-casing. Example: `Bp Author Skill Create` |
| `{{parent_plugin_name}}` | Computed | Directory name | The name of the parent plugin. Extracted from `.claude-plugin/plugin.json` if present, otherwise derived from the current directory basename. Used in gateway invocation examples. Example: `hiivmind-blueprint-author` |
| `{{skill_short_name}}` | Computed | Last segment(s) | Short form used in help command examples. Derived from the last one or two segments of the skill name. Example: `skill-create` from `bp-author-skill-create` |
| `{{skill_directory}}` | Computed | Same as `skill_name` | Directory name under `skills/` where this skill's files live. Typically identical to `skill_name`. Example: `bp-author-skill-create` |
| `{{lib_version}}` | Default / Detected | `v3.0.0` | Version tag of hiivmind-blueprint-lib. Read from `BLUEPRINT_LIB_VERSION.yaml` if it exists, otherwise defaults to `v3.0.0`. Used in documentation links and Phase 2 bootstrap reference. Example: `v3.0.0` |
| `{{lib_ref}}` | Default / Detected | `hiivmind/hiivmind-blueprint-lib@v3.0.0` | Full GitHub reference string in `owner/repo@version` format. Read from `BLUEPRINT_LIB_VERSION.yaml` if it exists. Used in the template's `definitions.source` reference comment. |

### Conditional Section Placeholders

These control whether entire sections of the SKILL.md template are included or removed.

| Placeholder | Source | Default | Description |
|------------|--------|---------|-------------|
| `{{#if_runtime_flags}}` ... `{{/if_runtime_flags}}` | `computed.features.runtime_flags` | Excluded | When enabled, includes the Runtime Flags section with `--verbose`, `--quiet`, `--debug`, `--no-log`, `--no-display` flag documentation. |
| `{{#if_intent_detection}}` ... `{{/if_intent_detection}}` | `computed.features.intent_detection` | Excluded | When enabled, includes the Intent Detection section documenting T/F/U flag semantics and resolution flow. |
| `{{#workflow_graph}}` ... `{{/workflow_graph}}` | `computed.features.visualization` | Excluded | When enabled, includes an ASCII art workflow graph overview. Requires `{{graph_ascii}}` to be populated with the graph content. |
| `{{graph_ascii}}` | Computed | -- | ASCII art representation of the workflow graph. Only needed when the `workflow_graph` section is enabled. Generated from the starter nodes. |
| `{{#examples}}` ... `{{/examples}}` | Always enabled | Included | Quick Examples section. Contains `{{#items}}` loop for individual examples. |
| `{{#related_skills}}` ... `{{/related_skills}}` | Always enabled | Included | Related Skills section. Contains `{{#skills}}` loop for skill links. |

---

## workflow.yaml Template Placeholders

These placeholders appear in `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`.

### Required Placeholders

| Placeholder | Source | Default | Description |
|------------|--------|---------|-------------|
| `{{skill_id}}` | Computed | Same as `skill_name` | The workflow identity name. Used in the `name:` field at the top of workflow.yaml. Must match the skill name for consistency. Example: `bp-author-skill-create` |
| `{{description}}` | Computed | -- | Workflow description. Same value as the SKILL.md description, used in the workflow `description:` field. |
| `{{lib_ref}}` | Default / Detected | `hiivmind/hiivmind-blueprint-lib@v3.0.0` | Library reference in `owner/repo@version` format. Used in `definitions.source:`. This is the primary version pin for type definitions and execution semantics. |
| `{{state_variables}}` | Computed | `phase, flags, computed` | Comma-separated list documenting which state fields the workflow uses. Appears in the `initial_state` comment. For scaffolded skills, the default set is always `phase, flags, computed`. Additional fields are added based on features. |
| `{{start_node}}` | Computed | `start_execution` | The name of the first node to execute. If intent detection is enabled, this becomes `parse_intent`. Otherwise defaults to `start_execution`. |
| `{{success_message}}` | Computed | `{Title} completed successfully` | Message displayed when the workflow reaches its success ending. Derived from the title-cased skill name. Example: `Bp Author Skill Create completed successfully` |

### Node Template Placeholders

These appear within the `{{#nodes}}` ... `{{/nodes}}` loop and are populated per-node
from the starter node definitions built in Phase 5, Step 5.2.

| Placeholder | Source | Description |
|------------|--------|-------------|
| `{{id}}` | Computed | Node identifier in snake_case. Example: `parse_intent`, `start_execution` |
| `{{type}}` | Computed | Node type: `action`, `conditional`, `user_prompt`, or `reference` |
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
| `{{#if_reference}}` | Computed | Block included only for `type: reference` nodes |
| `{{doc}}` | Computed | Path to the referenced document |
| `{{section}}` | Computed | Optional section heading within the referenced document |
| `{{next_node}}` | Computed | Next node after reference processing completes |

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
| `{{type}}` | Computed | Precondition type (e.g., `tool_available`, `path_check`) |
| `{{#params}}` | Computed | Loop over precondition parameters |

---

## Placeholder Resolution Order

Placeholders must be resolved in a specific order because some depend on others:

```
1. User input (Phase 1):
   skill_name  -->  skill_directory, skill_short_name, title, skill_id
   structure   -->  needs_gateway, needs_intent_mapping
   features    -->  conditional section flags

2. Context detection (Phase 2):
   has_plugin_manifest   -->  parent_plugin_name
   has_version_file      -->  lib_version, lib_ref

3. Derived values (Phase 4/5):
   skill_name + features  -->  description
   features               -->  allowed_tools
   features               -->  start_node, state_variables
   skill_name             -->  success_message
   start_node + features  -->  nodes (starter set)
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
| lib_version is semver with v prefix | Matches `/^v\d+\.\d+\.\d+$/` | Invalid library version format |

---

## Examples

### Minimal Skill (no optional features)

```
skill_name:          "my-tool-run"
skill_directory:     "my-tool-run"
skill_short_name:    "run"
title:               "My Tool Run"
parent_plugin_name:  "my-tool"
description:         "This skill should be used when the user asks to \"run\". Triggers on \"run\"."
allowed_tools:       "Read, Write, Glob, Bash, AskUserQuestion"
lib_version:         "v3.0.0"
lib_ref:             "hiivmind/hiivmind-blueprint-lib@v3.0.0"
skill_id:            "my-tool-run"
start_node:          "start_execution"
state_variables:     "phase, flags, computed"
success_message:     "My Tool Run completed successfully"
```

Conditional sections removed: `if_runtime_flags`, `if_intent_detection`, `workflow_graph`.

### Full-Featured Skill (all features enabled)

```
skill_name:          "data-pipeline-setup"
skill_directory:     "data-pipeline-setup"
skill_short_name:    "setup"
title:               "Data Pipeline Setup"
parent_plugin_name:  "data-pipeline"
description:         "This skill should be used when the user asks to \"setup\", \"initialize pipeline\"... Triggers on \"setup\", \"init\"."
allowed_tools:       "Read, Write, Glob, Bash, AskUserQuestion"
lib_version:         "v3.0.0"
lib_ref:             "hiivmind/hiivmind-blueprint-lib@v3.0.0"
skill_id:            "data-pipeline-setup"
start_node:          "parse_intent"
state_variables:     "phase, flags, computed, intent_flags, intent_matches"
success_message:     "Data Pipeline Setup completed successfully"
```

Conditional sections included: `if_runtime_flags`, `if_intent_detection`, `workflow_graph`, `examples`.
