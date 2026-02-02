# Type Loader Protocol

This document specifies how workflow type definitions (consequences and preconditions) are loaded and resolved at workflow initialization.

---

## Overview

Workflows reference type definitions via the `definitions` block:

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1.0.0

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
    # 1. Determine source type
    source = definitions_block.source
    source_type = classify_source(source)

    # 2. Resolve URL
    url = resolve_url(source, source_type)

    # 3. Check cache
    cache_key = compute_cache_key(source, source_type)
    cached = check_cache(cache_key)
    IF cached AND NOT is_stale(cached):
        RETURN cached.registry

    # 4. Fetch definitions
    IF source_type == "local":
        bundle = read_local(definitions_block.path)
    ELSE:
        bundle = fetch_remote(url)

    # 5. Validate and build registry
    validate_bundle(bundle)
    registry = build_registry(bundle)

    # 6. Update cache
    write_cache(cache_key, bundle)

    # 7. Load extensions
    IF definitions_block.extensions:
        FOR each ext IN definitions_block.extensions:
            ext_registry = load_types({ source: ext })
            registry = merge_registry(registry, ext_registry)

    RETURN registry
```

---

## Source Classification

The loader supports multiple source formats:

### Direct URL

```yaml
definitions:
  source: https://github.com/hiivmind/hiivmind-blueprint-lib/releases/download/v1.0.0/bundle.yaml
```

Classification: `source_type = "url"`

### GitHub Shorthand

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1.0.0
```

Classification: `source_type = "github"`

URL construction:
```
{owner}/{repo}@{version}
  → https://github.com/{owner}/{repo}/releases/download/{version}/bundle.yaml
```

### Local Embedded

```yaml
definitions:
  source: local
  path: ./vendor/blueprint-types/bundle.yaml
```

Classification: `source_type = "local"`

### Classification Logic

```
FUNCTION classify_source(source):
    IF source == "local":
        RETURN "local"
    IF source.startsWith("https://") OR source.startsWith("http://"):
        RETURN "url"
    IF source.matches(/^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+@/):
        RETURN "github"
    THROW "Unknown source format: {source}"
```

---

## URL Resolution

### GitHub Shorthand Resolution

```
FUNCTION resolve_github_url(source):
    # Parse: owner/repo@version
    match = source.match(/^([^\/]+)\/([^@]+)@(.+)$/)
    owner = match[1]
    repo = match[2]
    version = match[3]

    # Construct URL
    RETURN "https://github.com/{owner}/{repo}/releases/download/{version}/bundle.yaml"
```

**Version formats:**

| Format | Example | Behavior |
|--------|---------|----------|
| Exact | `@v1.2.3` | Use exact version |
| Minor | `@v1.2` | Latest patch in v1.2.x (requires resolution) |
| Major | `@v1` | Latest minor in v1.x.x (requires resolution) |
| Latest | `@latest` | Most recent release (not recommended) |

**Note:** Non-exact versions require querying GitHub API for resolution. Prefer exact versions for reproducibility.

---

## Caching

### Cache Location

```
~/.claude/cache/hiivmind/blueprint/
├── types/
│   └── {owner}/
│       └── {repo}/
│           └── {version}/
│               ├── bundle.yaml
│               └── metadata.yaml
├── workflows/                          # Extracted workflows (v1.2+)
│   └── {owner}/
│       └── {repo}/
│           └── {version}/
│               └── {workflow-name}/
│                   ├── workflow.yaml   # Extracted from bundle
│                   └── metadata.yaml
├── logging/                            # Extracted logging defaults (v1.3+)
│   └── {owner}/
│       └── {repo}/
│           └── {version}/
│               ├── defaults.yaml       # Extracted from bundle
│               └── metadata.yaml
├── engine/
│   └── {version}/
│       └── engine.md
└── url-cache/
    └── {sha256-of-url}/
        ├── bundle.yaml
        └── metadata.yaml
```

**Note:** Workflows and logging defaults are extracted from bundles on first reference and cached separately for faster subsequent loads. See `workflow-loader.md` and `logging-config-loader.md` for the respective loading protocols.

### Cache Key Computation

```
FUNCTION compute_cache_key(source, source_type):
    IF source_type == "github":
        # Parse owner/repo@version
        RETURN "{owner}/{repo}/{version}"
    IF source_type == "url":
        RETURN "url-cache/" + sha256(source)
    IF source_type == "local":
        RETURN null  # Local sources are not cached
```

### Metadata Format

**Type Bundle Metadata:**

```yaml
# types/{owner}/{repo}/{version}/metadata.yaml
url: "https://github.com/hiivmind/hiivmind-blueprint-lib/releases/download/v1.0.0/bundle.yaml"
fetched_at: "2026-01-27T10:30:00Z"
sha256: "a1b2c3d4e5f6..."
schema_version: "1.2"
consequence_count: 43
precondition_count: 27
workflow_count: 1                       # v1.2+
```

