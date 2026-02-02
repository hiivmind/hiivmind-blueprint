# Composable Intent Detection Workflow

## Goal

Make intent mapping a universally reusable workflow that can be composed into any gateway, eliminating the N-conditional-nodes routing cascade problem.

---

## Problem Analysis

### Current State (hiivmind-corpus gateway)

**What works well:**
- `intent-mapping.yaml` - Clean 3VL config (11 flags, 19 rules, priorities)
- Consequence types exist: `parse_intent_flags`, `match_3vl_rules`, `dynamic_route`

**What's broken:**
- `workflow.yaml` has 19 sequential conditional nodes for routing (lines 254-354)
- Adding a new action requires: flag + rule + conditional node + delegate node
- The `dynamic_route` consequence sets `computed.dynamic_target` but engine doesn't use it

### The Cascade Problem

```yaml
# Current: O(N) nodes for N actions
execute_matched_action:          # if action == X → X
route_action_detect_context:     # else if action == Y → Y
route_action_discover_corpora:   # else if action == Z → Z
# ... 16 more conditionals
```

---

## Solution Design

### The Missing Piece: Dynamic `on_success` in Engine

The `dynamic_route` consequence already exists and sets `computed.dynamic_target`. What's missing is engine support for interpolating routing targets:

```yaml
on_success: "${computed.dynamic_target}"  # Currently doesn't work!
```

### After: O(1) Routing

```yaml
execute_matched_intent:
  type: action
  actions:
    - type: dynamic_route
      action: "${computed.intent_matches.winner.action}"  # Sets computed.dynamic_target
  on_success: "${computed.dynamic_target}"  # Routes to delegate_init, detect_context, etc.
  on_failure: show_main_menu
```

No action table needed - the intent-mapping.yaml rule's `action` field already maps to node names.

---

## Implementation Details

### 1. Engine Enhancement: Dynamic `on_success`

Update `lib/workflow/engine.md` to support interpolated routing:

```yaml
# In action node execution:
on_success: "${computed.dispatch_target}"  # Now works!
```

Engine pseudocode change:
```
FUNCTION execute_action_node(node, state):
    # ... execute actions ...

    # NEW: Interpolate on_success if it's a variable reference
    next_node = node.on_success
    IF next_node.startsWith("${"):
        next_node = interpolate(next_node, state)

    RETURN { success: true, next_node: next_node }
```

### 2. Reusable Intent Detection Workflow

For maximum composability, create `lib/workflows/intent-detection.yaml`:

```yaml
name: intent-detection
version: "1.0.0"

inputs:
  arguments: null           # Required
  intent_flags: null        # Required
  intent_rules: null        # Required
  fallback_action: "show_main_menu"

outputs:
  matched_action: "${computed.matched_action}"
  intent: "${intent}"

start_node: check_has_input

nodes:
  check_has_input:
    type: conditional
    condition:
      type: evaluate_expression
      expression: "arguments != null && arguments.trim().length > 0"
    branches:
      true: parse_intent_flags
      false: use_fallback

  parse_intent_flags:
    type: action
    actions:
      - type: parse_intent_flags
        input: "${inputs.arguments}"
        flag_definitions: "${inputs.intent_flags}"
        store_as: computed.intent_flags
    on_success: match_intent_rules
    on_failure: use_fallback

  match_intent_rules:
    type: action
    actions:
      - type: match_3vl_rules
        flags: "${computed.intent_flags}"
        rules: "${inputs.intent_rules}"
        store_as: computed.intent_matches
    on_success: check_clear_winner
    on_failure: use_fallback

  check_clear_winner:
    type: conditional
    condition:
      type: evaluate_expression
      expression: "computed.intent_matches.clear_winner == true"
    branches:
      true: set_winner
      false: show_disambiguation

  set_winner:
    type: action
    actions:
      - type: set_state
        field: computed.matched_action
        value: "${computed.intent_matches.winner.action}"
    on_success: success_resolved
    on_failure: use_fallback

  show_disambiguation:
    type: user_prompt
    prompt:
      question: "Multiple intents detected. Which did you mean?"
      header: "Clarify"
      options_from_state: computed.intent_matches.top_candidates
    on_response:
      selected:
        consequence:
          - type: set_state
            field: computed.matched_action
            value: "${user_responses.show_disambiguation.selected.rule.action}"
        next_node: success_resolved

  use_fallback:
    type: action
    actions:
      - type: set_state
        field: computed.matched_action
        value: "${inputs.fallback_action}"
    on_success: success_resolved
    on_failure: success_resolved

endings:
  success_resolved:
    type: success
    outputs:
      matched_action: "${computed.matched_action}"
```

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/workflow/engine.md` | Add dynamic `on_success`/`on_failure` interpolation support |
| `lib/intent_detection/execution.md` | Document dynamic routing pattern |
| `templates/gateway-command.md.template` | Use `dynamic_route` + interpolated routing |

## New Files to Create

| File | Purpose |
|------|---------|
| `lib/workflows/intent-detection.yaml` | Reusable intent detection sub-workflow |
| `lib/blueprint/patterns/intent-composition.md` | Document the pattern |

---

## Before/After Comparison

### Before (hiivmind-corpus)

```
Workflow nodes for intent routing: 19 conditionals (~100 lines)
Adding new action: 3 changes (flag + rule + conditional node)
```

### After

```
Workflow nodes for intent routing: 1 action node with dynamic_route (~5 lines)
Adding new action: 1 change (rule in intent-mapping.yaml with action: node_name)
```

---

## Implementation Steps

1. **Update engine.md** to support `on_success: "${...}"` interpolation
2. **Create `lib/workflows/intent-detection.yaml`** as reusable sub-workflow
3. **Update `gateway-command.md.template`** to use `dynamic_route` + interpolated routing
4. **Document pattern** in `lib/blueprint/patterns/intent-composition.md`
5. **Migrate hiivmind-corpus** as reference implementation (optional, separate PR)

---

## Verification

1. Test dynamic `on_success` interpolation in engine
2. Generate a new gateway command with the updated templates
3. Verify single `dynamic_route` node instead of N conditionals
4. Add a new action (add rule to intent-mapping.yaml with `action: new_node_name`)
5. Verify routing works without adding conditional nodes
6. Test disambiguation flow still works
