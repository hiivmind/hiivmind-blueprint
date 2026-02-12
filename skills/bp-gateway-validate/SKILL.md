---
name: bp-gateway-validate
description: >
  This skill should be used when the user asks to "validate gateway", "check gateway routing",
  "verify gateway command", "lint gateway", "test gateway", or needs to verify a gateway
  command structure is complete and correct. Triggers on "validate gateway", "check gateway",
  "verify gateway", "lint gateway", "test gateway", "gateway errors".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Validate Gateway Command

Comprehensive read-only validation of a gateway command across 4 dimensions: route completeness, intent alignment, skill references, and structure. Reports all issues without modifying any files.

> **Validation Checklist:** `patterns/gateway-validation-checklist.md`
> **Gateway Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
> **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
> **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`

---

## Procedure Overview

```
+--------------------------+
| Phase 1: Load            |
|   Gateway Files          |
+-----------+--------------+
            |
+-----------v--------------+
| Phase 2: Route           |
|   Completeness           |
+-----------+--------------+
            |
+-----------v--------------+
| Phase 3: Intent          |
|   Mapping Alignment      |
+-----------+--------------+
            |
+-----------v--------------+
| Phase 4: Skill           |
|   Reference Validation   |
+-----------+--------------+
            |
+-----------v--------------+
| Phase 5: Structure       |
|   Validation             |
+-----------+--------------+
            |
