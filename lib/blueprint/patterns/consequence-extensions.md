# Consequence Extensions Meta-Pattern

Guidance for plugins converted by hiivmind-blueprint that need domain-specific consequence types beyond the standard core and extension sets.

---

## When to Use Extensions vs Core

### Use Core Consequences When:

- The operation is workflow-engine intrinsic (state mutation, control flow)
- The operation is domain-agnostic (works across any plugin)
- The operation doesn't depend on plugin-specific configuration

**Core examples:** `set_flag`, `evaluate`, `compute`, `display_message`

### Use Generic Extensions When:

- The operation is common across many plugins
- The operation doesn't require plugin-specific knowledge
- Standard file, git, or web operations

**Generic extension examples:** `read_file`, `clone_repo`, `web_fetch`

### Create Custom Extensions When:

- The operation is specific to your plugin's domain
- The operation requires plugin-specific configuration or state
- You need to encapsulate complex domain logic

**Custom extension examples:**
- hiivmind-corpus: `read_config`, `add_source`, `update_source`, `discover_installed_corpora`
- GitHub plugin: `create_issue`, `merge_pr`, `add_label`
- Database plugin: `execute_query`, `migrate_schema`

---

## Extension Locations

Custom consequences can live in three locations:

| Location | When to Use |
|----------|-------------|
| **hiivmind-blueprint-lib** | Common extensions useful across many plugins (contribute via PR) |
| **Local to your plugin** | Plugin-specific operations not reusable elsewhere |
| **Dedicated extension library** | Domain-specific extensions shared by related plugins (e.g., `myorg/blueprint-database-extensions`) |

---

## Extension File Format

All consequence definitions use YAML format matching the hiivmind-blueprint-lib schema.

**Schema Reference:** `hiivmind/hiivmind-blueprint-lib@v2.0.0/schema/consequence-definition.json`

### Structure

```yaml
# consequences/my-domain.yaml
schema_version: "1.0"

consequences:
  - type: my_custom_action
    description: Brief description of what this does
    category: domain/subcategory

    parameters:
      - name: required_param
        type: string
        required: true
        description: What this parameter does

      - name: optional_param
        type: string
        required: false
        default: "default_value"
        description: Optional parameter description

    payload:
      tool: Bash  # or Read, Write, Edit, etc.
      template: |
        # Command template with ${param} interpolation
        my-cli --input "${required_param}" --opt "${optional_param}"

    # OR for computed results:
    evaluation:
      expression: "custom_logic(${required_param})"
      store_as: computed.result
```

### Example: Domain-Specific Extension

```yaml
# consequences/corpus-config.yaml
schema_version: "1.0"

consequences:
  - type: read_config
    description: Read and parse corpus config.yaml
    category: corpus/config

    parameters:
      - name: path
        type: string
        required: false
        default: "data/config.yaml"
        description: Path to config file (defaults to corpus standard location)

      - name: store_as
        type: string
        required: true
        description: State path to store parsed config

    payload:
      tool: Read
      template: "${path}"

    post_process:
      parse: yaml
      store_as: "${store_as}"

  - type: add_source
    description: Add a source entry to corpus config
    category: corpus/config

    parameters:
      - name: source_id
        type: string
        required: true
        description: Unique identifier for the source

      - name: source_type
        type: enum
        values: [git, local, web]
        required: true
        description: Type of source

      - name: url
        type: string
        required: false
        description: URL for git or web sources

    payload:
      tool: Edit
      # Implementation details...
```

---

## Integrating Custom Extensions

### Option 1: Contribute to hiivmind-blueprint-lib

For extensions useful across many plugins:

1. Fork `hiivmind/hiivmind-blueprint-lib`
2. Add definition file to `consequences/extensions/`
3. Update `consequences/index.yaml` with new types
4. Submit PR with tests and documentation

### Option 2: Local Plugin Extensions

For plugin-specific operations:

```
{your-plugin}/
├── consequences/
│   └── {domain}.yaml          # Your custom consequence definitions
├── skills/
│   └── my-skill/
│       └── workflow.yaml      # References your custom types
└── plugin.json
```

**Workflow reference pattern:**

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
  local_extensions:
    - consequences/{domain}.yaml

nodes:
  my_action:
    type: action
    actions:
      - type: my_custom_action  # Resolved from local extension
        required_param: "${value}"
```

### Option 3: Dedicated Extension Library

For domain-specific extensions shared across plugins:

```
myorg/blueprint-database-extensions/
├── consequences/
│   ├── index.yaml
│   └── database.yaml
├── preconditions/
│   └── database.yaml
└── README.md
```

**Workflow reference:**

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
  extensions:
    - myorg/blueprint-database-extensions@v1.0.0
```

---

## Validation

Validate your extension definitions against the JSON Schema:

```bash
LIB_SCHEMA="file:///path/to/hiivmind-blueprint-lib/schema/"
SCHEMA_DIR="/path/to/hiivmind-blueprint-lib/schema"

# Validate your consequence definitions
~/.rye/shims/check-jsonschema \
  --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/consequence-definition.json" \
  consequences/my-domain.yaml
```

---

## Best Practices

### Keep Extensions Focused

Each extension file should handle one cohesive domain:
- **Good:** `git.yaml` for all git operations
- **Bad:** `utilities.yaml` mixing unrelated operations

### Document Failure Conditions

Always specify when consequences fail:

```yaml
- type: my_action
  description: Does something useful
  # ...
  failure_conditions:
    - condition: "File not found"
      behavior: "Sets error flag, continues"
    - condition: "Parse error"
      behavior: "Fails node execution"
```

### Use Common Patterns

Follow the patterns in hiivmind-blueprint-lib core consequences:
- `store_as` for storing results
- `from` for reading from state
- `path` for file system paths
- Support `${}` interpolation in all string parameters

### Consider Composability

Design consequences to work well together:

```yaml
# Good: composable
- type: read_config
  store_as: config
- type: evaluate
  expression: "len(config.sources) > 0"
  set_flag: has_sources

# Bad: monolithic
- type: check_config_has_sources  # Does too much
  set_flag: has_sources
```

---

## Related Documentation

- **Type Definitions (authoritative):** `hiivmind/hiivmind-blueprint-lib@v2.0.0`
- **Consequence Schema:** `hiivmind/hiivmind-blueprint-lib@v2.0.0/schema/consequence-definition.json`
- **Core Consequences:** `hiivmind/hiivmind-blueprint-lib@v2.0.0/consequences/core/`
- **Extension Consequences:** `hiivmind/hiivmind-blueprint-lib@v2.0.0/consequences/extensions/`
- **Workflow Engine:** `lib/workflow/engine.md`
- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md`
