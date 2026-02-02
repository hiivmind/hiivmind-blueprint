# Intent Detection Guide

Implement O(1) gateway routing using 3-valued logic (3VL) intent detection.

## The Problem

Traditional gateway routing uses a cascade of conditionals:

```yaml
# O(N) routing - one conditional per action
route_to_init:
  type: conditional
  condition: { type: state_equals, field: computed.matched_action, value: "delegate_init" }
  branches: { on_true: delegate_init, on_false: route_to_build }

route_to_build:
  type: conditional
  condition: { type: state_equals, field: computed.matched_action, value: "delegate_build" }
  branches: { on_true: delegate_build, on_false: route_to_refresh }

# ... continues for each skill
```

**Problems:**
- Adding skills requires adding conditional nodes
- Workflow becomes verbose
- Hard to maintain

## The Solution: Dynamic Routing

Use 3VL intent matching with dynamic `on_success`:

```yaml
execute_dynamic_route:
  type: action
  actions:
    - type: dynamic_route
      action: "${computed.matched_action}"
  on_success: "${computed.dynamic_target}"  # Interpolated at runtime!
  on_failure: show_main_menu
```

The `dynamic_route` consequence sets `computed.dynamic_target`, which is then interpolated into `on_success`.

**Result:** O(1) routing regardless of skill count.

## How 3VL Works

### Intent Flags

Define keywords that indicate user intent:

```yaml
# intent-mapping.yaml
intent_flags:
  wants_init:
    keywords: ["init", "initialize", "setup", "create new"]
    description: "User wants to initialize"

  wants_build:
    keywords: ["build", "index", "generate"]
    description: "User wants to build"

  wants_refresh:
    keywords: ["refresh", "sync", "update", "check"]
    description: "User wants to refresh"
```

### Intent Rules

Map flag combinations to actions:

```yaml
intent_rules:
  - name: "initialize"
    conditions:
      wants_init: T        # True
      wants_build: F       # False
    action: "delegate_init"
    priority: 100

  - name: "build"
    conditions:
      wants_init: F
      wants_build: T
    action: "delegate_build"
    priority: 90

  - name: "refresh"
    conditions:
      wants_refresh: T
    action: "delegate_refresh"
    priority: 80
```

### 3-Valued Logic

- **T (True)** - Flag must be present
- **F (False)** - Flag must NOT be present
- **U (Unknown)** - Flag doesn't matter

This allows precise intent matching with fallback rules.

## Complete Gateway Implementation

### 1. Create intent-mapping.yaml

```yaml
# commands/my-plugin/intent-mapping.yaml
intent_flags:
  wants_init:
    keywords: ["init", "initialize", "setup"]
  wants_build:
    keywords: ["build", "index", "create"]
  wants_refresh:
    keywords: ["refresh", "sync", "update"]
  wants_discover:
    keywords: ["discover", "list", "show"]

intent_rules:
  - name: "init"
    conditions: { wants_init: T }
    action: "delegate_init"
    priority: 100

  - name: "build"
    conditions: { wants_build: T, wants_init: F }
    action: "delegate_build"
    priority: 90

  - name: "refresh"
    conditions: { wants_refresh: T }
    action: "delegate_refresh"
    priority: 80

  - name: "discover"
    conditions: { wants_discover: T }
    action: "delegate_discover"
    priority: 70

fallback_action: "show_main_menu"
```

### 2. Create workflow.yaml

