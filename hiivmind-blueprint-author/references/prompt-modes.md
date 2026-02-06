# Prompt Modes Reference

Complete reference for the 5 prompt interface modes in hiivmind-blueprint-lib v2.4.0+.

> **Configuration Examples:** `references/prompts-config-examples.md`
> **Node Definition:** `hiivmind/hiivmind-blueprint-lib@v3.0.0/nodes/workflow_nodes.yaml`

---

## Overview

Prompt modes control how `user_prompt` nodes interact with users across different interfaces:

| Mode | Interface | Description |
|------|-----------|-------------|
| `interactive` | Claude Code CLI | AskUserQuestion tool with structured options |
| `tabular` | Text-based | Markdown table with text input matching |
| `forms` | Web UI | Rich clickable forms/buttons |
| `structured` | API | JSON schema for programmatic access |
| `autonomous` | Embedded agent | LLM evaluates without user interaction |

---

## Mode Configuration

Configure modes at the workflow level in `initial_state.prompts`:

```yaml
initial_state:
  prompts:
    interface: "auto"  # auto-detect or explicit
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
```

---

## interactive (Default)

Uses Claude Code's `AskUserQuestion` tool for structured chip-style selection.

### When to Use

- Running in Claude Code CLI
- Want structured option selection
- Need multi-select capability
- Prefer automatic response parsing

### Configuration

```yaml
initial_state:
  prompts:
    mode: "interactive"  # or omit (default)
```

### User Experience

Presents structured options as selectable chips. User clicks or types number.

---

## tabular

Renders options as a markdown table, parses user text response.

### When to Use

- Running in environments without AskUserQuestion tool
- Want text-based interaction
- Need flexible input matching (typo tolerance)
- Want to support custom "other" responses

### Configuration

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"    # exact, prefix, fuzzy
      other_handler: "prompt"     # prompt, route, fail
      fuzzy_threshold: 0.7        # for fuzzy strategy
      case_sensitive: false       # default: false
      show_option_ids: true       # default: true
      instruction_text: "Type your choice:"
```

### Match Strategies

| Strategy | Behavior | Example |
|----------|----------|---------|
| `exact` | Must match option ID exactly | "markdown" → "markdown" |
| `prefix` | Match by prefix | "mark" → "markdown" |
| `fuzzy` | Tolerate typos | "markdwon" → "markdown" |

### Other Handlers

| Handler | Behavior |
|---------|----------|
| `prompt` | Re-display table, ask again |
| `route` | Route to `on_response.other` |
| `fail` | Workflow fails with error |

### User Experience

```markdown
## Which format do you prefer?

| Option ID | Label | Description |
|-----------|-------|-------------|
| markdown | Markdown | Portable, human-readable |
| json | JSON | Machine-parseable |

**Type your choice:**
```

---

## forms

Rich HTML-like forms for web interfaces.

### When to Use

- Running on Claude.ai web interface
- Want clickable buttons/cards
- Need rich visual presentation

### Configuration

```yaml
initial_state:
  prompts:
    modes:
      web: "forms"
```

### User Experience

Options rendered as clickable cards/buttons in web UI. Falls back to tabular for text-only interfaces.

---

## structured

JSON schema for API/programmatic access.

### When to Use

- Building API integrations
- Programmatic workflow execution
- Need machine-readable prompt format

### Configuration

```yaml
initial_state:
  prompts:
    modes:
      api: "structured"
```

### Response Format

Node returns structured prompt data:

```json
{
  "awaiting_input": true,
  "prompt": {
    "question": "Select output format",
    "options": [
      { "id": "json", "label": "JSON", "description": "..." }
    ],
    "response_format": {
      "selected_id": "string (required)"
    }
  }
}
```

API consumer responds with:

```yaml
state.api_response:
  node_id: "select_format"
  selected_id: "json"
```

---

## autonomous

LLM evaluates options without user interaction.

### When to Use

- Embedded agents that cannot prompt users
- Automated workflow execution
- Agent-to-agent communication

### Configuration

```yaml
initial_state:
  prompts:
    modes:
      agent: "autonomous"
    autonomous:
      strategy: "best_match"
      context_fields:
        - computed.intent_flags
        - arguments
      fallback: "other"
      confidence_threshold: 0.7
      explain_selection: true
```

### Strategies

| Strategy | Behavior |
|----------|----------|
| `best_match` | LLM evaluates semantic match |
| `first_valid` | First option passing validation |
| `weighted` | Use option weights if available |

### Confidence Threshold

If no option meets the threshold, routes to `fallback` handler (default: `other`).

### User Experience

No user interaction. LLM selects based on context. Selection logged if `explain_selection: true`.

---

## Multi-Modal Configuration

Configure different modes for different interfaces:

```yaml
initial_state:
  prompts:
    interface: "auto"  # Auto-detect interface
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.6
```

### Interface Detection

| Environment | Detected Interface |
|-------------|-------------------|
| Claude Code CLI | `claude_code` |
| Claude.ai web | `web` |
| API request | `api` |
| Task subagent | `agent` |

---

## Quick Reference

### Mode Selection Guide

| Your Use Case | Recommended Mode |
|---------------|------------------|
| Claude Code CLI | `interactive` (default) |
| Fallback for non-Claude | `tabular` |
| Web application | `forms` |
| API integration | `structured` |
| Autonomous agents | `autonomous` |

### Configuration Patterns

**Simple (Claude Code only):**
```yaml
# No configuration needed - defaults to interactive
```

**Text fallback:**
```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
```

**Multi-interface:**
```yaml
initial_state:
  prompts:
    interface: "auto"
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
```

---

## Prose Pattern Mapping

| Prose Pattern | Suggested Mode | Configuration |
|---------------|----------------|---------------|
| "Ask user to select..." | interactive | (default) |
| "Present table and wait for text..." | tabular | `match_strategy: prefix` |
| "Allow user to type choice or custom" | tabular | `other_handler: route` |
| "Exact match required" | tabular | `match_strategy: exact` |
| "Tolerate typos" | tabular | `match_strategy: fuzzy` |
| "Web form with buttons" | forms | `modes.web: forms` |
| "API endpoint" | structured | `modes.api: structured` |
| "Agent decides automatically" | autonomous | `modes.agent: autonomous` |

---

## Fetching Examples

```bash
# Prompts config schema
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/schema/config/prompts-config.json?ref=v3.0.0 \
  --jq '.content' | base64 -d

# User prompt node definition
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/nodes/workflow_nodes.yaml?ref=v3.0.0 \
  --jq '.content' | base64 -d | yq '.nodes.user_prompt'

# User prompt examples
gh api repos/hiivmind/hiivmind-blueprint-lib/contents/examples/nodes.yaml?ref=v3.0.0 \
  --jq '.content' | base64 -d | yq '.examples.user_prompt'
```

---

## Related Documentation

- **Configuration Examples:** `references/prompts-config-examples.md`
- **Node Features:** `references/node-features.md`
- **Node Mapping Pattern:** `lib/patterns/node-mapping.md`
