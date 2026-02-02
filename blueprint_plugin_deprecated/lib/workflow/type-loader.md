# Type Loader Protocol

This document provides a user-facing reference for type definition loading. The authoritative loading semantics are defined in YAML.

> **Authoritative Source:** `hiivmind-blueprint-lib/resolution/type-loader.yaml`

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

## Source Format

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
```

**Pattern:** `{owner}/{repo}@{version}`

**Version formats:**

| Format | Example | Behavior |
|--------|---------|----------|
| Exact | `@v2.0.0` | Use exact version (recommended) |
| Minor | `@v2.0` | Latest patch in v2.0.x |
| Major | `@v2` | Latest minor in v2.x.x |

---

## Loading Process

> **Source:** `hiivmind-blueprint-lib/resolution/type-loader.yaml` → `loading_algorithm`

1. Parse `definitions.source` to extract owner, repo, version
2. Construct raw GitHub URL: `https://raw.githubusercontent.com/{owner}/{repo}/{version}/`
3. Fetch index files: `consequences/index.yaml`, `preconditions/index.yaml`
4. Build TypeRegistry with type lookup tables
5. Lazy-load individual type definitions on first use
6. Load extensions if specified

---

## Extension Loading

Multiple type sources can be combined:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0
  extensions:
    - mycorp/custom-types@v1.0.0
```

**Collision handling:** When type names collide, use namespace prefix:

```yaml
actions:
  - type: clone_repo                          # Base type
  - type: mycorp/custom-types:clone_repo      # Namespaced
```

---

## TypeRegistry Structure

```yaml
type_registry:
  consequences:
    set_flag:
      category: core/state
      loaded: false      # Lazy load on first use
    clone_repo:
      category: extensions/git
      loaded: false

  preconditions:
    file_exists:
      category: core/filesystem
      loaded: false
    flag_set:
      category: core/state
      loaded: false
```

---

## Validation

After loading, the engine validates all workflow types exist:

- Consequence types in action nodes
- Precondition types in conditional/validation_gate nodes
- Entry precondition types

---

## Error Messages

```
Error: Unknown consequence type: docker_build

This type is not in the loaded definitions.

Loaded from: hiivmind/hiivmind-blueprint-lib@v2.0.0 (43 consequences)

Suggestions:
- Check for typos in the type name
- Add an extension with this type
```

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine overview
- **Workflow Loader:** `lib/workflow/workflow-loader.md` - Workflow loading protocol
- **Type Resolution:** `lib/blueprint/patterns/type-resolution.md` - Pattern details