```yaml
# commands/my-plugin/workflow.yaml
name: "my-plugin-gateway"
version: "1.0.0"
description: "Unified entry point"

initial_state:
  arguments: null
  intent_flags: null
  intent_rules: null
  fallback_action: "show_main_menu"
  computed:
    matched_action: null
    dynamic_target: null

start_node: load_config

nodes:
  # Phase 1: Load configuration
  load_config:
    type: action
    actions:
      - type: read_file
        path: "intent-mapping.yaml"
        store_as: computed.config
      - type: set_state
        field: intent_flags
        value: "${computed.config.intent_flags}"
      - type: set_state
        field: intent_rules
        value: "${computed.config.intent_rules}"
    on_success: check_has_arguments
    on_failure: error_loading_config

  # Phase 2: Check for input
  check_has_arguments:
    type: conditional
    condition:
      type: evaluate_expression
      expression: "arguments != null && arguments.trim() != ''"
    branches:
      on_true: detect_intent
      on_false: show_main_menu

  # Phase 3: Detect intent using reusable sub-workflow
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
    context:
      arguments: "${arguments}"
      intent_flags: "${intent_flags}"
      intent_rules: "${intent_rules}"
      fallback_action: "show_main_menu"
    next_node: execute_dynamic_route

  # Phase 4: Dynamic routing (THE KEY)
  execute_dynamic_route:
    type: action
    actions:
      - type: dynamic_route
        action: "${computed.matched_action}"
    on_success: "${computed.dynamic_target}"  # DYNAMIC!
    on_failure: show_main_menu

  # Fallback menu
  show_main_menu:
    type: user_prompt
    prompt:
      question: "What would you like to do?"
      header: "Menu"
      options:
        - id: init
          label: "Initialize"
          description: "Create new project"
        - id: build
          label: "Build"
          description: "Build the project"
        - id: refresh
          label: "Refresh"
          description: "Sync with upstream"
    on_response:
      init:
        consequence:
          - type: set_state
            field: computed.matched_action
            value: "delegate_init"
        next_node: execute_dynamic_route
      build:
        consequence:
          - type: set_state
            field: computed.matched_action
            value: "delegate_build"
        next_node: execute_dynamic_route
      refresh:
        consequence:
          - type: set_state
            field: computed.matched_action
            value: "delegate_refresh"
        next_node: execute_dynamic_route

  # Delegate nodes (one per skill)
  delegate_init:
    type: action
    actions:
      - type: invoke_skill
        skill: "my-plugin-init"
    on_success: success
    on_failure: error_skill_failed

  delegate_build:
    type: action
    actions:
      - type: invoke_skill
        skill: "my-plugin-build"
    on_success: success
    on_failure: error_skill_failed

  delegate_refresh:
    type: action
    actions:
      - type: invoke_skill
        skill: "my-plugin-refresh"
    on_success: success
    on_failure: error_skill_failed

endings:
  success:
    type: success
    message: "Operation completed"

  error_loading_config:
    type: error
    message: "Failed to load intent configuration"

  error_skill_failed:
    type: error
    message: "Skill execution failed"
```

## Adding a New Skill

With dynamic routing, add:

1. **Flag** in `intent-mapping.yaml`:
   ```yaml
   wants_new_feature:
     keywords: ["new feature", "add feature"]
   ```

2. **Rule** in `intent-mapping.yaml`:
   ```yaml
   - name: "new_feature"
     conditions: { wants_new_feature: T }
     action: "delegate_new_feature"
     priority: 85
   ```

3. **Delegate node** in `workflow.yaml`:
   ```yaml
   delegate_new_feature:
     type: action
     actions:
       - type: invoke_skill
         skill: "my-plugin-new-feature"
     on_success: success
     on_failure: error_skill_failed
   ```

**No conditional cascade updates!**

## Comparison

| Aspect | O(N) Cascade | O(1) Dynamic |
|--------|--------------|--------------|
| Routing nodes | One per skill | One total |
| Add skill | Add conditional | Add delegate only |
| YAML lines | ~10 per skill | Constant |
| Testing | All branches | Single path |
| Maintenance | Grows with skills | Constant |

## Disambiguation

When multiple rules match with similar scores, show disambiguation:

```yaml
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
      next_node: execute_dynamic_route
```

## Best Practices

1. **Keyword overlap:** Avoid keywords that match multiple flags
2. **Priority ordering:** Higher priority = more specific rules
3. **Fallback action:** Always define a fallback
4. **Testing:** Test with varied user inputs
5. **Disambiguation threshold:** Configure when to show clarification

## Next Steps

- [Workflow Authoring Guide](workflow-authoring-guide.md) - Node types and state
- [Getting Started](getting-started.md) - Gateway generation via skill
