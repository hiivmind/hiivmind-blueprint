---
name: bp-gateway-create
description: >
  This skill should be used when the user asks to "create gateway", "add gateway command",
  "set up intent routing", "create plugin entrypoint", "generate gateway",
  "unified command for plugin", or needs to create a gateway command for a multi-skill plugin.
  Triggers on "create gateway", "gateway create", "add gateway", "plugin entrypoint",
  "intent routing", "unified command", "gateway setup".
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion
---

# Create Gateway Command

Create a complete gateway command with 3VL intent detection for routing user requests to the
appropriate skill in a multi-skill plugin.

> **File Generation Guide:** `patterns/gateway-file-generation.md`
> **Routing Design Procedure:** `patterns/routing-design-procedure.md`
> **Gateway Command Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
> **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`

---

## Overview

This skill generates three files that together form a gateway command:

1. **Gateway command markdown** -- `commands/{plugin_name}.md`
2. **Intent mapping configuration** -- `commands/{plugin_name}/intent-mapping.yaml`
3. **Gateway workflow** -- `commands/{plugin_name}/workflow.yaml`

The gateway acts as a unified entry point for a plugin. It parses natural language input,
matches it against 3VL intent flags, and routes to the correct skill. When no clear match
is found, it presents an interactive menu.

---

## Phase 1: Analyze Plugin

### Step 1.1: Discover Skills

Scan the target plugin for all SKILL.md files:

```pseudocode
DISCOVER_SKILLS():
  # Search skills/ directory
  skill_files = Glob(CLAUDE_PLUGIN_ROOT + "/skills/*/SKILL.md")

  computed.skills = []

  FOR file IN skill_files:
    content = Read(file)
    frontmatter = parse_yaml_frontmatter(content)

    skill = {
      path:        file,
      directory:   parent_directory(file),
      id:          basename(parent_directory(file)),
      name:        frontmatter.name,
      description: frontmatter.description,
      tools:       frontmatter["allowed-tools"]
    }
    computed.skills.append(skill)

  computed.skill_count = len(computed.skills)
```

If `computed.skill_count == 0`, display a message and exit:

> No SKILL.md files found. Verify the plugin directory contains a `skills/`
> subdirectory with at least one skill, then try again.

### Step 1.2: Extract Keywords

From each skill's description frontmatter, extract trigger keywords and action verbs:

```pseudocode
EXTRACT_KEYWORDS():
  FOR skill IN computed.skills:
    description = skill.description

    # Extract quoted phrases from description
    # Pattern: words inside double quotes in "Triggers on" or description text
    quoted = extract_all_matches(description, /"([^"]+)"/)

    # Extract verb-noun pairs (action words)
    # Pattern: common action verbs followed by nouns
    verbs = extract_all_matches(description, /\b(create|add|update|find|show|delete|validate|generate|analyze|convert|setup|discover|check|list)\s+(\w+)/i)
    verb_phrases = [match.group(0) for match in verbs]

    # Merge and deduplicate
    skill.keywords = deduplicate(quoted + verb_phrases)
    skill.keyword_count = len(skill.keywords)
```

### Step 1.3: Detect Keyword Overlap

Check for keywords shared between multiple skills, which indicates 3VL intent detection
will be valuable for disambiguation:

```pseudocode
DETECT_OVERLAP():
  all_keywords = {}

  FOR skill IN computed.skills:
    FOR keyword IN skill.keywords:
      normalized = lowercase(keyword)
      IF normalized NOT IN all_keywords:
        all_keywords[normalized] = []
      all_keywords[normalized].append(skill.id)

  computed.keyword_overlap = {}
  FOR keyword, skill_ids IN all_keywords:
    IF len(skill_ids) > 1:
      computed.keyword_overlap[keyword] = skill_ids

  computed.overlap_count = len(computed.keyword_overlap)
