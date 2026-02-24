> **Used by:** `SKILL.md` Phase 4
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`

# Flag Generation Rules

Naming conventions, standard flag definitions, overlap resolution strategies, and merging rules
for generating `intent_flags` in intent-mapping.yaml.

---

## Naming Conventions

All intent flags follow strict naming rules to ensure consistency across plugins:

| Rule | Convention | Example |
|------|-----------|---------|
| Prefix | Always `has_` | `has_setup`, `has_convert` |
| Case | `snake_case` after prefix | `has_flags_help`, `has_logging_help` |
| Length | 5-25 characters total | `has_init` (min), `has_display_help` (typical) |
| Uniqueness | Must be unique within the intent_flags block | No duplicates allowed |
| Descriptive | Should clearly indicate what the flag detects | `has_query` not `has_q` |

**Deriving flag names from skill names:**

```pseudocode
function derive_flag_name(skill_name, plugin_name):
  # Strip plugin name prefix if present
  short = skill_name.replace(plugin_name + "-", "")

  # Convert hyphens to underscores
  short = short.replace("-", "_")

  # Truncate to keep total flag name under 25 chars
  if len("has_" + short) > 25:
    short = short[:21]  # Leave room for "has_" prefix

  return "has_" + short
```

**Examples:**

| Skill Name | Plugin Name | Flag Name |
|------------|-------------|-----------|
| `hiivmind-blueprint-author-setup` | `hiivmind-blueprint-author` | `has_setup` |
| `hiivmind-blueprint-author-convert` | `hiivmind-blueprint-author` | `has_convert` |
| `hiivmind-pulse-gh-operations` | `hiivmind-pulse-gh` | `has_operations` |

---

## Standard Flag Set

Every gateway intent mapping should include these standard flags. They handle universal user
intents that are common across all plugins.

### Help Flags

These three flags handle all help-related intents:

```yaml
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
    - "?"
    - "explain"
    - "guide"
    - "what can"
    - "show commands"
  description: "User needs guidance or documentation"

has_flags_help:
  keywords:
    - "flags"
    - "options"
    - "arguments"
    - "--verbose"
    - "--quiet"
    - "--terse"
    - "--debug"
    - "--log-level"
    - "runtime flags"
    - "what flags"
  description: "User wants to understand runtime flags"
```

### Optional Help Topic Flags

Include these when the plugin has configurable logging, display, or prompts:

```yaml
has_logging_help:
  keywords: ["logging", "log", "logs", "log level", "log-level", "log-format", "log-dir"]
  description: "Logging configuration topic"

has_display_help:
  keywords: ["display", "verbosity", "batch", "batch mode", "show controls"]
  description: "Display configuration topic"

has_prompts_help:
  keywords: ["prompts", "prompt", "interactive", "tabular", "match strategy"]
  description: "Prompts configuration topic"
```

**When to include optional help flags:**

| Condition | Include |
|-----------|---------|
| Plugin has `initial_state.logging` in any workflow | `has_logging_help` |
| Plugin has `initial_state.output` in any workflow | `has_display_help` |
| Plugin has `initial_state.prompts` in any workflow | `has_prompts_help` |
| Plugin is simple (no configurable subsystems) | None of the optional flags |

### Action Type Flags

These flags detect the general category of action the user wants to perform:

```yaml
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

**When to include action type flags:**

- Include all four if the plugin has skills that map to create/modify/query/delete operations
- Omit `has_delete` if no skill performs destructive operations
- Omit `has_modify` if no skill modifies existing artifacts

---

## Overlap Resolution Strategy

When two or more flags share keywords, 3VL negative keywords disambiguate them. The resolution
follows a strict priority ordering.

### Resolution Algorithm

