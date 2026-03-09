# Routing Design Procedure

> **Used by:** `SKILL.md` Phase 3, Step 3.3
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

This document describes how to design the routing workflow nodes for a gateway command.
It defines the fixed topology, node interconnections, edge case handling, and the
delegation pattern for skill invocation.

---

## Fixed Topology

Every gateway workflow shares the same node skeleton. The variable parts are the delegation
nodes (one per skill) and the menu options. The fixed nodes handle argument detection,
intent parsing, winner evaluation, disambiguation, and menu display.

### Node Interconnection Diagram

```
                     START
                       |
                       v
              check_arguments
               /            \
          (has args)     (no args)
             /                \
            v                  v
       parse_intent      show_main_menu ------+
            |                  |               |
            v             (user selects)       |
    check_clear_winner         |               |
         /        \            v               |
    (winner)   (ambiguous)   delegate_*        |
       /            \          |               |
      v              v         |               |
execute_matched   show_dis-    |               |
   _intent       ambiguation   |               |
      |              |         |               |
      v         (user picks)   |               |
 delegate_*         |          |               |
      |             v          |               |
      |         delegate_*     |               |
      |             |          |               |
      +------+------+----+----+               |
             |            |                    |
             v            v                    |
          success    error_delegation          |
                                               |
                     cancelled <---------------+
```

---

## Node Specifications

### check_arguments

**Type:** `conditional`
**Purpose:** Determine whether the user provided any arguments with the gateway invocation.

```yaml
check_arguments:
  type: conditional
  description: "Check if user provided arguments"
  condition:
    type: state_check
    field: arguments
    operator: not_null
  branches:
    on_true: parse_intent
    on_false: show_main_menu
```

**Edge case -- whitespace-only input:**

If the user invokes `/{plugin_name}   ` (whitespace only), the arguments field should be
normalized to `null` before this check. The normalization happens during argument parsing
in the gateway command markdown's execution preamble:

```pseudocode
IF arguments IS NOT NULL:
  arguments = trim(arguments)
  IF arguments == "":
    arguments = null
```

### parse_intent

**Type:** `action`
**Purpose:** Run the 3VL flag matching algorithm against user input and the intent mapping
configuration.

```yaml
parse_intent:
  type: action
  description: "Parse user input against 3VL intent flags"
  actions:
    - type: mutate_state
      operation: set
      field: computed.intent_flags
      value: "${parse_3vl_flags(arguments, intent_flags)}"
    - type: mutate_state
      operation: set
      field: computed.intent_matches
      value: "${match_3vl_rules(computed.intent_flags, intent_rules)}"
  on_success: check_clear_winner
  on_failure: show_main_menu
```

**Output state after this node:**

| Field | Type | Description |
|-------|------|-------------|
| `computed.intent_flags` | `map<string, T\|F\|U>` | Each flag evaluated against input |
| `computed.intent_matches` | `object` | Match results with candidates and scores |
| `computed.intent_matches.clear_winner` | `boolean` | Whether a single candidate won |
| `computed.intent_matches.winner` | `object\|null` | Winning rule (if clear winner) |
| `computed.intent_matches.winner.action` | `string` | Action name to route to |
| `computed.intent_matches.top_candidates` | `array` | Top N candidates for disambiguation |

### check_clear_winner

**Type:** `conditional`
**Purpose:** Evaluate whether the intent matching produced an unambiguous winner.

A "clear winner" is defined as a candidate whose score leads the second-place candidate
by 2 or more points. This threshold prevents routing on marginal differences.

```yaml
check_clear_winner:
  type: conditional
  description: "Check if intent matching produced a clear winner"
  condition:
    type: state_check
    field: computed.intent_matches.clear_winner
    operator: "true"
  branches:
    on_true: execute_matched_intent
    on_false: show_disambiguation
```

### execute_matched_intent

**Type:** `action`
**Purpose:** Perform dynamic routing to the action specified by the winning rule.

This node uses dynamic `on_success` targeting: the transition target is read from state
rather than hardcoded. This enables O(1) routing regardless of the number of skills.

```yaml
execute_matched_intent:
  type: action
  description: "Route to the winning intent action"
  actions:
    - type: mutate_state
      operation: set
      field: computed.dynamic_target
      value: "${computed.intent_matches.winner.action}"
  on_success: "${computed.dynamic_target}"
  on_failure: show_main_menu
```

**Dynamic targets must resolve to:**
- `delegate_{skill_id}` -- routes to a skill delegation node
- `show_full_help` -- routes to help display (handled as an ending or inline action)
- `show_flag_help` -- routes to flag documentation display
- `show_skill_help_{skill_id}` -- routes to skill-specific help

### show_disambiguation

**Type:** `user_prompt`
**Purpose:** Present the top candidate matches when no clear winner was found.

The options are built dynamically from `computed.intent_matches.top_candidates`.

```yaml
show_disambiguation:
  type: user_prompt
  description: "Present top candidates when no clear winner"
  prompt:
    question: "I found multiple possible matches. Which did you mean?"
    header: "Clarify"
    options_from_state: "computed.intent_matches.top_candidates"
    option_mapping:
      id: "candidate.action"
      label: "candidate.description"
      description: "candidate.score_summary"
  on_response:
    "${selected_id}":
      consequence:
        - type: mutate_state
          operation: set
          field: intent
          value: "${selected_id}"
      next_node: "${selected_id}"
```

**Edge case -- single candidate but below threshold:**

