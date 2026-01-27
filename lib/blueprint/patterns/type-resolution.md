# Type Resolution Pattern

This document describes how workflow type definitions (consequences and preconditions) are resolved from external sources, following a model similar to GitHub Actions.

## Overview

Workflows can reference type definitions from external sources:

```yaml
# workflow.yaml
definitions:
  source: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml

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
  source: <URL | "local" | "owner/repo@version">
  path: <local path if source is "local">
  extensions: [<additional sources>]
  fallback: <error | warn | embedded>
```

### 2. Determine Source Type

| Source Format | Resolution |
|---------------|------------|
| `https://...` | Direct URL fetch |
| `local` | Load from `path` |
| `owner/repo@version` | Construct GitHub release URL |

**GitHub URL Construction:**
```
owner/repo@v1.0.0  →  https://github.com/{owner}/{repo}/releases/download/v1.0.0/bundle.yaml
owner/repo@v1      →  Requires version resolution (not recommended for production)
```

### 3. Check Local Cache

Before fetching, check if the definitions are cached:

```
~/.claude/cache/blueprint-types/
├── hiivmind/
│   └── hiivmind-blueprint-types/
│       ├── v1.0.0/
│       │   ├── bundle.yaml
│       │   └── fetched_at.txt
│       └── v1.2.0/
│           └── ...
```

**Cache key**: `{owner}/{repo}/{version}` or SHA256 of URL for direct URLs.

### 4. Fetch if Needed

If not cached or cache is stale:

1. Fetch the bundle.yaml (or index files)
2. Validate against the schema
3. Store in cache with fetch timestamp

### 5. Load Extensions

For each entry in `extensions`:
1. Resolve using same protocol
2. Merge types into the registry
3. Handle namespace conflicts (see below)

### 6. Validate Workflow Types

After loading definitions, validate that all types used in the workflow exist:

```python
for node in workflow.nodes:
    for consequence in node.actions:
        if consequence.type not in definitions.consequences:
            raise ValidationError(f"Unknown consequence type: {consequence.type}")
```

## Lock File Format

The `.blueprint-types.lock` file ensures reproducible builds:

```yaml
# .blueprint-types.lock
# Auto-generated - do not edit manually

schema_version: "1.0"
generated_at: "2026-01-27T05:30:00Z"

resolved:
  hiivmind/hiivmind-blueprint-types:
    requested: "@v1"
    resolved: "v1.3.2"
    sha256: "a1b2c3d4e5f6789..."
    url: "https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.3.2/bundle.yaml"
    fetched_at: "2026-01-27T05:30:00Z"

  mycorp/custom-types:
    requested: "@v2.0.0"
    resolved: "v2.0.0"
    sha256: "f6e5d4c3b2a1..."
    url: "https://github.com/mycorp/custom-types/releases/download/v2.0.0/bundle.yaml"
    fetched_at: "2026-01-27T05:30:00Z"
```

**Lock file semantics:**
- If lock file exists and entry matches `requested`, use `resolved` version
- If no lock file or entry missing, resolve latest matching version
- `sha256` enables integrity verification (optional)

## Caching Architecture

### Layer 1: Global Cache (User-Level)

Location: `~/.claude/cache/blueprint-types/`

Shared across all plugins. Fetched once per version.

```
~/.claude/cache/blueprint-types/
├── hiivmind/
│   └── hiivmind-blueprint-types/
│       └── v1.0.0/
│           ├── bundle.yaml
│           ├── consequences/
│           │   ├── index.yaml
│           │   └── definitions/
│           ├── preconditions/
│           └── metadata.yaml
```

**metadata.yaml:**
```yaml
url: "https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml"
fetched_at: "2026-01-27T05:30:00Z"
sha256: "a1b2c3d4..."
```

### Layer 2: Lock File (Plugin-Level)

Location: `<plugin_root>/.blueprint-types.lock`

Committed to version control for reproducibility.

### Layer 3: Offline Fallback

If network is unavailable:

1. Check lock file for exact version
2. Use cached version if available
3. Use embedded definitions if `fallback: embedded`
4. Error with clear message if truly missing

## Namespace Prefixes

When loading extensions, type collisions are handled via namespaces:

```yaml
# No prefix for base types (when unambiguous)
- type: clone_repo

# Explicit namespace when using extensions
- type: mycorp/custom-types:docker_build

# Or when resolving collisions
- type: hiivmind/hiivmind-blueprint-types:clone_repo
```

**Resolution order:**
1. Check base definitions first
2. Then check extensions in order declared
3. If collision, require explicit namespace

## Fallback Strategies

| `fallback` Value | Behavior on Fetch Failure |
|------------------|---------------------------|
| `error` | Fail workflow validation immediately |
| `warn` | Log warning, try cache, then embedded |
| `embedded` | Silently use embedded definitions |

**Recommended:**
- Production workflows: `error` or explicit version + lock file
- Development workflows: `warn` for flexibility

## Version Compatibility

### Semantic Versioning

| Version Request | Matches |
|-----------------|---------|
| `@v1.2.3` | Exact version only |
| `@v1.2` | Latest v1.2.x |
| `@v1` | Latest v1.x.x |
| `@latest` | Most recent release (not recommended) |

### Breaking Change Detection

Type definitions declare a `since` version. Workflows can declare minimum version:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-types@v1
  requires:
    consequences: ">=1.1.0"  # Need run_script (added in 1.1)
    preconditions: ">=1.0.0"
```

## Validation Steps

After loading definitions, validate:

1. **Schema Compliance**: definitions match expected structure
2. **Type Existence**: all workflow types exist in definitions
3. **Parameter Matching**: required parameters are provided
4. **Version Compatibility**: definitions version satisfies requirements

## Example Resolution Flow

```
workflow.yaml:
  definitions:
    source: hiivmind/hiivmind-blueprint-types@v1.0.0

Resolution:
1. Parse: owner=hiivmind, repo=hiivmind-blueprint-types, version=v1.0.0
2. Cache check: ~/.claude/cache/blueprint-types/hiivmind/hiivmind-blueprint-types/v1.0.0/
3. Cache miss → Construct URL:
   https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml
4. Fetch bundle.yaml
5. Validate against schema
6. Store in cache
7. Return type registry
```

## Configurable Registries

For enterprise environments, configure alternate registries:

```yaml
# ~/.claude/blueprint-types.yaml
registries:
  default: https://github.com
  mycorp: https://github.enterprise.mycorp.com
  internal: https://gitops.internal.mycorp.com
```

Then reference:

```yaml
definitions:
  source: mycorp://team/custom-types@v1  # Uses mycorp registry
```

## Error Messages

Provide clear, actionable error messages:

```
Error: Failed to resolve type definitions

Source: hiivmind/hiivmind-blueprint-types@v1.0.0
URL: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml
Error: 404 Not Found

Suggestions:
- Check the version exists at the URL
- Verify network connectivity
- Use --offline flag with cached definitions
- Set fallback: embedded for graceful degradation
```

## Implementation Notes

### For Workflow Executors

1. Load definitions at workflow start (before first node)
2. Cache loaded types in memory for the session
3. Validate all types exist before execution begins
4. Provide clear errors with resolution suggestions

### For Definition Publishers

1. Use semantic versioning strictly
2. Never remove or rename types in minor versions
3. Publish both bundle.yaml and directory structure
4. Include checksums in release artifacts
5. Document breaking changes in CHANGELOG.md