**Workflow Metadata (v1.2+):**

```yaml
# workflows/{owner}/{repo}/{version}/{workflow-name}/metadata.yaml
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
  preconditions:
    - evaluate_expression
```

### Staleness Check

```
FUNCTION is_stale(cached):
    # Never stale for exact versions
    IF cached.version matches /^v\d+\.\d+\.\d+$/:
        RETURN false

    # Check freshness for non-exact versions
    age = now() - cached.fetched_at
    IF age > 24 hours:
        RETURN true  # Re-resolve non-exact versions daily

    RETURN false
```

---

## Fetching

### Remote Fetch (URL)

```
FUNCTION fetch_remote(url):
    # Use WebFetch tool
    response = CALL WebFetch with:
        url: url
        prompt: "Return the raw YAML content"

    IF response.status >= 400:
        THROW "Failed to fetch types: {response.status} {url}"

    # Handle redirects
    IF response.redirect_url:
        RETURN fetch_remote(response.redirect_url)

    RETURN parse_yaml(response.content)
```

### Local Read

```
FUNCTION read_local(path):
    # Resolve relative path from workflow location
    resolved_path = resolve_path(path, workflow_directory)

    IF NOT file_exists(resolved_path):
        THROW "Local type definitions not found: {resolved_path}"

    content = CALL Read with:
        file_path: resolved_path

    RETURN parse_yaml(content)
```

---

## Bundle Format

Type definitions are bundled as a single YAML file:

```yaml
# bundle.yaml
schema_version: "1.1"
bundled_at: "2026-01-27T10:00:00Z"
source_repo: "https://github.com/hiivmind/hiivmind-blueprint-lib"

consequences:
  # Core consequences (30)
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

  clone_repo:
    category: extensions/git
    # ... full definition
    since: "1.0.0"

  # ... all 43 consequences

preconditions:
  # Core preconditions (22)
  file_exists:
    category: core/filesystem
    parameters:
      - name: path
        type: string
        required: true
    evaluation: "file_exists(interpolate(path))"
    since: "1.0.0"

  flag_set:
    category: core/state
    # ... full definition
    since: "1.0.0"

  # ... all 27 preconditions

stats:
  total_consequences: 43
  total_preconditions: 27
```

---

## Registry Building

```
FUNCTION build_registry(bundle):
    registry = {
        schema_version: bundle.schema_version,
        consequences: {},
        preconditions: {}
    }

    # Load consequences
    FOR each type_name, definition IN bundle.consequences:
        registry.consequences[type_name] = {
            ...definition,
            source: bundle.source_repo
        }

    # Load preconditions
    FOR each type_name, definition IN bundle.preconditions:
        registry.preconditions[type_name] = {
            ...definition,
            source: bundle.source_repo
        }

    RETURN registry
```

---

## Extension Loading

Multiple type sources can be combined:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1.0.0
  extensions:
    - mycorp/custom-types@v2.0.0
    - https://example.com/domain-types.yaml
```

### Merge Strategy

```
FUNCTION merge_registry(base, extension):
    result = copy(base)

    FOR each type_name, definition IN extension.consequences:
        IF type_name IN result.consequences:
            # Collision - require namespace prefix
            namespaced_name = "{extension.source}:{type_name}"
            result.consequences[namespaced_name] = definition
        ELSE:
            result.consequences[type_name] = definition

    FOR each type_name, definition IN extension.preconditions:
        IF type_name IN result.preconditions:
            namespaced_name = "{extension.source}:{type_name}"
            result.preconditions[namespaced_name] = definition
        ELSE:
            result.preconditions[type_name] = definition

    RETURN result
```

### Using Namespaced Types

When collisions exist:

```yaml
# In workflow.yaml
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

### Bundle Validation

```
FUNCTION validate_bundle(bundle):
    # Check schema version
    IF bundle.schema_version < MINIMUM_SCHEMA_VERSION:
        THROW "Bundle schema version {bundle.schema_version} is too old"

    # Check required fields
    IF NOT bundle.consequences:
        THROW "Bundle missing 'consequences' section"
    IF NOT bundle.preconditions:
        THROW "Bundle missing 'preconditions' section"

    # Validate each consequence
    FOR each name, def IN bundle.consequences:
        validate_consequence_definition(name, def)

    # Validate each precondition
    FOR each name, def IN bundle.preconditions:
        validate_precondition_definition(name, def)
```

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

## Fallback Strategies

When remote fetch fails:

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1.0.0
  fallback: embedded  # or "error" or "warn"