```pseudocode
function resolve_overlap(flag_a, flag_b, shared_keywords):
  # Step 1: Determine which flag "owns" each shared keyword
  for kw in shared_keywords:
    # Priority: skill-specific > action type > standard
    owner = determine_owner(kw, flag_a, flag_b)
    loser = flag_b if owner == flag_a else flag_a

    # Step 2: Add distinguishing keywords as negatives to the loser
    owner_unique = get_unique_keywords(owner)
    loser.negative_keywords.extend(owner_unique[:3])

  # Step 3: If still ambiguous, use T/F conditions in rules
  # (the rule with more specific conditions wins)
```

### Ownership Priority

| Flag Category | Priority | Rationale |
|---------------|----------|-----------|
| Skill-specific (`has_setup`, `has_convert`) | Highest | Direct skill routing |
| Action type (`has_init`, `has_modify`) | Medium | General action classification |
| Standard help (`has_help`, `has_flags_help`) | Lower | Universal intents |
| Help topics (`has_logging_help`) | Lowest | Specific documentation topics |

### Example Resolution

Given these flags with overlap on "create":

```
has_init:    keywords: ["create", "new", "init", "setup"]
has_setup:   keywords: ["setup", "create", "initialize", "infrastructure"]
```

Resolution:
1. "create" appears in both `has_init` and `has_setup`
2. `has_setup` is skill-specific (higher priority than action type `has_init`)
3. Add `has_init` unique keywords as negatives to `has_setup`: `negative_keywords: ["new"]`
4. Add `has_setup` unique keywords as negatives to `has_init`: `negative_keywords: ["infrastructure"]`
5. In rules, the `has_setup: T, has_init: F` condition routes to setup-specific handling

---

## Flag Merging Rules

When two proposed flags are too similar, they should be merged rather than kept separate.

### Merge Criteria

Two flags should be merged when:

```pseudocode
function should_merge(flag_a, flag_b):
  shared = set(flag_a.keywords) & set(flag_b.keywords)
  total = set(flag_a.keywords) | set(flag_b.keywords)

  overlap_ratio = len(shared) / len(total)

  # Merge if >60% keyword overlap
  if overlap_ratio > 0.6:
    return true

  # Merge if both route to the same skill
  if flag_a.target_skill == flag_b.target_skill:
    return true

  return false
```

### Merge Procedure

```pseudocode
function merge_flags(flag_a, flag_b):
  merged = {
    # Use the more specific flag name
    flag_name: flag_a.flag_name if is_skill_specific(flag_a) else flag_b.flag_name,

    # Union of all keywords
    keywords: deduplicate(flag_a.keywords + flag_b.keywords),

    # Union of negative keywords
    negative_keywords: deduplicate(flag_a.negative_keywords + flag_b.negative_keywords),

    # Concatenate descriptions
    description: flag_a.description + " / " + flag_b.description
  }

  # Remove the merged-away flag from the catalog
  return merged
```

### When NOT to Merge

- Flags from different categories (never merge a standard flag with a skill-specific flag)
- Flags that route to different skills (overlap should be resolved with negatives instead)
- Help flags (always keep `has_help`, `has_help_flag`, and `has_flags_help` separate)

---

## Flag Count Guidelines

| Plugin Size | Expected Flags | Breakdown |
|-------------|---------------|-----------|
| Small (2-3 skills) | 7-10 | 3 help + 2-4 action + 2-3 skill |
| Medium (4-7 skills) | 10-16 | 3-6 help + 4 action + 4-7 skill |
| Large (8+ skills) | 15-25 | 6 help + 4 action + 8+ skill |

**Warning thresholds:**

- Fewer than 5 flags total: may be too coarse, users will hit fallback often
- More than 25 flags total: may be too fine-grained, consider merging similar skills
- More negative keywords than positive keywords on any flag: rethink the flag design

---

## Related Documentation

- **Keyword Extraction Algorithm:** `patterns/keyword-extraction-algorithm.md`
- **Intent Mapping Template:** `${CLAUDE_PLUGIN_ROOT}/templates/intent-mapping.yaml.template`
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
