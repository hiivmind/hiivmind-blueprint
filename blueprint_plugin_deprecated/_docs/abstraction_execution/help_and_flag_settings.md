# Runtime Flags and Help Display System

## Current State Analysis

### What Kleene Does Well (Help Display)

The Kleene gateway (`/home/nathanielramm/git/kleene-games/kleene/commands/kleene.md`) excels at:

1. **Progressive Disclosure**
   - No action → shows interactive menu first (not a wall of text)
   - Settings commands without values show current state + explanation

2. **Formatted Help Box** (lines 542-614)
   - ASCII box drawing (═══) for visual separation
   - Organized by domain: PLAY, SAVES, EXPORT, GENERATE, ANALYZE, REGISTRY, SETTINGS
   - Examples inline with each command

3. **Self-Documenting Settings**
   ```
   /kleene temperature     → Shows current: 5, scale, and usage
   /kleene temperature 7   → Sets value and confirms
   ```

4. **Keyword-Based Intent Routing** - Simple but limited:
   ```markdown
   ### Temperature Actions
   Keywords: "temperature", "temp", "improv", "adaptation"
   ```

### What hiivmind-blueprint Has

**Strengths:**
- Sophisticated 3VL intent detection with O(1) dynamic routing
- Comprehensive runtime flags (documented in lib/):
  - Display: `--verbose`, `--quiet`, `--terse`, `--debug`, `--no-batch`, `--no-display`
  - Logging: `--log-level=X`, `--log-format=X`, `--log-dir=X`, `--trace`, `--no-log`, `--ci`
- 4-tier configuration hierarchy (runtime → workflow → plugin → lib defaults)

**Gaps:**
- No `--help` or `-h` flag support
- No help command implementation
- Flags documented in `lib/workflow/` but not discoverable by users
- Arguments field in SKILL.md doesn't expose flags
- No current-state display for settings

## Proposed Solution

### 1. Add Help Flag to Intent Detection

In `commands/hiivmind-blueprint/intent-mapping.yaml`:

```yaml
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
      - "?"
      - "explain"
      - "guide"
      - "what can"
      - "show commands"
    description: "Natural language help request"
```

### 2. Create Help Display Template

New template: `templates/help-display.md.template`

Kleene-style formatted box with:
- Section headers by category
- Inline flag documentation
- Examples with explanations
- Current state indicators (where applicable)

### 3. Add Intent Rules for Help

```yaml
intent_rules:
  - name: "explicit_help_flag"
    conditions:
      has_help_flag: T
    action: show_full_help
    priority: 100    # Highest - explicit --help always wins

  - name: "help_with_skill"
    conditions:
      has_help: T
      has_init: T    # or any skill flag
    action: show_skill_help
    priority: 85

  - name: "help_with_flags"
    conditions:
      has_help: T
      has_flags: T   # New flag for "--verbose", "--quiet" etc
    action: show_flag_help
    priority: 80
```

### 4. Document Flags in Gateway Command

Update `commands/hiivmind-blueprint.md` to include:

```markdown
## Runtime Flags

| Flag | Effect |
|------|--------|
| `--verbose`, `-v` | Show all node details and condition evaluations |
| `--quiet`, `-q` | Only user prompts and final result |
| `--terse` | Batch summaries only |
| `--debug` | Full state dumps |
| `--log-level=X` | Set logging level (error/warn/info/debug/trace) |
| `--no-log` | Disable logging |

## Help

| Command | Description |
|---------|-------------|
| `/hiivmind-blueprint --help` | Show full command reference |
| `/hiivmind-blueprint help init` | Help for init skill |
| `/hiivmind-blueprint help flags` | Explain runtime flags |
```

### 5. Skill-Specific Help (Optional Enhancement)

Each skill could expose a `help:` block in SKILL.md frontmatter:

```yaml
---
name: hiivmind-blueprint-init
description: Initialize blueprint project structure
help:
  summary: Prepares a plugin for deterministic workflow patterns
  usage: /hiivmind-blueprint init [target_plugin_path]
  flags:
    - "--verbose: Show detailed progress"
    - "--dry-run: Preview changes without writing"
  examples:
    - "/hiivmind-blueprint init ../my-plugin"
    - "/hiivmind-blueprint init --verbose"
---
```

## Implementation Steps

### Step 1: Add Help Flags to Intent Mapping
**File**: `commands/hiivmind-blueprint/intent-mapping.yaml`
- Add `has_help_flag` for explicit `--help`, `-h`
- Add `has_flags_help` for "flags", "options", "arguments"
- Add intent rules: `explicit_help_flag` (priority 100), `help_with_skill` (85), `help_flags` (80)

### Step 2: Add Help Nodes to Workflow
**File**: `commands/hiivmind-blueprint/workflow.yaml`
- Add `show_full_help` node - renders ASCII box help
- Add `show_skill_help` node - skill-specific help
- Add `show_flag_help` node - explains runtime flags

### Step 3: Create Help Display Template
**File**: `templates/help-display.md.template` (NEW)
- Kleene-style ASCII box with ═══ borders
- Sections: SKILLS, FLAGS, EXAMPLES
- Placeholder interpolation for generated plugins

### Step 4: Document in Gateway Command
**File**: `commands/hiivmind-blueprint.md`
- Add "Runtime Flags" section with table
- Add "Help" section with usage examples

### Step 5: Update Gateway Template for Auto-Generation
**File**: `templates/gateway-command.md.template`
- Include help display generation
- Reference help-display.md.template

### Step 6: Update Intent Mapping Template
**File**: `templates/intent-mapping.yaml.template`
- Include standard help flags pattern
- Document as reusable pattern

## Files Summary

| File | Action |
|------|--------|
| `commands/hiivmind-blueprint/intent-mapping.yaml` | Modify |
| `commands/hiivmind-blueprint/workflow.yaml` | Modify |
| `commands/hiivmind-blueprint.md` | Modify |
| `templates/help-display.md.template` | Create |
| `templates/gateway-command.md.template` | Modify |
| `templates/intent-mapping.yaml.template` | Modify |

## Design Decisions (Confirmed)

1. **Help format**: Kleene-style ASCII box (═══) with visual separators, organized by domain, inline examples

2. **Flag persistence**: Per-invocation only - `/hiivmind-blueprint --verbose analyze` resets for next command

3. **Auto-generated help**: Yes - when hiivmind-blueprint generates workflows for other plugins, it auto-generates help content from intent-mapping and skill frontmatter

## Verification

1. Test `--help` flag detection:
   ```
   /hiivmind-blueprint --help
   /hiivmind-blueprint -h
   /hiivmind-blueprint help
   ```

2. Test skill-specific help:
   ```
   /hiivmind-blueprint help init
   /hiivmind-blueprint --help convert
   ```

3. Test flag documentation:
   ```
   /hiivmind-blueprint help flags
   /hiivmind-blueprint --verbose analyze skill.md
   ```

4. Test disambiguation when help + skill:
   ```
   /hiivmind-blueprint help me initialize
   ```
