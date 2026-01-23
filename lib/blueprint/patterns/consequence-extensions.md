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

## Extension File Template

Create your extension file at `lib/workflow/consequences/extensions/{domain}.md`:

```markdown
# {Domain} Consequences

Brief description of the domain and what these consequences handle.

---

## {consequence_type}

One-line description.

```yaml
- type: {consequence_type}
  param1: value
  param2: "${computed.dynamic_value}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `param1` | string | Yes | What this parameter does |
| `param2` | string | No | Optional parameter description |

**Effect:**
```
pseudocode showing what happens
```

**Notes:**
- Important behavioral notes
- Failure conditions

---

## Common Patterns

### Pattern Name

```yaml
actions:
  - type: {consequence_type}
    # Example usage
```

---

## Related Documentation

- **Parent:** [README.md](README.md) - Extension overview
- **Core:** [../core/](../core/) - Core consequences
- **Domain patterns:** `lib/{domain}/patterns/` - Domain-specific algorithms
```

---

## Example: Corpus Extensions

The hiivmind-corpus plugin defines these domain-specific extensions:

### config.md (3 types)

| Type | Purpose |
|------|---------|
| `read_config` | Read and parse corpus config.yaml (hardcoded path) |
| `write_config_entry` | Update specific field in config.yaml |
| `add_source` | Add source entry with full spec to config.sources |
| `update_source` | Update existing source by ID |

**Why custom extensions?** These operations:
- Depend on corpus-specific file structure (`data/config.yaml`)
- Encapsulate YAML parsing and manipulation
- Handle corpus source schema validation

### discovery.md (1 type)

| Type | Purpose |
|------|---------|
| `discover_installed_corpora` | Scan multiple locations for installed corpus plugins |

**Why custom extension?** This operation:
- Knows corpus-specific installation locations
- Returns corpus-specific metadata structure
- Implements complex multi-path scanning logic

---

## Integrating Custom Extensions

When converting a plugin with hiivmind-blueprint:

### 1. Identify Domain Operations

During the analyze phase, look for operations that:
- Reference plugin-specific files or configuration
- Implement domain-specific algorithms
- Would be reusable across multiple skills in your plugin

### 2. Create Extension File

Add to your converted plugin:

```
{plugin}/
├── lib/
│   └── workflow/
│       └── consequences/
│           └── extensions/
│               └── {your-domain}.md
```

### 3. Update Extension README

Add your custom extensions to `extensions/README.md`:

```markdown
| Extension | Purpose | Consequence Count |
|-----------|---------|-------------------|
| [{domain}.md]({domain}.md) | {Description} | {count} |
```

### 4. Update JSON Schema (Optional)

If using formal validation, add your custom consequence types to `lib/schema/workflow-schema.json`.

---

## Schema Definition

For each custom consequence type, define its JSON Schema:

```json
{
  "consequence_{your_type}": {
    "type": "object",
    "required": ["type", "required_param"],
    "properties": {
      "type": { "const": "{your_type}" },
      "required_param": {
        "type": "string",
        "description": "[EXT:{domain}] What this does"
      },
      "optional_param": {
        "type": "string"
      }
    },
    "additionalProperties": false
  }
}
```

**Convention:** Prefix descriptions with `[EXT:{domain}]` to indicate extension consequences in validation output.

---

## Best Practices

### Keep Extensions Focused

Each extension file should handle one cohesive domain:
- **Good:** `git.md` for all git operations
- **Bad:** `utilities.md` mixing unrelated operations

### Document Failure Conditions

Always specify when consequences fail:

```markdown
**Failure:** If file doesn't exist or YAML is invalid.
```

### Use Common Patterns

Follow the patterns in `core/shared.md`:
- `store_as` for storing results
- `from` for reading from state
- `path` for file system paths
- Support `${}` interpolation

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

- **Consequence taxonomy:** `lib/workflow/consequences/README.md`
- **Core consequences:** `lib/workflow/consequences/core/`
- **Generic extensions:** `lib/workflow/consequences/extensions/`
- **Schema definition:** `lib/schema/workflow-schema.json`
- **Workflow schema:** `lib/workflow/schema.md`