```

### Fallback Behavior

| Value | Behavior |
|-------|----------|
| `error` | Fail immediately if fetch fails |
| `warn` | Log warning, try cache, then embedded |
| `embedded` | Silently use embedded definitions |

### Embedded Definitions Location

```
{plugin_root}/lib/types/
├── bundle.yaml
├── consequences/
│   ├── index.yaml
│   └── definitions/
│       ├── core/
│       └── extensions/
└── preconditions/
    ├── index.yaml
    └── definitions/
        ├── core/
        └── extensions/
```

### Fallback Algorithm

```
FUNCTION fetch_with_fallback(url, fallback_mode, plugin_root):
    TRY:
        RETURN fetch_remote(url)
    CATCH error:
        IF fallback_mode == "error":
            THROW error

        IF fallback_mode == "warn":
            LOG "Warning: Failed to fetch types from {url}: {error}"
            LOG "Attempting fallback..."

        # Try cache first
        cached = check_cache(url)
        IF cached:
            LOG "Using cached definitions (may be stale)"
            RETURN cached

        # Fall back to embedded
        embedded_path = "{plugin_root}/lib/types/bundle.yaml"
        IF file_exists(embedded_path):
            LOG "Using embedded definitions"
            RETURN read_local(embedded_path)

        THROW "No type definitions available: {error}"
```

---

## Offline Mode

For airgapped environments:

### Option 1: Vendor Dependencies

```bash
# Download bundle during build
curl -o vendor/blueprint-types/bundle.yaml \
  https://github.com/hiivmind/hiivmind-blueprint-lib/releases/download/v1.0.0/bundle.yaml
```

```yaml
# workflow.yaml
definitions:
  source: local
  path: ./vendor/blueprint-types/bundle.yaml
```

### Option 2: Pre-populate Cache

```bash
# Warm cache before offline operation
mkdir -p ~/.claude/cache/hiivmind/blueprint/types/hiivmind/hiivmind-blueprint-lib/v1.0.0/
cp bundle.yaml ~/.claude/cache/hiivmind/blueprint/types/hiivmind/hiivmind-blueprint-lib/v1.0.0/
```

### Option 3: Use Embedded Fallback

```yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v1.0.0
  fallback: embedded
```

---

## Lock File Support

For reproducible builds, use a lock file located at `.hiivmind/blueprint/types.lock`:

```yaml
# .hiivmind/blueprint/types.lock
schema: "1.0"
generated_at: "2026-01-27T12:00:00Z"
generated_by: "hiivmind-blueprint v1.1.0"

engine:
  version: "1.1.0"
  sha256: "abc123..."
  source: "hiivmind/hiivmind-blueprint@v1.1.0"

types:
  hiivmind/hiivmind-blueprint-lib:
    requested: "@v1"
    resolved: "v1.3.2"
    sha256: "def456..."
    fetched_at: "2026-01-27T05:30:00Z"

  # Additional type sources (extensions)
  mycorp/custom-types:
    requested: "@v2.0.0"
    resolved: "v2.0.0"
    sha256: "ghi789..."
```

### Lock File Usage

```
FUNCTION resolve_with_lock(source, lock_file_path):
    lock_file = read_yaml(lock_file_path)  # .hiivmind/blueprint/types.lock

    IF lock_file exists:
        entry = lock_file.types[source]
        IF entry:
            # Use locked version instead of requested
            version = entry.resolved
            RETURN construct_url(source, version)

    # No lock entry - resolve normally
    RETURN resolve_url(source)
```

### Plugin-Level Lock File Location

Lock files are stored at `.hiivmind/blueprint/types.lock` within the target plugin:

```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Copied from cache/source
│       └── types.lock             # Version pinning
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # References .hiivmind/blueprint/engine.md
│       └── workflow.yaml
```

This structure aligns with the hiivmind ecosystem pattern (e.g., `.hiivmind/github/` for hiivmind-pulse-gh).

---

## Error Messages

Provide clear, actionable errors:

```
Error: Failed to resolve type definitions

Source: hiivmind/hiivmind-blueprint-lib@v1.0.0
URL: https://github.com/hiivmind/hiivmind-blueprint-lib/releases/download/v1.0.0/bundle.yaml
Error: 404 Not Found

Suggestions:
- Check the version exists: https://github.com/hiivmind/hiivmind-blueprint-lib/releases
- Verify network connectivity
- Use cached definitions (if available)
- Set fallback: embedded for graceful degradation
```

```
Error: Unknown consequence type: docker_build

This type is not in the loaded definitions.

Loaded from: hiivmind/hiivmind-blueprint-lib@v1.0.0 (43 consequences)

Suggestions:
- Check for typos in the type name
- Add an extension with this type:
    definitions:
      source: hiivmind/hiivmind-blueprint-lib@v1.0.0
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
- **Consequence Index:** `lib/consequences/definitions/index.yaml` - Local consequence registry
- **Precondition Index:** `lib/preconditions/definitions/index.yaml` - Local precondition registry
