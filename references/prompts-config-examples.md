# Prompts Configuration Examples

Examples of configuring user_prompt execution modes.

---

## Default Interactive Mode (No Configuration)

When `initial_state.prompts` is omitted, interactive mode is used:

```yaml
name: "my-skill"
version: "1.0.0"

initial_state:
  phase: "start"
  # No prompts config - defaults to interactive mode

nodes:
  ask_choice:
    type: user_prompt
    prompt:
      question: "Which option do you prefer?"
      header: "Choice"
      options:
        - id: option_a
          label: "Option A"
          description: "First option"
        - id: option_b
          label: "Option B"
          description: "Second option"
    on_response:
      option_a:
        next_node: handle_a
      option_b:
        next_node: handle_b
```

**Behavior:** Uses AskUserQuestion tool with chip-style selection.

---

## Explicit Interactive Mode

Explicitly specify interactive mode:

```yaml
initial_state:
  prompts:
    mode: "interactive"
```

---

## Tabular Mode with Prefix Matching (Recommended Default)

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
```

**User sees:**

```markdown
## Which format do you prefer?

| Option ID | Label | Description |
|-----------|-------|-------------|
| markdown | Markdown | Portable, human-readable |
| json | JSON | Machine-parseable |
| yaml | YAML | Structured, readable |

**Please type the Option ID of your choice.**
```

**Matching behavior:**
- User types "markdown" → matches "markdown" (exact)
- User types "mark" → matches "markdown" (prefix)
- User types "j" → matches "json" (prefix)
- User types "xyz" → no match, re-prompts

---

## Tabular Mode with Exact Matching

For strict input validation:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "exact"
      other_handler: "prompt"
```

**Matching behavior:**
- User types "markdown" → matches "markdown"
- User types "mark" → no match, re-prompts
- User types "MARKDOWN" → matches "markdown" (case-insensitive by default)

---

## Tabular Mode with Fuzzy Matching

Tolerates typos:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "fuzzy"
      fuzzy_threshold: 0.7
      other_handler: "prompt"
```

**Matching behavior:**
- User types "markdown" → matches "markdown" (100% similarity)
- User types "markdwon" → matches "markdown" (88% similarity > 70% threshold)
- User types "mrakdown" → matches "markdown" (87% similarity > 70% threshold)
- User types "xyz" → no match (0% similarity < 70% threshold), re-prompts

---

## Tabular Mode with Route to Other Handler

Accept custom user input:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      other_handler: "route"

nodes:
  select_or_custom:
    type: user_prompt
    prompt:
      question: "Select a preset or enter a custom value"
      header: "Config"
      options:
        - id: minimal
          label: "Minimal"
          description: "Basic configuration"
        - id: full
          label: "Full"
          description: "All features enabled"
    on_response:
      minimal:
        next_node: apply_minimal
      full:
        next_node: apply_full
      other:                              # Required when other_handler: "route"
        consequence:
          - type: mutate_state
            operation: set
            field: custom_config
            value: "${user_responses.select_or_custom.text}"
        next_node: parse_custom_config
```

**Matching behavior:**
- User types "minimal" → routes to apply_minimal
- User types "my custom config" → routes to other handler
- `state.user_responses.select_or_custom.text` contains "my custom config"

---

## Tabular Mode with Fail on No Match

Error if user doesn't select a valid option:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "exact"
      other_handler: "fail"
```

**Matching behavior:**
- User types "markdown" → matches, continues
- User types "xyz" → workflow fails with error

---

## Case-Sensitive Matching

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "exact"
      case_sensitive: true
      other_handler: "prompt"
```

**Matching behavior:**
- User types "markdown" → matches "markdown"
- User types "MARKDOWN" → no match, re-prompts
- User types "Markdown" → no match, re-prompts

---

## Hidden Option IDs

Show only Label and Description columns:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      show_option_ids: false

nodes:
  select_format:
    type: user_prompt
    prompt:
      question: "Which format?"
      header: "Format"
      options:
        - id: markdown
          label: "Markdown"
          description: "Portable, human-readable"
        - id: json
          label: "JSON"
          description: "Machine-parseable"
```

**User sees:**

```markdown
## Which format?

| Label | Description |
|-------|-------------|
| Markdown | Portable, human-readable |
| JSON | Machine-parseable |

**Please type the Option ID of your choice.**
```

---

## Custom Instruction Text

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      instruction_text: "**Enter your selection (you can type just the first few letters):**"
```

---

## Dynamic Options with Tabular Mode

Works the same as interactive mode:

```yaml
initial_state:
  prompts:
    mode: "tabular"
    tabular:
      match_strategy: "prefix"
      other_handler: "route"

nodes:
  show_matches:
    type: user_prompt
    prompt:
      question: "Multiple matches found. Which did you mean?"
      header: "Clarify"
      options_from_state: computed.matches
      option_mapping:
        id: name
        label: name
        description: description
    on_response:
      selected:
        consequence:
          - type: mutate_state
            operation: set
            field: selected_match
            value: "${user_responses.show_matches.selected}"
        next_node: process_match
      other:
        consequence:
          - type: mutate_state
            operation: set
            field: search_query
            value: "${user_responses.show_matches.text}"
        next_node: re_search
```

---

## State After User Response

### Matched Option (Static)

```yaml
state.user_responses.select_format:
  handler_id: "markdown"
  raw:
    text: "mark"
    matched_by: "prefix"
```

### Matched Option (Dynamic)

```yaml
state.user_responses.show_matches:
  handler_id: "selected"
  selected: { name: "option-1", description: "First match" }  # Original item
  raw:
    text: "option"
    matched_by: "prefix"
```

### No Match (Route to Other)

```yaml
state.user_responses.select_or_custom:
  handler_id: "other"
  text: "my custom value"
```

---

## Related Documentation

- **Config Loader:** `lib/workflow/prompts-config-loader.md`
- **Node Type:** `hiivmind-blueprint-lib/nodes/core/user-prompt.yaml`
- **Schema:** `hiivmind-blueprint-lib/schema/prompts-config.json`
