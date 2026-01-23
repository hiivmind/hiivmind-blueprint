# Intent Detection Execution

Algorithms for parsing user input into 3VL flags and matching against rule tables.

---

## Flag Parsing Algorithm

Given user input and flag definitions, produce a map of flag names to 3VL values.

### Pseudocode

```
FUNCTION parse_intent_flags(input, flag_definitions):
  flags = {}

  FOR each flag_name, definition IN flag_definitions:
    flags[flag_name] = U  # Default: Unknown

    # Check negative keywords first (more specific)
    IF definition.negative_keywords:
      FOR each keyword IN definition.negative_keywords:
        IF input.toLowerCase().includes(keyword.toLowerCase()):
          flags[flag_name] = F  # False
          BREAK

    # Check positive keywords (if not already F)
    IF flags[flag_name] != F:
      FOR each keyword IN definition.keywords:
        IF input.toLowerCase().includes(keyword.toLowerCase()):
          flags[flag_name] = T  # True
          BREAK

  RETURN flags
```

### Key Points

1. **Case-insensitive matching** - All comparisons ignore case
2. **Negative keywords first** - More specific phrases like "don't create" should override "create"
3. **First match wins** - Within positive keywords, first match sets the flag
4. **Substring matching** - Keywords can appear anywhere in input

### Example

**Input:** "help me create a new corpus without building"

**Flag definitions:**
```yaml
has_help:
  keywords: ["help", "how do i"]
has_init:
  keywords: ["create", "new", "initialize"]
has_build:
  keywords: ["build", "scan"]
  negative_keywords: ["without building", "skip build"]
```

**Result:**
```yaml
has_help: T    # "help" matched
has_init: T    # "create", "new" matched
has_build: F   # "without building" matched negative keyword
```

---

## Rule Matching Algorithm

Given parsed flags and a rules array, score and rank rules.

### Pseudocode

```
FUNCTION match_3vl_rules(flags, rules):
  candidates = []

  FOR each rule IN rules:
    score = 0
    excluded = false

    FOR each condition_key, rule_val IN rule.conditions:
      state_val = flags[condition_key] || U  # Default to Unknown

      IF (state_val == T AND rule_val == T) OR (state_val == F AND rule_val == F):
        score += 2  # Hard match
      ELSE IF (state_val == T AND rule_val == F) OR (state_val == F AND rule_val == T):
        excluded = true  # Exclusion
        BREAK
      ELSE IF state_val == U AND rule_val == U:
        score += 0  # No contribution
      ELSE:
        score += 1  # Soft match (any other combination)

    IF NOT excluded:
      candidates.append({ rule: rule, score: score })

  # Sort by score (descending), then priority (descending)
  candidates.sort(by: (-score, -rule.priority))

  RETURN candidates
```

### Winner Selection

```
FUNCTION determine_winner(candidates):
  IF candidates.length == 0:
    RETURN { clear_winner: false, winner: null, top_candidates: [] }

  IF candidates.length == 1:
    RETURN { clear_winner: true, winner: candidates[0].rule, top_candidates: candidates }

  top_score = candidates[0].score
  second_score = candidates[1].score

  IF top_score >= second_score + 2:
    RETURN {
      clear_winner: true,
      winner: candidates[0].rule,
      top_candidates: candidates[0..3]  # Top 3 for reference
    }
  ELSE:
    RETURN {
      clear_winner: false,
      winner: null,
      top_candidates: candidates[0..3]  # Top 3 for disambiguation
    }
```

---

## Disambiguation Strategy

When there's no clear winner, present top candidates to the user.

### Menu Construction

```
FUNCTION build_disambiguation_menu(top_candidates):
  options = []
  FOR each candidate IN top_candidates[0..2]:  # Max 3 options
    options.append({
      id: candidate.rule.name,
      label: candidate.rule.name,
      description: candidate.rule.description
    })

  RETURN {
    question: "I detected multiple possible intents. Which did you mean?",
    header: "Clarify",
    options: options
  }
```

### User Response Handling

After user selects from disambiguation:
1. Set `intent` to the selected rule's name
2. Set `matched_action` to the selected rule's action
3. Route to execute the action

If user types custom text instead of selecting:
1. Capture the new text as `arguments`
2. Re-run flag parsing with the new input
3. Re-attempt rule matching

---

## Fallback Behavior

When no rules match (all excluded or empty candidates):

### Navigate Fallback

If the input appears to be a question or search query, default to navigation:

```
FUNCTION apply_fallback(input, flags):
  # If no keywords matched at all, treat as navigation query
  all_unknown = ALL flags IN [U]

  IF all_unknown:
    RETURN { intent: "navigate", action: "discover_corpora" }

  # Otherwise, show clarification menu
  RETURN { intent: null, action: "ask_clarification" }
```

### Rationale

Users often come with documentation questions. If they type something like "how do partitions work" without matching any command keywords, routing to navigation is usually the right choice.

---

## Performance Considerations

### Keyword Indexing

For large keyword sets, consider pre-building a keyword index:

```python
keyword_index = {}
for flag_name, definition in flag_definitions.items():
    for keyword in definition.keywords:
        keyword_lower = keyword.lower()
        if keyword_lower not in keyword_index:
            keyword_index[keyword_lower] = []
        keyword_index[keyword_lower].append((flag_name, 'positive'))
    for keyword in definition.get('negative_keywords', []):
        keyword_lower = keyword.lower()
        if keyword_lower not in keyword_index:
            keyword_index[keyword_lower] = []
        keyword_index[keyword_lower].append((flag_name, 'negative'))
```

Then scan input once for all keywords rather than checking each keyword individually.

### Early Termination

Once a flag is set to `F` (from negative keyword), skip checking positive keywords for that flag.

---

## Implementation Notes

### Tool Integration

In workflow execution, these algorithms are invoked via consequences:

```yaml
# Parse input to flags
- type: parse_intent_flags
  input: "${arguments}"
  flag_definitions: "${intent_flags}"
  store_as: computed.intent_flags

# Match flags to rules
- type: match_3vl_rules
  flags: "${computed.intent_flags}"
  rules: "${intent_rules}"
  store_as: computed.intent_matches
```

### State Storage

Results are stored in workflow state:

```yaml
computed:
  intent_flags:
    has_help: T
    has_init: T
    has_build: U
    # ...
  intent_matches:
    clear_winner: true
    winner:
      name: "help_with_init"
      action: "extract_project_for_init"
      priority: 80
    top_candidates:
      - rule: { ... }
        score: 4
```

---

## Related Documentation

- **3VL Framework:** `lib/intent_detection/framework.md`
- **Variable Interpolation:** `lib/intent_detection/variables.md`
- **Workflow Consequences:** `lib/workflow/consequences.md`
