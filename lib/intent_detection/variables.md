# Variable Interpolation

Pattern syntax and resolution for `${...}` placeholders in workflow and intent detection configurations.

---

## Pattern Syntax

Variables use the `${path.to.value}` pattern:

```yaml
message: "Analyzing request: ${arguments}"
action: "${computed.intent_matches.winner.action}"
skill_args: "${source_url}"
```

---

## Resolution Order

When resolving a path, check locations in this order:

1. **`state.computed.{path}`** - Derived/calculated values
2. **`state.flags.{path}`** - Boolean flags
3. **`state.user_responses.{path}`** - User prompt responses
4. **`state.{path}`** - Top-level state fields

**First match wins.** This order allows computed values to override raw state.

---

## Common Patterns

### Top-Level State

```yaml
${arguments}          # → state.arguments
${intent}             # → state.intent
${target_corpus}      # → state.target_corpus
${target_topic}       # → state.target_topic
${source_url}         # → state.source_url
```

### Computed Values

```yaml
${computed.context_type}           # → state.computed.context_type
${computed.available_corpora}      # → state.computed.available_corpora
${computed.selected_corpus}        # → state.computed.selected_corpus
${computed.intent_flags}           # → 3VL flag values map
${computed.intent_matches}         # → Rule matching results
${computed.matched_action}         # → Action from winning rule
${computed.extracted_project}      # → Extracted project name/URL
```

### Flags

```yaml
${flags.has_arguments}             # → state.flags.has_arguments
${flags.in_corpus_dir}             # → state.flags.in_corpus_dir
${flags.has_installed_corpora}     # → state.flags.has_installed_corpora
```

### User Responses

```yaml
${user_responses.show_main_menu.id}        # Selected option ID
${user_responses.show_main_menu.raw.text}  # Custom text input
${user_responses.select_corpus.selected}   # Selected corpus object
```

### Array Access

```yaml
${computed.available_corpora[0]}           # First corpus
${computed.intent_matches.top_candidates[0].rule.name}  # First candidate's name
${computed.intent_matches.top_candidates[1].rule.action}  # Second candidate's action
```

### Nested Object Access

```yaml
${computed.selected_corpus.name}           # Corpus name field
${computed.intent_matches.winner.action}   # Winning rule's action field
${computed.intent_matches.winner.priority} # Winning rule's priority
```

---

## Special Variables

### Environment Variables

```yaml
${ARGUMENTS}                       # Command-line arguments passed to command
${CLAUDE_PLUGIN_ROOT}              # Plugin root directory (for file paths)
```

### File References

Variables can reference external files:

```yaml
flag_definitions: "${intent_flags}"     # References intent_flags from workflow
rules: "${intent_rules}"                # References intent_rules from workflow
```

When a variable references a YAML structure defined elsewhere in the same file (like `intent_flags` or `intent_rules` at the top level of workflow.yaml), it loads that structure.

For cross-file references with imports:

```yaml
imports:
  intent_mapping: "intent-mapping.yaml"

# Later in the workflow:
flag_definitions: "${imports.intent_mapping.intent_flags}"
rules: "${imports.intent_mapping.intent_rules}"
```

---

## Interpolation in Different Contexts

### String Messages

Variables are replaced within strings:

```yaml
- type: display_message
  message: "Found ${computed.file_count} files in ${computed.source_id}"
```

Result: `"Found 42 files in polars-docs"`

### Object Values

Variables can reference entire objects:

```yaml
- type: set_state
  field: computed.selected_corpus
  value: "${computed.available_corpora[0]}"
```

The entire corpus object is assigned, not just a string.

### Expression Context

Variables are available in expressions:

```yaml
- type: evaluate
  expression: "computed.available_corpora.length > 0"
  set_flag: has_corpora
```

Here, `computed.available_corpora` resolves from state without `${}` syntax (expressions have direct state access).

---

## Null Handling

When a variable path doesn't exist:

| Context | Behavior |
|---------|----------|
| String interpolation | Replaced with empty string `""` |
| Object assignment | Assigned as `null` |
| Expression evaluation | Treated as `null` (may cause expression error) |
| Condition checks | Treated as falsy |

**Best practice:** Use `state_not_null` preconditions or explicit checks before accessing potentially-undefined paths.

---

## Escaping

To include a literal `${` in output, escape with backslash:

```yaml
message: "Use \${variable} syntax for interpolation"
```

Result: `"Use ${variable} syntax for interpolation"`

---

## Resolution Examples

### Intent Detection Context

```yaml
# After parse_intent_flags:
computed.intent_flags:
  has_help: T
  has_init: T
  has_build: U

# Variable references:
${computed.intent_flags.has_help}     # → "T"
${computed.intent_flags.has_init}     # → "T"
${computed.intent_flags.has_build}    # → "U"
```

### After Rule Matching

```yaml
# After match_3vl_rules:
computed.intent_matches:
  clear_winner: true
  winner:
    name: "help_with_init"
    action: "extract_project_for_init"
    priority: 80
  top_candidates:
    - rule: { name: "help_with_init", ... }
      score: 4

# Variable references:
${computed.intent_matches.clear_winner}      # → true
${computed.intent_matches.winner.name}       # → "help_with_init"
${computed.intent_matches.winner.action}     # → "extract_project_for_init"
${computed.intent_matches.top_candidates[0].score}  # → 4
```

---

## Related Documentation

- **3VL Framework:** `lib/intent_detection/framework.md`
- **Execution Algorithms:** `lib/intent_detection/execution.md`
- **Workflow State:** `lib/workflow/state.md`
