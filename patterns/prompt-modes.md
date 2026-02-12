# Prompt Modes Pattern

Configure multi-modal prompt interfaces for user_prompt nodes.

---

## When to Use

Configure prompt modes when:
- Workflow runs in environments beyond Claude Code CLI
- Need text-based fallback for non-Claude contexts
- Building API integrations
- Creating autonomous agent workflows

---

## Mode Selection

| Interface | Default Mode | Alternative |
|-----------|--------------|-------------|
| Claude Code CLI | interactive | tabular |
| Web (Claude.ai) | forms | interactive |
| API | structured | - |
| Embedded agent | autonomous | - |

---

## Configuration Patterns

### Default (Claude Code Only)

No configuration needed - interactive mode is default:

```yaml
initial_state:
  phase: "start"
  # No prompts config = interactive mode
```

### Text-Based Fallback

For environments without AskUserQuestion tool:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"   # exact, prefix, fuzzy
      other_handler: "prompt"    # prompt, route, fail
```

### Multi-Interface Support

For workflows that run across different interfaces:

```yaml
initial_state:
  prompts:
    interface: "auto"  # auto-detect interface
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
      context_fields:
        - computed.intent_flags
        - arguments
      confidence_threshold: 0.7
      fallback: "other"
```

### API-Only

For programmatic access:

```yaml
initial_state:
  prompts:
    interface: "api"
    modes:
      api: "structured"
```

### Agent-Only

For autonomous workflows:

```yaml
initial_state:
  prompts:
    interface: "agent"
    modes:
      agent: "autonomous"
    autonomous:
      strategy: "best_match"
      context_fields:
        - computed.intent_flags
        - arguments
      confidence_threshold: 0.6
      explain_selection: true
```

---

## Tabular Mode Details

### Match Strategies

| Strategy | Behavior | Use When |
|----------|----------|----------|
| `exact` | Must match ID exactly | Strict input validation |
| `prefix` | Match by prefix | User convenience |
| `fuzzy` | Tolerate typos | User-friendly input |

### Other Handlers

| Handler | Behavior | Requires |
|---------|----------|----------|
| `prompt` | Re-display and ask again | Nothing |
| `route` | Route to `on_response.other` | `on_response.other` defined |
| `fail` | Workflow fails | Nothing |

### Tabular Display

```markdown
## Which format do you prefer?

| Option ID | Label | Description |
|-----------|-------|-------------|
| markdown | Markdown | Portable, human-readable |
| json | JSON | Machine-parseable |

**Please type the Option ID of your choice.**
```

---

## Autonomous Mode Details

### Strategies

| Strategy | Behavior |
|----------|----------|
| `best_match` | LLM evaluates semantic match |
| `first_valid` | First option passing validation |
| `weighted` | Use option weights |

### Context Fields

Specify state paths for LLM to evaluate:

```yaml
autonomous:
  context_fields:
    - computed.intent_flags
    - arguments
    - computed.context
```

### Confidence Threshold

If no option meets threshold, routes to fallback:

```yaml
autonomous:
  confidence_threshold: 0.7
  fallback: "other"  # routes to on_response.other
```

---

## Prose Pattern Mapping

| Prose in Skill | Recommended Config |
|----------------|-------------------|
| "Ask user to select..." | interactive (default) |
| "Present options as text table" | `mode: tabular` |
| "Allow typing prefix to select" | `match_strategy: prefix` |
| "Accept custom user input" | `other_handler: route` |
| "Must match exactly" | `match_strategy: exact` |
| "Tolerate typos" | `match_strategy: fuzzy` |
| "For web interface" | `modes.web: forms` |
| "For API access" | `modes.api: structured` |
| "Agent decides automatically" | `modes.agent: autonomous` |
| "Multi-interface workflow" | Full modes config |

---

## Node Definition Unchanged

The user_prompt node definition is the same regardless of mode:

```yaml
ask_format:
  type: user_prompt
  prompt:
    question: "Which format do you prefer?"
    header: "Format"
    options:
      - id: markdown
        label: "Markdown"
        description: "Portable, human-readable"
      - id: json
        label: "JSON"
        description: "Machine-parseable"
  on_response:
    markdown:
      next_node: generate_markdown
    json:
      next_node: generate_json
```

The mode configuration in `initial_state.prompts` controls how the node is rendered and how responses are processed.

---

## Related Documentation

- **Prompt Modes Reference:** `references/prompt-modes.md`
- **Node Features:** `references/node-features.md`
- **Prompts Config Examples:** `references/prompts-config-examples.md`
- **Node Mapping Pattern:** `lib/patterns/node-mapping.md`
