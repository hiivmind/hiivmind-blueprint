# Prompts Config Loader Protocol

This document provides a user-facing reference for prompts configuration resolution. The authoritative execution semantics are defined in YAML.

> **Authoritative Source:** `hiivmind-blueprint-lib/nodes/core/user-prompt.yaml`

---

## Overview

Prompts configuration controls how `user_prompt` nodes present questions and collect responses:

```yaml
# workflow.yaml
initial_state:
  prompts:
    mode: "tabular"                # Execution mode
    tabular:
      match_strategy: "prefix"     # How to match user input
      other_handler: "prompt"      # What to do on no match
```

---

## Execution Modes

| Mode | Tool Required | Behavior |
|------|---------------|----------|
| `interactive` | AskUserQuestion | Use Claude Code's structured prompt tool (default) |
| `tabular` | None | Render markdown table, parse user text response |

### Interactive Mode (Default)

Uses the `AskUserQuestion` tool for structured prompts:
- Chip-style option display
- Single-click selection
- Automatic response parsing

### Tabular Mode

Renders options as a markdown table:
- Option ID, Label, Description columns
- User types their choice in chat
- Engine matches input to option IDs

---

## Configuration Options

```yaml
prompts:
  mode: "interactive"              # "interactive" | "tabular"

  tabular:                         # Settings for tabular mode
    match_strategy: "prefix"       # "exact" | "prefix" | "fuzzy"
    other_handler: "prompt"        # "prompt" | "route" | "fail"
    fuzzy_threshold: 0.7           # 0.0-1.0 (for fuzzy strategy)
    case_sensitive: false          # Case sensitivity for matching
    show_option_ids: true          # Show Option ID column
    instruction_text: "**Please type the Option ID of your choice.**"
```

---

## Match Strategies

| Strategy | Behavior | Example |
|----------|----------|---------|
| `exact` | User must type exact option ID | "markdown" matches "markdown" only |
| `prefix` | User can type ID prefix | "mark" matches "markdown" |
| `fuzzy` | Similarity scoring | "markdwon" matches "markdown" (88% similarity) |

### Prefix Matching (Default)

```
User input: "mark"
Options: ["markdown", "json", "yaml"]

1. Lowercase both input and option IDs
2. Check if any option ID starts with input
3. Match: "markdown" starts with "mark" → matched
```

### Exact Matching

```
User input: "mark"
Options: ["markdown", "json", "yaml"]

1. Lowercase both input and option IDs
2. Check for exact match
3. No match: "mark" ≠ "markdown"
```

### Fuzzy Matching

```
User input: "markdwon"
Options: ["markdown", "json", "yaml"]

1. Calculate Levenshtein similarity for each option
2. "markdwon" vs "markdown" = 88% similarity
3. 88% > 70% threshold → matched
```

---

## Other Handlers

When user input doesn't match any option ID:

| Handler | Behavior |
|---------|----------|
| `prompt` | Re-display table, ask user to choose again |
| `route` | Route to `on_response.other` handler |
| `fail` | End workflow with error |

### Re-prompt Behavior

```markdown
I didn't recognize "xyz" as a valid option.

## Which format do you prefer?

| Option ID | Label | Description |
|-----------|-------|-------------|
| markdown | Markdown | Portable, human-readable |
| json | JSON | Machine-parseable |

**Please type the Option ID of your choice.**
```

### Route to Other Handler

Requires `on_response.other` in the node definition:

```yaml
select_format:
  type: user_prompt
  prompt:
    question: "Which format?"
    header: "Format"
    options: [...]
  on_response:
    markdown:
      next_node: generate_markdown
    json:
      next_node: generate_json
    other:                           # Required when other_handler: "route"
      consequence:
        - type: set_state
          field: custom_format
          value: "${user_responses.select_format.text}"
      next_node: handle_custom_format
```

---

## Tabular Mode Table Format

When a user_prompt node executes in tabular mode:

```markdown
## Which format do you prefer?

| Option ID | Label | Description |
|-----------|-------|-------------|
| markdown | Markdown | Portable, human-readable |
| json | JSON | Machine-parseable |
| yaml | YAML | Structured, readable |

**Please type the Option ID of your choice.**
```

---

## State Storage

User responses are stored differently based on match result:

### Matched Option

```yaml
state.user_responses.{node_id}:
  handler_id: "markdown"       # The matched option ID
  raw:
    text: "mark"               # Original user input
    matched_by: "prefix"       # How it was matched
```

### No Match (route to other)

```yaml
state.user_responses.{node_id}:
  handler_id: "other"          # Special handler
  text: "custom format"        # User's custom input
```

---

## Multi-Turn Conversation

Tabular mode is conversational: the workflow pauses after displaying the table.

```
Turn 1:
  → Workflow executes to user_prompt node
  → Render markdown table
  → Set state.awaiting_input = { node_id: "select_format", type: "tabular" }
  → Pause workflow

Turn 2:
  → User responds with text
  → Engine detects awaiting_input state
  → Match user input to options
  → Route based on match result
  → Clear awaiting_input
  → Continue workflow
```

---

## Backward Compatibility

- If `prompts` block omitted → default to `mode: "interactive"`
- If `mode: "tabular"` but `tabular` block omitted → use framework defaults
- Existing workflows continue to work unchanged

---

## Defaults

| Setting | Default |
|---------|---------|
| `mode` | `"interactive"` |
| `match_strategy` | `"prefix"` |
| `other_handler` | `"prompt"` |
| `fuzzy_threshold` | `0.7` |
| `case_sensitive` | `false` |
| `show_option_ids` | `true` |

---

## Validation

The validate skill checks:

1. `mode` is valid enum value
2. `match_strategy` is valid enum value
3. `other_handler` is valid enum value
4. If `other_handler: "route"`, `on_response.other` exists in all user_prompt nodes
5. `fuzzy_threshold` is between 0.0 and 1.0

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine overview
- **Node Types:** `hiivmind-blueprint-lib/nodes/core/user-prompt.yaml` - Authoritative execution
- **Schema:** `hiivmind-blueprint-lib/schema/prompts-config.json` - JSON Schema
- **Examples:** `references/prompts-config-examples.md` - Usage examples
