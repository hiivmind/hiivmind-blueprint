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

---

## Dynamic Routing Pattern

The intent detection pipeline typically ends with dynamic routing to the matched action. This eliminates the need for N conditional nodes to handle N possible actions.

### Traditional Approach (O(N))

```yaml
# This grows with each action added
route_to_init:
  type: conditional
  condition: { type: state_equals, field: computed.matched_action, value: "delegate_init" }
  branches:
    true: delegate_init
    false: route_to_build

route_to_build:
  type: conditional
  condition: { type: state_equals, field: computed.matched_action, value: "delegate_build" }
  branches:
    true: delegate_build
    false: route_to_refresh
# ... and so on
```

### Dynamic Approach (O(1))

```yaml
# Single node handles all routing
execute_dynamic_route:
  type: action
  actions:
    - type: dynamic_route
      action: "${computed.matched_action}"
  on_success: "${computed.dynamic_target}"  # Interpolated at runtime
  on_failure: show_main_menu
```

### How It Works

1. **Intent matching** sets `computed.matched_action` to a node name (e.g., `"delegate_init"`)
2. **`dynamic_route` consequence** copies this to `computed.dynamic_target`
3. **Engine interpolates** `on_success: "${computed.dynamic_target}"` at runtime
4. **Routing occurs** directly to the delegate node

### Engine Support

The workflow engine supports variable interpolation in routing targets:

```
FUNCTION resolve_routing_target(target, state):
    IF target.includes("${"):
        resolved = interpolate(target, state)
        IF resolved == null OR resolved == "":
            THROW "Dynamic routing target resolved to null/empty"
        RETURN resolved
    ELSE:
        RETURN target
```

See `lib/workflow/engine.md` for the full specification.

### Adding New Actions

With dynamic routing, adding a new action requires only:

1. **Add flag definition** (if new keywords needed)
2. **Add rule** with `action: delegate_new_action`
3. **Add delegate node** in workflow

No conditional cascade updates needed.

### Complete Pipeline Example

```yaml
nodes:
  # Step 1: Parse input to flags
  parse_flags:
    type: action
    actions:
      - type: parse_intent_flags
        input: "${arguments}"
        flag_definitions: "${intent_flags}"
        store_as: computed.intent_flags
    on_success: match_rules
    on_failure: show_menu

  # Step 2: Match flags to rules
  match_rules:
    type: action
    actions:
      - type: match_3vl_rules
        flags: "${computed.intent_flags}"
        rules: "${intent_rules}"
        store_as: computed.intent_matches
    on_success: check_winner
    on_failure: show_menu

  # Step 3: Check for clear winner
  check_winner:
    type: conditional
    condition:
      type: evaluate_expression
      expression: "computed.intent_matches.clear_winner == true"
    branches:
      true: set_action
      false: show_disambiguation

  # Step 4: Set the matched action
  set_action:
    type: action
    actions:
      - type: set_state
        field: computed.matched_action
        value: "${computed.intent_matches.winner.action}"
    on_success: dynamic_route
    on_failure: show_menu

  # Step 5: Route dynamically
  dynamic_route:
    type: action
    actions:
      - type: dynamic_route
        action: "${computed.matched_action}"
    on_success: "${computed.dynamic_target}"  # THE KEY!
    on_failure: show_menu

  # Delegate nodes (targets of dynamic routing)
  delegate_init:
    type: action
    actions:
      - type: invoke_skill
        skill: "my-plugin-init"
    on_success: success
    on_failure: error

  delegate_build:
    type: action
    actions:
      - type: invoke_skill
        skill: "my-plugin-build"
    on_success: success
    on_failure: error
```

---

## Distributed Workflow Support (v1.2+)

As of bundle schema version 1.2, the intent-detection workflow is available as a remote workflow reference from `hiivmind-blueprint-lib`:

```yaml
# Remote workflow reference (recommended for new gateways)
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
    fallback_action: "show_main_menu"
  next_node: execute_dynamic_route
```

**Migration Path:**

| Current | Target |
|---------|--------|
| `doc: "lib/workflows/intent-detection.yaml"` | `workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection` |
| Local file maintenance | Automatic updates via version pinning |
| Manual sync | Cache-based freshness |

**Benefits:**
- Single source of truth across all gateways
- Version pinning for reproducibility
- Automatic caching
- Dependency validation (types exist in loaded registry)

The local file at `lib/workflows/intent-detection.yaml` remains available as an embedded fallback for offline scenarios.

See `lib/workflow/workflow-loader.md` for the complete loading protocol.

---

## Related Documentation

- **3VL Framework:** `docs/intent-detection/framework.md`
- **Variable Interpolation:** `docs/intent-detection/variables.md`
- **Intent Detection Guide:** `docs/intent-detection-guide.md`
- **Workflow Engine:** `lib/workflow/engine.md`
- **Workflow Loader:** `lib/workflow/workflow-loader.md`
- **Intent Composition Pattern:** `lib/blueprint/patterns/intent-composition.md`
- **Reusable Sub-workflow (remote):** `hiivmind/hiivmind-blueprint-lib@v1.x:intent-detection`