+-----------v--------------+
| Phase 6: Report          |
+--------------------------+
```

---

## Phase 1: Load Gateway Files

### Step 1.1: Determine Gateway Location

Determine the gateway command directory to validate.

**If path was provided as argument:**

1. Read the file at the provided path.
2. If it is a directory, look for `workflow.yaml`, `intent-mapping.yaml`, and a sibling `.md` file inside it.
3. If it is a single file, infer the directory from the parent and locate the other two files.
4. Store the resolved directory in `computed.gateway.directory`.

**If no path was provided:**

Present an AskUserQuestion to locate the gateway:

```json
{
  "questions": [{
    "question": "Which gateway command should I validate?",
    "header": "Gateway Location",
    "options": [
      {
        "label": "I'll provide a path",
        "description": "Enter the path to the gateway command directory"
      },
      {
        "label": "Search commands/ directory",
        "description": "Glob for commands/*/workflow.yaml under the plugin root"
      },
      {
        "label": "Search current directory",
        "description": "Glob for **/commands/*/workflow.yaml in the working directory"
      }
    ],
    "multiSelect": false
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_RESPONSE(response):
  IF response == "I'll provide a path":
    # Ask the user to enter the path
    user_path = AskUserQuestion("Enter the gateway directory path:")
    IF directory_exists(user_path):
      computed.gateway.directory = user_path
    ELSE:
      DISPLAY "Error: Directory not found at " + user_path
      EXIT
  ELSE IF response == "Search commands/ directory":
    # Use Glob to find all gateway workflows under the plugin root
    matches = Glob(pattern: "${CLAUDE_PLUGIN_ROOT}/commands/*/workflow.yaml")
    IF len(matches) == 0:
      DISPLAY "No gateway commands found in commands/ directory"
      EXIT
    ELSE IF len(matches) == 1:
      computed.gateway.directory = parent_directory(matches[0])
    ELSE:
      # Multiple found, present list as follow-up question
      selected = AskUserQuestion("Multiple gateways found. Select one:", matches)
      computed.gateway.directory = parent_directory(selected)
  ELSE IF response == "Search current directory":
    # Use Glob to search current working directory
    matches = Glob(pattern: "**/commands/*/workflow.yaml")
    IF len(matches) == 0:
      DISPLAY "No gateway commands found in current directory"
      EXIT
    ELSE IF len(matches) == 1:
      computed.gateway.directory = parent_directory(matches[0])
    ELSE:
      # Multiple found, present list
      selected = AskUserQuestion("Multiple gateways found. Select one:", matches)
      computed.gateway.directory = parent_directory(selected)
```

Store the resolved directory in `computed.gateway.directory`.

### Step 1.2: Read All Three Gateway Files

Read the three gateway files from `computed.gateway.directory`:

```pseudocode
LOAD_GATEWAY_FILES():
  base_dir = computed.gateway.directory

  # 1. Gateway command markdown (.md)
  md_candidates = Glob(base_dir + "/../*.md")
  IF len(md_candidates) == 0:
    md_candidates = Glob(base_dir + "/*.md")
  IF len(md_candidates) == 0:
    computed.gateway.command_md = null
    computed.validation.load_issues.append({
      severity: "error",
      message: "No gateway command .md file found in " + base_dir
    })
  ELSE:
    computed.gateway.command_md_path = md_candidates[0]
    computed.gateway.command_md = Read(md_candidates[0])

  # 2. Gateway workflow (workflow.yaml)
  workflow_path = base_dir + "/workflow.yaml"
  IF file_exists(workflow_path):
    computed.gateway.workflow_path = workflow_path
    computed.gateway.workflow = Read(workflow_path)
  ELSE:
    computed.gateway.workflow = null
    computed.validation.load_issues.append({
      severity: "error",
      message: "workflow.yaml not found at " + workflow_path
    })

  # 3. Intent mapping (intent-mapping.yaml)
  intent_path = base_dir + "/intent-mapping.yaml"
  IF file_exists(intent_path):
    computed.gateway.intent_mapping_path = intent_path
    computed.gateway.intent_mapping = Read(intent_path)
  ELSE:
    computed.gateway.intent_mapping = null
    computed.validation.load_issues.append({
      severity: "warning",
      message: "intent-mapping.yaml not found at " + intent_path + " (optional but recommended)"
    })
```

### Step 1.3: Validate Parsability

Verify each loaded file parses correctly before proceeding to deeper validation:

```pseudocode
VALIDATE_PARSABILITY():
  # Check workflow.yaml parses as valid YAML
  IF computed.gateway.workflow IS NOT null:
    parsed = parse_yaml(computed.gateway.workflow)
    IF parsed IS INVALID:
      computed.validation.load_issues.append({
        severity: "error",
        message: "workflow.yaml is not valid YAML: " + parse_error
      })
    ELSE:
      computed.gateway.workflow_parsed = parsed

  # Check intent-mapping.yaml parses as valid YAML
  IF computed.gateway.intent_mapping IS NOT null:
    parsed = parse_yaml(computed.gateway.intent_mapping)
    IF parsed IS INVALID:
      computed.validation.load_issues.append({
        severity: "error",
        message: "intent-mapping.yaml is not valid YAML: " + parse_error
      })
    ELSE:
      computed.gateway.intent_mapping_parsed = parsed

  # Check command .md has valid frontmatter
  IF computed.gateway.command_md IS NOT null:
    frontmatter = extract_yaml_frontmatter(computed.gateway.command_md)
    IF frontmatter IS INVALID:
      computed.validation.load_issues.append({
        severity: "error",
        message: "Gateway .md file has invalid or missing YAML frontmatter"
      })
    ELSE:
      computed.gateway.command_frontmatter = frontmatter

  # If any fatal load errors, report and stop
  fatal_errors = [i for i in computed.validation.load_issues if i.severity == "error"]
  IF len(fatal_errors) > 0:
    DISPLAY "## Load Errors"
    FOR issue IN fatal_errors:
      DISPLAY "- [ERROR] " + issue.message
    DISPLAY ""
    DISPLAY "Cannot proceed with validation until load errors are resolved."
    EXIT
```

Store all parsed structures in `computed.gateway.workflow_parsed`, `computed.gateway.intent_mapping_parsed`, and `computed.gateway.command_frontmatter`.

Initialize issue collectors:
```
computed.validation.route_issues = []
computed.validation.intent_issues = []
computed.validation.reference_issues = []
computed.validation.structure_issues = []
```

---

## Phase 2: Route Completeness

Validate that the gateway workflow routes to all skills and that all routing paths are complete.

### Step 2.1: Delegation Node Coverage

Extract all delegation nodes from the workflow and compare against discovered skills in the plugin.

```pseudocode
CHECK_DELEGATION_COVERAGE():
  workflow = computed.gateway.workflow_parsed

  # Extract delegation nodes from workflow
  delegation_nodes = [n for n_id, n in workflow.nodes
                      if n_id.startswith("delegate_") OR
                         (n.type == "action" AND any(a.type == "invoke_skill" for a in n.get("actions", [])))]
  delegated_skills = []
  FOR node in delegation_nodes:
    FOR action in node.get("actions", []):
      IF action.type == "invoke_skill":
        delegated_skills.append(action.skill OR action.skill_path)

  # Also extract skill names from dynamic routing (execute_skill node pattern)
  IF "execute_skill" in workflow.nodes:
    exec_node = workflow.nodes["execute_skill"]
    FOR action in exec_node.get("actions", []):
      IF action.type == "invoke_skill" AND "${" in str(action.get("skill_path", "")):
        computed.gateway.uses_dynamic_routing = true

  # Discover all skills in the plugin
  plugin_root = extract_plugin_root(computed.gateway.directory)
  skill_files = Glob(plugin_root + "/skills/*/SKILL.md")
  discovered_skills = [extract_skill_name(f) for f in skill_files]

  computed.gateway.delegated_skills = delegated_skills
  computed.gateway.discovered_skills = discovered_skills

  # Compare sets
  IF NOT computed.gateway.uses_dynamic_routing:
    missing = set(discovered_skills) - set(delegated_skills)
    extra = set(delegated_skills) - set(discovered_skills)

    FOR skill in missing:
      computed.validation.route_issues.append({
        severity: "error",
        dimension: "route_completeness",
        check_id: "RC-01",
        message: "Skill '" + skill + "' exists in skills/ but has no delegation node in workflow"
      })
    FOR skill in extra:
      computed.validation.route_issues.append({
        severity: "warning",
        dimension: "route_completeness",
        check_id: "RC-02",
        message: "Delegation node references skill '" + skill + "' which was not found in skills/"
      })
```

### Step 2.2: Intent Rule to Delegation Node Mapping

Verify that every delegation action in the intent rules has a corresponding target in the workflow.

```pseudocode
CHECK_RULE_TO_DELEGATION():
  IF computed.gateway.intent_mapping_parsed IS null:
    computed.validation.route_issues.append({
      severity: "info",
      dimension: "route_completeness",
      check_id: "RC-03",
      message: "No intent-mapping.yaml found; skipping rule-to-delegation check"
    })
    RETURN

  intent_mapping = computed.gateway.intent_mapping_parsed
  rules = intent_mapping.get("rules", intent_mapping.get("intent_rules", []))

  # Extract all delegate_ actions from rules
  rule_actions = set()
  FOR rule in rules:
    action = rule.get("action", "")
    IF action.startswith("delegate_"):
      rule_actions.add(action)

  # Extract all delegation targets from actions section (if present)
  actions_section = intent_mapping.get("actions", {})
  action_delegates = set()
  FOR action_id, action_def in actions_section:
    IF action_id.startswith("delegate_"):
      action_delegates.add(action_id)

  # Cross-check: every rule delegate_ action should have a matching delegation node
  workflow_node_ids = set(computed.gateway.workflow_parsed.get("nodes", {}).keys())

  FOR action in rule_actions:
    IF action not in action_delegates AND action not in workflow_node_ids:
      computed.validation.route_issues.append({
        severity: "error",
        dimension: "route_completeness",
        check_id: "RC-04",
        message: "Intent rule action '" + action + "' has no matching action definition or workflow node"
      })
```

### Step 2.3: Fallback Exists

Verify that a fallback rule with empty conditions exists in the intent mapping, providing a menu or default action when no intent is matched.

```pseudocode
CHECK_FALLBACK():
  intent_mapping = computed.gateway.intent_mapping_parsed
  IF intent_mapping IS null:
    RETURN

  # Check for explicit fallback section
  has_explicit_fallback = "fallback" in intent_mapping

  # Check for empty-conditions rule in intent_rules
  rules = intent_mapping.get("rules", intent_mapping.get("intent_rules", []))
  has_empty_rule = false
  FOR rule in rules:
    conditions = rule.get("conditions", rule.get("condition", {}))
    IF conditions IS EMPTY OR conditions == {}:
      has_empty_rule = true
      computed.gateway.fallback_action = rule.get("action", "show_main_menu")

  IF NOT has_explicit_fallback AND NOT has_empty_rule:
    computed.validation.route_issues.append({
      severity: "error",
      dimension: "route_completeness",
      check_id: "RC-05",
      message: "No fallback rule found. Add a rule with empty conditions or a 'fallback:' section"
    })
  ELSE:
    computed.validation.route_issues.append({
      severity: "info",
      dimension: "route_completeness",
      check_id: "RC-05",
      message: "Fallback rule present: action = '" + computed.gateway.fallback_action + "'"
    })
```

### Step 2.4: Menu Skill Coverage

Verify that the `show_main_menu` user_prompt node (or equivalent) offers options for all discovered skills.

```pseudocode
CHECK_MENU_COVERAGE():
  workflow = computed.gateway.workflow_parsed
  menu_node = null

  # Find the menu node (typically show_menu or show_main_menu)
  FOR node_id, node in workflow.get("nodes", {}):
    IF node.get("type") == "user_prompt":
      prompt = node.get("prompt", {})
      options = prompt.get("options", [])
      IF len(options) >= 2:
        menu_node = node
        menu_node_id = node_id
        break

  IF menu_node IS null:
    computed.validation.route_issues.append({
      severity: "warning",
      dimension: "route_completeness",
      check_id: "RC-06",
      message: "No menu node (user_prompt with multiple options) found in workflow"
    })
    RETURN

  # Extract option IDs from the menu
  menu_options = [opt.get("id") for opt in menu_node.get("prompt", {}).get("options", [])]

  # Check that menu covers all discovered skills (by short name)
  discovered_short_names = [extract_short_name(s) for s in computed.gateway.discovered_skills]

  FOR short_name in discovered_short_names:
    IF short_name not in menu_options:
      computed.validation.route_issues.append({
        severity: "warning",
        dimension: "route_completeness",
        check_id: "RC-07",
        message: "Skill '" + short_name + "' is not listed in the menu options of node '" + menu_node_id + "'"
      })

  # Also check for extra menu options that do not map to skills
  FOR option_id in menu_options:
    IF option_id not in discovered_short_names:
      computed.validation.route_issues.append({
        severity: "info",
        dimension: "route_completeness",
        check_id: "RC-08",
        message: "Menu option '" + option_id + "' does not correspond to a discovered skill short name"
      })
```

---

## Phase 3: Intent Mapping Alignment

Validate that the intent-mapping.yaml is internally consistent and aligned with the workflow.

### Step 3.1: Action Definitions Match Rule References

Verify that every action referenced in `intent_rules` has a corresponding definition in the `actions` section.

```pseudocode
CHECK_ACTION_DEFINITIONS():
  intent_mapping = computed.gateway.intent_mapping_parsed
  IF intent_mapping IS null:
    computed.validation.intent_issues.append({
      severity: "info",
      dimension: "intent_alignment",
      check_id: "IA-01",
      message: "No intent-mapping.yaml; skipping action definition checks"
    })
    RETURN

  rules = intent_mapping.get("rules", intent_mapping.get("intent_rules", []))
  actions_section = intent_mapping.get("actions", {})
  fallback = intent_mapping.get("fallback", {})

  # Collect all action names referenced by rules
  rule_action_names = set()
  FOR rule in rules:
    action = rule.get("action", "")
    IF action:
      rule_action_names.add(action)

  # Add fallback action
  IF "action" in fallback:
    rule_action_names.add(fallback["action"])

  # Check each referenced action exists in the actions section
  FOR action_name in rule_action_names:
    IF action_name not in actions_section:
      computed.validation.intent_issues.append({
        severity: "error",
        dimension: "intent_alignment",
        check_id: "IA-01",
        message: "Rule references action '" + action_name + "' but no definition found in actions section"
      })

  # Check for orphan action definitions (defined but never referenced)
  FOR action_id in actions_section:
    IF action_id not in rule_action_names:
      computed.validation.intent_issues.append({
        severity: "warning",
        dimension: "intent_alignment",
        check_id: "IA-02",
        message: "Action definition '" + action_id + "' is never referenced by any intent rule"
      })
```

### Step 3.2: Skill Name Consistency

Verify that skill names used in `delegate_X` actions are consistent between the workflow and the intent-mapping.

```pseudocode
CHECK_SKILL_NAME_CONSISTENCY():
  intent_mapping = computed.gateway.intent_mapping_parsed
  workflow = computed.gateway.workflow_parsed
  IF intent_mapping IS null:
    RETURN

  actions_section = intent_mapping.get("actions", {})
  workflow_nodes = workflow.get("nodes", {})

  # Extract skill names from intent-mapping delegate actions
  intent_skill_names = {}
  FOR action_id, action_def in actions_section:
    IF action_id.startswith("delegate_"):
      skill_name = action_def.get("skill", "")
      intent_skill_names[action_id] = skill_name

  # Extract skill names from workflow on_response consequences
  workflow_skill_names = {}
  FOR node_id, node in workflow_nodes:
    IF node.get("type") == "user_prompt":
      on_response = node.get("on_response", {})
      FOR response_id, handler in on_response:
        FOR consequence in handler.get("consequence", []):
          IF consequence.get("type") == "mutate_state" AND consequence.get("field", "").endswith("matched_skill"):
            workflow_skill_names[response_id] = consequence.get("value", "")

  # Cross-check consistency
  FOR action_id, intent_skill in intent_skill_names:
    # Find the corresponding workflow reference
    short_id = action_id.replace("delegate_", "")
    IF short_id in workflow_skill_names:
      workflow_skill = workflow_skill_names[short_id]
      IF intent_skill != workflow_skill AND intent_skill != "" AND workflow_skill != "":
        computed.validation.intent_issues.append({
          severity: "error",
          dimension: "intent_alignment",
          check_id: "IA-03",
          message: "Skill name mismatch for '" + action_id + "': intent-mapping has '" + intent_skill + "', workflow has '" + workflow_skill + "'"
        })
```

### Step 3.3: Help Actions Present

Verify that standard help actions are defined in the intent-mapping.

```pseudocode
CHECK_HELP_ACTIONS():
  intent_mapping = computed.gateway.intent_mapping_parsed
  IF intent_mapping IS null:
    RETURN

  actions_section = intent_mapping.get("actions", {})
  rules = intent_mapping.get("rules", intent_mapping.get("intent_rules", []))

  # Required help actions
  expected_help_actions = ["show_full_help", "show_flag_help"]
  recommended_help_actions = ["show_logging_help", "show_display_help", "show_prompts_help"]

  FOR action_name in expected_help_actions:
    IF action_name not in actions_section:
      # Also check if any rule references it (may be handled inline)
      rule_refs = [r for r in rules if r.get("action") == action_name]
      IF len(rule_refs) == 0:
        computed.validation.intent_issues.append({
          severity: "warning",
          dimension: "intent_alignment",
          check_id: "IA-04",
          message: "Expected help action '" + action_name + "' is not defined in actions section"
        })

  FOR action_name in recommended_help_actions:
    IF action_name not in actions_section:
      computed.validation.intent_issues.append({
        severity: "info",
        dimension: "intent_alignment",
        check_id: "IA-05",
        message: "Recommended help action '" + action_name + "' is not defined (optional but enhances UX)"
      })

  # Check that help-related intent flags exist
  intent_flags = intent_mapping.get("intent_flags", {})
  IF "has_help" not in intent_flags AND "has_help_flag" not in intent_flags:
    computed.validation.intent_issues.append({
      severity: "warning",
      dimension: "intent_alignment",
      check_id: "IA-06",
      message: "No help-related intent flags (has_help or has_help_flag) found in intent_flags"
    })
```

---

## Phase 4: Skill Reference Validation

Validate that all referenced skills actually exist at the expected paths and can be resolved.

### Step 4.1: Skill Existence

Verify each invoke_skill target has a corresponding SKILL.md file on disk.

```pseudocode
CHECK_SKILL_EXISTENCE():
  plugin_root = extract_plugin_root(computed.gateway.directory)

  # Collect all skill references from both workflow and intent-mapping
  skill_references = set()

  # From workflow: invoke_skill actions
  workflow = computed.gateway.workflow_parsed
  FOR node_id, node in workflow.get("nodes", {}):
    IF node.get("type") == "action":
      FOR action in node.get("actions", []):
        IF action.get("type") == "invoke_skill":
          skill_ref = action.get("skill", action.get("skill_path", ""))
          IF "${" not in skill_ref:
            skill_references.add(skill_ref)

  # From workflow: on_response consequences that set matched_skill
  FOR node_id, node in workflow.get("nodes", {}):
    IF node.get("type") == "user_prompt":
      FOR response_id, handler in node.get("on_response", {}):
        FOR consequence in handler.get("consequence", []):
          IF consequence.get("field", "").endswith("matched_skill"):
            value = consequence.get("value", "")
            IF value and "${" not in value:
              skill_references.add(value)

  # From intent-mapping: delegate action skill names
  IF computed.gateway.intent_mapping_parsed IS NOT null:
    actions_section = computed.gateway.intent_mapping_parsed.get("actions", {})
    FOR action_id, action_def in actions_section:
      IF action_def.get("type") == "invoke_skill":
        skill_ref = action_def.get("skill", "")
        IF skill_ref and "${" not in skill_ref:
          skill_references.add(skill_ref)

  # Verify each skill reference resolves to a real SKILL.md
  FOR skill_ref in skill_references:
    # Try direct path first
    IF "/" in skill_ref:
      skill_path = skill_ref
    ELSE:
      # Assume skill name -> skills/{name}/SKILL.md convention
      skill_path = plugin_root + "/skills/" + skill_ref + "/SKILL.md"

    IF NOT file_exists(skill_path):
      computed.validation.reference_issues.append({
        severity: "error",
        dimension: "skill_references",
        check_id: "SR-01",
        message: "Skill reference '" + skill_ref + "' does not resolve to a SKILL.md at '" + skill_path + "'"
      })
    ELSE:
      computed.validation.reference_issues.append({
        severity: "info",
        dimension: "skill_references",
        check_id: "SR-02",
        message: "Skill '" + skill_ref + "' verified at '" + skill_path + "'"
      })
```

### Step 4.2: Path Correctness

Verify that all file paths referenced in the gateway files resolve to real files.

```pseudocode
CHECK_PATH_CORRECTNESS():
  plugin_root = extract_plugin_root(computed.gateway.directory)

  # Collect all path references from the workflow
  path_references = []
  workflow_text = computed.gateway.workflow
  intent_text = computed.gateway.intent_mapping OR ""
  command_text = computed.gateway.command_md OR ""

  # Find ${CLAUDE_PLUGIN_ROOT}/... path patterns
  FOR text, source_file in [(workflow_text, "workflow.yaml"),
                             (intent_text, "intent-mapping.yaml"),
                             (command_text, "command.md")]:
    matches = regex_findall(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^\s"\'}\)]+)', text)
    FOR match in matches:
      resolved_path = plugin_root + "/" + match
      IF NOT file_exists(resolved_path) AND NOT directory_exists(resolved_path):
        computed.validation.reference_issues.append({
          severity: "warning",
          dimension: "skill_references",
          check_id: "SR-03",
          message: "Path '${CLAUDE_PLUGIN_ROOT}/" + match + "' in " + source_file + " does not resolve to '" + resolved_path + "'"
        })
```

### Step 4.3: Allowed-Tools Sufficiency

Verify the gateway command .md has the minimum required tools for gateway operation.

```pseudocode
CHECK_ALLOWED_TOOLS():
  IF computed.gateway.command_frontmatter IS null:
    RETURN

  frontmatter = computed.gateway.command_frontmatter
  allowed_tools_str = frontmatter.get("allowed-tools", "")
  allowed_tools = [t.strip() for t in allowed_tools_str.split(",")]

  # Minimum required for gateway routing
  minimum_tools = ["Read", "AskUserQuestion"]

  FOR tool in minimum_tools:
    IF tool not in allowed_tools:
      computed.validation.reference_issues.append({
        severity: "warning",
        dimension: "skill_references",
        check_id: "SR-04",
        message: "Gateway command .md is missing minimum required tool '" + tool + "' in allowed-tools"
      })

  # Recommended tools for full gateway functionality
  recommended_tools = ["Glob", "Bash"]
  FOR tool in recommended_tools:
    IF tool not in allowed_tools:
      computed.validation.reference_issues.append({
        severity: "info",
        dimension: "skill_references",
        check_id: "SR-05",
        message: "Gateway command .md does not include recommended tool '" + tool + "' in allowed-tools"
      })
```

---

## Phase 5: Structure Validation

Validate the internal structure and consistency of each gateway file.

> **Detail:** See `patterns/gateway-validation-checklist.md` for the complete checklist with detection methods.

### Step 5.1: Gateway Markdown Frontmatter

Verify the gateway command .md has valid frontmatter with required fields.

```pseudocode
CHECK_GATEWAY_FRONTMATTER():
  IF computed.gateway.command_frontmatter IS null:
    computed.validation.structure_issues.append({
      severity: "error",
      dimension: "structure",
      check_id: "ST-01",
      message: "Gateway command .md has no parseable frontmatter"
    })
    RETURN

  fm = computed.gateway.command_frontmatter

  # Required frontmatter fields
  required_fields = {
    "name": "Plugin name identifier",
    "description": "Gateway description"
  }

  FOR field, purpose in required_fields:
    IF field not in fm OR fm[field] IS EMPTY:
      computed.validation.structure_issues.append({
        severity: "error",
        dimension: "structure",
        check_id: "ST-01",
        message: "Gateway command .md frontmatter missing required field '" + field + "' (" + purpose + ")"
      })

  # Recommended frontmatter fields
  IF "arguments" not in fm:
    computed.validation.structure_issues.append({
      severity: "warning",
      dimension: "structure",
      check_id: "ST-02",
      message: "Gateway command .md frontmatter missing 'arguments' section (recommended for CLI usage)"
    })

  # Verify name matches directory name
  gateway_dir_name = basename(computed.gateway.directory)
  parent_dir_name = basename(parent_directory(computed.gateway.directory))
  IF fm.get("name") != gateway_dir_name AND fm.get("name") != parent_dir_name:
    computed.validation.structure_issues.append({
      severity: "warning",
      dimension: "structure",
      check_id: "ST-03",
      message: "Gateway name '" + fm.get("name") + "' does not match directory name '" + gateway_dir_name + "'"
    })
```

### Step 5.2: Workflow Routing Nodes

Verify the workflow has the proper routing structure expected of a gateway command.

```pseudocode
CHECK_ROUTING_STRUCTURE():
  workflow = computed.gateway.workflow_parsed
  nodes = workflow.get("nodes", {})

  # Check for essential routing patterns
  routing_patterns = {
    "intent_check": false,    # A node that checks arguments/intent
    "menu_node": false,       # A user_prompt node offering skill selection
    "skill_dispatch": false   # A node that invokes a skill dynamically
  }

  FOR node_id, node in nodes:
    node_type = node.get("type", "")

    # Check for argument/intent checking node
    IF node_type == "conditional":
      condition = node.get("condition", {})
      field = condition.get("field", "")
      IF "matched_action" in field OR "matched_skill" in field OR "arguments" in field OR "intent" in field:
        routing_patterns["intent_check"] = true

    # Check for menu user_prompt
    IF node_type == "user_prompt":
      options = node.get("prompt", {}).get("options", [])
      IF len(options) >= 2:
        routing_patterns["menu_node"] = true

    # Check for skill dispatch action
    IF node_type == "action":
      FOR action in node.get("actions", []):
        IF action.get("type") == "invoke_skill":
          routing_patterns["skill_dispatch"] = true

  # Report missing patterns
  IF NOT routing_patterns["intent_check"]:
    computed.validation.structure_issues.append({
      severity: "warning",
      dimension: "structure",
      check_id: "ST-04",
      message: "No intent/argument checking node found (conditional on matched_action, arguments, or intent)"
    })

  IF NOT routing_patterns["menu_node"]:
    computed.validation.structure_issues.append({
      severity: "warning",
      dimension: "structure",
      check_id: "ST-05",
      message: "No menu node found (user_prompt with 2+ options for skill selection)"
    })

  IF NOT routing_patterns["skill_dispatch"]:
    computed.validation.structure_issues.append({
      severity: "error",
      dimension: "structure",
      check_id: "ST-06",
      message: "No skill dispatch node found (action node with invoke_skill type)"
    })
```

### Step 5.3: Intent Mapping Structure

Verify the intent-mapping.yaml follows the expected structure.

```pseudocode
CHECK_INTENT_MAPPING_STRUCTURE():
  intent_mapping = computed.gateway.intent_mapping_parsed
  IF intent_mapping IS null:
    RETURN

  # Check intent_flags section
  intent_flags = intent_mapping.get("intent_flags", {})
  IF len(intent_flags) == 0:
    computed.validation.structure_issues.append({
      severity: "warning",
      dimension: "structure",
      check_id: "ST-07",
      message: "intent_flags section is empty or missing"
    })
  ELSE:
    # Validate each flag has a keywords array
    FOR flag_name, flag_def in intent_flags:
      IF "keywords" not in flag_def:
        computed.validation.structure_issues.append({
          severity: "error",
          dimension: "structure",
          check_id: "ST-08",
          message: "Intent flag '" + flag_name + "' is missing required 'keywords' array"
        })
      ELIF NOT is_array(flag_def["keywords"]) OR len(flag_def["keywords"]) == 0:
        computed.validation.structure_issues.append({
          severity: "warning",
          dimension: "structure",
          check_id: "ST-09",
          message: "Intent flag '" + flag_name + "' has empty keywords array"
        })

      # Validate flag naming convention (has_ prefix)
      IF NOT flag_name.startswith("has_"):
        computed.validation.structure_issues.append({
          severity: "info",
          dimension: "structure",
          check_id: "ST-10",
          message: "Intent flag '" + flag_name + "' does not follow has_ prefix convention"
        })

  # Check rules section
  rules = intent_mapping.get("rules", intent_mapping.get("intent_rules", []))
  IF NOT is_array(rules) OR len(rules) == 0:
    computed.validation.structure_issues.append({
      severity: "error",
      dimension: "structure",
      check_id: "ST-11",
      message: "Rules section is empty or missing (need at least one routing rule)"
    })
  ELSE:
    FOR i, rule in enumerate(rules):
      # Each rule must have conditions and action
      IF "conditions" not in rule AND "condition" not in rule:
        computed.validation.structure_issues.append({
          severity: "error",
          dimension: "structure",
          check_id: "ST-12",
          message: "Rule [" + str(i) + "] '" + rule.get("name", "unnamed") + "' is missing 'conditions' field"
        })
      IF "action" not in rule:
        computed.validation.structure_issues.append({
          severity: "error",
          dimension: "structure",
          check_id: "ST-13",
          message: "Rule [" + str(i) + "] '" + rule.get("name", "unnamed") + "' is missing 'action' field"
        })

      # Validate condition flag references exist in intent_flags
      conditions = rule.get("conditions", rule.get("condition", {}))
      IF is_map(conditions):
        FOR flag_name in conditions:
          IF flag_name not in intent_flags:
            computed.validation.structure_issues.append({
              severity: "error",
              dimension: "structure",
              check_id: "ST-14",
              message: "Rule '" + rule.get("name", "unnamed") + "' references flag '" + flag_name + "' which is not defined in intent_flags"
            })
```

### Step 5.4: Circular Routing Detection

Verify that delegation nodes do not route back into the routing logic, creating an infinite loop.

```pseudocode
CHECK_CIRCULAR_ROUTING():
  workflow = computed.gateway.workflow_parsed
  nodes = workflow.get("nodes", {})
  start_node = workflow.get("start_node", "")

  # Identify routing nodes (nodes involved in intent detection and menu)
  routing_node_ids = set()
  FOR node_id, node in nodes:
    IF node_id == start_node:
      routing_node_ids.add(node_id)
    IF node.get("type") == "conditional":
      condition = node.get("condition", {})
      field = condition.get("field", "")
      IF "matched" in field OR "intent" in field OR "arguments" in field:
        routing_node_ids.add(node_id)
    IF node.get("type") == "user_prompt":
      options = node.get("prompt", {}).get("options", [])
      IF len(options) >= 2:
        routing_node_ids.add(node_id)

  # Identify delegation/dispatch nodes
  dispatch_node_ids = set()
  FOR node_id, node in nodes:
    IF node.get("type") == "action":
      FOR action in node.get("actions", []):
        IF action.get("type") == "invoke_skill":
          dispatch_node_ids.add(node_id)

  # Check if any dispatch node routes back to a routing node
  FOR node_id in dispatch_node_ids:
    node = nodes[node_id]
    targets = []
    IF "on_success" in node:
      targets.append(node["on_success"])
    IF "on_failure" in node:
      targets.append(node["on_failure"])

    FOR target in targets:
      IF target in routing_node_ids:
        computed.validation.structure_issues.append({
          severity: "warning",
          dimension: "structure",
          check_id: "ST-15",
          message: "Dispatch node '" + node_id + "' routes back to routing node '" + target + "' (potential circular routing)"
        })
```

---

## Phase 6: Report

### Step 6.1: Per-Dimension Summary

For each validation dimension, compute pass/fail status and display a summary table.

```pseudocode
BUILD_DIMENSION_SUMMARIES():
  dimensions = [
    ("Route Completeness", computed.validation.route_issues),
    ("Intent Alignment", computed.validation.intent_issues),
    ("Skill References", computed.validation.reference_issues),
    ("Structure", computed.validation.structure_issues)
  ]

  computed.validation.summaries = []
  FOR dim_name, issues in dimensions:
    errors = [i for i in issues if i.severity == "error"]
    warnings = [i for i in issues if i.severity == "warning"]
    infos = [i for i in issues if i.severity == "info"]

    IF len(errors) > 0:
      status = "FAIL"
    ELIF len(warnings) > 0:
      status = "WARN"
    ELSE:
      status = "PASS"

    computed.validation.summaries.append({
      dimension: dim_name,
      status: status,
      errors: len(errors),
      warnings: len(warnings),
      info: len(infos),
      issues: issues
    })
```

Display the summary table:

```
## Gateway Validation Results

| Dimension          | Status | Errors | Warnings | Info |
|--------------------|--------|--------|----------|------|
| Route Completeness | {status} | {errors} | {warnings} | {info} |
| Intent Alignment   | {status} | {errors} | {warnings} | {info} |
| Skill References   | {status} | {errors} | {warnings} | {info} |
| Structure          | {status} | {errors} | {warnings} | {info} |
```

### Step 6.2: Issue Details

Display all issues grouped by dimension and severity (errors first, then warnings, then info).

```pseudocode
DISPLAY_ISSUES():
  FOR summary in computed.validation.summaries:
    IF len(summary.issues) == 0:
      CONTINUE

    DISPLAY "### " + summary.dimension + " (" + summary.status + ")"
    DISPLAY ""

    # Sort: errors first, then warnings, then info
    sorted_issues = sorted(summary.issues, key=lambda i: {"error": 0, "warning": 1, "info": 2}[i.severity])

    FOR issue in sorted_issues:
      icon = {"error": "[ERROR]", "warning": "[WARN]", "info": "[INFO]"}[issue.severity]
      DISPLAY "- " + icon + " **" + issue.check_id + ":** " + issue.message
    DISPLAY ""
```

### Step 6.3: Fix Suggestions

For each error and warning issue, provide an actionable fix suggestion.

```pseudocode
DISPLAY_FIX_SUGGESTIONS():
  all_issues = (computed.validation.route_issues
              + computed.validation.intent_issues
              + computed.validation.reference_issues
              + computed.validation.structure_issues)

  fixable_issues = [i for i in all_issues if i.severity in ("error", "warning")]

  IF len(fixable_issues) == 0:
    RETURN

  DISPLAY "### Fix Suggestions"
  DISPLAY ""

  FIX_MAP = {
    "RC-01": "Add a delegate_{skill_short_name} node to workflow.yaml, or add an intent rule with action: delegate_{skill_short_name} in intent-mapping.yaml",
    "RC-02": "Remove the delegation node for the missing skill, or create the skill under skills/",
    "RC-04": "Add an action definition for '{action}' in the actions section of intent-mapping.yaml",
    "RC-05": "Add a rule with empty conditions: { conditions: {}, action: show_main_menu } or a fallback: section",
    "RC-06": "Add a user_prompt node with options for each skill to the workflow",
    "RC-07": "Add an option entry for the skill in the menu node's prompt.options array",
    "IA-01": "Add a definition for '{action}' in the actions section of intent-mapping.yaml",
    "IA-02": "Remove the unused action definition, or add a rule that references it",
    "IA-03": "Ensure the skill name is identical in both intent-mapping.yaml actions and workflow.yaml consequences",
    "IA-04": "Add the help action definition in the actions section of intent-mapping.yaml",
    "IA-06": "Add has_help or has_help_flag to intent_flags with help-related keywords",
    "SR-01": "Verify the skill name and create the SKILL.md at the expected path, or fix the reference",
    "SR-03": "Update the path reference to point to an existing file, or create the missing file",
    "SR-04": "Add the missing tool to the allowed-tools list in the gateway .md frontmatter",
    "ST-01": "Add YAML frontmatter with at least name and description to the gateway .md file",
    "ST-03": "Rename the gateway or update the frontmatter name to match the directory",
    "ST-06": "Add an action node with type: invoke_skill to dispatch to the matched skill",
    "ST-08": "Add a keywords array to the intent flag definition",
    "ST-11": "Add at least one routing rule to the rules section",
    "ST-12": "Add a conditions field to the rule (use {} for unconditional fallback)",
    "ST-13": "Add an action field specifying which action to take when the rule matches",
    "ST-14": "Add the missing flag to intent_flags, or fix the flag name in the rule conditions"
  }

  FOR issue in fixable_issues:
    IF issue.check_id in FIX_MAP:
      DISPLAY "- **" + issue.check_id + ":** " + FIX_MAP[issue.check_id]
```

### Step 6.4: Overall Assessment

Compute and display the overall validation result.

```pseudocode
OVERALL_ASSESSMENT():
  all_issues = (computed.validation.route_issues
              + computed.validation.intent_issues
              + computed.validation.reference_issues
              + computed.validation.structure_issues)

  total_errors = count(i for i in all_issues if i.severity == "error")
  total_warnings = count(i for i in all_issues if i.severity == "warning")
  total_info = count(i for i in all_issues if i.severity == "info")

  IF total_errors > 0:
    overall = "FAIL"
    message = str(total_errors) + " error(s) found. Gateway routing may not function correctly."
  ELIF total_warnings > 0:
    overall = "WARN"
    message = "No errors, but " + str(total_warnings) + " warning(s) should be addressed."
  ELSE:
    overall = "PASS"
    message = "Gateway validation passed. All checks cleared."

  DISPLAY ""
  DISPLAY "---"
  DISPLAY ""
  DISPLAY "## Overall: " + overall
  DISPLAY ""
  DISPLAY message
  DISPLAY ""
  DISPLAY "**Total:** " + str(total_errors) + " errors, " + str(total_warnings) + " warnings, " + str(total_info) + " info"
```

### Step 6.5: Offer Next Actions

Present the user with options for what to do after validation:

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Next Actions",
    "options": [
      {
        "label": "Fix issues",
        "description": "Apply suggested fixes to the gateway files"
      },
      {
        "label": "Re-validate",
        "description": "Run validation again after making manual changes"
      },
      {
        "label": "Validate individual skills",
        "description": "Run bp-skill-validate on referenced skills"
      },
      {
        "label": "Done",
        "description": "Validation complete, no further action needed"
      }
    ],
    "multiSelect": false
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT_ACTION(response):
  SWITCH response:
    CASE "Fix issues":
      DISPLAY "To fix the detected issues, review the suggestions above and edit the gateway files."
      DISPLAY "Gateway files are located at:"
      DISPLAY "  - " + computed.gateway.command_md_path
      DISPLAY "  - " + computed.gateway.workflow_path
      DISPLAY "  - " + computed.gateway.intent_mapping_path
      DISPLAY ""
      DISPLAY "After making changes, re-run this validation skill."
    CASE "Re-validate":
      DISPLAY "Re-running validation..."
      # Reset issue collectors
      computed.validation.route_issues = []
      computed.validation.intent_issues = []
      computed.validation.reference_issues = []
      computed.validation.structure_issues = []
      GOTO Phase 2
    CASE "Validate individual skills":
      DISPLAY "To validate individual skills, invoke:"
      DISPLAY ""
      DISPLAY "  Skill(skill: \"bp-skill-validate\", args: \"<path-to-workflow.yaml>\")"
      DISPLAY ""
      DISPLAY "Recommended targets:"
      FOR skill in computed.gateway.discovered_skills:
        DISPLAY "  - " + skill
    CASE "Done":
      DISPLAY "Gateway validation complete."
      EXIT
```

---

## Reference Documentation

- **Validation Checklist:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-gateway-validate/patterns/gateway-validation-checklist.md`
- **Gateway Command Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Schema Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/patterns/schema-validation-rules.md`

---

## Related Skills

- Gateway creation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-gateway-create/SKILL.md`
- Intent mapping validation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-intent-validate/SKILL.md`
- Workflow validation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-skill-validate/SKILL.md`
- Plugin discovery: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-plugin-discover/SKILL.md`
