> **Used by:** `SKILL.md` Phases 2-5
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`, `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`

# Gateway Validation Checklist

Complete checklist of all validation checks performed by the gateway-validate skill, organized by dimension. Each check has an ID, description, severity level, and automated detection method.

---

## Severity Levels

| Level | Meaning | Action Required |
|-------|---------|-----------------|
| **error** | Must fix before gateway will route correctly | Blocks correct operation |
| **warning** | Should fix; may cause unexpected behavior | Review and address |
| **info** | Observation or suggestion | Optional improvement |

---

## Dimension 1: Route Completeness (8 checks)

Ensures every skill is reachable through the gateway and all routing paths are complete.

| ID | Check | Severity | Detection Method |
|----|-------|----------|-----------------|
| RC-01 | All skills have delegation nodes | error | Compare `Glob(skills/*/SKILL.md)` against workflow delegation node targets. `missing = set(discovered_skills) - set(delegated_skills)` |
| RC-02 | No extra delegation nodes for nonexistent skills | warning | `extra = set(delegated_skills) - set(discovered_skills)` |
| RC-03 | Intent mapping present (if used) | info | Check `file_exists(intent-mapping.yaml)`. If absent, skip intent-related checks. |
| RC-04 | All rule delegate actions have definitions | error | For each `delegate_*` action in intent rules, verify it exists in the `actions` section or as a workflow node ID. |
| RC-05 | Fallback rule exists | error | Check for a rule with `conditions: {}` or a `fallback:` section in intent-mapping.yaml. |
| RC-06 | Menu node present | warning | Scan workflow for a `user_prompt` node with 2+ options. |
| RC-07 | Menu includes all skills | warning | Extract option IDs from the menu node; compare against discovered skill short names. |
| RC-08 | No orphan menu options | info | Check each menu option ID corresponds to a discovered skill. Extra options may be intentional (e.g., "help"). |

**Pseudocode summary:**

```
delegation_nodes = [n for n in workflow.nodes if n.id.startswith("delegate_")]
delegated_skills = [n.actions[0].skill for n in delegation_nodes]
discovered_skills = [extract_name(f) for f in Glob("skills/*/SKILL.md")]
missing = set(discovered_skills) - set(delegated_skills)    # RC-01
extra = set(delegated_skills) - set(discovered_skills)       # RC-02

menu_node = find_user_prompt_with_options(workflow.nodes)     # RC-06
menu_options = [opt.id for opt in menu_node.prompt.options]
menu_missing = set(skill_short_names) - set(menu_options)     # RC-07
```

---

## Dimension 2: Intent Alignment (6 checks)

Ensures the intent-mapping.yaml is internally consistent and correctly linked to the workflow.

| ID | Check | Severity | Detection Method |
|----|-------|----------|-----------------|
| IA-01 | All rule actions have definitions | error | For each `action` field in intent rules, verify a matching key exists in the `actions` section. |
| IA-02 | No orphan action definitions | warning | For each key in `actions`, verify at least one rule references it. `orphans = set(actions.keys()) - set(rule_actions)` |
| IA-03 | Skill names match between workflow and mapping | error | Compare `delegate_X` skill name in intent-mapping `actions` with the corresponding `mutate_state` value in workflow `on_response` handlers. |
| IA-04 | Help actions defined | warning | Check that `show_full_help` and `show_flag_help` exist in the `actions` section. |
| IA-05 | Extended help actions present | info | Check for `show_logging_help`, `show_display_help`, `show_prompts_help` in `actions`. Optional but enhances UX. |
| IA-06 | Help intent flags defined | warning | Verify `has_help` or `has_help_flag` exists in `intent_flags` with keywords like `"help"`, `"--help"`, `"-h"`. |

**Pseudocode summary:**

```
rule_actions = set(rule.action for rule in intent_rules)
defined_actions = set(actions.keys())
undefined = rule_actions - defined_actions                    # IA-01
orphan_defs = defined_actions - rule_actions                  # IA-02

for action_id in defined_actions:
  if action_id.startswith("delegate_"):
    intent_skill = actions[action_id].skill
    short = action_id.replace("delegate_", "")
    workflow_skill = workflow.on_response[short].consequence[0].value
    assert intent_skill == workflow_skill                     # IA-03
```

---

## Dimension 3: Skill References (5 checks)

Ensures all skill references resolve to real files and paths are correct.

| ID | Check | Severity | Detection Method |
|----|-------|----------|-----------------|
| SR-01 | All invoke_skill targets exist | error | For each `invoke_skill` action (non-dynamic), resolve the skill path and verify `SKILL.md` exists at `skills/{name}/SKILL.md`. |
| SR-02 | SKILL.md files found at expected paths | info | Positive confirmation for each resolved skill reference. |
| SR-03 | No broken path references | warning | Scan all three gateway files for `${CLAUDE_PLUGIN_ROOT}/...` paths; resolve and check file existence. |
| SR-04 | Gateway allowed-tools sufficient | warning | Parse gateway .md frontmatter `allowed-tools`; verify minimum set includes `Read` and `AskUserQuestion`. |
| SR-05 | Recommended tools present | info | Check for `Glob` and `Bash` in allowed-tools (recommended but not required). |

**Pseudocode summary:**

```
skill_refs = extract_invoke_skill_targets(workflow)
skill_refs += extract_delegate_skills(intent_mapping.actions)

for ref in skill_refs:
  if "${" in ref:
    continue  # dynamic reference, cannot validate statically
  path = plugin_root + "/skills/" + ref + "/SKILL.md"
  assert file_exists(path)                                    # SR-01

path_refs = regex_findall(r'\$\{CLAUDE_PLUGIN_ROOT\}/(\S+)', all_file_text)
for path_ref in path_refs:
  resolved = plugin_root + "/" + path_ref
  assert file_exists(resolved) or dir_exists(resolved)       # SR-03

allowed = parse_frontmatter(command_md)["allowed-tools"].split(",")
assert "Read" in allowed and "AskUserQuestion" in allowed    # SR-04
```

---

## Dimension 4: Structure (6+ checks)

Validates internal consistency and correct structure of each gateway file.

| ID | Check | Severity | Detection Method |
|----|-------|----------|-----------------|
| ST-01 | Gateway .md frontmatter valid | error | Parse YAML frontmatter; verify `name` and `description` fields are present and non-empty. |
| ST-02 | Arguments section present | warning | Check for `arguments` key in frontmatter (recommended for CLI discoverability). |
| ST-03 | Command name matches directory | warning | Compare `frontmatter.name` with `basename(gateway_directory)` or parent directory name. |
| ST-04 | Intent checking node exists | warning | Scan workflow for a `conditional` node whose condition references `matched_action`, `matched_skill`, `arguments`, or `intent`. |
| ST-05 | Menu node exists | warning | Scan workflow for a `user_prompt` node with 2+ options. |
| ST-06 | Skill dispatch node exists | error | Scan workflow for an `action` node with an `invoke_skill` consequence. |
| ST-07 | Intent flags section populated | warning | Check `intent_flags` in intent-mapping.yaml is non-empty. |
| ST-08 | All flags have keywords array | error | For each flag in `intent_flags`, verify `keywords` is present and is a non-empty array. |
| ST-09 | No empty keywords arrays | warning | For each flag, verify `keywords` has at least one entry. |
| ST-10 | Flag naming convention | info | Verify all intent flag names use the `has_` prefix. Non-standard names may indicate a typo. |
| ST-11 | Rules section populated | error | Check `rules` or `intent_rules` in intent-mapping.yaml is a non-empty array. |
| ST-12 | All rules have conditions | error | Each rule must have a `conditions` or `condition` field. |
| ST-13 | All rules have action | error | Each rule must have an `action` field specifying the target action. |
| ST-14 | Rule conditions reference valid flags | error | Each flag name in a rule's conditions must exist in `intent_flags`. |
| ST-15 | No circular routing | warning | Verify dispatch nodes (`invoke_skill`) do not route back to routing/intent-checking nodes via `on_success` or `on_failure`. |

**Pseudocode summary:**

```
# ST-01: Frontmatter
fm = extract_frontmatter(command_md)
assert "name" in fm and fm["name"] != ""
assert "description" in fm and fm["description"] != ""

# ST-04/05/06: Routing patterns
has_intent_check = any(
  n.type == "conditional" and "matched" in n.condition.field
  for n in workflow.nodes
)
has_menu = any(
  n.type == "user_prompt" and len(n.prompt.options) >= 2
  for n in workflow.nodes
)
has_dispatch = any(
  n.type == "action" and any(a.type == "invoke_skill" for a in n.actions)
  for n in workflow.nodes
)

# ST-14: Flag reference validation
for rule in rules:
  for flag_name in rule.conditions.keys():
    assert flag_name in intent_flags

# ST-15: Circular routing
routing_nodes = {start_node} | {intent_check_nodes} | {menu_nodes}
dispatch_nodes = {nodes with invoke_skill}
for dn in dispatch_nodes:
  assert dn.on_success not in routing_nodes
  assert dn.on_failure not in routing_nodes
```

---

## Check Count Summary

| Dimension | Checks | Errors (max) | Warnings (max) | Info (max) |
|-----------|--------|--------------|----------------|------------|
| Route Completeness | 8 | 3 | 2 | 3 |
| Intent Alignment | 6 | 2 | 2 | 2 |
| Skill References | 5 | 1 | 2 | 2 |
| Structure | 15 | 7 | 5 | 3 |
| **Total** | **34** | **13** | **11** | **10** |

Note: Actual issue counts depend on the gateway being validated. Multiple instances of the same check can fire (e.g., RC-01 fires once per missing skill, ST-08 fires once per flag without keywords).

---

## Fix Suggestion Map

Quick-reference map from check ID to recommended fix:

| ID | Fix |
|----|-----|
| RC-01 | Add a delegation node or intent rule for the missing skill |
| RC-02 | Remove the orphan delegation node or create the referenced skill |
| RC-04 | Add an action definition in intent-mapping.yaml `actions` section |
| RC-05 | Add `fallback: { action: show_menu }` or a rule with `conditions: {}` |
| RC-07 | Add an option in the menu node's `prompt.options` array |
| IA-01 | Add the missing action to the `actions` section |
| IA-02 | Remove unused action definition or add a rule referencing it |
| IA-03 | Align skill names between intent-mapping and workflow |
| IA-04 | Add `show_full_help` and `show_flag_help` action definitions |
| IA-06 | Add `has_help` flag with keywords: `["help", "--help", "-h"]` |
| SR-01 | Create the skill or fix the skill name reference |
| SR-03 | Update the broken path or create the missing file |
| SR-04 | Add `Read, AskUserQuestion` to the gateway .md `allowed-tools` |
| ST-01 | Add YAML frontmatter with `name` and `description` |
| ST-03 | Make `name` match the directory name |
| ST-06 | Add an `invoke_skill` action node for dispatching to skills |
| ST-08 | Add `keywords: [...]` to the intent flag definition |
| ST-11 | Add at least one rule to the `rules` array |
| ST-12 | Add `conditions: { ... }` to the rule |
| ST-13 | Add `action: <target_action>` to the rule |
| ST-14 | Define the referenced flag in `intent_flags` or fix the flag name |
| ST-15 | Route dispatch `on_success` to an ending, not back to routing |

---

## Related Documentation

- **Gateway Command Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Schema Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/patterns/schema-validation-rules.md`
- **Graph Validation Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/patterns/graph-validation-algorithm.md`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
