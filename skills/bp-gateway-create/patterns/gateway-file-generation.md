# Gateway File Generation

> **Used by:** `SKILL.md` Phase 3
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`

This document provides the complete placeholder catalog for generating the three gateway
files. Each placeholder uses `{{placeholder}}` syntax in templates and is substituted at
generation time from `computed.*` state.

---

## Placeholder Catalog

### Universal Placeholders

These placeholders appear across multiple templates and must be consistent:

| Placeholder | Source | Description | Example |
|-------------|--------|-------------|---------|
| `{{plugin_name}}` | `computed.plugin_name` | Plugin identifier (kebab-case) | `hiivmind-pulse-gh` |
| `{{plugin_description}}` | `computed.plugin_description` | One-line plugin purpose | `GitHub automation plugin` |
| `{{PLUGIN_TITLE}}` | Derived from `computed.plugin_name` | Uppercase display title | `HIIVMIND PULSE GH` |
| `{{lib_ref}}` | `BLUEPRINT_LIB_VERSION.yaml` | External lib reference | `hiivmind/hiivmind-blueprint-lib@{computed.lib_version}` |
| `{{lib_version}}` | Extracted from `{{lib_ref}}` | Version tag only | `{computed.lib_version}` |

### Gateway Command Template (`gateway-command.md.template`)

Placeholders specific to the gateway command markdown file:

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `{{plugin_name}}` | Universal | Used in frontmatter `name:`, usage examples, help commands |
| `{{#if_runtime_flags}}...{{/if_runtime_flags}}` | Always `true` for gateways | Conditional block for runtime flag section |
| `{{#workflow_graph}}...{{/workflow_graph}}` | `computed.workflow_graph` | Optional ASCII graph of node topology |
| `{{graph_ascii}}` | `computed.workflow_graph.ascii` | The actual ASCII graph content |
| `{{#examples}}...{{/examples}}` | `computed.examples` | Loop over usage examples |
| `{{command}}` | `computed.examples[].command` | Full command string (e.g., `/my-plugin create skill`) |
| `{{skill_name}}` | `computed.examples[].skill_name` | Name of skill the example routes to |
| `{{#if_intent_detection}}...{{/if_intent_detection}}` | `computed.gateway_mode == "full"` | Conditional: include 3VL explanation |
| `{{#skills}}...{{/skills}}` | `computed.skills` | Loop over all skills for Related Skills section |
| `{{skill_label}}` | `computed.skills[].name` | Human-readable skill name |
| `{{skill_directory}}` | `computed.skills[].id` | Directory name containing the skill |

### Intent Mapping Template (`intent-mapping.yaml.template`)

Placeholders for the intent detection configuration:

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `{{plugin_name}}` | Universal | Comment header, action references |
| `{{PLUGIN_TITLE}}` | Universal | Display title in help action content |
| `{{plugin_description}}` | Universal | Show in full help action content |
| `{{#skill_flags}}...{{/skill_flags}}` | `computed.intent_flags` (skill-specific only) | Loop to generate `has_{skill_id}` flags |
| `{{skill_id}}` | `computed.skills[].id` (sanitized) | Skill identifier for flag/rule/action names |
| `{{skill_name}}` | `computed.skills[].name` | Full skill name for descriptions |
| `{{#keywords}}...{{/keywords}}` | `computed.intent_flags[].keywords` | Loop over flag keywords |
| `{{#negative_keywords}}...{{/negative_keywords}}` | `computed.intent_flags[].negative_keywords` | Optional negative keyword loop |
| `{{#skill_help_rules}}...{{/skill_help_rules}}` | Derived from `computed.skills` | Loop to generate per-skill help rules |
| `{{#init_skill}}...{{/init_skill}}` | Skill mapped to `has_init` | Conditional: generate init rule |
| `{{init_skill_id}}` | ID of skill mapped to init action | Used in `delegate_{{init_skill_id}}` |
| `{{init_target}}` | Short noun for what init creates | e.g., `skill`, `corpus`, `plugin` |
| `{{#query_skill}}...{{/query_skill}}` | Skill mapped to `has_query` | Conditional: generate query rule |
| `{{query_skill_id}}` | ID of skill mapped to query action | Used in `delegate_{{query_skill_id}}` |
| `{{query_target}}` | Short noun for what query shows | e.g., `skills`, `status`, `inventory` |
| `{{#modify_skill}}...{{/modify_skill}}` | Skill mapped to `has_modify` | Conditional: generate modify rule |
| `{{modify_skill_id}}` | ID of skill mapped to modify action | Used in `delegate_{{modify_skill_id}}` |
| `{{modify_target}}` | Short noun for what modify changes | e.g., `configuration`, `rules` |
| `{{#skill_rules}}...{{/skill_rules}}` | `computed.intent_rules` (skill-specific only) | Loop for custom skill routing rules |
| `{{rule_name}}` | `computed.intent_rules[].name` | Unique rule identifier |
| `{{#conditions}}...{{/conditions}}` | `computed.intent_rules[].conditions` | Loop over flag/value pairs |
| `{{flag}}` | Condition flag name | e.g., `has_init` |
| `{{value}}` | Condition flag value | `T`, `F`, or `U` |
| `{{#skills}}...{{/skills}}` | `computed.skills` | Loop for action definitions and menu options |
| `{{skill_label}}` | `computed.skills[].name` | Display label in menu |
| `{{skill_short_desc}}` | First sentence of `computed.skills[].description` | Menu option description |
| `{{skill_command}}` | Primary command keyword for skill | e.g., `create`, `discover`, `analyze` |
| `{{padding}}` | Computed whitespace | Aligns descriptions in help display |
| `{{skill_purpose}}` | `computed.skills[].description` (full) | Detailed purpose for skill-specific help |
| `{{skill_description}}` | `computed.skills[].description` | Full description text |
| `{{#skill_examples}}...{{/skill_examples}}` | `computed.skills[].examples` | Loop for skill-specific usage examples |
| `{{example}}` | `computed.skills[].examples[]` | Individual example command string |
| `{{#skill_help_actions}}...{{/skill_help_actions}}` | Derived from `computed.skills` | Loop for per-skill help display actions |

### Workflow Template (`workflow.yaml.template`)

The gateway workflow uses a subset of the general workflow template placeholders:

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `{{skill_id}}` | `computed.plugin_name + "-gateway"` | Workflow name |
| `{{description}}` | Gateway description string | Workflow description |
| `{{lib_ref}}` | Universal | `definitions.source` value |
| `{{start_node}}` | Always `check_arguments` | Entry point node |
| `{{success_message}}` | `"Request handled by " + computed.plugin_name` | Success ending message |

---

## Substitution Procedure

The substitution process follows this order:

1. **Load template** -- Read the `.template` file from `${CLAUDE_PLUGIN_ROOT}/templates/`
2. **Resolve universal placeholders** -- `plugin_name`, `PLUGIN_TITLE`, `lib_ref`, `lib_version`
3. **Resolve conditional blocks** -- Evaluate `{{#if_*}}...{{/if_*}}` and include or exclude
4. **Resolve loop blocks** -- Expand `{{#items}}...{{/items}}` for each element
5. **Resolve remaining placeholders** -- Substitute all `{{name}}` tokens with values
6. **Strip template comments** -- Remove lines starting with `#` that are template metadata
7. **Validate output** -- Ensure no unresolved `{{...}}` tokens remain

```pseudocode
SUBSTITUTE_TEMPLATE(template, context):
  output = template

  # Step 1: Conditionals
  FOR conditional IN find_all(output, /\{\{#if_(\w+)\}\}(.*?)\{\{\/if_\1\}\}/s):
    flag_name = conditional.group(1)
    content = conditional.group(2)
    IF context[flag_name]:
      output = output.replace(conditional.group(0), content)
    ELSE:
      output = output.replace(conditional.group(0), "")

  # Step 2: Loops
  FOR loop IN find_all(output, /\{\{#(\w+)\}\}(.*?)\{\{\/\1\}\}/s):
    collection_name = loop.group(1)
    body = loop.group(2)
    items = context[collection_name]
    expanded = ""
    FOR item IN items:
      expanded += substitute_placeholders(body, item)
    output = output.replace(loop.group(0), expanded)

  # Step 3: Simple placeholders
  FOR placeholder IN find_all(output, /\{\{(\w+)\}\}/):
    name = placeholder.group(1)
    IF name IN context:
      output = output.replace(placeholder.group(0), str(context[name]))

  # Step 4: Validation
  remaining = find_all(output, /\{\{(\w+)\}\}/)
  IF remaining:
    WARN "Unresolved placeholders: " + [r.group(1) for r in remaining]

  RETURN output
```

---

## File Output Locations

| File | Output Path | Template Source |
|------|------------|----------------|
| Gateway command | `${CLAUDE_PLUGIN_ROOT}/commands/{plugin_name}.md` | `gateway-command.md.template` |
| Intent mapping | `${CLAUDE_PLUGIN_ROOT}/commands/{plugin_name}/intent-mapping.yaml` | `intent-mapping.yaml.template` |
| Gateway workflow | `${CLAUDE_PLUGIN_ROOT}/commands/{plugin_name}/workflow.yaml` | `workflow.yaml.template` (gateway variant) |

---

## Related Documentation

- **SKILL.md Phase 3:** `../SKILL.md` -- Generation steps that invoke this procedure
- **Routing Design Procedure:** `routing-design-procedure.md` -- Node interconnection design
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Gateway Command Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
