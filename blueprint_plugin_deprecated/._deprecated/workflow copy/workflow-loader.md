# Workflow Loader Protocol

This document specifies how reusable workflows are loaded and resolved at execution time. Workflows can be referenced from remote repositories, enabling distributed, composable workflow ecosystems.

---

## Overview

Workflows can reference reusable sub-workflows via the `reference` node type:

```yaml
# workflow.yaml
nodes:
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
    context:
      arguments: "${arguments}"
      intent_flags: "${intent_flags}"
    next_node: execute_dynamic_route
```

The workflow loader resolves these references before or during execution.

---

## Loading Algorithm

```
FUNCTION load_workflow(workflow_ref):
    # 1. Parse reference
    source = parse_workflow_reference(workflow_ref)

    # 2. Construct raw URL
    base_url = "https://raw.githubusercontent.com/{source.owner}/{source.repo}/{source.version}/"

    # 3. Fetch workflow index
    index_url = base_url + "workflows/index.yaml"
    index = fetch(index_url)

    # 4. Verify workflow exists
    IF source.workflow_name NOT IN index.workflows:
        THROW "Workflow not found: {source.workflow_name} in {source.base_ref}"

    # 5. Fetch workflow content
    workflow_info = index.workflows[source.workflow_name]
    workflow_url = base_url + "workflows/" + workflow_info.path
    workflow = fetch(workflow_url)

    # 6. Validate workflow
    validate_workflow(workflow)

    RETURN workflow
```

---

## Reference Parsing

### Workflow Reference Format

```
{owner}/{repo}@{version}:{workflow-name}
```

**Examples:**
- `hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection`
- `mycorp/custom-workflows@v1.0.0:validation-pipeline`

### Parsing Logic

```
FUNCTION parse_workflow_reference(ref):
    # Parse: owner/repo@version:workflow-name
    match = ref.match(/^([^\/]+)\/([^@]+)@([^:]+):(.+)$/)

    IF NOT match:
        THROW "Invalid workflow reference format: {ref}"

    RETURN {
        owner: match[1],
        repo: match[2],
        version: match[3],
        workflow_name: match[4],
        base_ref: "{match[1]}/{match[2]}@{match[3]}"
    }
```

### Local Workflow References

For local workflows, use the `doc` parameter instead:

```yaml
detect_intent:
  type: reference
  doc: "lib/workflows/intent-detection.yaml"
  context:
    arguments: "${arguments}"
  next_node: execute_dynamic_route
```

---

## Workflow Index Format

The workflow repository contains an index file listing available workflows:

```yaml
# workflows/index.yaml
schema_version: "2.0"

workflows:
  intent-detection:
    version: "1.0.0"
    path: "core/intent-detection.yaml"
    description: "3VL intent detection with dynamic routing"
    depends_on:
      consequences:
        - parse_intent_flags
        - match_3vl_rules
        - set_state
        - dynamic_route
      preconditions:
        - evaluate_expression
    inputs:
      - name: arguments
        type: string
        required: true
        description: "User input to parse"
      - name: intent_flags
        type: object
        required: true
        description: "Flag definitions from intent-mapping.yaml"
      - name: intent_rules
        type: array
        required: true
        description: "Rules from intent-mapping.yaml"
      - name: fallback_action
        type: string
        required: false
        default: "show_main_menu"
        description: "Action when no rules match"
    outputs:
      - name: computed.matched_action
        type: string
        description: "The resolved action to execute"
      - name: computed.intent_flags
        type: object
        description: "Parsed 3VL flag values"
      - name: computed.intent_matches
        type: object
        description: "Match results with winner and candidates"
```

### Workflow Definition Fields

| Field | Required | Description |
|-------|----------|-------------|
| `version` | Yes | Workflow version (semver) |
| `path` | Yes | Path to workflow file relative to workflows/ |
| `description` | Yes | What the workflow does |
| `depends_on` | No | Type dependencies (for validation) |
| `depends_on.consequences` | No | Required consequence types |
| `depends_on.preconditions` | No | Required precondition types |
| `inputs` | Yes | Input parameters |
| `inputs[].name` | Yes | Parameter name |
| `inputs[].type` | Yes | Parameter type |
| `inputs[].required` | Yes | Is required |
| `inputs[].default` | No | Default value if not required |
| `inputs[].description` | Yes | Parameter description |
| `outputs` | Yes | Output fields |
| `outputs[].name` | Yes | Output field path |
| `outputs[].type` | Yes | Output type |
| `outputs[].description` | Yes | Output description |

