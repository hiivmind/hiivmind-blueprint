# Distributed Composable Workflows - Architecture Design

## Goal

Create an ecosystem of distributed, composable, reusable workflows that can be fetched from remote sources, cached, and referenced by any plugin - similar to how types work today.

---

## Status

- ✅ Dynamic routing implemented in engine.md
- ✅ intent-detection.yaml created locally
- 🔲 Need to design distributed workflow loading system
- 🔲 Need to decide repository structure

---

## Architectural Options

### Option A: Extend hiivmind-blueprint-lib

Add a `workflows/` section to the existing bundle:

```yaml
# bundle.yaml structure
schema_version: "1.2"

consequences:
  # ... 43 types
preconditions:
  # ... 27 types
workflows:
  intent-detection:
    version: "1.0.0"
    description: "3VL intent detection with dynamic routing"
    inputs: [arguments, intent_flags, intent_rules, fallback_action]
    outputs: [computed.matched_action]
    content: |
      # Full workflow YAML embedded
```

**Pros:**
- Single source of truth for all reusable components
- Existing versioning/caching infrastructure
- Types and workflows often used together

**Cons:**
- Mixes semantic definitions (types) with implementations (workflows)
- Larger bundle downloads

### Option B: New Repository (hiivmind-blueprint-workflows)

Separate repo for workflow library:

```
hiivmind-blueprint-workflows/
├── bundle.yaml               # Workflow index
├── workflows/
│   ├── intent-detection.yaml
│   ├── file-processing.yaml
│   └── validation-pipeline.yaml
└── README.md
```

**Reference in gateway:**
```yaml
includes:
  - source: hiivmind/hiivmind-blueprint-workflows@v1.0.0
    workflows:
      - intent-detection
```

**Pros:**
- Clean separation (types ≠ workflows)
- Independent versioning cadence
- Workflows may evolve faster

**Cons:**
- Third repo to manage
- Users fetch from multiple sources

### Option C: Unified Library (hiivmind-blueprint-lib)

Rename blueprint-types to a broader "library" concept:

```
hiivmind-blueprint-lib/
├── types/
│   ├── consequences/
│   └── preconditions/
├── workflows/
│   ├── intent-detection.yaml
│   └── validation-pipeline.yaml
└── bundle.yaml
```

**Pros:**
- Conceptually clean: "library of reusable components"
- Single version for compatible types + workflows

**Cons:**
- Breaking change to existing blueprint-types references
- Migration needed

---

## Decision: Extend blueprint-types ✅

**Rationale:**
1. **Simplest path** - No new repos, no migrations
2. **Types and workflows are coupled** - intent-detection.yaml uses `parse_intent_flags`, `match_3vl_rules`, etc.
3. **Version coherence** - When types change, workflows may need updates too
4. **Single fetch** - One bundle download gives you everything

The original "types only" scope was a reasonable starting point, but the ecosystem has matured to support workflows as first-class citizens.

---

## Implementation Plan

### Phase 1: Workflow Loader Protocol

Create `lib/workflow/workflow-loader.md` (similar to type-loader.md):

```
FUNCTION load_workflow(workflow_ref):
    # Parse: owner/repo@version:workflow-name
    source = parse_workflow_reference(workflow_ref)

    # Check cache
    cache_key = "{source.owner}/{source.repo}/{source.version}/workflows/{source.name}"
    cached = check_cache(cache_key)
    IF cached AND NOT is_stale(cached):
        RETURN cached.content

    # Fetch bundle (reuse type loader infrastructure)
    bundle = load_types({ source: source.base })

    # Extract workflow
    IF source.name NOT IN bundle.workflows:
        THROW "Workflow not found: {source.name}"

    workflow_def = bundle.workflows[source.name]
    RETURN parse_yaml(workflow_def.content)
```

### Phase 2: Engine Enhancement for Workflow References

Update the `reference` node type in engine.md to support remote workflows:

```yaml
# Current (local only)
detect_intent:
  type: reference
  doc: "lib/workflows/intent-detection.yaml"
  next_node: execute_dynamic_route

# New (remote support)
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
  # OR inline for local
  doc: "./workflows/intent-detection.yaml"
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
  next_node: execute_dynamic_route
```

### Phase 3: Bundle Format Extension

Add `workflows` section to bundle.yaml:

```yaml
# In hiivmind-blueprint-lib bundle.yaml
schema_version: "1.2"  # Bump for workflows support

consequences:
  # ... existing 43 types

preconditions:
  # ... existing 27 types

workflows:
  intent-detection:
    version: "1.0.0"
    description: "3VL intent detection with dynamic routing"
    depends_on:
      consequences:
        - parse_intent_flags
        - match_3vl_rules
        - set_state
        - dynamic_route
    inputs:
      - name: arguments
        required: true
        description: "User input to parse"
      - name: intent_flags
        required: true
        description: "Flag definitions from intent-mapping.yaml"
      - name: intent_rules
        required: true
        description: "Rules from intent-mapping.yaml"
      - name: fallback_action
        required: false
        default: "show_main_menu"
    outputs:
      - name: computed.matched_action
        description: "The action to execute"
    content: |
      name: intent-detection
      version: "1.0.0"
      # ... full workflow YAML
```

