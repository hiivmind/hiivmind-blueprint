# Logging Config Loader Protocol

This document specifies how logging configuration is loaded and resolved at workflow initialization. Logging configuration follows a 4-tier priority hierarchy and integrates with the distributed composable workflow model.

---

## Overview

Logging configuration can be specified at multiple levels, with higher-priority levels overriding lower ones:

```yaml
# workflow.yaml
initial_state:
  logging:
    level: "debug"     # Skill-specific (priority 2)

# Plugin-level: .hiivmind/blueprint/logging.yaml
logging:
  level: "warn"        # Plugin-wide (priority 3)

# Framework defaults: from bundle.logging_defaults
logging:
  level: "info"        # Framework (priority 4)
```

The logging config loader resolves these before workflow execution begins.

---

## Loading Algorithm

```
FUNCTION load_logging_config(workflow, plugin_root, runtime_flags):
    # Priority 1: Runtime flags (--log-level, --verbose, etc.)
    runtime_config = extract_logging_from_runtime(runtime_flags)

    # Priority 2: Skill config (workflow.initial_state.logging)
    skill_config = workflow.initial_state.logging ?? {}

    # Priority 3: Plugin config (.hiivmind/blueprint/logging.yaml)
    plugin_config_path = "{plugin_root}/.hiivmind/blueprint/logging.yaml"
    IF file_exists(plugin_config_path):
        plugin_config = read_yaml(plugin_config_path)
    ELSE:
        plugin_config = {}

    # Priority 4: Framework defaults (from bundle)
    framework_config = load_framework_defaults(workflow.definitions)

    # Merge: runtime > skill > plugin > framework (deep merge)
    resolved_config = deep_merge(
        framework_config,  # Lowest priority
        plugin_config,
        skill_config,
        runtime_config     # Highest priority
    )

    # Validate resolved config
    validate_logging_config(resolved_config)

    RETURN resolved_config
```

---

## Runtime Flag Extraction

Runtime flags map to logging configuration:

```
FUNCTION extract_logging_from_runtime(flags):
    config = {}

    # Level flags
    IF flags.log_level:
        config.level = flags.log_level
    IF flags.verbose OR flags.v:
        config.level = "debug"
    IF flags.quiet OR flags.q:
        config.level = "error"
    IF flags.trace:
        config.level = "trace"

    # Output flags
    IF flags.log_format:
        config.output = config.output ?? {}
        config.output.format = flags.log_format
    IF flags.log_dir:
        config.output = config.output ?? {}
        config.output.location = flags.log_dir

    # Control flags
    IF flags.no_log:
        config.enabled = false
    IF flags.ci:
        config.ci = config.ci ?? {}
        config.ci.format = "github"

    RETURN config
```

### Standard Flag Mappings

| Flag | Maps To |
|------|---------|
| `--verbose`, `-v` | `logging.level: "debug"` |
| `--quiet`, `-q` | `logging.level: "error"` |
| `--trace` | `logging.level: "trace"` |
| `--log-level=X` | `logging.level: X` |
| `--log-format=X` | `logging.output.format: X` |
| `--log-dir=X` | `logging.output.location: X` |
| `--no-log` | `logging.enabled: false` |
| `--ci` | `logging.ci.format: "github"` |

---

## Framework Defaults Loading

Framework defaults are loaded from the type bundle's `logging_defaults` section:

```
FUNCTION load_framework_defaults(definitions_block):
    # 1. Load bundle using type loader
    bundle = load_types(definitions_block)

    # 2. Extract logging_defaults
    IF bundle.logging_defaults:
        RETURN bundle.logging_defaults.content
    ELSE:
        # Fallback to hardcoded defaults if bundle lacks logging_defaults
        RETURN HARDCODED_DEFAULTS

CONST HARDCODED_DEFAULTS = {
    enabled: true,
    level: "info",
    auto: {
        init: true,
        finalize: true,
        write: true,
        node_tracking: true
    },
    capture: {
        nodes: true,
        state_changes: false,
        user_responses: true,
        timing: true
    },
    output: {
        format: "yaml",
        location: ".logs/",
        filename: "{skill_name}-{timestamp}.{ext}"
    },
    retention: {
        strategy: "count",
        count: 10
    },
    ci: {
        format: "none",
        annotations: true
    }
}
```

---

## Caching

### Cache Location

Logging defaults from bundles are cached alongside type definitions:

```
~/.claude/cache/hiivmind/blueprint/
├── types/
│   └── {owner}/{repo}/{version}/
│       ├── bundle.yaml
│       └── metadata.yaml
├── workflows/
│   └── {owner}/{repo}/{version}/
│       └── {workflow-name}/
├── logging/                                # NEW: Logging defaults cache
│   └── {owner}/{repo}/{version}/
│       ├── defaults.yaml                   # Extracted logging_defaults
│       └── metadata.yaml
└── engine/
    └── {version}/
        └── engine.md
```