---

## Dependency Validation

When loading a workflow, validate that all required types exist:

```
FUNCTION validate_workflow_dependencies(workflow_info, type_registry):
    IF workflow_info.depends_on:
        # Check consequences
        FOR each type_name IN workflow_info.depends_on.consequences:
            IF type_name NOT IN type_registry.consequences:
                THROW "Workflow requires missing consequence type: {type_name}"

        # Check preconditions
        FOR each type_name IN workflow_info.depends_on.preconditions:
            IF type_name NOT IN type_registry.preconditions:
                THROW "Workflow requires missing precondition type: {type_name}"
```

---

## Execution: Reference Node with Remote Workflow

When the engine encounters a reference node with a `workflow` parameter:

```
FUNCTION execute_reference_node(node, types, state):
    IF node.workflow:
        # Remote workflow reference
        workflow = load_workflow(node.workflow)
    ELSE IF node.doc:
        # Local file reference
        workflow = parse_yaml(read_file(node.doc))
    ELSE:
        THROW "Reference node requires 'workflow' or 'doc' parameter"

    # Build context with interpolation
    context = {}
    FOR each key, value IN node.context:
        context[key] = interpolate(value, state)

    # Merge context into state (for shared state execution)
    FOR each key, value IN context:
        state[key] = value

    # Execute the referenced workflow
    # Note: State is SHARED - the workflow can read/write parent state
    execute_workflow(workflow, types, state)

    # Resolve next node (supports dynamic interpolation)
    target = resolve_routing_target(node.next_node, state)

    RETURN { next_node: target }
```

---

## Input/Output Mapping

### Inputs

Inputs are mapped from parent state via the `context` parameter:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"           # Maps state.arguments
    intent_flags: "${intent_flags}"     # Maps state.intent_flags
    intent_rules: "${intent_rules}"     # Maps state.intent_rules
    fallback_action: "show_main_menu"   # Literal value
  next_node: execute_dynamic_route
```

### Outputs

Since reference nodes share state, outputs are automatically available in the parent:

```yaml
# After intent-detection workflow completes:
# - state.computed.matched_action is set
# - state.computed.intent_flags is set
# - state.computed.intent_matches is set

# Parent workflow can use these directly:
execute_dynamic_route:
  type: action
  actions:
    - type: dynamic_route
      action: "${computed.matched_action}"
  on_success: "${computed.dynamic_target}"
  on_failure: show_main_menu
```

For isolated execution with explicit output mapping, use `invoke_skill` instead:

```yaml
detect_intent:
  type: action
  actions:
    - type: invoke_skill
      skill: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
      input:
        arguments: "${arguments}"
        intent_flags: "${intent_flags}"
        intent_rules: "${intent_rules}"
      output_mapping:
        - from: computed.matched_action
          to: computed.resolved_action
  on_success: execute_dynamic_route
  on_failure: show_main_menu
```

---

## Version Pinning

Use exact versions for reproducible builds:

| Reference | Behavior |
|-----------|----------|
| `@v2.0.0` | Exact version (recommended for production) |
| `@v2.0` | Latest patch in v2.0.x |
| `@v2` | Latest minor in v2.x.x (development) |

---

## Error Messages

Provide clear, actionable errors:

```
Error: Workflow not found

Reference: hiivmind/hiivmind-blueprint-lib@v2.0.0:my-workflow
URL: https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/workflows/index.yaml

Available workflows in this version:
- intent-detection (v1.0.0)

Suggestions:
- Check the workflow name for typos
- Verify the workflow exists in the specified version
- Check available workflows: https://github.com/hiivmind/hiivmind-blueprint-lib/releases
```

```
Error: Workflow dependency missing

Workflow: intent-detection@v1.0.0
Missing consequence type: parse_intent_flags

The workflow requires consequence types that are not in the loaded type registry.

Loaded types: hiivmind/hiivmind-blueprint-lib@v1.0.0 (35 consequences)
Required types: 43 consequences (workflow needs v2.0.0+)

Suggestions:
- Update type definitions to v2.0.0 or later
- Add an extension with the missing type
```

---

## Related Documentation

- **Type Loader:** `lib/workflow/type-loader.md` - Type resolution protocol
- **Engine:** `lib/workflow/engine.md` - Execution engine with reference node support
- **Intent Composition:** `lib/blueprint/patterns/intent-composition.md` - Usage patterns
- **Reusable Workflow:** `lib/workflows/intent-detection.yaml` - Local reference
