---
name: bp-gateway
description: >
  This skill should be used when the user asks to "create gateway", "set up intent routing",
  "create intent mapping", "validate gateway", "add routing to plugin",
  "multi-skill routing", "update gateway". Triggers on "gateway", "intent routing",
  "intent mapping", "routing", "multi-skill", "3VL".
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion
inputs:
  - name: plugin_path
    type: string
    required: false
    description: Path to the plugin root directory (prompted if not provided)
outputs:
  - name: gateway_files
    type: array
    description: List of gateway files created or validated
  - name: validation_report
    type: object
    description: Validation results (if validate mode)
---

# Gateway & Intent Routing Setup

Unified gateway skill that discovers skills, extracts keywords, designs 3VL intent routing,
generates gateway files, and validates the result. Absorbs the full lifecycle from skill
discovery through routing validation into a single coherent flow.

> **Keyword Extraction:** `patterns/keyword-extraction-algorithm.md`
> **Flag Generation:** `patterns/flag-generation-rules.md`
> **Routing Design:** `patterns/routing-design-procedure.md`
> **Gateway File Generation:** `patterns/gateway-file-generation.md`
> **Gateway Validation:** `patterns/gateway-validation-checklist.md`
> **3VL Validation:** `patterns/3vl-validation-rules.md`
> **Coverage Analysis:** `patterns/coverage-analysis-algorithm.md`

---

## Overview

This skill creates and validates gateway commands for multi-skill plugins. A gateway is the
unified entry point that parses natural language input, matches it against 3VL intent flags,
and routes to the correct skill. When no clear match is found, it presents an interactive menu.

**Three output files form a complete gateway:**

1. **Gateway command markdown** -- `commands/{plugin_name}.md`
2. **Intent mapping configuration** -- `commands/{plugin_name}/intent-mapping.yaml`
3. **Gateway workflow** -- `commands/{plugin_name}/workflow.yaml`

**Modes of operation:**

| Mode | Trigger | What Happens |
|------|---------|--------------|
| Full create | Default (no flags) | Phases 1-5 in sequence |
| Validate only | `--validate-only` | Phase 1 (load) then Phase 5 (validate) |
| Regenerate | `--regenerate` | Rebuild from current skills, preserve customizations |

---

## Phase 1: Mode Detection

Parse invocation arguments to determine operation mode and resolve the target plugin.

### Step 1.1: Parse Flags

```pseudocode
PARSE_MODE(args):
  computed.mode = "full"
  computed.plugin_path = null
  computed.validate_only = false
  computed.regenerate = false

  IF args contains "--validate-only":
    computed.mode = "validate"
    computed.validate_only = true

  IF args contains "--regenerate":
    computed.mode = "regenerate"
    computed.regenerate = true

  IF args contains a bare path:
    computed.plugin_path = extract_path(args)
  ELIF input "plugin_path" was provided:
    computed.plugin_path = input.plugin_path
```

### Step 1.2: Resolve Plugin Path

If `computed.plugin_path` is not set, prompt the user:

```json
{
  "questions": [{
    "question": "Which plugin should I set up a gateway for?",
    "header": "Plugin",
    "multiSelect": false,
    "options": [
      {
        "label": "Current plugin",
        "description": "Use the plugin at ${CLAUDE_PLUGIN_ROOT}"
      },
      {
        "label": "Specify path",
        "description": "I'll provide the path to a plugin directory"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_PLUGIN_SCOPE(response):
  SWITCH response:
    CASE "Current plugin":
      computed.plugin_path = CLAUDE_PLUGIN_ROOT
    CASE "Specify path":
      computed.plugin_path = ask_user_for_path()
      IF NOT file_exists(computed.plugin_path + "/.claude-plugin/plugin.json"):
        WARN "No .claude-plugin/plugin.json found. Are you sure this is a plugin?"
```

### Step 1.3: Detect Plugin Name

```pseudocode
DETECT_PLUGIN_NAME():
  manifest_path = computed.plugin_path + "/.claude-plugin/plugin.json"
  IF file_exists(manifest_path):
    manifest = Read(manifest_path)
    computed.plugin_name = parse_json(manifest).name
  ELSE:
    computed.plugin_name = basename(computed.plugin_path)

  computed.command_dir = computed.plugin_path + "/commands/" + computed.plugin_name
```

### Step 1.4: Route by Mode

```pseudocode
ROUTE_MODE():
  IF computed.mode == "validate":
    # Load existing gateway files, then jump to Phase 5
    LOAD_EXISTING_GATEWAY()
    GOTO Phase 5

  IF computed.mode == "regenerate":
    # Load existing gateway for diff comparison later
    LOAD_EXISTING_GATEWAY()
    computed.existing_gateway = computed.gateway_files_content
    # Continue to Phase 2 (full discovery + design + generate)

  # Default "full" mode continues to Phase 2
```

---

## Phase 2: Discover

Scan the plugin for all skills and extract keyword information for intent routing design.

### Step 2.1: Scan for Skills

