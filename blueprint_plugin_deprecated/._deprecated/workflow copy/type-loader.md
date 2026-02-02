# Type Loader Protocol

This document specifies how workflow type definitions (consequences and preconditions) are loaded and resolved at workflow initialization.

---

## Overview

Workflows reference type definitions via the `definitions` block:

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

nodes:
  my_node:
    type: action
    actions:
      - type: clone_repo          # Resolved from definitions
        url: "${source_url}"
```

The type loader resolves these definitions before workflow execution begins.

---

## Loading Algorithm

```
FUNCTION load_types(definitions_block):
    # 1. Parse source
    source = definitions_block.source
    parts = parse_source(source)  # {owner, repo, version}

    # 2. Construct base URL
    base_url = "https://raw.githubusercontent.com/{parts.owner}/{parts.repo}/{parts.version}/"

    # 3. Fetch index files
    consequences_index = fetch(base_url + "consequences/index.yaml")
    preconditions_index = fetch(base_url + "preconditions/index.yaml")

    # 4. Build registry from indexes
    registry = build_registry(consequences_index, preconditions_index)

    # 5. Load extensions
    IF definitions_block.extensions:
        FOR each ext IN definitions_block.extensions:
            ext_registry = load_types({ source: ext })
            registry = merge_registry(registry, ext_registry)

    RETURN registry
```

---

## Source Format

The loader supports GitHub shorthand format:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
```

### Source Parsing

```
FUNCTION parse_source(source):
    # Parse: owner/repo@version
    match = source.match(/^([^\/]+)\/([^@]+)@(.+)$/)
    RETURN {
        owner: match[1],
        repo: match[2],
        version: match[3]
    }
```

### URL Construction

```
FUNCTION construct_base_url(owner, repo, version):
    RETURN "https://raw.githubusercontent.com/{owner}/{repo}/{version}/"
```

**Version formats:**

| Format | Example | Behavior |
|--------|---------|----------|
| Exact | `@v2.0.0` | Use exact version (recommended) |
| Minor | `@v2.0` | Latest patch in v2.0.x |
| Major | `@v2` | Latest minor in v2.x.x |

**Note:** Use exact versions for reproducibility.

---

## Fetching

### Fetch Function

```
FUNCTION fetch(url):
    # Use WebFetch tool
    response = CALL WebFetch with:
        url: url
        prompt: "Return the raw YAML content"

    IF response.status >= 400:
        THROW "Failed to fetch types: {response.status} {url}"

    # Handle redirects
    IF response.redirect_url:
        RETURN fetch(response.redirect_url)

    RETURN parse_yaml(response.content)
```

### Fetch Order

1. Fetch `consequences/index.yaml` - type lookup table
2. Fetch `preconditions/index.yaml` - type lookup table
3. For each type referenced in workflow, fetch individual definition file on demand

---

## Index Format

Type definitions use index files for lookup:

```yaml
# consequences/index.yaml
schema_version: "1.1"

type_lookup:
  set_flag: core/state
  set_state: core/state
  clone_repo: extensions/git
  # ... all types

categories:
  core/state:
    description: State mutation operations
    types: [set_flag, set_state, append_state, ...]
```

### Individual Type Files

```yaml
# consequences/core/state.yaml
types:
  set_flag:
    category: core/state
    description:
      brief: Set boolean flag
    parameters:
      - name: flag
        type: string
        required: true
      - name: value
        type: boolean
        required: true
    payload:
      kind: state_mutation
      effect: "state.flags[flag] = value"
    since: "1.0.0"
```

---

## Registry Building

```
FUNCTION build_registry(consequences_index, preconditions_index):
    registry = {
        consequences: {},
        preconditions: {}
    }

    # Build type lookup from indexes
    FOR each type_name, category IN consequences_index.type_lookup:
        registry.consequences[type_name] = {
            category: category,
            loaded: false  # Lazy load full definition
        }

    FOR each type_name, category IN preconditions_index.type_lookup:
        registry.preconditions[type_name] = {
            category: category,
            loaded: false
        }

    RETURN registry
```

### Lazy Loading

Full type definitions are loaded on first use:

```
FUNCTION get_type_definition(registry, type_name, base_url):
    entry = registry.consequences[type_name]

    IF NOT entry.loaded:
        # Construct path: core/state -> consequences/core/state.yaml
        category_path = entry.category.replace("/", "/")
        url = base_url + "consequences/" + category_path + ".yaml"

        definitions = fetch(url)
        entry.definition = definitions.types[type_name]
        entry.loaded = true

    RETURN entry.definition
```

---

## Extension Loading

Multiple type sources can be combined:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
  extensions:
    - mycorp/custom-types@v1.0.0
```

### Merge Strategy

```
FUNCTION merge_registry(base, extension):
    result = copy(base)

    FOR each type_name, entry IN extension.consequences:
        IF type_name IN result.consequences:
            # Collision - require namespace prefix
            namespaced_name = "{extension.source}:{type_name}"
            result.consequences[namespaced_name] = entry
        ELSE:
            result.consequences[type_name] = entry

    FOR each type_name, entry IN extension.preconditions:
        IF type_name IN result.preconditions:
            namespaced_name = "{extension.source}:{type_name}"
            result.preconditions[namespaced_name] = entry
        ELSE:
            result.preconditions[type_name] = entry

    RETURN result
```

### Using Namespaced Types

When collisions exist:

```yaml
nodes:
  my_action:
    type: action
    actions:
      # Base type (unambiguous)
      - type: set_flag
        flag: ready
        value: true

      # Namespaced type (collision resolved)
      - type: mycorp/custom-types:clone_repo
        url: "${internal_repo}"
```

---

## Validation

### Workflow Type Validation

After loading, verify all workflow types exist:

```
FUNCTION validate_workflow_types(workflow, registry):
    # Check all consequence types in action nodes
    FOR each node IN workflow.nodes:
        IF node.type == "action":
            FOR each action IN node.actions:
                IF action.type NOT IN registry.consequences:
                    THROW "Unknown consequence type: {action.type}"

        IF node.type == "conditional":
            validate_precondition_type(node.condition, registry)

        IF node.type == "validation_gate":
            FOR each validation IN node.validations:
                validate_precondition_type(validation, registry)

    # Check entry preconditions
    FOR each precondition IN workflow.entry_preconditions:
        validate_precondition_type(precondition, registry)
```

---

## Error Messages

Provide clear, actionable errors:

```
Error: Failed to resolve type definitions

Source: hiivmind/hiivmind-blueprint-lib@v2.0.0
URL: https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/consequences/index.yaml
Error: 404 Not Found

Suggestions:
- Check the version exists: https://github.com/hiivmind/hiivmind-blueprint-lib/tags
- Verify network connectivity
```

```
Error: Unknown consequence type: docker_build

This type is not in the loaded definitions.

Loaded from: hiivmind/hiivmind-blueprint-lib@v2.0.0 (43 consequences)

Suggestions:
- Check for typos in the type name
- Add an extension with this type:
    definitions:
      source: hiivmind/hiivmind-blueprint-lib@v2.0.0
      extensions:
        - mycorp/docker-types@v1.0.0
- Define a custom consequence in your plugin
```

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine that uses loaded types
- **Workflow Loader:** `lib/workflow/workflow-loader.md` - Workflow loading protocol (v1.2+)
- **Logging Config Loader:** `lib/workflow/logging-config-loader.md` - Logging configuration loading protocol (v1.3+)
- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - Resolution protocol details
