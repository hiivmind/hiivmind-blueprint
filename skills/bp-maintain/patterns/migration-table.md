# Migration Table

Complete migration changes for each schema version step, with before/after YAML examples.

## 2.0 -> 2.1: Replace validation_gate with conditional + audit

### Change

Remove `validation_gate` node type. Replace with `conditional` node using `audit` config.

### Before (v2.0)

```yaml
nodes:
  check_inputs:
    type: validation_gate
    description: "Validate all required inputs"
    validations:
      - type: path_check
        path: "${computed.config_path}"
        error_message: "Config file not found"
      - type: state_check
        field: "flags.initialized"
        operator: "true"
        error_message: "System not initialized"
    on_valid: process_data
    on_invalid: validation_failed
```

### After (v2.1)

```yaml
nodes:
  check_inputs:
    type: conditional
    description: "Validate all required inputs"
    condition:
      type: all_of
      conditions:
        - type: path_check
          path: "${computed.config_path}"
        - type: state_check
          field: "flags.initialized"
          operator: "true"
    audit:
      enabled: true
      output: "computed.validation_errors"
      messages:
        path_check: "Config file not found"
        state_check: "System not initialized"
    branches:
      on_true: process_data
      on_false: validation_failed
```

### Key Mappings

| v2.0 Field | v2.1 Field |
|------------|------------|
| `type: validation_gate` | `type: conditional` |
| `validations[]` | `condition.conditions[]` |
| `on_valid` | `branches.on_true` |
| `on_invalid` | `branches.on_false` |
| `validations[].error_message` | `audit.messages[type]` |

---

## 2.1 -> 2.2: Unify logging/display into output config

### Change

Merge separate `logging` and `display` configs under `initial_state` into a single
`output` config.

### Before (v2.1)

```yaml
initial_state:
  logging:
    enabled: true
    format: "yaml"
    location: ".logs/"
    level: "normal"
    ci_mode: false
  display:
    enabled: true
    use_icons: true
    batch:
      enabled: true
      threshold: 3
```

### After (v2.2)

```yaml
initial_state:
  output:
    level: "normal"
    display_enabled: true
    batch_enabled: true
    batch_threshold: 3
    use_icons: true
    log_enabled: true
    log_format: "yaml"
    log_location: ".logs/"
    ci_mode: false
```

### Key Mappings

| v2.1 Field | v2.2 Field |
|------------|------------|
| `logging.enabled` | `output.log_enabled` |
| `logging.format` | `output.log_format` |
| `logging.location` | `output.log_location` |
| `logging.level` | `output.level` |
| `logging.ci_mode` | `output.ci_mode` |
| `display.enabled` | `output.display_enabled` |
| `display.use_icons` | `output.use_icons` |
| `display.batch.enabled` | `output.batch_enabled` |
| `display.batch.threshold` | `output.batch_threshold` |

---

## 2.2 -> 2.3: Add prompts configuration

### Change

Add `prompts` configuration under `initial_state` for multi-modal support.

### Before (v2.2)

```yaml
initial_state:
  output:
    level: "normal"
    # ... output fields
```

### After (v2.3)

```yaml
initial_state:
  output:
    level: "normal"
    # ... output fields
  prompts:
    interface: "auto"
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"
      other_handler: "prompt"
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.7
```

### Default Values

The `prompts` config is added with sensible defaults. The `interface: "auto"` setting
auto-detects the runtime environment.

---

## 2.3 -> 2.4: Make output and prompts required

### Change

Both `output` and `prompts` configs become required. If either is missing or incomplete,
fill in default values for missing fields.

### Output Defaults

```yaml
output:
  level: "normal"
  display_enabled: true
  batch_enabled: true
  batch_threshold: 3
  use_icons: true
  log_enabled: true
  log_format: "yaml"
  log_location: ".logs/"
  ci_mode: false
```

### Prompts Defaults

```yaml
prompts:
  interface: "auto"
  modes:
    claude_code: "interactive"
    web: "forms"
    api: "structured"
    agent: "autonomous"
  tabular:
    match_strategy: "prefix"
    other_handler: "prompt"
  autonomous:
    strategy: "best_match"
    confidence_threshold: 0.7
```

### Behavior

- If `output` exists but is missing fields, add the missing fields with defaults
- If `output` does not exist, add the full default config
- Same for `prompts`
- This migration is idempotent — running it on a complete v2.4 config is a no-op