```pseudocode
DISCOVER_SKILLS():
  skill_files = Glob(computed.plugin_path + "/skills/*/SKILL.md")

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

If `computed.skill_count == 0`:

> No SKILL.md files found. Verify the plugin directory contains a `skills/`
> subdirectory with at least one skill, then try again.

Then exit.

### Step 2.2: Extract Keywords

From each skill's description frontmatter, extract trigger keywords and action verbs
using the algorithm in `patterns/keyword-extraction-algorithm.md`:

```pseudocode
EXTRACT_KEYWORDS():
  FOR skill IN computed.skills:
    description = skill.description

    # 1. Extract quoted phrases from description
    quoted = extract_all_matches(description, /"([^"]+)"/)

    # 2. Extract "Triggers on" section
    triggers_match = regex_find(description, /Triggers on\s+(.+?)\.?\s*$/)
    IF triggers_match:
      trigger_items = split_and_trim(triggers_match.group(1), ",")
      trigger_items = [strip_quotes(item) for item in trigger_items]

    # 3. Extract verb-noun pairs (action words)
    verbs = extract_all_matches(description,
      /\b(create|add|update|find|show|delete|validate|generate|
          analyze|convert|setup|discover|check|list|build|
          rebuild|refresh|sync|remove|verify|scan)\s+(\w+)/i)
    verb_phrases = [match.group(0) for match in verbs]

    # 4. Merge, deduplicate, normalize to lowercase
    all_kw = quoted + trigger_items + verb_phrases
    seen = set()
    unique = []
    FOR kw IN all_kw:
      normalized = kw.strip().lower()
      IF normalized NOT IN seen AND len(normalized) > 1:
        seen.add(normalized)
        unique.append(normalized)

    skill.keywords = unique
    skill.keyword_count = len(skill.keywords)
```

### Step 2.3: Detect Keyword Overlap

Check for keywords shared between multiple skills to determine where 3VL disambiguation
is needed:

```pseudocode
DETECT_OVERLAP():
  keyword_index = {}  # keyword -> [skill_ids]

  FOR skill IN computed.skills:
    FOR keyword IN skill.keywords:
      normalized = lowercase(keyword)
      keyword_index.setdefault(normalized, []).append(skill.id)

  computed.keyword_overlap = {}
  FOR keyword, skill_ids IN keyword_index:
    IF len(skill_ids) > 1:
      computed.keyword_overlap[keyword] = skill_ids

  computed.overlap_count = len(computed.keyword_overlap)

  # Assess per-skill overlap severity
  FOR skill IN computed.skills:
    overlapping = count(kw for kw in skill.keywords if kw in computed.keyword_overlap)
    total = len(skill.keywords)
    skill.overlap_pct = (overlapping / total * 100) IF total > 0 ELSE 0
    skill.needs_negative_keywords = (skill.overlap_pct > 30)
```

### Step 2.4: Build Skill Inventory

Display the discovered skills, keywords, and overlap analysis:

```
## Skill Inventory: {computed.plugin_name}

Found {computed.skill_count} skills. Keyword overlap: {computed.overlap_count} shared keywords.

| # | Skill | Keywords | Overlap % | Needs Negatives |
|---|-------|----------|-----------|-----------------|
{for i, skill in enumerate(computed.skills)}
| {i+1} | {skill.name} | {skill.keyword_count} | {skill.overlap_pct:.0f}% | {skill.needs_negative_keywords} |
{/for}
```

### Step 2.5: Determine Gateway Recommendation

Based on the number of skills, recommend whether a gateway is needed:

| Skill Count | Recommendation |
|-------------|----------------|
| 1 skill | No gateway needed |
| 2-3 skills | Optional (simple menu may suffice) |
| 4+ skills | Yes, with 3VL intent detection |

If `computed.skill_count == 1`:

> This plugin has only 1 skill. A gateway command is not needed.
> Users can invoke the skill directly.

Then exit.

If `computed.skill_count >= 2 AND computed.skill_count <= 3`:

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

If `computed.skill_count >= 4`, set `computed.gateway_mode = "full"` automatically:

> Plugin has {computed.skill_count} skills. Creating gateway with 3VL intent detection.

---

## Phase 3: Design

Design the 3VL flag categories and intent routing rules. If `computed.gateway_mode == "menu_only"`,
skip this phase and proceed to Phase 4 with an empty `computed.intent_flags` and a single
fallback rule routing to `show_main_menu`.

### Step 3.1: Generate 3VL Flags

Build flag categories from two sources: standard flags (included in every gateway) and
skill-specific flags derived from keyword extraction.

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

> **Detail:** See `patterns/flag-generation-rules.md` for the complete standard flag
> definitions, naming conventions, and when to include optional flags.

**Skill-specific flag generation:**

```pseudocode
BUILD_SKILL_FLAGS():
  computed.intent_flags = copy(STANDARD_FLAGS)
  computed.skill_flags = []
  standard_keywords = flatten([f.keywords for f in STANDARD_FLAGS])

  FOR skill IN computed.skills:
    skill_id = sanitize_id(skill.id)
    flag_name = "has_" + skill_id

    # Collect unique keywords not already covered by standard flags
    unique_keywords = [k for k in skill.keywords if k not in standard_keywords]

    # Generate negative keywords from overlapping skills
    negative_kws = []
    IF skill.needs_negative_keywords:
      FOR kw IN skill.keywords:
        IF kw IN computed.keyword_overlap:
          other_skills = [s for s in computed.keyword_overlap[kw] if s != skill.id]
          FOR other_id IN other_skills:
            other_unique = get_unique_keywords(other_id, computed.skills)
            negative_kws.extend(other_unique[:3])

    negative_kws = deduplicate(negative_kws)

    IF len(unique_keywords) > 0:
      flag_def = {
        flag_name:         flag_name,
        keywords:          unique_keywords,
        negative_keywords: negative_kws,
        description:       "Specific to " + skill.name
      }
      computed.intent_flags[flag_name] = flag_def
      computed.skill_flags.append(flag_def)
      skill.has_dedicated_flag = true
    ELSE:
      skill.has_dedicated_flag = false
