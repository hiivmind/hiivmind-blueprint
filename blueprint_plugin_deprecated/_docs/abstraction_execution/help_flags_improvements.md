# Plan: Add Configuration Help Generation to hiivmind-blueprint Gateway

## Problem

When hiivmind-blueprint generates gateway commands for plugins, it should automatically include configuration topic help. Currently:
- ✅ Full help (`--help`) is generated
- ✅ Skill-specific help (`help <skill>`) is generated
- ✅ Flags help (`help flags`) exists but combines all flags
- ❌ Separate config topic help (`help logging`, `help display`, `help prompts`) is **not** generated

Users of any generated gateway should be able to type:
- `help logging` → see logging levels, flags, and priority hierarchy
- `help display` → see verbosity levels and batch mode options
- `help prompts` → see prompt mode options and match strategies
- `help flags` → already exists (quick reference of all runtime flags)

## Current State

The `intent-mapping.yaml.template` already has:
- `has_flags_help` intent flag (keywords: "flags", "options", "--verbose", etc.)
- `show_flag_help` action (combined display + logging flags in one display)

The goal is to add **three more specific topic helps** that provide deeper detail.

## Solution

Add three new configuration help topics (logging, display, prompts) to the gateway generation templates.

---

## Files to Modify

| File | Changes |
|------|---------|
| `templates/intent-mapping.yaml.template` | Add 3 config flags, 3 config rules, 3 config help actions |
| `templates/gateway-command.md.template` | Add Configuration Help section to documentation |

Note: `workflow.yaml.template` is for generating individual skill workflows, not gateway workflows. The gateway workflow is generated from `intent-mapping.yaml.template` which contains the action definitions.

---

## Implementation Details

### 1. Update `templates/intent-mapping.yaml.template`

**Add config intent flags** (after existing `has_flags_help` flag, around line 52):

```yaml
  # Configuration topic flags (for detailed topic-specific help)
  has_logging_help:
    keywords:
      - "logging"
      - "log"
      - "logs"
      - "log level"
      - "log-level"
      - "log-format"
      - "log-dir"
    description: "Logging configuration topic"

  has_display_help:
    keywords:
      - "display"
      - "verbosity"
      - "batch"
      - "batch mode"
      - "show controls"
    description: "Display configuration topic"

  has_prompts_help:
    keywords:
      - "prompts"
      - "prompt"
      - "interactive"
      - "tabular"
      - "match strategy"
    description: "Prompts configuration topic"
```

**Add config intent rules** (after `help_with_flags` rule around line 135, priority 90 - above skill help):

```yaml
  # Configuration topic help (priority 90 - above skill help)
  - name: "help_with_logging"
    conditions:
      has_logging_help: T
    action: show_logging_help
    priority: 90
    description: "Help for logging configuration"

  - name: "help_with_display"
    conditions:
      has_display_help: T
    action: show_display_help
    priority: 90
    description: "Help for display configuration"

  - name: "help_with_prompts"
    conditions:
      has_prompts_help: T
    action: show_prompts_help
    priority: 90
    description: "Help for prompts configuration"
```

**Add config help actions** (after `show_flag_help` action around line 313):

```yaml
  show_logging_help:
    type: display
    content: |
      # ... logging help content (see Help Content below)

  show_display_help:
    type: display
    content: |
      # ... display help content

  show_prompts_help:
    type: display
    content: |
      # ... prompts help content
```

**Update show_full_help action** to include CONFIGURATION section (around line 260):

```yaml
      CONFIGURATION
        /{{plugin_name}} help logging    Logging levels & configuration
        /{{plugin_name}} help display    Verbosity & batch mode
        /{{plugin_name}} help prompts    Prompt modes & strategies
        /{{plugin_name}} help flags      All runtime flags
```

### 2. Update `templates/gateway-command.md.template`

**Add Configuration Help section** (after Help Commands table around line 82):

```markdown
### Configuration Help

| Command | Description |
|---------|-------------|
| `/{{plugin_name}} help logging` | Logging levels, flags, and priority hierarchy |
| `/{{plugin_name}} help display` | Display verbosity and batch mode options |
| `/{{plugin_name}} help prompts` | Prompt modes and match strategies |
| `/{{plugin_name}} help flags` | Quick reference for all runtime flags |
```

---

## Help Content (to embed in templates)