If `top_candidates` has exactly one entry but its score did not meet the clear-winner
threshold, disambiguation still presents it as an option alongside "Show full menu":

```pseudocode
IF len(top_candidates) == 1 AND NOT clear_winner:
  # Add "Show full menu" as second option
  top_candidates.append({
    action: "show_main_menu",
    description: "Show all available operations",
    score_summary: "Browse full menu"
  })
```

### show_main_menu

**Type:** `user_prompt`
**Purpose:** Present the full skill menu when no arguments were provided or intent
could not be determined.

Options are generated statically at file-generation time, one per discovered skill:

```yaml
show_main_menu:
  type: user_prompt
  description: "Present full skill menu"
  prompt:
    question: "What would you like to do with {plugin_name}?"
    header: "Menu"
    options:
      - id: {skill_1_id}
        label: "{skill_1_name}"
        description: "{skill_1_short_desc}"
      - id: {skill_2_id}
        label: "{skill_2_name}"
        description: "{skill_2_short_desc}"
      # ... one per skill
  on_response:
    {skill_1_id}:
      consequence:
        - type: mutate_state
          operation: set
          field: intent
          value: "{skill_1_id}"
      next_node: delegate_{skill_1_id}
    {skill_2_id}:
      consequence:
        - type: mutate_state
          operation: set
          field: intent
          value: "{skill_2_id}"
      next_node: delegate_{skill_2_id}
```

### delegate_{skill_id} (one per skill)

**Type:** `action`
**Purpose:** Invoke a specific skill, passing through the original user arguments.

One delegation node is generated for each discovered skill. The node uses `invoke_skill`
to hand off execution entirely to the target skill's SKILL.md.

```yaml
delegate_{skill_id}:
  type: action
  description: "Delegate to {skill_name}"
  actions:
    - type: invoke_skill
      skill: "{skill_name}"
      args: "${arguments}"
  on_success: success
  on_failure: error_delegation
```

**Important:** Gateways are routers, not executors. The delegation node must invoke the
skill immediately without pre-processing, validating, or answering the user's request.
The target skill handles all context gathering and execution.

---

## Edge Cases

### No Arguments Provided

When the user invokes `/{plugin_name}` with no arguments:

1. `check_arguments` evaluates `arguments == null` -> `on_false`
2. Routes directly to `show_main_menu`
3. User selects from the full skill list
4. Routes to `delegate_{selected_skill}`

No intent parsing occurs. This is the simplest path through the workflow.

### Ambiguous Match (Multiple Candidates)

When the user's input matches keywords from multiple skills with similar scores:

1. `parse_intent` evaluates flags and matches rules
2. `check_clear_winner` finds no candidate with a 2+ point lead -> `on_false`
3. `show_disambiguation` presents the top 3 candidates
4. User selects one
5. Routes to the corresponding `delegate_{skill_id}`

### Single Skill Match Below Threshold

Rare case where only one candidate matched but its score is too low for automatic routing
(e.g., only soft matches, no hard matches):

1. `check_clear_winner` returns `false` (score below threshold despite single candidate)
2. `show_disambiguation` presents the single candidate plus "Show full menu"
3. User confirms or switches to menu

### Help Intent Matching

Help intents (`show_full_help`, `show_flag_help`, `show_skill_help_*`) are handled as
special actions that display content rather than delegating to a skill. These map to
display actions defined in the intent-mapping.yaml `actions:` section.

When `execute_matched_intent` resolves `computed.dynamic_target` to a help action:

1. The action type is `display` (not `invoke_skill`)
2. Content is rendered inline from the intent-mapping.yaml help content blocks
3. Workflow reaches the `success` ending after display

### Fallback Rule (Empty Conditions)

The final rule in every intent-mapping.yaml has `conditions: {}` (empty). This rule
matches any input because there are no conditions to fail. Its specificity is zero,
so it only wins when no other rule matches.

```yaml
- name: "show_menu"
  conditions: {}
  action: show_main_menu
  description: "No clear intent, show interactive menu"
```

This guarantees every input eventually resolves to either a skill delegation or the menu.

---

## Node Generation Procedure

When generating the workflow.yaml, follow this sequence:

```pseudocode
BUILD_WORKFLOW_NODES():
  nodes = {}

  # 1. Fixed nodes (same for every gateway)
  nodes["check_arguments"] = build_check_arguments_node()
  nodes["parse_intent"] = build_parse_intent_node()
  nodes["check_clear_winner"] = build_check_clear_winner_node()
  nodes["execute_matched_intent"] = build_execute_matched_node()
  nodes["show_disambiguation"] = build_disambiguation_node()
  nodes["show_main_menu"] = build_main_menu_node(computed.skills)

  # 2. Delegation nodes (one per skill)
  FOR skill IN computed.skills:
    node_id = "delegate_" + sanitize_id(skill.id)
    nodes[node_id] = build_delegation_node(skill)

  # 3. Endings
  endings = {
    success: { type: "success", message: "Request handled by " + computed.plugin_name },
    error_delegation: { type: "error", message: "Failed to delegate to skill", recovery: "Try invoking the skill directly" },
    cancelled: { type: "error", message: "Operation cancelled by user" }
  }

  RETURN { nodes: nodes, endings: endings }
```

---

## Related Documentation

- **SKILL.md Phase 3:** `../SKILL.md` -- Generation steps that invoke this procedure
- **Gateway File Generation:** `gateway-file-generation.md` -- Placeholder catalog
- **Workflow Generation Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