### Metadata Format

```yaml
# logging/{owner}/{repo}/{version}/metadata.yaml
bundle_source: "hiivmind/hiivmind-blueprint-types@v1.3.0"
extracted_at: "2026-01-28T10:30:00Z"
bundle_sha256: "abc123..."
defaults_version: "1.0.0"
```

### Cache Key

```
FUNCTION compute_logging_cache_key(source):
    RETURN "logging/{source.owner}/{source.repo}/{source.version}"
```

---

## Plugin-Level Configuration

Plugin-wide logging defaults are stored at `.hiivmind/blueprint/logging.yaml`:

```yaml
# {plugin_root}/.hiivmind/blueprint/logging.yaml
#
# Plugin-wide logging defaults (priority 3)
# See: lib/workflow/logging-config-loader.md

logging:
  # Override framework defaults for this plugin
  level: "warn"                    # Less verbose by default

  output:
    location: "data/logs/"         # Plugin prefers data/ directory
    format: "yaml"

  retention:
    strategy: "days"
    days: 14

  ci:
    format: "github"               # Plugin runs in GitHub Actions
```

### Plugin Config Discovery

```
FUNCTION find_plugin_config(skill_path):
    # Walk up from skill directory to find .hiivmind/blueprint/
    current = skill_path
    WHILE current != "/":
        candidate = "{current}/.hiivmind/blueprint/logging.yaml"
        IF file_exists(candidate):
            RETURN candidate
        current = parent_directory(current)
    RETURN null
```

---

## Deep Merge Strategy

Configuration is merged from lowest to highest priority:

```
FUNCTION deep_merge(...objects):
    result = {}

    FOR each obj IN objects:
        FOR each key, value IN obj:
            IF value is object AND result[key] is object:
                # Recursively merge nested objects
                result[key] = deep_merge(result[key], value)
            ELSE:
                # Overwrite scalar or null values
                result[key] = value

    RETURN result
```

### Merge Example

```yaml
# Framework defaults (lowest)
logging:
  enabled: true
  level: "info"
  auto:
    init: true
    node_tracking: true
  output:
    format: "yaml"
    location: ".logs/"

# Plugin config (middle)
logging:
  level: "warn"
  output:
    location: "data/logs/"

# Skill config (highest)
logging:
  auto:
    node_tracking: false

# Result:
logging:
  enabled: true           # From framework
  level: "warn"           # From plugin (overrides framework)
  auto:
    init: true            # From framework
    node_tracking: false  # From skill (overrides framework)
  output:
    format: "yaml"        # From framework
    location: "data/logs/"  # From plugin (overrides framework)
```

---

## Sub-Workflow Inheritance

When a `reference` node invokes a sub-workflow, logging configuration is inherited by default:

### Default Inheritance

```yaml
# Parent workflow has logging config in state.logging
# Sub-workflow inherits parent's state.logging

detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-types@v1.0.0:intent-detection
  context:
    arguments: "${arguments}"
    # logging is inherited automatically (state is shared)
  next_node: execute_dynamic_route
```

### Override for Sub-Workflow

To override logging for a specific sub-workflow, pass `context.logging`:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-types@v1.0.0:intent-detection
  context:
    arguments: "${arguments}"
    logging:                        # Override for this sub-workflow
      level: "debug"                # More verbose for intent detection
      auto:
        node_tracking: true         # Track nodes in sub-workflow
  next_node: execute_dynamic_route
```

### Log Nesting

Sub-workflow logs are nested within the parent's log:

```yaml
# Parent workflow log
node_history:
  - id: validate_input
    outcome: success
    timestamp: "2026-01-28T10:30:00Z"

  - id: detect_intent
    outcome: success
    timestamp: "2026-01-28T10:30:01Z"
    sub_workflow:                   # Nested sub-workflow log
      name: "intent-detection"
      version: "1.0.0"
      node_history:
        - id: parse_flags
          outcome: success
        - id: match_rules
          outcome: success
      status: "success"

  - id: execute_action
    outcome: success
    timestamp: "2026-01-28T10:30:02Z"
