# Type Resolution Pattern

This document describes how workflow type definitions (consequences and preconditions) are resolved from external sources.

---

## Overview

Workflows reference type definitions from hiivmind-blueprint-lib via raw GitHub URLs:

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

nodes:
  my_node:
    type: action
    actions:
      - type: clone_repo          # Resolved from external definitions
        url: "${source.url}"
```

## Resolution Protocol

### 1. Parse the Definitions Block

When a workflow is loaded, examine the `definitions` block:

```yaml
definitions:
  source: <"owner/repo@version">
  extensions: [<additional sources>]
```

### 2. Construct Raw GitHub URL

The source is resolved to raw GitHub URLs:

```
owner/repo@version  →  https://raw.githubusercontent.com/{owner}/{repo}/{version}/
```

**Example:**
```
hiivmind/hiivmind-blueprint-lib@v2.0.0
  → https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/
```

### 3. Fetch Type Definitions

Fetch the index files on demand:

1. Fetch `consequences/index.yaml` for consequence types
2. Fetch `preconditions/index.yaml` for precondition types
3. For each referenced type, fetch the individual definition file

### 4. Load Extensions

For each entry in `extensions`:
1. Resolve using same protocol
2. Merge types into the registry
3. Handle namespace conflicts (see below)

### 5. Validate Workflow Types

After loading definitions, validate that all types used in the workflow exist:

```python
for node in workflow.nodes:
    for consequence in node.actions:
        if consequence.type not in definitions.consequences:
            raise ValidationError(f"Unknown consequence type: {consequence.type}")
```

---

## Source Format

Only the GitHub shorthand format is supported:

| Source Format | Example |
|---------------|---------|
| `owner/repo@version` | `hiivmind/hiivmind-blueprint-lib@v2.0.0` |

**Version formats:**

| Format | Example | Behavior |
|--------|---------|----------|
| Exact | `@v2.0.0` | Use exact version (recommended) |
| Minor | `@v2.0` | Latest patch in v2.0.x |
| Major | `@v2` | Latest minor in v2.x.x |

**Note:** Use exact versions for reproducibility. Non-exact versions resolve to the latest matching tag.

---

## Namespace Prefixes

When loading extensions, type collisions are handled via namespaces:

```yaml
# No prefix for base types (when unambiguous)
- type: clone_repo

# Explicit namespace when using extensions
- type: mycorp/custom-types:docker_build

# Or when resolving collisions
- type: hiivmind/hiivmind-blueprint-lib:clone_repo
```

**Resolution order:**
1. Check base definitions first
2. Then check extensions in order declared
3. If collision, require explicit namespace

---

## Version Compatibility

### Semantic Versioning

| Version Request | Matches |
|-----------------|---------|
| `@v2.0.0` | Exact version only |
| `@v2.0` | Latest v2.0.x |
| `@v2` | Latest v2.x.x |

### Breaking Change Detection

Type definitions declare a `since` version. Workflows can declare minimum version:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2
  requires:
    consequences: ">=2.0.0"
    preconditions: ">=2.0.0"
```

---

## Example Resolution Flow

```
workflow.yaml:
  definitions:
    source: hiivmind/hiivmind-blueprint-lib@v2.0.0

Resolution:
1. Parse: owner=hiivmind, repo=hiivmind-blueprint-lib, version=v2.0.0
2. Construct base URL:
   https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/
3. Fetch consequences/index.yaml
4. Fetch preconditions/index.yaml
5. For each type used in workflow, fetch individual definition file
6. Build type registry
7. Validate all workflow types exist
```

---

## Error Messages

Provide clear, actionable error messages:

```
Error: Failed to resolve type definitions

Source: hiivmind/hiivmind-blueprint-lib@v2.0.0
URL: https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/consequences/index.yaml
Error: 404 Not Found

Suggestions:
- Check the version exists: https://github.com/hiivmind/hiivmind-blueprint-lib/tags
- Verify network connectivity
```

---

## Implementation Notes

### For Workflow Executors

1. Load definitions at workflow start (before first node)
2. Fetch types on demand (lazy loading)
3. Validate all types exist before execution begins
4. Provide clear errors with resolution suggestions

### For Definition Publishers

1. Use semantic versioning strictly
2. Never remove or rename types in minor versions
3. Publish individual type files in structured directories
4. Document breaking changes in CHANGELOG.md

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Abstract execution engine that uses type loading
- **Type Loader:** `lib/workflow/type-loader.md` - Detailed loading protocol implementation
- **Plugin Structure:** `lib/blueprint/patterns/plugin-structure.md` - `.hiivmind/blueprint/` layout