### Logging Help
```
═══════════════════════════════════════════════════════════
LOGGING CONFIGURATION
═══════════════════════════════════════════════════════════

LEVELS
  error    Errors only
  warn     Errors + warnings
  info     Normal operation (default)
  debug    Development details
  trace    Full system debugging

FLAGS
  --verbose, -v      Set level to debug
  --quiet, -q        Set level to error
  --trace            Set level to trace
  --log-level=X      Set exact level
  --log-format=X     Output format (yaml|json|markdown)
  --log-dir=X        Log directory
  --no-log           Disable logging
  --ci               GitHub CI annotations

PRIORITY (highest to lowest)
  1. Runtime flags
  2. Workflow initial_state.logging
  3. Plugin .hiivmind/blueprint/logging.yaml
  4. Framework defaults

═══════════════════════════════════════════════════════════
```

### Display Help
```
═══════════════════════════════════════════════════════════
DISPLAY CONFIGURATION
═══════════════════════════════════════════════════════════

VERBOSITY LEVELS
  silent    User prompts + final result only
  terse     Batch summaries + prompts + result
  normal    Node transitions + batched internals (default)
  verbose   All details, condition evaluations
  debug     Full state dumps, diagnostics

FLAGS
  --verbose, -v      Set to verbose
  --quiet, -q        Set to silent
  --terse            Set to terse
  --debug            Set to debug
  --no-batch         Disable node batching
  --no-display       Disable all display output

BATCH MODE
  Collapses non-interactive nodes into summaries
  threshold: 3 (min nodes to batch)
  expand_on_error: true (show details on failure)

═══════════════════════════════════════════════════════════
```

### Prompts Help
```
═══════════════════════════════════════════════════════════
PROMPTS CONFIGURATION
═══════════════════════════════════════════════════════════

MODES
  interactive    Show options via AskUserQuestion (default)
  tabular        Execute in table format for batch operations

MATCH STRATEGIES
  exact          Option must match input exactly
  prefix         Option prefix matches input
  fuzzy          Fuzzy string matching

OTHER HANDLERS
  prompt         Re-prompt user on unrecognized input
  route          Route to specified node
  fail           Fail workflow on unrecognized input

CONFIGURATION
  Set in workflow initial_state.prompts:

  prompts:
    mode: interactive
    match_strategy: prefix
    on_no_match: prompt

═══════════════════════════════════════════════════════════
```

### Flags Quick Reference
```
═══════════════════════════════════════════════════════════
RUNTIME FLAGS QUICK REFERENCE
═══════════════════════════════════════════════════════════

VERBOSITY
  --verbose, -v      More output (logging=debug, display=verbose)
  --quiet, -q        Less output (logging=error, display=silent)
  --terse            Minimal display output
  --debug            Maximum display details
  --trace            Maximum logging details

LOGGING
  --log-level=X      Set log level (error|warn|info|debug|trace)
  --log-format=X     Set format (yaml|json|markdown)
  --log-dir=X        Set log directory
  --no-log           Disable logging entirely
  --ci               Enable GitHub CI annotations

DISPLAY
  --no-batch         Disable node batching
  --no-display       Disable display output

MORE INFO
  help logging       Full logging reference
  help display       Full display reference
  help prompts       Prompt mode reference

═══════════════════════════════════════════════════════════
```

---

## Verification

1. **Validate template syntax** - Check that the modified templates have valid YAML structure

2. **Regenerate hiivmind-nexus-demo gateway** using `/hiivmind-blueprint gateway` to test the new templates:
   - Target: `~/git/hiivmind/hiivmind-nexus-demo`
   - This will overwrite the manual changes I made earlier

3. **Test the generated config help commands:**
   - `/hiivmind-nexus-demo help logging` → shows logging reference
   - `/hiivmind-nexus-demo help display` → shows display reference
   - `/hiivmind-nexus-demo help prompts` → shows prompts reference
   - `/hiivmind-nexus-demo help flags` → shows flags quick reference (already existed)

4. **Test keyword variations:**
   - `/hiivmind-nexus-demo help log` → logging help
   - `/hiivmind-nexus-demo help verbosity` → display help
   - `/hiivmind-nexus-demo help interactive` → prompts help

5. **Test full help updated:**
   - `/hiivmind-nexus-demo --help` → includes CONFIGURATION section

6. **Ensure no conflicts with existing skills** (3VL handles naturally)

---

## Notes

The manual changes I made to hiivmind-nexus-demo will be replaced when we regenerate the gateway from the updated templates. This is the correct approach - the templates are the source of truth.
