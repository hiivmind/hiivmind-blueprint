# Workflow Loader Protocol

This document specifies how reusable workflows are loaded and resolved at execution time. Workflows can be referenced from remote bundles, enabling distributed, composable workflow ecosystems.

---

## Overview

Workflows can reference reusable sub-workflows via the `reference` node type:

```yaml
# workflow.yaml
nodes:
  detect_intent:
    type: reference
    workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
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

    # 2. Check cache
    cache_key = compute_workflow_cache_key(source)
    cached = check_workflow_cache(cache_key)
    IF cached AND NOT is_stale(cached):
        RETURN cached.content

    # 3. Load bundle (reuse type loader)
    bundle = load_types({ source: source.base_ref })

    # 4. Extract workflow
    IF source.workflow_name NOT IN bundle.workflows:
        THROW "Workflow not found: {source.workflow_name} in {source.base_ref}"

    workflow_def = bundle.workflows[source.workflow_name]

    # 5. Parse and validate workflow content
    workflow = parse_yaml(workflow_def.content)
    validate_workflow(workflow)

    # 6. Update cache
    write_workflow_cache(cache_key, workflow_def)

    RETURN workflow
```

---

## Reference Parsing

### Workflow Reference Format

```
{owner}/{repo}@{version}:{workflow-name}
```

**Examples:**
- `hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection`
- `mycorp/custom-workflows@v2.0.0:validation-pipeline`

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

## Bundle Format Extension

Type bundles can include a `workflows` section:

```yaml
# bundle.yaml
schema_version: "1.2"  # Bump for workflow support

consequences:
  # ... existing types

preconditions:
  # ... existing types

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
    content: |
      # Full workflow YAML embedded here
      name: intent-detection
      version: "1.0.0"
      ...
```

### Workflow Definition Fields

| Field | Required | Description |
|-------|----------|-------------|
| `version` | Yes | Workflow version (semver) |
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
| `content` | Yes | Full workflow YAML (embedded) |

---

## Caching

### Cache Location

```
~/.claude/cache/hiivmind/blueprint/
├── types/                              # Existing type cache
│   └── {owner}/{repo}/{version}/
│       ├── bundle.yaml
│       └── metadata.yaml
├── workflows/                          # NEW: Workflow cache
│   └── {owner}/{repo}/{version}/
│       └── {workflow-name}/
│           ├── workflow.yaml           # Extracted workflow content
│           └── metadata.yaml           # Extraction metadata
└── engine/
    └── {version}/
        └── engine.md
```

### Cache Key Computation

```
FUNCTION compute_workflow_cache_key(source):
    RETURN "workflows/{source.owner}/{source.repo}/{source.version}/{source.workflow_name}"
```

### Metadata Format

```yaml
# metadata.yaml
bundle_source: "hiivmind/hiivmind-blueprint-lib@v1.0.0"
workflow_name: "intent-detection"
workflow_version: "1.0.0"
extracted_at: "2026-01-28T10:30:00Z"
bundle_sha256: "abc123..."
depends_on:
  consequences:
    - parse_intent_flags
    - match_3vl_rules
    - set_state
    - dynamic_route
```

### Staleness Check

```
FUNCTION is_workflow_stale(cached, source):
    # Same logic as type loader - exact versions never stale
    IF source.version matches /^v\d+\.\d+\.\d+$/:
        RETURN false

    # Check freshness for non-exact versions
    age = now() - cached.extracted_at
    IF age > 24 hours:
        RETURN true

    RETURN false
```

---

## Dependency Validation

When loading a workflow, validate that all required types exist:

```
FUNCTION validate_workflow_dependencies(workflow_def, type_registry):
    IF workflow_def.depends_on:
        # Check consequences
        FOR each type_name IN workflow_def.depends_on.consequences:
            IF type_name NOT IN type_registry.consequences:
                THROW "Workflow requires missing consequence type: {type_name}"

        # Check preconditions
        FOR each type_name IN workflow_def.depends_on.preconditions:
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
  workflow: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
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
      skill: hiivmind/hiivmind-blueprint-lib@v1.0.0:intent-detection
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

## Fallback Strategies

### Remote Fetch Failure

When remote workflow fetch fails, apply fallback based on `fallback` setting:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1.0.0
  fallback: warn  # or "error" or "embedded"
```

| Value | Behavior |
|-------|----------|
| `error` | Fail immediately if fetch fails |
| `warn` | Log warning, try cache, then embedded |
| `embedded` | Silently use embedded workflows |

### Embedded Workflows

Embedded workflows are stored at:

```
{plugin_root}/lib/workflows/
├── intent-detection.yaml
├── validation-pipeline.yaml
└── ...
```

```
FUNCTION get_embedded_workflow(workflow_name, plugin_root):
    path = "{plugin_root}/lib/workflows/{workflow_name}.yaml"
    IF file_exists(path):
        RETURN parse_yaml(read_file(path))
    THROW "Embedded workflow not found: {workflow_name}"
```

---

## Version Pinning

### Lock File Support

Workflow versions can be pinned in `.hiivmind/blueprint/types.lock`:

```yaml
# .hiivmind/blueprint/types.lock
schema: "1.0"
generated_at: "2026-01-28T12:00:00Z"
generated_by: "hiivmind-blueprint v1.2.0"

engine:
  version: "1.2.0"
  sha256: "abc123..."

types:
  hiivmind/hiivmind-blueprint-lib:
    requested: "@v1"
    resolved: "v1.2.0"
    sha256: "def456..."

workflows:                              # NEW: Workflow pins
  hiivmind/hiivmind-blueprint-lib:
    intent-detection:
      resolved: "v1.0.0"
      sha256: "ghi789..."
```

### Lock File Resolution

```
FUNCTION resolve_workflow_with_lock(ref, lock_file_path):
    lock_file = read_yaml(lock_file_path)
    source = parse_workflow_reference(ref)

    IF lock_file.workflows:
        bundle_entry = lock_file.workflows[source.base_ref]
        IF bundle_entry AND bundle_entry[source.workflow_name]:
            workflow_entry = bundle_entry[source.workflow_name]
            # Verify SHA if cached
            cached = check_workflow_cache(source)
            IF cached AND sha256(cached) == workflow_entry.sha256:
                RETURN cached

    # No lock or mismatch - resolve normally
    RETURN load_workflow(ref)
```

---

## Error Messages

Provide clear, actionable errors:

```
Error: Workflow not found in bundle

Reference: hiivmind/hiivmind-blueprint-lib@v1.0.0:my-workflow
Bundle URL: https://github.com/hiivmind/hiivmind-blueprint-lib/releases/download/v1.0.0/bundle.yaml

Available workflows in this bundle:
- intent-detection (v1.0.0)
- validation-pipeline (v1.0.0)

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

Loaded types: hiivmind/hiivmind-blueprint-lib@v0.9.0 (35 consequences)
Required types: 43 consequences (workflow needs v1.0.0+)

Suggestions:
- Update type definitions to v1.0.0 or later
- Add an extension with the missing type
```

---

## Related Documentation

- **Type Loader:** `lib/workflow/type-loader.md` - Type resolution protocol
- **Engine:** `lib/workflow/engine.md` - Execution engine with reference node support
- **Intent Composition:** `lib/blueprint/patterns/intent-composition.md` - Usage patterns
- **Reusable Workflow:** `lib/workflows/intent-detection.yaml` - Local reference