```

---

## Validation

```
FUNCTION validate_logging_config(config):
    errors = []

    # Level validation
    valid_levels = ["error", "warn", "info", "debug", "trace"]
    IF config.level AND config.level NOT IN valid_levels:
        errors.push("Invalid log level: {config.level}")

    # Output format validation
    valid_formats = ["yaml", "json", "markdown"]
    IF config.output?.format AND config.output.format NOT IN valid_formats:
        errors.push("Invalid output format: {config.output.format}")

    # Retention validation
    valid_strategies = ["none", "days", "count"]
    IF config.retention?.strategy AND config.retention.strategy NOT IN valid_strategies:
        errors.push("Invalid retention strategy: {config.retention.strategy}")

    IF config.retention?.strategy == "days" AND NOT config.retention?.days:
        errors.push("retention.days required when strategy is 'days'")

    IF config.retention?.strategy == "count" AND NOT config.retention?.count:
        errors.push("retention.count required when strategy is 'count'")

    # CI format validation
    valid_ci_formats = ["none", "github", "plain", "json"]
    IF config.ci?.format AND config.ci.format NOT IN valid_ci_formats:
        errors.push("Invalid CI format: {config.ci.format}")

    IF errors.length > 0:
        THROW "Logging configuration validation failed:\n" + errors.join("\n")
```

---

## Lock File Support

Logging config versions can be pinned in `.hiivmind/blueprint/types.lock`:

```yaml
# .hiivmind/blueprint/types.lock
schema: "1.1"                       # Bumped for logging support
generated_at: "2026-01-28T12:00:00Z"
generated_by: "hiivmind-blueprint v1.3.0"

engine:
  version: "1.3.0"
  sha256: "abc123..."
  source: "hiivmind/hiivmind-blueprint@v1.3.0"

types:
  hiivmind/hiivmind-blueprint-types:
    requested: "@v1"
    resolved: "v1.3.0"
    sha256: "def456..."
    fetched_at: "2026-01-28T05:30:00Z"

logging:                            # NEW: Logging config pins
  hiivmind/hiivmind-blueprint-types:
    resolved: "v1.0.0"              # Version of logging_defaults
    sha256: "ghi789..."
    fetched_at: "2026-01-28T05:30:00Z"
```

### Lock Resolution

```
FUNCTION resolve_logging_with_lock(source, lock_file_path):
    lock_file = read_yaml(lock_file_path)

    IF lock_file.logging AND lock_file.logging[source]:
        entry = lock_file.logging[source]

        # Check cache
        cached = check_logging_cache(source, entry.resolved)
        IF cached AND sha256(cached) == entry.sha256:
            RETURN cached

    # No lock or mismatch - load normally
    RETURN load_framework_defaults({ source: source })
```

---

## Integration with Workflow Execution

The logging config loader is called during workflow initialization (Phase 1 of engine.md):

```
FUNCTION initialize(workflow_path, plugin_root, runtime_flags):
    # 1. Load workflow
    workflow = parse_yaml(read_file(workflow_path))

    # 2. Load type definitions
    types = load_types(workflow.definitions)

    # 3. Load and resolve logging config  # NEW
    logging_config = load_logging_config(workflow, plugin_root, runtime_flags)

    # 4. Validate
    validate_schema(workflow)
    validate_types_exist(workflow, types)
    validate_graph_connectivity(workflow)

    # ... (rest of initialization)

    # 5. Initialize state with logging config
    state = {
        ...
        logging: logging_config,        # Store resolved config
        log: null,                      # Log session (initialized by init_log)
        ...
    }

    # 6. Auto-inject init_log if enabled
    IF logging_config.auto.init:
        execute_consequence({
            type: "init_log",
            workflow_name: workflow.name,
            log_level: logging_config.level
        }, types, state)

    RETURN { workflow, types, state }
```

---

## Error Messages

Provide clear, actionable errors:

```
Error: Invalid logging configuration

Source: .hiivmind/blueprint/logging.yaml
Error: Invalid log level: "verbose"

Valid levels: error, warn, info, debug, trace

Suggestions:
- Use 'debug' for verbose logging
- Use 'trace' for maximum detail
```

```
Error: Logging defaults not found in bundle

Bundle: hiivmind/hiivmind-blueprint-types@v1.2.0
Missing: logging_defaults section

This bundle version doesn't include logging defaults.

Suggestions:
- Update to v1.3.0 or later for logging_defaults support
- Use fallback: embedded for graceful degradation
- Define plugin-level defaults in .hiivmind/blueprint/logging.yaml
```

---

## Related Documentation

- **Engine:** `lib/workflow/engine.md` - Execution engine with logging integration
- **Type Loader:** `lib/workflow/type-loader.md` - Type loading protocol (logging cache extends this)
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Configuration options
- **Consequence Types:** `lib/consequences/definitions/core/logging.yaml` - 10 logging consequences
- **Precondition Types:** `lib/preconditions/definitions/core/logging.yaml` - 3 logging preconditions
- **Log Schema:** `lib/schema/logging-schema.json` - Log output structure
