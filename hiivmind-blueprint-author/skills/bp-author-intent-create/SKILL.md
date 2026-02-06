---
name: bp-author-intent-create
description: >
  This skill should be used when the user asks to "create intent mapping", "add intent detection",
  "generate intent-mapping.yaml", "define keyword routing", "set up 3VL matching",
  "create routing rules", or needs to create intent-mapping.yaml for a gateway. Triggers on
  "intent create", "create intent", "intent mapping", "keyword routing", "3VL setup",
  "routing rules", "intent detection".
allowed-tools: Read, Write, Glob, Grep, AskUserQuestion
---

# Create Intent Mapping

Generate a complete `intent-mapping.yaml` for a gateway command by discovering skills, extracting
keywords from descriptions, detecting overlap, designing flag categories, generating 3VL rules,
and writing the final routing configuration.

> **Keyword Extraction Algorithm:** `patterns/keyword-extraction-algorithm.md`
> **Flag Generation Rules:** `patterns/flag-generation-rules.md`
> **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`

---

## Overview

This skill produces a complete `intent-mapping.yaml` file that enables a gateway command to route
user input to the correct skill using three-valued logic (3VL) keyword matching. The process:

1. **Discover** all skills in the target plugin
2. **Extract** trigger keywords from each skill's description
3. **Detect** keyword overlap between skills
4. **Design** flag categories with user review
5. **Generate** 3VL rules mapping flag combinations to skills
6. **Write** the final intent-mapping.yaml file

**Output contract:** A valid `intent-mapping.yaml` at `commands/{plugin-name}/intent-mapping.yaml`
containing `intent_flags`, `intent_rules` (with 3VL conditions), `actions`, and a `fallback`.

---

## Phase 1: Discover Skills

### Step 1.1: Determine Plugin Scope

Present the user with an option to select which plugin to generate intent mapping for:

```json
{
  "questions": [{
    "question": "Which plugin should I create intent mapping for?",
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
HANDLE_SCOPE(response):
  SWITCH response:
    CASE "Current plugin":
      computed.plugin_root = CLAUDE_PLUGIN_ROOT
    CASE "Specify path":
      # Ask user for the path via follow-up prompt
      computed.plugin_root = user_provided_path
      # Validate the path exists and contains .claude-plugin/plugin.json
      if not file_exists(computed.plugin_root + "/.claude-plugin/plugin.json"):
        WARN "No .claude-plugin/plugin.json found at this path. Are you sure this is a plugin?"
```

Extract the plugin name from `computed.plugin_root`:

```pseudocode
# Read .claude-plugin/plugin.json to get the plugin name
plugin_manifest = Read(computed.plugin_root + "/.claude-plugin/plugin.json")
computed.plugin_name = plugin_manifest.name
```

### Step 1.2: Glob for All SKILL.md Files

Search the plugin for SKILL.md files in both `skills/` and `skills-prose/` directories:

```pseudocode
FIND_SKILLS():
  computed.skill_files = []

  # Search skills/ directory (workflow-based skills)
  files = Glob(computed.plugin_root + "/skills/*/SKILL.md")
  computed.skill_files += files

  # Search skills-prose/ directory (prose-based skills)
  files = Glob(computed.plugin_root + "/skills-prose/*/SKILL.md")
  computed.skill_files += files

  # Deduplicate by absolute path
  computed.skill_files = deduplicate(computed.skill_files)
```

If `computed.skill_files` is empty:

> No SKILL.md files found in this plugin. Verify the plugin has skills in `skills/` or
> `skills-prose/` directories.

Then offer to retry with a different path or exit.

### Step 1.3: Extract Frontmatter from Each Skill

For each discovered SKILL.md, read the file and extract the YAML frontmatter:

```pseudocode
EXTRACT_METADATA():
  computed.skills = []

  FOR file IN computed.skill_files:
    content = Read(file.path)
    frontmatter = parse_yaml_frontmatter(content)

    skill = {
      name:        frontmatter.name,
      description: frontmatter.description,
      path:        file.path,
      directory:   parent_directory(file.path),
      tools:       split(frontmatter["allowed-tools"], ", ")
    }

    computed.skills.append(skill)
```

Display the discovered skills:

```
## Discovered Skills: {computed.plugin_name}

Found {len(computed.skills)} skills:

| # | Skill Name | Path |
|---|------------|------|
{for i, skill in enumerate(computed.skills)}
| {i+1} | {skill.name} | {skill.path} |
{/for}
```

Store in `computed.skills[]` with `name`, `description`, `path`, `directory`, and `tools` fields.

---

## Phase 2: Extract Keywords

### Step 2.1: Parse Trigger Phrases from Descriptions

For each skill in `computed.skills`, parse the `description` field to extract candidate keywords
using the algorithm documented in `patterns/keyword-extraction-algorithm.md`.

```pseudocode
function extract_keywords(description):
  keywords = []

  # 1. Extract quoted phrases: "create issue", "close PR"
  quoted = regex_find_all(description, /"([^"]+)"/)
  keywords.extend(quoted)

  # 2. Extract "Triggers on" section
  triggers_match = regex_find(description, /Triggers on\s+(.+?)\.?\s*$/)
  if triggers_match:
    trigger_items = split_and_trim(triggers_match.group(1), ",")
    # Strip surrounding quotes from each item
    trigger_items = [strip_quotes(item) for item in trigger_items]
    keywords.extend(trigger_items)

  # 3. Extract action verbs paired with their objects
  verb_phrases = regex_find_all(description,
    /\b(create|delete|update|find|show|list|analyze|convert|validate|generate|set up|add|remove|check|verify|scan|discover|build|rebuild)\s+\w+(\s+\w+)?/i)
  keywords.extend(verb_phrases)

  # 4. Extract standalone action verbs
  verbs = regex_find_all(description,
    /\b(create|delete|update|find|show|list|analyze|convert|validate|generate|setup|init|discover|scan|verify|check|build|rebuild|refresh|sync)\b/i)
  keywords.extend(verbs)

  # 5. Deduplicate preserving order, normalize to lowercase
  seen = set()
  unique = []
  for kw in keywords:
    normalized = kw.strip().lower()
    if normalized not in seen and len(normalized) > 1:
      seen.add(normalized)
      unique.append(normalized)

  return unique
```

> **Detail:** See `patterns/keyword-extraction-algorithm.md` for the complete regex catalog,
> edge case handling, and priority ordering rules.

Apply extraction to each skill:

```pseudocode
EXTRACT_ALL_KEYWORDS():
  FOR skill IN computed.skills:
    skill.raw_keywords = extract_keywords(skill.description)
```

### Step 2.2: Present Extracted Keywords for Review

Display the extracted keywords grouped by skill so the user can verify:

```
## Extracted Keywords

{for skill in computed.skills}
### {skill.name}
Keywords: {", ".join(skill.raw_keywords)}

{/for}
```

Ask the user to confirm or adjust:

```json
{
  "questions": [{
    "question": "Are the extracted keywords correct? You can adjust them in the next step.",
    "header": "Keywords",
    "multiSelect": false,
    "options": [
      {
        "label": "Keywords look good",
        "description": "Proceed to overlap detection"
      },
      {
        "label": "Edit keywords for a skill",
        "description": "I want to add, remove, or change keywords for one or more skills"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_KEYWORD_REVIEW(response):
  SWITCH response:
    CASE "Keywords look good":
      GOTO Phase 3
    CASE "Edit keywords for a skill":
      # Present follow-up listing each skill
      # For each skill the user wants to edit, ask for the new keyword list
      # Update computed.skills[].raw_keywords with the edited values
      # Redisplay the updated table and re-ask for confirmation
```

---

## Phase 3: Detect Overlap

### Step 3.1: Find Keywords Appearing in Multiple Skills

Build a keyword-to-skills index to identify keywords that appear across multiple skills:

```pseudocode
function detect_overlap(skills):
  keyword_index = {}  # keyword -> [skill_names]

  FOR skill IN skills:
    FOR kw IN skill.raw_keywords:
      keyword_index.setdefault(kw, []).append(skill.name)

  # Find overlapping keywords (appear in 2+ skills)
  computed.overlap = {}
  FOR kw, skill_list IN keyword_index:
    IF len(skill_list) > 1:
      computed.overlap[kw] = skill_list

  return computed.overlap
```

### Step 3.2: Assess Overlap Severity

For each skill, calculate the percentage of its keywords that overlap with other skills:

```pseudocode
function assess_overlap_severity(skills, overlap):
  FOR skill IN skills:
    overlapping_count = count(kw for kw in skill.raw_keywords if kw in overlap)
    total_count = len(skill.raw_keywords)
    skill.overlap_pct = (overlapping_count / total_count * 100) if total_count > 0 else 0

    if skill.overlap_pct > 30:
      skill.needs_negative_keywords = true
    else:
      skill.needs_negative_keywords = false
```

If significant overlap exists (any skill has >30% shared keywords), recommend 3VL negative
keywords for disambiguation:

```
## Keyword Overlap Analysis

{if len(computed.overlap) > 0}
**Overlapping keywords found:**

| Keyword | Skills |
|---------|--------|
{for kw, skill_list in computed.overlap.items()}
| "{kw}" | {", ".join(skill_list)} |
{/for}

**Per-skill overlap:**

| Skill | Overlap % | Needs Negative Keywords |
|-------|-----------|------------------------|
{for skill in computed.skills}
| {skill.name} | {skill.overlap_pct:.0f}% | {skill.needs_negative_keywords} |
{/for}

> **Recommendation:** Skills with >30% overlap should use negative keywords (3VL `F` conditions)
> to disambiguate. The flag generation phase will create appropriate negative_keywords entries.
{else}
No significant keyword overlap detected. Each skill has unique trigger phrases.
{/if}
```

### Step 3.3: Display Overlap Matrix

If overlap exists, display a matrix showing which skills share keywords:

```pseudocode
function display_overlap_matrix(skills, overlap):
  # Build skill-pair overlap counts
  pairs = {}
  FOR kw, skill_list IN overlap:
    FOR i, s1 IN enumerate(skill_list):
      FOR s2 IN skill_list[i+1:]:
        pair_key = (s1, s2)
        pairs.setdefault(pair_key, 0)
        pairs[pair_key] += 1

  # Display as table
  DISPLAY "### Overlap Matrix (shared keyword count)"
  # Render NxN matrix with skill names as row/column headers
```

---

## Phase 4: Design Flag Categories

### Step 4.1: Group Keywords into has_X Flags

Start with the standard flag set that every gateway should include, then add skill-specific flags.

**Standard flags (always included):**

| Flag | Keywords | Purpose |
|------|----------|---------|
| `has_help` | "help", "how do i", "how to", "?", "explain", "guide", "what can", "show commands" | Natural language help |
| `has_help_flag` | "--help", "-h", "-?" | Explicit help flag |
| `has_flags_help` | "flags", "options", "arguments", "--verbose", "--quiet", "runtime flags" | Flag documentation |
| `has_init` | "create", "new", "initialize", "init", "start", "setup" | Create new things |
| `has_modify` | "add", "update", "edit", "change", "modify", "extend" | Modify existing things |
| `has_query` | "find", "search", "show", "list", "what", "where", "check", "status" | Query/inspect things |
| `has_delete` | "delete", "remove", "clear", "reset" | Remove things |

> **Detail:** See `patterns/flag-generation-rules.md` for the complete standard flag definitions,
> naming conventions, and when to include optional flags like `has_logging_help`, `has_display_help`,
> and `has_prompts_help`.

**Skill-specific flag generation:**

```pseudocode
function generate_skill_flags(skills, overlap):
  computed.skill_flags = []

  FOR skill IN skills:
    # Derive a flag name from the skill name
    # Strip common prefixes (plugin name) to get the short ID
    skill_id = derive_short_id(skill.name)
    flag_name = "has_" + skill_id

    # Collect unique keywords (not already covered by standard flags)
    unique_kws = [kw for kw in skill.raw_keywords
                  if kw not in STANDARD_FLAG_KEYWORDS]

    # Generate negative keywords from overlapping skills
    negative_kws = []
    if skill.needs_negative_keywords:
      # For each overlapping keyword, find the OTHER skills that share it
      for kw in skill.raw_keywords:
        if kw in overlap:
          other_skills = [s for s in overlap[kw] if s != skill.name]
          # Add keywords unique to those other skills as negatives
          for other in other_skills:
            other_unique = get_unique_keywords(other, skills)
            negative_kws.extend(other_unique[:3])  # Top 3 distinguishing keywords

    negative_kws = deduplicate(negative_kws)

    computed.skill_flags.append({
      flag_name:         flag_name,
      skill_name:        skill.name,
      skill_id:          skill_id,
      keywords:          unique_kws,
      negative_keywords: negative_kws,
      description:       "Specific to " + skill.name
    })
```

### Step 4.2: Generate Complete Flag Catalog

Combine standard flags with skill-specific flags into `computed.all_flags`:

```pseudocode
ASSEMBLE_FLAGS():
  computed.all_flags = STANDARD_FLAGS + computed.skill_flags
```

Display the proposed flag catalog:

```
## Proposed Flag Categories

### Standard Flags
| Flag | Keywords | Description |
|------|----------|-------------|
{for flag in STANDARD_FLAGS}
| {flag.flag_name} | {", ".join(flag.keywords[:5])}... | {flag.description} |
{/for}

### Skill-Specific Flags
| Flag | Keywords | Negative Keywords | Description |
|------|----------|-------------------|-------------|
{for flag in computed.skill_flags}
| {flag.flag_name} | {", ".join(flag.keywords[:5])}... | {", ".join(flag.negative_keywords[:3]) or "none"} | {flag.description} |
{/for}
```

### Step 4.3: Review Flag Design

Present the proposed flag design for user review and approval:

```json
{
  "questions": [{
    "question": "Review the proposed flag categories. Any adjustments needed?",
    "header": "Flags",
    "multiSelect": false,
    "options": [
      {
        "label": "Looks good",
        "description": "Proceed with these flag categories"
      },
      {
        "label": "Add flag",
        "description": "I want to add a custom flag category"
      },
      {
        "label": "Remove flag",
        "description": "Some flags are unnecessary"
      },
      {
        "label": "Merge flags",
        "description": "Some flags should be combined"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_FLAG_REVIEW(response):
  SWITCH response:
    CASE "Looks good":
      GOTO Phase 5
    CASE "Add flag":
      # Ask for: flag name, keywords, description
      # Validate: name starts with "has_", uses snake_case
      # Append to computed.all_flags
      # Redisplay catalog and re-ask
    CASE "Remove flag":
      # Present list of non-standard flags as options
      # Remove selected flag from computed.all_flags
      # Warn if removing a skill-specific flag (skill will not be routable)
      # Redisplay catalog and re-ask
    CASE "Merge flags":
      # Present pairs of flags that share keywords
      # User selects which to merge
      # Combine keywords lists, use first flag's name
      # Remove the merged-away flag
      # Redisplay catalog and re-ask
```

---

## Phase 5: Generate Rules

### Step 5.1: Map Flag Combinations to Skills

Generate 3VL rules that map flag combinations to skill actions. Rules follow these patterns:

**Pure single intents** -- one skill flag true, competing flags false:

```pseudocode
function generate_pure_rules(skill_flags):
  rules = []
  FOR flag IN skill_flags:
    conditions = {flag.flag_name: "T"}
    # Set competing skill flags to F for disambiguation
    FOR other_flag IN skill_flags:
      if other_flag.flag_name != flag.flag_name:
        # Only add F condition if there is keyword overlap
        if has_overlap(flag, other_flag):
          conditions[other_flag.flag_name] = "F"

    rules.append({
      name:        flag.skill_id + "_only",
      conditions:  conditions,
      action:      "delegate_" + flag.skill_id,
      description: "Route to " + flag.skill_name
    })

  return rules
```

**Compound intents** -- help combined with a skill-specific flag:

```pseudocode
function generate_help_rules(skill_flags):
  rules = []
  FOR flag IN skill_flags:
    rules.append({
      name:        "help_with_" + flag.skill_id,
      conditions:  {"has_help": "T", flag.flag_name: "T"},
      action:      "show_skill_help_" + flag.skill_id,
      description: "Help with " + flag.skill_name
    })
  return rules
```

**Action type compound rules** -- action type flag combined with skill flag:

```pseudocode
function generate_action_compound_rules(skill_flags):
  rules = []
  # Only generate these if skills map to action types
  # E.g., has_init + has_setup -> delegate_setup
  # These are generated when skill keywords overlap with action type keywords
  FOR flag IN skill_flags:
    for action_flag in ["has_init", "has_modify", "has_query", "has_delete"]:
      if shares_keywords(flag, action_flag):
        rules.append({
          name:        action_flag.replace("has_", "") + "_" + flag.skill_id,
          conditions:  {action_flag: "T", flag.flag_name: "T"},
          action:      "delegate_" + flag.skill_id,
          description: action_flag.replace("has_", "").title() + " via " + flag.skill_name
        })
  return rules
```

### Step 5.2: Set Priorities

Assign priorities to rules following the standard ordering:

```pseudocode
function assign_priorities(all_rules):
  # Priority tiers (lower number = higher priority, evaluated first)
  PRIORITY_TIERS = {
    "explicit_help_flag":  100,  # --help/-h always wins
    "help_with_flags":      90,  # Runtime flag docs
    "help_with_*":          80,  # Skill-specific help
    "general_help":         70,  # Catch-all help
    "*_only":               10,  # Pure single-intent skill routing
    "action_compound":      15,  # Action type + skill compound
    "show_menu":             0   # Fallback (always last)
  }

  FOR rule IN all_rules:
    # Match rule name against priority patterns
    if rule.name == "explicit_help_flag":
      rule.priority = 100
    elif rule.name == "help_with_flags":
      rule.priority = 90
    elif rule.name.startswith("help_with_"):
      rule.priority = 80
    elif rule.name == "general_help":
      rule.priority = 70
    elif rule.name.endswith("_only"):
      rule.priority = 10
    else:
      rule.priority = 15

  # Sort by priority descending (highest priority first in rule list)
  all_rules.sort(key=lambda r: r.priority, reverse=True)
```

### Step 5.3: Configure Fallback

Every intent mapping must have a fallback rule that activates when no other rule matches:

```pseudocode
function generate_fallback(plugin_name, skills):
  computed.fallback_rule = {
    name:        "show_menu",
    conditions:  {},  # Empty conditions = always matches
    action:      "show_main_menu",
    description: "No clear intent, show interactive menu"
  }

  computed.fallback_action = {
    type: "user_prompt",
    prompt: {
      question: "What would you like to do with " + plugin_name + "?",
      header: "Menu",
      options: [
        {
          id:          skill_flag.skill_id,
          label:       skill_flag.skill_name,
          description: truncate(skill_flag.description, 80)
        }
        for skill_flag in computed.skill_flags
      ]
    }
  }
```

Store the assembled rule set in `computed.all_rules` (including help rules, skill rules, and
the fallback).

---

## Phase 6: Generate File

### Step 6.1: Load Template

Load the intent-mapping.yaml template from the plugin's template directory:

```pseudocode
LOAD_TEMPLATE():
  template_path = CLAUDE_PLUGIN_ROOT + "/templates/intent-mapping.yaml.template"
  computed.template = Read(template_path)

  if computed.template is empty or null:
    WARN "Template not found at " + template_path
    # Fall back to generating from scratch without template
    computed.use_template = false
  else:
    computed.use_template = true
```

### Step 6.2: Populate Template

Replace template placeholders with computed values:

```pseudocode
POPULATE_TEMPLATE():
  if computed.use_template:
    output = computed.template

    # Replace simple placeholders
    output = replace(output, "{{plugin_name}}", computed.plugin_name)
    output = replace(output, "{{PLUGIN_TITLE}}", computed.plugin_name.upper().replace("-", " "))
    output = replace(output, "{{plugin_description}}", computed.plugin_description or "")

    # Replace iterable sections (Mustache-style)
    # {{#skill_flags}} ... {{/skill_flags}}
    output = expand_section(output, "skill_flags", computed.skill_flags)
    output = expand_section(output, "skill_help_rules", computed.skill_flags)
    output = expand_section(output, "skill_rules", computed.all_rules)
    output = expand_section(output, "skills", computed.skills)
    output = expand_section(output, "skill_help_actions", computed.skill_flags)
    output = expand_section(output, "examples", computed.examples or [])

  else:
    # Generate YAML directly from computed state
    output = generate_yaml_from_state()
```

If not using the template, generate the YAML structure directly:

```pseudocode
function generate_yaml_from_state():
  yaml = "# Intent mapping for " + computed.plugin_name + " gateway\n"
  yaml += "# Generated by bp-author-intent-create\n\n"

  # Emit intent_flags
  yaml += "intent_flags:\n"
  FOR flag IN computed.all_flags:
    yaml += "  " + flag.flag_name + ":\n"
    yaml += "    keywords:\n"
    FOR kw IN flag.keywords:
      yaml += '      - "' + kw + '"\n'
    IF flag.negative_keywords:
      yaml += "    negative_keywords:\n"
      FOR nkw IN flag.negative_keywords:
        yaml += '      - "' + nkw + '"\n'
    yaml += '    description: "' + flag.description + '"\n\n'

  # Emit intent_rules
  yaml += "intent_rules:\n"
  FOR rule IN computed.all_rules:
    yaml += "  - name: " + '"' + rule.name + '"\n'
    yaml += "    conditions:\n"
    FOR flag_name, value IN rule.conditions:
      yaml += "      " + flag_name + ": " + value + "\n"
    yaml += "    action: " + rule.action + "\n"
    yaml += '    description: "' + rule.description + '"\n\n'

  # Emit fallback
  yaml += "  # Default fallback\n"
  yaml += '  - name: "show_menu"\n'
  yaml += "    conditions: {}\n"
  yaml += "    action: show_main_menu\n"
  yaml += '    description: "No clear intent, show interactive menu"\n\n'

  # Emit actions
  yaml += "actions:\n"
  FOR skill_flag IN computed.skill_flags:
    yaml += "  delegate_" + skill_flag.skill_id + ":\n"
    yaml += "    type: invoke_skill\n"
    yaml += '    skill: "' + skill_flag.skill_name + '"\n'
    yaml += "    pass_arguments: true\n\n"

  # Emit show_main_menu action
  yaml += "  show_main_menu:\n"
  yaml += "    type: user_prompt\n"
  yaml += "    prompt:\n"
  yaml += '      question: "What would you like to do with ' + computed.plugin_name + '?"\n'
  yaml += '      header: "Menu"\n'
  yaml += "      options:\n"
  FOR skill_flag IN computed.skill_flags:
    yaml += "        - id: " + skill_flag.skill_id + "\n"
    yaml += '          label: "' + skill_flag.skill_name + '"\n'
    yaml += '          description: "' + truncate(skill_flag.description, 60) + '"\n'

  return yaml
```

### Step 6.3: Write to Output Path

Determine the output path and write the generated file:

```pseudocode
WRITE_OUTPUT():
  output_path = computed.plugin_root + "/commands/" + computed.plugin_name + "/intent-mapping.yaml"
  output_dir = parent_directory(output_path)

  # Check if output directory exists
  if not directory_exists(output_dir):
    WARN "Directory " + output_dir + " does not exist. Creating it."
    # The Write tool will create parent directories

  # Check if file already exists
  if file_exists(output_path):
    # Present overwrite options
    ASK_USER:
      question: "intent-mapping.yaml already exists at this path. What should I do?"
      options:
        - "Overwrite": Replace the existing file
        - "Backup and replace": Rename existing to intent-mapping.yaml.bak, then write new
        - "Write to alternate path": I'll specify a different output path
        - "Cancel": Do not write the file

    HANDLE response:
      "Overwrite":          # Proceed with Write
      "Backup and replace": # Read existing, Write to .bak, then Write new
      "Write to alternate": # Ask for path, use that instead
      "Cancel":             # Display the generated YAML in terminal and exit

  Write(output_path, computed.generated_yaml)
```

### Step 6.4: Display Summary and Offer Validation

After writing, display a summary of what was generated:

```
## Intent Mapping Generated

**File:** {output_path}
**Plugin:** {computed.plugin_name}

### Statistics
- **Flags:** {len(computed.all_flags)} total ({len(STANDARD_FLAGS)} standard + {len(computed.skill_flags)} skill-specific)
- **Rules:** {len(computed.all_rules)} total ({count_help_rules} help + {count_skill_rules} skill + 1 fallback)
- **Skills routed:** {len(computed.skill_flags)}

### Flag Summary
| Flag | Keywords | Negatives |
|------|----------|-----------|
{for flag in computed.all_flags}
| {flag.flag_name} | {len(flag.keywords)} | {len(flag.negative_keywords)} |
{/for}

### Rule Summary
| Rule | Conditions | Action |
|------|------------|--------|
{for rule in computed.all_rules}
| {rule.name} | {format_conditions(rule.conditions)} | {rule.action} |
{/for}
```

Offer validation:

```json
{
  "questions": [{
    "question": "Would you like to validate the generated intent mapping?",
    "header": "Validate",
    "multiSelect": false,
    "options": [
      {
        "label": "Validate now",
        "description": "Check for rule conflicts, unreachable skills, and missing coverage"
      },
      {
        "label": "Done",
        "description": "Intent mapping is complete"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_VALIDATION(response):
  SWITCH response:
    CASE "Validate now":
      GOTO validation subroutine (inline)

      # Check 1: Every skill has at least one rule that routes to it
      routed_skills = set(rule.action.replace("delegate_", "") for rule in computed.all_rules)
      unrouted = [sf.skill_id for sf in computed.skill_flags if sf.skill_id not in routed_skills]
      if unrouted:
        WARN "Skills with no routing rule: " + ", ".join(unrouted)

      # Check 2: No two rules have identical conditions
      condition_sets = [frozenset(rule.conditions.items()) for rule in computed.all_rules]
      duplicates = find_duplicates(condition_sets)
      if duplicates:
        WARN "Duplicate rule conditions found: " + str(duplicates)

      # Check 3: Fallback exists
      has_fallback = any(rule.conditions == {} for rule in computed.all_rules)
      if not has_fallback:
        WARN "No fallback rule with empty conditions"

      # Check 4: Help rules exist for each skill
      help_rules = [r for r in computed.all_rules if r.name.startswith("help_with_")]
      if len(help_rules) < len(computed.skill_flags):
        WARN "Not all skills have help rules"

      if no warnings:
        DISPLAY "Validation passed. All skills are routed, no conflicts detected."

    CASE "Done":
      DISPLAY "Intent mapping generation complete."
      EXIT
```

---

## State Flow

```
Phase 1                    Phase 2                  Phase 3
────────────────────────────────────────────────────────────────
computed.plugin_root    -> computed.skills[]      -> computed.overlap
computed.plugin_name       .raw_keywords             .overlap_pct
computed.skill_files                                  .needs_negative_keywords

Phase 4                    Phase 5                  Phase 6
────────────────────────────────────────────────────────────────
computed.all_flags      -> computed.all_rules     -> computed.generated_yaml
computed.skill_flags       .priority                 output_path
                           computed.fallback_rule    (written file)
                           computed.fallback_action
```

---

## Reference Documentation

- **Keyword Extraction Algorithm:** `patterns/keyword-extraction-algorithm.md` (local to this skill)
- **Flag Generation Rules:** `patterns/flag-generation-rules.md` (local to this skill)
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/workflow-generation.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`

---

## Related Skills

- **Gateway command generation:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-gateway-create/SKILL.md`
- **Plugin discovery and classification:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/SKILL.md`
- **Workflow validation:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/SKILL.md`
- **Prose skill analysis:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`