```

If `computed.overlap_count > 0`, report the overlapping keywords:

> Found {computed.overlap_count} keywords shared across multiple skills.
> 3VL intent detection recommended for disambiguation.

### Step 1.4: Determine Gateway Recommendation

Based on the number of skills, recommend whether a gateway is needed:

| Skill Count | Recommendation |
|-------------|----------------|
| 1 skill | No gateway needed |
| 2-3 skills | Optional (simple menu may suffice) |
| 4+ skills | Yes, with 3VL intent detection |

If `computed.skill_count == 1`, display:

> This plugin has only 1 skill. A gateway command is not needed.
> Users can invoke the skill directly.

Then exit.

If `computed.skill_count >= 2 AND computed.skill_count <= 3`, ask the user:

```json
{
  "questions": [{
    "question": "You have {computed.skill_count} skills. Would you like a gateway command?",
    "header": "Gateway",
    "multiSelect": false,
    "options": [
      {
        "label": "Yes with intent detection (Recommended)",
        "description": "3VL keyword matching for natural language routing"
      },
      {
        "label": "Simple menu only",
        "description": "Just a menu, no keyword matching"
      },
      {
        "label": "Skip",
        "description": "Don't create a gateway"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_GATEWAY_CHOICE(response):
  SWITCH response:
    CASE "Yes with intent detection (Recommended)":
      computed.gateway_mode = "full"
    CASE "Simple menu only":
      computed.gateway_mode = "menu_only"
    CASE "Skip":
      DISPLAY "Gateway creation skipped."
      EXIT
```

If `computed.skill_count >= 4`, set `computed.gateway_mode = "full"` automatically and
inform the user:

> Plugin has {computed.skill_count} skills. Creating gateway with 3VL intent detection.

---

## Phase 2: Design Intent Detection

If `computed.gateway_mode == "menu_only"`, skip this phase entirely and proceed to Phase 3
with an empty `computed.intent_flags` and a single fallback rule routing to `show_main_menu`.

### Step 2.1: Define Flag Categories

Build flag categories from two sources: standard flags (included in every gateway) and
skill-specific flags derived from the keyword extraction in Phase 1.

**Standard flags (always included):**

```yaml
# Help flags
has_help_flag:
  keywords: ["--help", "-h", "-?"]
  description: "Explicit help flag invoked"

has_help:
  keywords: ["help", "how do i", "how to", "?", "explain", "guide", "what can", "show commands"]
  description: "User needs guidance or documentation"

has_flags_help:
  keywords: ["flags", "options", "arguments", "--verbose", "--quiet", "--debug", "runtime flags"]
  description: "User wants to understand runtime flags"

# Action type flags
has_init:
  keywords: ["create", "new", "initialize", "init", "start", "setup"]
  description: "User wants to create something new"

has_modify:
  keywords: ["add", "update", "edit", "change", "modify", "extend"]
  description: "User wants to modify existing"

has_query:
  keywords: ["find", "search", "show", "list", "what", "where", "check", "status"]
  description: "User is asking a question or querying state"

has_delete:
  keywords: ["delete", "remove", "clear", "reset"]
  negative_keywords: ["undo delete", "restore"]
  description: "User wants to remove something"
```

**Skill-specific flags (generated per skill):**

```pseudocode
BUILD_SKILL_FLAGS():
  computed.intent_flags = copy(STANDARD_FLAGS)

  FOR skill IN computed.skills:
    flag_name = "has_" + sanitize_id(skill.id)

    # Collect unique keywords not already covered by standard flags
    standard_keywords = flatten([f.keywords for f in STANDARD_FLAGS])
    unique_keywords = [k for k in skill.keywords if k not in standard_keywords]

    # If skill has unique identifying keywords, create a flag
    IF len(unique_keywords) > 0:
      computed.intent_flags[flag_name] = {
        keywords: unique_keywords,
        description: "Specific to " + skill.name
      }
      skill.has_dedicated_flag = true
    ELSE:
      skill.has_dedicated_flag = false
```

Store the full flag catalog in `computed.intent_flags`.

### Step 2.2: Create Intent Rules

Map flag combinations to skill delegation actions. Rules are evaluated in declaration order;
more specific rules (more conditions) are listed first.

```pseudocode
BUILD_INTENT_RULES():
  computed.intent_rules = []

  # --- Help rules (highest priority, always included) ---

  computed.intent_rules.append({
    name: "explicit_help_flag",
    conditions: { has_help_flag: "T" },
    action: "show_full_help",
    description: "Explicit --help or -h flag"
  })

  computed.intent_rules.append({
    name: "help_with_flags",
    conditions: { has_flags_help: "T" },
    action: "show_flag_help",
    description: "User wants to understand runtime flags"
  })

  # Skill-specific help rules
  FOR skill IN computed.skills:
    IF skill.has_dedicated_flag:
      flag_name = "has_" + sanitize_id(skill.id)
      computed.intent_rules.append({
        name: "help_with_" + sanitize_id(skill.id),
        conditions: { has_help: "T", [flag_name]: "T" },
        action: "show_skill_help_" + sanitize_id(skill.id),
        description: "Help with " + skill.name
      })

  # --- Pure single intents (more conditions = higher specificity) ---

  # Map action-type flags to skills based on keyword overlap analysis
  # Example: if a skill's keywords include "create", it maps to has_init
  FOR skill IN computed.skills:
    primary_action = determine_primary_action(skill)
    exclusions = get_exclusion_flags(primary_action)

    conditions = { [primary_action]: "T" }
    FOR excl IN exclusions:
      conditions[excl] = "F"

    computed.intent_rules.append({
      name: sanitize_id(skill.id) + "_pure",
      conditions: conditions,
      action: "delegate_" + sanitize_id(skill.id),
      description: skill.description_short
    })

  # --- Compound intents (help + skill domain) ---

  FOR skill IN computed.skills:
    IF skill.has_dedicated_flag:
      flag_name = "has_" + sanitize_id(skill.id)
      computed.intent_rules.append({
        name: sanitize_id(skill.id) + "_direct",
        conditions: { [flag_name]: "T" },
        action: "delegate_" + sanitize_id(skill.id),
        description: "Direct match for " + skill.name
      })

  # --- General help fallback ---

  computed.intent_rules.append({
    name: "general_help",
    conditions: { has_help: "T" },
    action: "show_full_help",
    description: "General help request"
  })

  # --- Default fallback (empty conditions = lowest specificity) ---

  computed.intent_rules.append({
    name: "show_menu",
    conditions: {},
    action: "show_main_menu",
    description: "No clear intent, show interactive menu"
  })
```

### Step 2.3: Present Design to User

Display the proposed intent detection structure for review before generating files:

```
## Intent Detection Design

### Flag Categories ({computed.flag_count})

| Flag | Keywords (preview) | Description |
|------|-------------------|-------------|
{for flag_name, flag_def in computed.intent_flags}
| {flag_name} | {flag_def.keywords[:3].join(", ")}... | {flag_def.description} |
{/for}

### Intent Rules ({computed.rule_count})

| # | Rule | Conditions | Routes To | Description |
|---|------|------------|-----------|-------------|
{for i, rule in enumerate(computed.intent_rules)}
| {i+1} | {rule.name} | {len(rule.conditions)} flags | {rule.action} | {rule.description} |
{/for}

### Skill Routing

| Skill | Triggering Rules |
|-------|-----------------|
{for skill in computed.skills}
| {skill.name} | {rules_that_route_to(skill).join(", ")} |
{/for}
```

After displaying the table, ask for confirmation:

```json
{
  "questions": [{
    "question": "Does this intent detection design look correct?",
    "header": "Confirm",
    "multiSelect": false,
    "options": [
      {
        "label": "Looks good, proceed",
        "description": "Generate the gateway files with this design"
      },
      {
        "label": "Adjust flags",
        "description": "Add, remove, or modify flag categories"
      },
      {
        "label": "Adjust rules",
        "description": "Change rule conditions or routing targets"
      },
      {
        "label": "Start over",
        "description": "Re-analyze the plugin from scratch"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_DESIGN_REVIEW(response):
  SWITCH response:
    CASE "Looks good, proceed":
      CONTINUE to Phase 3
    CASE "Adjust flags":
      # Ask user which flags to change, then rebuild rules and re-present
      GOTO Step 2.1 with user modifications
    CASE "Adjust rules":
      # Ask user which rules to change, then re-present
      GOTO Step 2.2 with user modifications
    CASE "Start over":
      GOTO Phase 1, Step 1.1
```

---

## Phase 3: Generate Files

### Step 3.1: Create Command Directory

Determine the plugin name from the plugin manifest or directory name:

```pseudocode
PREPARE_OUTPUT():
  # Detect plugin name
  manifest_path = CLAUDE_PLUGIN_ROOT + "/.claude-plugin/plugin.json"
  IF file_exists(manifest_path):
    manifest = Read(manifest_path)
    computed.plugin_name = parse_json(manifest).name
  ELSE:
    computed.plugin_name = basename(CLAUDE_PLUGIN_ROOT)

  computed.command_dir = CLAUDE_PLUGIN_ROOT + "/commands/" + computed.plugin_name
```

Create the directory structure. If `commands/{plugin_name}/` already exists, the files inside
will be handled by the existing-file logic in each step below.

### Step 3.2: Generate intent-mapping.yaml

Load the intent mapping template and substitute all placeholders with the values computed
in Phase 2.

```pseudocode
GENERATE_INTENT_MAPPING():
  template = Read("${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template")

  # Build substitution context from computed state
  context = {
    plugin_name:        computed.plugin_name,
    plugin_description: computed.plugin_description,
    PLUGIN_TITLE:       uppercase(computed.plugin_name.replace("-", " ")),
    intent_flags:       computed.intent_flags,
    intent_rules:       computed.intent_rules,
    skills:             computed.skills
  }

  # Substitute all {{placeholder}} tokens
  # See patterns/gateway-file-generation.md for the complete placeholder catalog
  output = substitute_template(template, context)

  output_path = computed.command_dir + "/intent-mapping.yaml"
```

**Example of generated intent-mapping.yaml structure:**

```yaml
# Intent mapping for my-plugin gateway
# Generated by bp-gateway-create

intent_flags:
  has_help_flag:
    keywords:
      - "--help"
      - "-h"
      - "-?"
    description: "Explicit help flag invoked"

  has_help:
    keywords:
      - "help"
      - "how do i"
      - "how to"
    description: "User needs guidance or documentation"

  # ... standard flags ...

  has_my_skill:
    keywords:
      - "skill-specific-term"
      - "another-term"
    description: "Specific to my-skill"

intent_rules:
  - name: "explicit_help_flag"
    conditions:
      has_help_flag: T
    action: show_full_help
    description: "Explicit --help or -h flag"

  - name: "my_skill_pure"
    conditions:
      has_init: T
      has_modify: F
      has_query: F
    action: delegate_my_skill
    description: "Create new thing"

  - name: "show_menu"
    conditions: {}
    action: show_main_menu
    description: "No clear intent, show interactive menu"

actions:
  delegate_my_skill:
    type: invoke_skill
    skill: "my-skill"
    pass_arguments: true

  show_main_menu:
    type: user_prompt
    prompt:
      question: "What would you like to do?"
      header: "Menu"
      options:
        - id: my_skill
          label: "My Skill"
          description: "Does something useful"
```

If the output file already exists, ask the user before overwriting:

```json
{
  "questions": [{
    "question": "intent-mapping.yaml already exists. What should I do?",
    "header": "Overwrite",
    "multiSelect": false,
    "options": [
      { "label": "Overwrite", "description": "Replace the existing file" },
      { "label": "Backup and replace", "description": "Rename existing to .bak, then write new" },
      { "label": "Skip", "description": "Keep existing file unchanged" }
    ]
  }]
}
```

Write the output to `computed.command_dir + "/intent-mapping.yaml"`.
Store `computed.files_created.intent_mapping = output_path`.

### Step 3.3: Generate Gateway workflow.yaml

Build the routing workflow following the node interconnection design documented in
`patterns/routing-design-procedure.md`.

The workflow has a fixed topology. All gateways share this structure; the variable parts
are the skill delegation nodes and menu options.

```yaml
# Gateway workflow node structure (inline pseudocode)

name: "{computed.plugin_name}-gateway"
version: "1.0.0"
description: >
  Gateway command for {computed.plugin_name}. Routes requests to appropriate skills
  using 3VL intent detection.

definitions:
  source: "{computed.lib_ref}"

entry_preconditions: []

initial_state:
  phase: "detect"
  arguments: null
  intent: null
  flags:
    has_arguments: false
  computed: {}

  output:
    level: "normal"
    display_enabled: true
    batch_enabled: true
    batch_threshold: 3
    use_icons: true
    log_enabled: true
    log_format: "yaml"
    log_location: ".logs/"
    ci_mode: false

  prompts:
    interface: "auto"
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.7

start_node: check_arguments

nodes:
  check_arguments:
    type: conditional
    description: "Check if user provided arguments"
    condition:
      type: state_check
      field: arguments
      operator: not_null
    branches:
      on_true: parse_intent
      on_false: show_main_menu

  parse_intent:
    type: action
    description: "Parse user input against 3VL intent flags"
    actions:
      - type: mutate_state
        operation: set
        field: computed.intent_flags
        value: "${parse_3vl_flags(arguments, intent_flags)}"
      - type: mutate_state
        operation: set
        field: computed.intent_matches
        value: "${match_3vl_rules(computed.intent_flags, intent_rules)}"
    on_success: check_clear_winner
    on_failure: show_main_menu

  check_clear_winner:
    type: conditional
    description: "Check if intent matching produced a clear winner"
    condition:
      type: state_check
      field: computed.intent_matches.clear_winner
      operator: "true"
    branches:
      on_true: execute_matched_intent
      on_false: show_disambiguation

  execute_matched_intent:
    type: action
    description: "Route to the winning intent action"
    actions:
      - type: mutate_state
        operation: set
        field: computed.dynamic_target
        value: "${computed.intent_matches.winner.action}"
    on_success: "${computed.dynamic_target}"
    on_failure: show_main_menu

  show_disambiguation:
    type: user_prompt
    description: "Present top candidates when no clear winner"
    prompt:
      question: "I found multiple possible matches. Which did you mean?"
      header: "Clarify"
      options_from_state: "computed.intent_matches.top_candidates"
      option_mapping:
        id: "candidate.action"
        label: "candidate.description"
        description: "candidate.score_summary"
    on_response:
      "${selected_id}":
        consequence:
          - type: mutate_state
            operation: set
            field: intent
            value: "${selected_id}"
        next_node: "${selected_id}"

  show_main_menu:
    type: user_prompt
    description: "Present full skill menu when no arguments given"
    prompt:
      question: "What would you like to do with {computed.plugin_name}?"
      header: "Menu"
      options:
        # -- generated per skill --
        {for skill in computed.skills}
        - id: {sanitize_id(skill.id)}
          label: "{skill.name}"
          description: "{skill.description_short}"
        {/for}
    on_response:
      {for skill in computed.skills}
      {sanitize_id(skill.id)}:
        consequence:
          - type: mutate_state
            operation: set
            field: intent
            value: "{sanitize_id(skill.id)}"
        next_node: delegate_{sanitize_id(skill.id)}
      {/for}

  # -- Delegation nodes (one per skill) --
  {for skill in computed.skills}
  delegate_{sanitize_id(skill.id)}:
    type: action
    description: "Delegate to {skill.name}"
    actions:
      - type: invoke_skill
        skill: "{skill.name}"
        args: "${arguments}"
    on_success: success
    on_failure: error_delegation
  {/for}

endings:
  success:
    type: success
    message: "Request handled by {computed.plugin_name}"

  error_delegation:
    type: error
    message: "Failed to delegate to skill"
    recovery: "Try invoking the skill directly"

  cancelled:
    type: error
    message: "Operation cancelled by user"
```

Write the output to `computed.command_dir + "/workflow.yaml"`.
Store `computed.files_created.workflow = output_path`.

Apply the same existing-file check as in Step 3.2 if the file already exists.

### Step 3.4: Generate Gateway Command Markdown

Load the gateway command template and substitute all placeholders.

```pseudocode
GENERATE_GATEWAY_COMMAND():
  template = Read("${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template")

  # Build substitution context
  context = {
    plugin_name:        computed.plugin_name,
    plugin_description: computed.plugin_description,
    PLUGIN_TITLE:       uppercase(computed.plugin_name.replace("-", " ")),
    skills:             computed.skills,      # Array of skill objects
    examples:           computed.examples      # Generated usage examples
  }

  # Generate usage examples from skill names
  computed.examples = []
  FOR skill IN computed.skills:
    example_input = skill.keywords[0] if skill.keywords else skill.id
    computed.examples.append({
      command: "/" + computed.plugin_name + " " + example_input,
      skill_name: skill.name
    })

  # Substitute all {{placeholder}} tokens
  output = substitute_template(template, context)

  output_path = CLAUDE_PLUGIN_ROOT + "/commands/" + computed.plugin_name + ".md"
```

> **Detail:** See `patterns/gateway-file-generation.md` for the complete placeholder catalog
> covering all three generated files.

Write the output to the gateway command path.
Store `computed.files_created.gateway_command = output_path`.

Apply the same existing-file check as in Step 3.2 if the file already exists.

---

## Phase 4: Validate & Test

### Step 4.1: Validate Generated Files

Check that all three files were created and parse correctly:

```pseudocode
VALIDATE_FILES():
  computed.validation = { passed: true, errors: [] }

  expected_files = [
    computed.files_created.gateway_command,
    computed.files_created.workflow,
    computed.files_created.intent_mapping
  ]

  FOR file_path IN expected_files:
    IF NOT file_exists(file_path):
      computed.validation.errors.append("Missing: " + file_path)
      computed.validation.passed = false
      CONTINUE

    content = Read(file_path)

    IF file_path.endswith(".yaml"):
      # Attempt YAML parse
      parsed = try_parse_yaml(content)
      IF parsed IS error:
        computed.validation.errors.append("YAML parse error in " + file_path + ": " + parsed.message)
        computed.validation.passed = false

    IF file_path.endswith(".md"):
      # Check for frontmatter presence
      has_frontmatter = content.startswith("---")
      IF NOT has_frontmatter:
        computed.validation.errors.append("Missing YAML frontmatter in " + file_path)
        computed.validation.passed = false
```

If `computed.validation.passed == false`, display the errors and ask whether to continue
or abort.

### Step 4.2: Run Intent Matching Test Cases

Build test cases from the known skills and their keywords, then dry-run the intent
matching algorithm against the generated rules:

```pseudocode
BUILD_AND_RUN_TESTS():
  # Auto-generate test cases from skill keywords and standard patterns
  computed.test_cases = []

  # Standard test: empty input -> show menu
  computed.test_cases.append({
    input: "",
    expected: "show_main_menu",
    description: "Empty input shows menu"
  })

  # Standard test: help -> show help
  computed.test_cases.append({
    input: "help",
    expected: "show_full_help",
    description: "Help keyword shows help"
  })

  # Standard test: --help flag
  computed.test_cases.append({
    input: "--help",
    expected: "show_full_help",
    description: "Explicit help flag"
  })

  # Per-skill tests: use first keyword from each skill
  FOR skill IN computed.skills:
    IF skill.keywords:
      computed.test_cases.append({
        input: skill.keywords[0],
        expected: "delegate_" + sanitize_id(skill.id),
        description: "Primary keyword routes to " + skill.name
      })

  # Run all tests
  computed.test_results = []

  FOR test IN computed.test_cases:
    flags = parse_3vl_flags(test.input, computed.intent_flags)
    result = match_3vl_rules(flags, computed.intent_rules)
    actual_action = result.winner.action IF result.clear_winner ELSE "show_disambiguation"

    test_result = {
      input:       test.input,
      expected:    test.expected,
      actual:      actual_action,
      passed:      (actual_action == test.expected),
      description: test.description,
      flags:       flags,
      match_score: result.winner.score IF result.winner ELSE 0
    }
    computed.test_results.append(test_result)

  computed.tests_passed = count(r for r in computed.test_results if r.passed)
  computed.tests_total = len(computed.test_results)
```

### Step 4.3: Display Results

Present a comprehensive summary of the gateway generation:

```
## Gateway Generation Complete

### Files Created

| File | Path | Status |
|------|------|--------|
| Gateway command | {computed.files_created.gateway_command} | {status_icon} |
| Workflow | {computed.files_created.workflow} | {status_icon} |
| Intent mapping | {computed.files_created.intent_mapping} | {status_icon} |

### Intent Coverage

| Metric | Value |
|--------|-------|
| Flag categories | {len(computed.intent_flags)} |
| Intent rules | {len(computed.intent_rules)} |
| Skills routed | {computed.skill_count} |
| Keywords indexed | {total_keyword_count} |
| Keyword overlap detected | {computed.overlap_count} |

### Test Results: {computed.tests_passed}/{computed.tests_total} passed

| # | Input | Expected | Actual | Status |
|---|-------|----------|--------|--------|
{for i, test in enumerate(computed.test_results)}
| {i+1} | "{test.input}" | {test.expected} | {test.actual} | {test.passed ? "PASS" : "FAIL"} |
{/for}

### Usage

```
/{computed.plugin_name}                    # Show interactive menu
/{computed.plugin_name} help               # Show full help
/{computed.plugin_name} [request]          # Natural language routing
/{computed.plugin_name} help [skill]       # Help for specific skill
```
```

### Step 4.4: Offer Refinement

After displaying results, ask the user for next steps:

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Refine",
    "multiSelect": false,
    "options": [
      {
        "label": "Edit intent rules",
        "description": "Adjust flag conditions or routing targets"
      },
      {
        "label": "Add test cases",
        "description": "Define additional test inputs to verify routing"
      },
      {
        "label": "Regenerate files",
        "description": "Re-run file generation with current design"
      },
      {
        "label": "Done",
        "description": "Gateway creation complete"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_REFINEMENT(response):
  SWITCH response:
    CASE "Edit intent rules":
      # Ask which rules to modify, rebuild, and re-run Phase 3 + 4
      GOTO Phase 2, Step 2.2
    CASE "Add test cases":
      # Ask user for input/expected pairs, append to computed.test_cases, re-run Step 4.2
      GOTO Step 4.2
    CASE "Regenerate files":
      # Re-run Phase 3 with current computed state
      GOTO Phase 3
    CASE "Done":
      DISPLAY "Gateway creation complete. Files written to {computed.command_dir}/"
      EXIT
```

---

## Reference Documentation

- **Gateway File Generation:** `patterns/gateway-file-generation.md` (local to this skill)
- **Routing Design Procedure:** `patterns/routing-design-procedure.md` (local to this skill)
- **Gateway Command Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **3VL Intent Detection:** See `docs/intent-detection-guide.md` for conceptual overview

---

## Related Skills

- Plugin discovery: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-discover/SKILL.md`
- Gateway validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-gateway-validate/SKILL.md`
- Intent creation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-intent-create/SKILL.md`
- Skill creation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-create/SKILL.md`
- Plugin analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-analyze/SKILL.md`