```

### Step 3.2: Cluster Keywords and Design Rules

Map flag combinations to skill delegation actions. Rules are evaluated in declaration order;
more specific rules (more conditions) are listed first.

```pseudocode
BUILD_INTENT_RULES():
  computed.intent_rules = []

  # --- Help rules (highest priority) ---

  computed.intent_rules.append({
    name: "explicit_help_flag",
    conditions: { has_help_flag: "T" },
    action: "show_full_help",
    priority: 100,
    description: "Explicit --help or -h flag"
  })

  computed.intent_rules.append({
    name: "help_with_flags",
    conditions: { has_flags_help: "T" },
    action: "show_flag_help",
    priority: 90,
    description: "User wants to understand runtime flags"
  })

  # --- Compound rules: help + skill domain (target + action) ---

  FOR skill IN computed.skills:
    IF skill.has_dedicated_flag:
      flag_name = "has_" + sanitize_id(skill.id)
      computed.intent_rules.append({
        name: "help_with_" + sanitize_id(skill.id),
        conditions: { has_help: "T", [flag_name]: "T" },
        action: "show_skill_help_" + sanitize_id(skill.id),
        priority: 80,
        description: "Help with " + skill.name
      })

  # --- Pure single-action rules ---
  # Map action-type flags to skills based on keyword overlap analysis

  FOR skill IN computed.skills:
    IF skill.has_dedicated_flag:
      flag_name = "has_" + sanitize_id(skill.id)
      primary_action = determine_primary_action(skill)
      exclusions = get_competing_skill_flags(skill, computed.skills)

      conditions = { [primary_action]: "T", [flag_name]: "T" }
      FOR excl IN exclusions:
        conditions[excl] = "F"

      computed.intent_rules.append({
        name: sanitize_id(skill.id) + "_pure",
        conditions: conditions,
        action: "delegate_" + sanitize_id(skill.id),
        priority: 10,
        description: skill.name + " (primary action + domain)"
      })

  # --- Direct skill match rules ---

  FOR skill IN computed.skills:
    IF skill.has_dedicated_flag:
      flag_name = "has_" + sanitize_id(skill.id)
      computed.intent_rules.append({
        name: sanitize_id(skill.id) + "_direct",
        conditions: { [flag_name]: "T" },
        action: "delegate_" + sanitize_id(skill.id),
        priority: 15,
        description: "Direct match for " + skill.name
      })

  # --- General help fallback ---

  computed.intent_rules.append({
    name: "general_help",
    conditions: { has_help: "T" },
    action: "show_full_help",
    priority: 70,
    description: "General help request"
  })

  # --- Default fallback (empty conditions = lowest priority) ---

  computed.intent_rules.append({
    name: "show_menu",
    conditions: {},
    action: "show_main_menu",
    priority: 0,
    description: "No clear intent, show interactive menu"
  })

  # Sort by priority descending (highest first)
  computed.intent_rules.sort(key=lambda r: r.priority, reverse=True)
```

### Step 3.3: Detect and Resolve Collisions

Before presenting the design to the user, check for rule collisions:

```pseudocode
DETECT_COLLISIONS():
  computed.collisions = []

  FOR i, rule_a IN enumerate(computed.intent_rules):
    FOR rule_b IN computed.intent_rules[i+1:]:
      overlap = compute_overlap(rule_a.conditions, rule_b.conditions)

      IF overlap.is_subset AND rule_a.priority == rule_b.priority:
        computed.collisions.append({
          rules: [rule_a.name, rule_b.name],
          type: "subset_same_priority",
          fix: "Assign different priorities"
        })
      ELIF rule_a.conditions == rule_b.conditions AND rule_a.action != rule_b.action:
        computed.collisions.append({
          rules: [rule_a.name, rule_b.name],
          type: "duplicate_conditions",
          fix: "Merge rules or differentiate conditions"
        })

  IF len(computed.collisions) > 0:
    DISPLAY "Found {len(computed.collisions)} collision(s) in routing design."
    FOR collision IN computed.collisions:
      DISPLAY "  - {collision.type}: {collision.rules[0]} vs {collision.rules[1]}"
      DISPLAY "    Fix: {collision.fix}"