### Phase 4: Cache Structure

Extend existing cache:

```
~/.claude/cache/hiivmind/blueprint/
├── types/
│   └── {owner}/{repo}/{version}/
│       ├── bundle.yaml
│       └── metadata.yaml
├── workflows/                          # NEW
│   └── {owner}/{repo}/{version}/
│       └── {workflow-name}.yaml
└── engine/
    └── {version}/
```

### Phase 5: Update intent-detection.yaml

Move from `lib/workflows/` to `hiivmind-blueprint-lib`:

```
hiivmind-blueprint-lib/
├── workflows/
│   └── intent-detection.yaml
├── consequences/
│   └── ...
├── preconditions/
│   └── ...
└── bundle.yaml  # Now includes workflows section
```

---

## Files to Create/Modify

### In hiivmind-blueprint:

| File | Change |
|------|--------|
| `lib/workflow/engine.md` | Add remote workflow reference support to `reference` node |
| `lib/workflow/workflow-loader.md` | NEW: Workflow loading protocol |
| `lib/intent_detection/execution.md` | Add build-time documentation notice |
| `lib/workflows/intent-detection.yaml` | Move to blueprint-types (after phase 5) |

### In hiivmind-blueprint-lib:

| File | Change |
|------|--------|
| `bundle.yaml` | Add `workflows` section, bump schema_version to 1.2 |
| `workflows/intent-detection.yaml` | NEW: Moved from blueprint |
| `README.md` | Document workflow references |

---

## Verification

1. Reference a remote workflow in a test gateway
2. Verify caching works (second load hits cache)
3. Verify version pinning in types.lock includes workflows
4. Test offline mode with embedded fallback
5. Document the pattern in intent-composition.md

---

## Previous Implementation (Complete)

- ✅ `lib/workflow/engine.md` - Dynamic `on_success`/`on_failure` interpolation
- ✅ `lib/workflows/intent-detection.yaml` - Local sub-workflow (to be moved)
- ✅ `templates/gateway-command.md.template` - Dynamic routing template
- ✅ `lib/blueprint/patterns/intent-composition.md` - Pattern documentation
- ✅ `lib/intent_detection/execution.md` - Dynamic routing section

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



The implementation is complete. Let me provide a summary of what was created and modified.

  Summary

  I've implemented the distributed composable workflows architecture as specified in the plan. Here's what was created and modified:

  New Files Created

  1. lib/workflow/workflow-loader.md - Complete workflow loading protocol specification including:
    - Reference parsing (owner/repo@version:workflow-name format)
    - Cache structure (~/.claude/cache/hiivmind/blueprint/workflows/)
    - Bundle format extension for workflows
    - Input/output mapping
    - Fallback strategies
    - Version pinning with lock file support

  Modified Files

  2. lib/workflow/engine.md - Enhanced the reference node type to support:
    - Remote workflow references via workflow: parameter
    - Local file references via doc: parameter (existing)
    - Updated execution function to handle both sources
    - Added Related Documentation links
  3. lib/types/bundle.yaml - Extended bundle format:
    - Bumped schema_version to 1.2
    - Added workflows: section with intent-detection workflow embedded
    - Updated stats section to include total_workflows: 1
  4. lib/workflow/type-loader.md - Updated cache documentation:
    - Added workflows cache structure
    - Added workflow metadata format
    - Added reference to workflow-loader.md
  5. lib/intent_detection/execution.md - Added distributed workflow support section:
    - Migration path from local to remote
    - Benefits of remote workflows
    - Usage examples
  6. lib/blueprint/patterns/intent-composition.md - Updated with three options:
    - Option 1: Remote workflow reference (recommended v1.2+)
    - Option 2: Local file reference
    - Option 3: Invoke as skill (state isolated)
    - Comparison table
  7. lib/types/README.md - Updated type inventory:
    - Added workflows section documenting intent-detection
    - Updated bundle.yaml description
  8. CLAUDE.md - Updated architecture documentation:
    - Added workflow-loader.md to file tree
    - Updated bundle.yaml description
    - Updated Type Inventory to v1.2.0 with workflows count
    - Added "Referencing Remote Workflows" section
  9. templates/gateway-command.md.template - Added:
    - Reference to workflow-loader.md
    - Alternative section showing remote intent detection workflow usage

  Key Features Implemented
  ┌──────────────────────────────────────────────────────────────┬────────┐
  │                           Feature                            │ Status │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Workflow reference format (owner/repo@version:workflow-name) │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Remote workflow loading protocol                             │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Cache structure for workflows                                │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Bundle format with workflows: section                        │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Engine support for remote workflow: references               │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Intent-detection workflow in bundle                          │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Documentation updates                                        │ ✅     │
  ├──────────────────────────────────────────────────────────────┼────────┤
  │ Lock file support for workflows                              │ ✅     │
  └──────────────────────────────────────────────────────────────┴────────┘