```

### Step 3.4: Present Routing Table for Review

Display the proposed intent detection structure:

```
## Intent Detection Design

### Flag Categories ({len(computed.intent_flags)})

| Flag | Keywords (preview) | Description |
|------|-------------------|-------------|
{for flag_name, flag_def in computed.intent_flags}
| {flag_name} | {flag_def.keywords[:3].join(", ")}... | {flag_def.description} |
{/for}

### Intent Rules ({len(computed.intent_rules)})

| # | Rule | Conditions | Priority | Routes To | Description |
|---|------|------------|----------|-----------|-------------|
{for i, rule in enumerate(computed.intent_rules)}
| {i+1} | {rule.name} | {len(rule.conditions)} flags | {rule.priority} | {rule.action} | {rule.description} |
{/for}

### Skill Routing Coverage

| Skill | Dedicated Flag | Triggering Rules |
|-------|----------------|-----------------|
{for skill in computed.skills}
| {skill.name} | {skill.has_dedicated_flag} | {rules_that_route_to(skill).join(", ")} |
{/for}
```

Ask for confirmation:

```json
{
  "questions": [{
    "question": "Does this intent detection design look correct?",
    "header": "Confirm Design",
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
      CONTINUE to Phase 4
    CASE "Adjust flags":
      # Ask user which flags to change, rebuild rules, re-present
      GOTO Step 3.1 with user modifications
    CASE "Adjust rules":
      # Ask user which rules to change, re-present
      GOTO Step 3.2 with user modifications
    CASE "Start over":
      GOTO Phase 2, Step 2.1
```

---

## Phase 4: Generate

Produce the three gateway files. Handle `--regenerate` mode by diffing against existing
files and preserving user customizations.

### Step 4.1: Generate intent-mapping.yaml

Load the intent mapping template and substitute all placeholders with values computed
in Phase 3.

```pseudocode
GENERATE_INTENT_MAPPING():
  template_path = computed.plugin_path + "/templates/intent-mapping.yaml.template"
  computed.use_template = file_exists(template_path)

  IF computed.use_template:
    template = Read(template_path)
    output = substitute_template(template, {
      plugin_name:        computed.plugin_name,
      PLUGIN_TITLE:       uppercase(computed.plugin_name.replace("-", " ")),
      intent_flags:       computed.intent_flags,
      intent_rules:       computed.intent_rules,
      skills:             computed.skills
    })
  ELSE:
    output = generate_intent_mapping_yaml()

  output_path = computed.command_dir + "/intent-mapping.yaml"
```

**Direct YAML generation (when no template exists):**

```pseudocode
function generate_intent_mapping_yaml():
  yaml = "# Intent mapping for " + computed.plugin_name + " gateway\n"
  yaml += "# Generated by bp-gateway\n\n"

  # Emit intent_flags section
  yaml += "intent_flags:\n"
  FOR flag_name, flag_def IN computed.intent_flags:
    yaml += "  " + flag_name + ":\n"
    yaml += "    keywords:\n"
    FOR kw IN flag_def.keywords:
      yaml += '      - "' + kw + '"\n'
    IF flag_def.negative_keywords:
      yaml += "    negative_keywords:\n"
      FOR nkw IN flag_def.negative_keywords:
        yaml += '      - "' + nkw + '"\n'
    yaml += '    description: "' + flag_def.description + '"\n\n'

  # Emit intent_rules section
  yaml += "intent_rules:\n"
  FOR rule IN computed.intent_rules:
    yaml += "  - name: " + '"' + rule.name + '"\n'
    yaml += "    conditions:\n"
    FOR flag_name, value IN rule.conditions:
      yaml += "      " + flag_name + ": " + value + "\n"
    IF len(rule.conditions) == 0:
      yaml += "    conditions: {}\n"
    yaml += "    action: " + rule.action + "\n"
    yaml += '    description: "' + rule.description + '"\n\n'

  # Emit actions section
  yaml += "actions:\n"
  FOR skill IN computed.skills:
    skill_id = sanitize_id(skill.id)
    yaml += "  delegate_" + skill_id + ":\n"
    yaml += "    type: invoke_skill\n"
    yaml += '    skill: "' + skill.name + '"\n'
    yaml += "    pass_arguments: true\n\n"

  yaml += "  show_main_menu:\n"
  yaml += "    type: user_prompt\n"
  yaml += "    prompt:\n"
  yaml += '      question: "What would you like to do with ' + computed.plugin_name + '?"\n'
  yaml += '      header: "Menu"\n'
  yaml += "      options:\n"
  FOR skill IN computed.skills:
    skill_id = sanitize_id(skill.id)
    yaml += "        - id: " + skill_id + "\n"
    yaml += '          label: "' + skill.name + '"\n'
    yaml += '          description: "' + truncate(skill.description, 60) + '"\n'

  return yaml
```

### Step 4.2: Generate workflow.yaml

Build the routing workflow following `patterns/routing-design-procedure.md`. The workflow
has a fixed topology; the variable parts are the skill delegation nodes and menu options.

```pseudocode
GENERATE_WORKFLOW():
  # Build workflow YAML with the standard gateway topology:
  #   check_arguments -> parse_intent -> check_clear_winner
  #     -> execute_matched_intent / show_disambiguation / show_main_menu
  #     -> delegate_{skill_id} nodes (one per skill)

  # Variable sections generated from computed.skills:
  #   - show_main_menu options (one per skill)
  #   - delegate_* nodes (one per skill)
  #   - on_response mappings in show_main_menu

  output_path = computed.command_dir + "/workflow.yaml"
```

The workflow structure follows the template in `patterns/gateway-file-generation.md`.
Key nodes:

| Node | Type | Purpose |
|------|------|---------|
| `check_arguments` | conditional | Check if user provided arguments |
| `parse_intent` | action | Parse input against 3VL intent flags |
| `check_clear_winner` | conditional | Check if matching produced a clear winner |
| `execute_matched_intent` | action | Route to the winning intent action |
| `show_disambiguation` | user_prompt | Present top candidates when ambiguous |
| `show_main_menu` | user_prompt | Present full skill menu (no arguments) |
| `delegate_{skill_id}` | action | Invoke specific skill (one per skill) |

### Step 4.3: Generate Gateway Command Markdown

```pseudocode
GENERATE_GATEWAY_COMMAND():
  template_path = computed.plugin_path + "/templates/gateway-command.md.template"

  IF file_exists(template_path):
    template = Read(template_path)
    output = substitute_template(template, {
      plugin_name:        computed.plugin_name,
      PLUGIN_TITLE:       uppercase(computed.plugin_name.replace("-", " ")),
      skills:             computed.skills,
      examples:           computed.examples
    })
  ELSE:
    output = generate_gateway_markdown()

  # Generate usage examples from skill names
  computed.examples = []
  FOR skill IN computed.skills:
    example_input = skill.keywords[0] IF skill.keywords ELSE skill.id
    computed.examples.append({
      command: "/" + computed.plugin_name + " " + example_input,
      skill_name: skill.name
    })

  output_path = computed.plugin_path + "/commands/" + computed.plugin_name + ".md"
```

> **Detail:** See `patterns/gateway-file-generation.md` for the complete placeholder catalog
> covering all three generated files.

### Step 4.4: Handle Existing Files

For each output file, if it already exists, ask before overwriting:

```json
{
  "questions": [{
    "question": "{filename} already exists. What should I do?",
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

### Step 4.5: Handle Regenerate Mode

When `computed.regenerate == true`, diff the newly generated files against the existing
gateway files and preserve user customizations:

```pseudocode
HANDLE_REGENERATE():
  IF NOT computed.regenerate:
    RETURN

  FOR file_type IN ["intent_mapping", "workflow", "gateway_command"]:
    new_content = computed.generated[file_type]
    old_content = computed.existing_gateway[file_type]

    IF old_content IS NOT null:
      # Identify sections that differ
      diffs = compute_diff(old_content, new_content)
      custom_sections = identify_customizations(old_content, new_content)

      IF len(custom_sections) > 0:
        DISPLAY "Found {len(custom_sections)} customized sections in {file_type}:"
        FOR section IN custom_sections:
          DISPLAY "  - {section.name}: {section.description}"

        # Ask user whether to preserve each customization
        FOR section IN custom_sections:
          # Merge the customization into the new content
          new_content = merge_customization(new_content, section)

    computed.generated[file_type] = new_content
```

### Step 4.6: Write Files and Record

Write all generated files and store their paths:

```pseudocode
WRITE_ALL_FILES():
  computed.gateway_files = []

  Write(computed.generated.intent_mapping_path, computed.generated.intent_mapping)
  computed.gateway_files.append(computed.generated.intent_mapping_path)

  Write(computed.generated.workflow_path, computed.generated.workflow)
  computed.gateway_files.append(computed.generated.workflow_path)

  Write(computed.generated.gateway_command_path, computed.generated.gateway_command)
  computed.gateway_files.append(computed.generated.gateway_command_path)
```

---

## Phase 5: Validate

Comprehensive validation of the gateway across 6 dimensions. Runs on the files written in
Phase 4 (full/regenerate modes) or on existing files (validate-only mode).

> **Detail:** See `patterns/gateway-validation-checklist.md` for the complete checklist
> and `patterns/3vl-validation-rules.md` for truth tables and ranking algorithm specification.

### Step 5.1: Load Gateway Files

If not already loaded (validate-only mode), locate and parse all gateway files:

```pseudocode
LOAD_GATEWAY():
  # Locate the three gateway files
  gateway_md = Glob(computed.plugin_path + "/commands/*.md")
  intent_yaml = Glob(computed.command_dir + "/intent-mapping.yaml")
  workflow_yaml = Glob(computed.command_dir + "/workflow.yaml")

  # Parse intent-mapping.yaml
  IF file_exists(intent_yaml):
    content = Read(intent_yaml)
    computed.intent_mapping = parse_yaml(content)
    # Verify required sections: intent_flags, intent_rules (or rules), actions
  ELSE:
    DISPLAY "No intent-mapping.yaml found at " + computed.command_dir
    computed.validation_report.fatal = true
    EXIT

  # Discover all available skills for cross-referencing
  computed.available_skills = []
  skill_files = Glob(computed.plugin_path + "/skills/*/SKILL.md")
  FOR skill_file IN skill_files:
    fm = parse_yaml_frontmatter(Read(skill_file))
    computed.available_skills.append({ name: fm.name, path: skill_file })
```

### Step 5.2: Route Completeness

Check that every skill is reachable from at least one routing rule:

```pseudocode
CHECK_ROUTE_COMPLETENESS():
  computed.validation_report.route_issues = []

  # Check 1: Every skill has at least one rule routing to it
  FOR skill IN computed.available_skills:
    matching_rules = [r for r in computed.intent_mapping.rules
                      if r.action == "delegate_" + sanitize_id(skill.name)
                      or r.action == skill.name]
    IF len(matching_rules) == 0:
      computed.validation_report.route_issues.append({
        severity: "warning",
        check: "skill_coverage",
        message: "Skill '" + skill.name + "' has no routing rule.",
        fix: "Add a rule with action targeting this skill."
      })

  # Check 2: Every rule action targets a real skill or known built-in
  KNOWN_BUILTINS = ["show_full_help", "show_flag_help", "show_main_menu",
                    "show_skill_help_*"]
  FOR rule IN computed.intent_mapping.rules:
    IF NOT is_known_action(rule.action, computed.available_skills, KNOWN_BUILTINS):
      computed.validation_report.route_issues.append({
        severity: "error",
        check: "action_target",
        message: "Rule '" + rule.name + "' targets unknown action '" + rule.action + "'.",
        fix: "Rename action to match a skill or built-in, or create the missing skill."
      })

  # Check 3: Fallback exists
  has_fallback = any(len(r.conditions) == 0 for r in computed.intent_mapping.rules)
  IF NOT has_fallback:
    computed.validation_report.route_issues.append({
      severity: "error",
      check: "fallback_present",
      message: "No fallback rule found (rule with empty conditions).",
      fix: "Add a rule with empty conditions {} as the catch-all."
    })
```

### Step 5.3: Intent Alignment

Verify that routing rules accurately reflect skill descriptions:

```pseudocode
CHECK_INTENT_ALIGNMENT():
  computed.validation_report.alignment_issues = []

  FOR skill IN computed.available_skills:
    skill_description = parse_yaml_frontmatter(Read(skill.path)).description
    skill_keywords = extract_keywords(skill_description)

    # Check flag keywords overlap with skill keywords
    matching_flags = find_flags_covering_skill(skill_keywords, computed.intent_mapping.intent_flags)

    IF len(matching_flags) == 0:
      computed.validation_report.alignment_issues.append({
        severity: "warning",
        check: "keyword_alignment",
        message: "No flag keywords match skill '" + skill.name + "' description.",
        fix: "Add skill-specific keywords to an existing flag or create a new has_* flag."
      })
```

### Step 5.4: Skill Reference Validation

Verify all referenced skills exist on disk:

```pseudocode
CHECK_SKILL_REFERENCES():
  computed.validation_report.reference_issues = []

  FOR action IN computed.intent_mapping.actions:
    IF action.type == "invoke_skill":
      skill_name = action.skill
      matching = [s for s in computed.available_skills if s.name == skill_name]
      IF len(matching) == 0:
        computed.validation_report.reference_issues.append({
          severity: "error",
          check: "skill_exists",
          message: "Action references skill '" + skill_name + "' which does not exist on disk.",
          fix: "Create the skill or update the action to reference an existing skill."
        })
```

### Step 5.5: 3VL Semantics Validation

Validate truth table correctness and check for contradictory rules:

```pseudocode
CHECK_3VL_SEMANTICS():
  computed.validation_report.threevl_issues = []

  # Check 1: Valid condition values (T or F only; omitted = U)
  FOR rule IN computed.intent_mapping.rules:
    FOR flag_name, value IN rule.conditions:
      IF value NOT IN ["T", "F"]:
        computed.validation_report.threevl_issues.append({
          severity: "error",
          check: "invalid_condition_value",
          message: "Rule '" + rule.name + "' has '" + flag_name + ": " + value + "'. Expected T or F.",
          fix: "Change to T, F, or remove the flag for implicit U."
        })

      IF flag_name NOT IN computed.intent_mapping.intent_flags:
        computed.validation_report.threevl_issues.append({
          severity: "error",
          check: "undeclared_flag",
          message: "Rule '" + rule.name + "' references undeclared flag '" + flag_name + "'.",
          fix: "Add the flag to intent_flags or remove from this rule."
        })

  # Check 2: No ranking ties (identical conditions + same priority)
  FOR i, rule_a IN enumerate(computed.intent_mapping.rules):
    FOR rule_b IN computed.intent_mapping.rules[i+1:]:
      IF rule_a.conditions == rule_b.conditions:
        IF rule_a.priority == rule_b.priority AND rule_a.action != rule_b.action:
          computed.validation_report.threevl_issues.append({
            severity: "error",
            check: "ranking_tie",
            message: "Rules '" + rule_a.name + "' and '" + rule_b.name +
                     "' have identical conditions and priority. Routing is non-deterministic.",
            fix: "Assign different priorities or differentiate conditions."
          })

  # Check 3: No overly-broad rules swallowing specific ones
  FOR i, rule_a IN enumerate(computed.intent_mapping.rules):
    FOR rule_b IN computed.intent_mapping.rules[i+1:]:
      overlap = compute_overlap(rule_a.conditions, rule_b.conditions)
      IF overlap.is_subset:
        broad = rule_a IF len(rule_a.conditions) < len(rule_b.conditions) ELSE rule_b
        specific = rule_b IF len(rule_a.conditions) < len(rule_b.conditions) ELSE rule_a
        IF broad.priority >= specific.priority:
          computed.validation_report.threevl_issues.append({
            severity: "warning",
            check: "broad_swallows_specific",
            message: "Broad rule '" + broad.name + "' swallows specific rule '" + specific.name + "'.",
            fix: "Give the specific rule higher priority."
          })
```

### Step 5.6: Coverage Analysis

Detect gaps -- inputs that match no rule:

```pseudocode
CHECK_COVERAGE():
  computed.validation_report.coverage_issues = []

  # Standard verbs that should be routable
  STANDARD_VERBS = [
    "create", "new", "add", "make",
    "update", "edit", "modify", "change",
    "delete", "remove", "drop",
    "list", "show", "view", "display",
    "validate", "check", "verify", "lint",
    "help", "?"
  ]

  all_keywords = set()
  FOR flag_name, flag_def IN computed.intent_mapping.intent_flags:
    all_keywords.update(flag_def.keywords)

  uncovered_verbs = [v for v in STANDARD_VERBS if v not in all_keywords]

  IF len(uncovered_verbs) > 0:
    computed.validation_report.coverage_issues.append({
      severity: "info",
      check: "keyword_coverage",
      message: "Standard verbs not covered: " + ", ".join(uncovered_verbs),
      fix: "Add these verbs to relevant flag keyword lists if users are likely to use them."
    })

  # Check for missing negative keywords on overlapping flags
  keyword_to_flags = {}
  FOR flag_name, flag_def IN computed.intent_mapping.intent_flags:
    FOR keyword IN flag_def.keywords:
      keyword_to_flags.setdefault(keyword, []).append(flag_name)

  shared_keywords = {k: flags for k, flags in keyword_to_flags if len(flags) > 1}

  FOR keyword, flags IN shared_keywords:
    FOR flag_name IN flags:
      flag_def = computed.intent_mapping.intent_flags[flag_name]
      IF len(flag_def.get("negative_keywords", [])) == 0:
        computed.validation_report.coverage_issues.append({
          severity: "info",
          check: "missing_negative_keywords",
          message: "Keyword '" + keyword + "' shared by " + str(flags) +
                   ". Flag '" + flag_name + "' has no negative_keywords.",
          fix: "Add negative_keywords to disambiguate."
        })
```

> **Detail:** See `patterns/coverage-analysis-algorithm.md` for the complete gap detection
> procedure including flag combination enumeration.

### Step 5.7: Structural Validation

Validate YAML structure and required fields:

```pseudocode
CHECK_STRUCTURE():
  computed.validation_report.structure_issues = []

  # Check intent-mapping.yaml required sections
  required_sections = ["intent_flags", "intent_rules", "actions"]
  FOR section IN required_sections:
    IF section NOT IN computed.intent_mapping:
      computed.validation_report.structure_issues.append({
        severity: "error",
        check: "missing_section",
        message: "Required section '" + section + "' missing from intent-mapping.yaml.",
        fix: "Add the '" + section + "' section to the file."
      })

  # Check workflow.yaml structure
  IF file_exists(computed.command_dir + "/workflow.yaml"):
    workflow = parse_yaml(Read(computed.command_dir + "/workflow.yaml"))
    required_workflow_fields = ["name", "start_node", "nodes", "endings"]
    FOR field IN required_workflow_fields:
      IF field NOT IN workflow:
        computed.validation_report.structure_issues.append({
          severity: "error",
          check: "missing_workflow_field",
          message: "Required field '" + field + "' missing from workflow.yaml.",
          fix: "Add the '" + field + "' field."
        })

  # Check gateway command markdown has frontmatter
  gateway_md_path = computed.plugin_path + "/commands/" + computed.plugin_name + ".md"
  IF file_exists(gateway_md_path):
    content = Read(gateway_md_path)
    IF NOT content.startswith("---"):
      computed.validation_report.structure_issues.append({
        severity: "error",
        check: "missing_frontmatter",
        message: "Gateway command markdown missing YAML frontmatter.",
        fix: "Add --- delimited YAML frontmatter at the top of the file."
      })
```

### Step 5.8: Report Findings by Severity

Aggregate all validation dimensions and produce a comprehensive report:

```pseudocode
GENERATE_REPORT():
  dimensions = [
    ("Route Completeness", computed.validation_report.route_issues),
    ("Intent Alignment", computed.validation_report.alignment_issues),
    ("Skill References", computed.validation_report.reference_issues),
    ("3VL Semantics", computed.validation_report.threevl_issues),
    ("Coverage", computed.validation_report.coverage_issues),
    ("Structure", computed.validation_report.structure_issues)
  ]

  all_issues = []
  FOR dim_name, issues IN dimensions:
    FOR issue IN issues:
      issue.dimension = dim_name
      all_issues.append(issue)

  errors = [i for i in all_issues if i.severity == "error"]
  warnings = [i for i in all_issues if i.severity == "warning"]
  infos = [i for i in all_issues if i.severity == "info"]

  computed.validation_report.summary = {
    total_issues: len(all_issues),
    errors: len(errors),
    warnings: len(warnings),
    info: len(infos),
    passed: len(errors) == 0
  }
```

Display the summary:

```
## Validation Report: {computed.plugin_name} Gateway

### Dimension Summary

| Dimension | Status | Errors | Warnings | Info |
|-----------|--------|--------|----------|------|
{for dim_name, issues in dimensions}
| {dim_name} | {status(issues)} | {count_errors(issues)} | {count_warnings(issues)} | {count_info(issues)} |
{/for}

### Overall: {computed.validation_report.summary.passed ? "PASS" : "FAIL"}

- Errors: {computed.validation_report.summary.errors}
- Warnings: {computed.validation_report.summary.warnings}
- Info: {computed.validation_report.summary.info}

{if errors}
### Errors (must fix)

{for issue in errors}
[ERROR] {issue.dimension}: {issue.message}
  Fix: {issue.fix}

{/for}
{/if}

{if warnings}
### Warnings (should fix)

{for issue in warnings}
[WARN] {issue.dimension}: {issue.message}
  Fix: {issue.fix}

{/for}
{/if}

{if infos}
### Info (observations)

{for issue in infos}
[INFO] {issue.dimension}: {issue.message}
  Note: {issue.fix}

{/for}
{/if}
```

### Step 5.9: Offer Next Steps

```json
{
  "questions": [{
    "question": "Validation complete. What would you like to do?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {
        "label": "Fix issues",
        "description": "Re-run gateway generation with fixes applied"
      },
      {
        "label": "Re-validate",
        "description": "Run validation again after manual edits"
      },
      {
        "label": "Done",
        "description": "Validation review complete"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_VALIDATION_NEXT(response):
  SWITCH response:
    CASE "Fix issues":
      # Return to Phase 2 with validation context to guide fixes
      computed.fix_context = computed.validation_report
      GOTO Phase 2
    CASE "Re-validate":
      # Clear validation state and re-run Phase 5
      computed.validation_report = {}
      GOTO Phase 5, Step 5.1
    CASE "Done":
      DISPLAY "Validation complete."
      EXIT
```

---

## State Flow

```
Phase 1              Phase 2                Phase 3              Phase 4              Phase 5
──────────────────────────────────────────────────────────────────────────────────────────────
computed.mode     -> computed.skills[]   -> computed.intent     -> computed.generated -> computed.validation
computed             .keywords              _flags                 .intent_mapping       _report
.plugin_path         .keyword_count         computed.intent        .workflow              .route_issues
computed             computed                _rules                .gateway_command       .alignment_issues
.plugin_name         .keyword_overlap       computed               computed               .reference_issues
computed             computed                .collisions            .gateway_files         .threevl_issues
.gateway_mode        .skill_count           computed                                      .coverage_issues
computed                                     .skill_flags                                 .structure_issues
.regenerate                                                                               .summary
```

---

## Reference Documentation

- **Keyword Extraction Algorithm:** `patterns/keyword-extraction-algorithm.md` (local)
- **Flag Generation Rules:** `patterns/flag-generation-rules.md` (local)
- **Routing Design Procedure:** `patterns/routing-design-procedure.md` (local)
- **Gateway File Generation:** `patterns/gateway-file-generation.md` (local)
- **Gateway Validation Checklist:** `patterns/gateway-validation-checklist.md` (local)
- **3VL Validation Rules:** `patterns/3vl-validation-rules.md` (local)
- **Coverage Analysis Algorithm:** `patterns/coverage-analysis-algorithm.md` (local)
- **Gateway Command Template:** `${CLAUDE_PLUGIN_ROOT}/templates/gateway-command.md.template`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

---

## Related Skills

- **Assess skill coverage:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- **Enhance skill structure:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-enhance/SKILL.md`
- **Build new skills:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
- **Maintain workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/SKILL.md`
- **Visualize workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
