# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**hiivmind-blueprint** is a meta-plugin for Claude Code that converts existing prose-based skills to deterministic YAML workflow patterns. It provides tools to analyze, convert, and generate workflow-driven skills following the patterns established in hiivmind-corpus.

The core value: Transform imperative prose instructions into declarative YAML workflows with preconditions, actions, and consequences—enabling predictable, testable skill execution.

## Architecture

```
├── skills/                           # Eight core skills (the meta-plugin)
│   ├── hiivmind-blueprint-init/      # Initialize blueprint project structure
│   ├── hiivmind-blueprint-analyze/   # Deep analysis of existing skill
│   ├── hiivmind-blueprint-convert/   # Convert analysis → workflow.yaml
│   ├── hiivmind-blueprint-generate/  # Write files to destination
│   ├── hiivmind-blueprint-gateway/   # Generate gateway command for multi-skill plugins
│   ├── hiivmind-blueprint-discover/  # Find skills, show conversion status
│   ├── hiivmind-blueprint-upgrade/   # Upgrade existing workflows to latest schema
│   └── hiivmind-blueprint-validate/  # Validate workflow.yaml for correctness
│
├── commands/                         # Slash commands
│   └── hiivmind-blueprint/           # Gateway command (self-dogfooding)
│       ├── hiivmind-blueprint.md
│       ├── workflow.yaml
│       └── intent-mapping.yaml
│
├── lib/
│   ├── consequences/                 # Legacy location - definitions now in hiivmind-blueprint-lib
│   │   └── definitions/              # DEPRECATED: Use hiivmind-blueprint-lib/consequences/
│   │
│   ├── preconditions/                # Legacy location - definitions now in hiivmind-blueprint-lib
│   │   └── definitions/              # DEPRECATED: Use hiivmind-blueprint-lib/preconditions/
│   │
│   ├── workflow/                     # Workflow reference documentation
│   │   ├── engine.md                 # Comprehensive workflow execution reference (schema + state + execution + dynamic routing + logging)
│   │   ├── type-loader.md            # External type definitions loader
│   │   ├── workflow-loader.md        # Remote workflow resolution protocol (v1.2+)
│   │   ├── logging-config-loader.md  # Logging configuration resolution protocol (v1.3+)
│   │   └── legacy/                   # Archived redundant documentation
│   │
│   ├── workflows/                    # Reusable sub-workflows (local fallback)
│   │   └── intent-detection.yaml     # Composable 3VL intent detection (O(1) routing) - also in lib
│   │       ├── README.md             # Archive index with deprecation notices
│   │       ├── schema.md             # Redirect to engine.md
│   │       ├── state.md              # Redirect to engine.md
│   │       ├── execution.md          # Redirect to engine.md
│   │       ├── preconditions.md      # YAML definitions authoritative
│   │       ├── validation-queries.md # Converted to validation workflow
│   │       ├── validation-report-format.md
│   │       ├── logging-schema.md     # JSON Schema at lib/schema/logging-schema.json
│   │       └── consequences/         # YAML definitions authoritative
│   │
│   ├── schema/                       # Schemas consolidated to hiivmind-blueprint-lib
│   │   └── README.md                 # Points to hiivmind-blueprint-lib/schema/
│   │
│   └── blueprint/patterns/           # Blueprint-specific patterns
│       ├── skill-analysis.md         # How to analyze SKILL.md structure
│       ├── node-mapping.md           # Map prose → workflow nodes
│       ├── intent-composition.md     # Composable intent detection pattern (O(1) vs O(N))
│       ├── workflow-generation.md    # Generate workflow.yaml
│       ├── type-resolution.md        # External type resolution protocol
│       ├── plugin-structure.md       # .hiivmind/blueprint/ layout (with logging.yaml v1.3+)
│       ├── logging-configuration.md  # 4-tier logging configuration + sub-workflow inheritance
│       └── consequence-extensions.md # Creating custom extensions
│
├── templates/                        # Templates for generation
│   ├── workflow.yaml.template        # Base workflow structure
│   ├── thin-loader.md.template       # Minimal SKILL.md template
│   ├── skill-with-executor.md.template # Thin SKILL.md with engine reference (NEW)
│   ├── gateway-command.md.template   # Gateway command template
│   ├── intent-mapping.yaml.template  # 3VL intent config template
│   ├── plugin.json.template          # Plugin manifest template
│   └── node-templates/               # Per-node-type templates
│       ├── action.yaml.template
│       ├── conditional.yaml.template
│       ├── user-prompt.yaml.template
│       ├── validation-gate.yaml.template
│       └── reference.yaml.template
│
├── references/                       # Reference documentation
│   ├── node-type-examples.md         # Examples of each node type
│   ├── precondition-examples.md      # Precondition usage examples
│   └── consequence-examples.md       # Consequence usage examples
│
├── CLAUDE.md                         # This file
└── README.md
```

## Skill Lifecycle

```
                        /hiivmind-blueprint (gateway command)
                                 │
                    hiivmind-blueprint-discover ← shows conversion status
                                 │
                                 ▼
hiivmind-blueprint-init → hiivmind-blueprint-analyze → hiivmind-blueprint-convert
       (once)                    │                              │
                                 │                              ▼
                                 │              hiivmind-blueprint-generate
                                 │                        │
                                 └── hiivmind-blueprint-gateway (multi-skill)
                                                          │
                                                          ├── hiivmind-blueprint-validate
                                                          │     (check workflow.yaml)
                                                          │
                                                          └── hiivmind-blueprint-upgrade
                                                                (when schema evolves)
```

**Core Skills:**
1. **hiivmind-blueprint-init**: Initialize blueprint project, copy lib frameworks
2. **hiivmind-blueprint-analyze**: Deep analysis of SKILL.md (phases, conditionals, actions)
3. **hiivmind-blueprint-convert**: Transform analysis into workflow.yaml
4. **hiivmind-blueprint-generate**: Write thin loader + workflow.yaml to skill directory
5. **hiivmind-blueprint-gateway**: Generate gateway command + intent-mapping for plugins
6. **hiivmind-blueprint-discover**: Scan skills, report conversion status
7. **hiivmind-blueprint-upgrade**: Update workflows to latest schema version
8. **hiivmind-blueprint-validate**: Validate workflow.yaml for schema, references, graph structure

## Key Design Decisions

### Conversion Philosophy

- **Preserve semantics**: Workflow must produce same behavior as prose
- **Explicit over implicit**: Make all branching and state visible in YAML
- **Progressive complexity**: Simple skills get simple workflows

### Gateway Recommendations

| Plugin Type | Recommendation |
|-------------|----------------|
| Single skill | Embed simple routing in SKILL.md |
| 2-3 skills | Optional gateway |
| 4+ skills | Gateway with 3VL intent detection |

### Complexity Classification

| Complexity | Indicators | Approach |
|------------|------------|----------|
| Low | 1-3 phases, linear | Single action chain |
| Medium | 4-6 phases, simple branching | Standard workflow |
| High | 7+ phases, complex loops | Manual review needed |

### Template Conventions

- `{{placeholder}}` in templates (generation time)
- `${variable}` in workflows (runtime interpolation)

## Workflow Schema (Summary)

Workflows are YAML files with this structure:

```yaml
workflow:
  id: skill-name
  version: "1.0"
  description: What the workflow does

phases:
  - id: phase_name
    description: What this phase accomplishes
    nodes:
      - id: action_id
        type: action
        description: What this action does
        tool: Read | Edit | Bash | ...
        preconditions:
          - type: file_exists
            path: "${some_path}"
        consequences:
          - type: file_read
            path: "${some_path}"
```

**Node Types:**
- `action` - Execute a tool call
- `conditional` - Branch based on state
- `user-prompt` - Get user input
- `validation-gate` - Verify state before continuing
- `reference` - Include another workflow

See `lib/workflow/engine.md` for complete specification.

## Analysis Output Format

The `analyze` skill produces structured output:

```yaml
analysis:
  skill_name: example-skill
  complexity: medium
  phases:
    - id: validate_input
      prose_location: "lines 15-28"
      actions:
        - description: "Check file exists"
          tool: Read
          conditional: false
        - description: "Validate format"
          tool: custom_validation
          conditional: true
          condition: "if file has header"
  conditionals:
    - location: "line 32"
      type: if-else
      branches: 2
      affects_phases: [validate_input]
  state_variables:
    - name: file_path
      source: user_input
      used_in: [validate_input, process_file]
```

## Lib Framework Usage

### Workflow Library

Skills reference workflow patterns from `lib/workflow/`:

```markdown
## Execute Phase

**See:** `lib/workflow/engine.md` - Phase execution semantics

For each phase in workflow.phases:
1. Check all preconditions
2. Execute nodes in order
3. Record consequences
```

### Intent Detection

Gateway commands use 3VL intent detection. The algorithms are self-contained in the consequence definitions (`parse_intent_flags`, `match_3vl_rules`). For conceptual overview, see `docs/intent-detection/`.

For practical implementation, see `docs/intent-detection-guide.md`.

## Working with Templates

Templates use `{{placeholder}}` syntax:

```yaml
# templates/workflow.yaml.template
workflow:
  id: {{skill_id}}
  version: "1.0"
  description: {{description}}

phases:
  - id: {{first_phase_id}}
    description: {{first_phase_description}}
    nodes: []
```

Generation replaces placeholders with analyzed values.

## Cross-Cutting Concerns

These features span multiple skills and must stay synchronized:

| Feature | Relevant Skills | What to Check |
|---------|-----------------|---------------|
| Workflow schema version | all skills | Schema compatibility |
| Node type catalog | analyze, convert, validate, templates | All node types documented |
| Precondition types | convert, generate, validate | Match lib/preconditions/definitions/ (33 types) |
| Consequence types | convert, generate, validate | Match lib/consequences/definitions/ (49 types) |
| 3VL intent rules | gateway, discover, validate | Rule syntax consistency |
| Dynamic routing | gateway, engine.md, intent-composition.md | `on_success: "${...}"` interpolation |
| Complexity classification | analyze, discover | Thresholds aligned |
| Validation queries | validate | Match engine.md and type definitions |
| Report format | validate | Consistent status icons and structure |
| JSON Schema definitions | validate, upgrade | Match YAML schema docs, all types included |
| Logging configuration | analyze, convert, generate, validate | Config/usage alignment |
| Logging config loader | engine.md, logging-config-loader.md | 4-tier hierarchy, auto-injection |

## Schema Validation

Use `check-jsonschema` to validate YAML files against JSON schemas. This tool is available at `~/.rye/shims/check-jsonschema`.

All schemas are consolidated in **hiivmind-blueprint-lib/schema/**.

### Available Schemas

| Schema | Validates | Location |
|--------|-----------|----------|
| `common.json` | Shared definitions (semver, identifiers) | `hiivmind-blueprint-lib/schema/` |
| `workflow.json` | workflow.yaml files | `hiivmind-blueprint-lib/schema/` |
| `workflow-definitions.json` | definitions block | `hiivmind-blueprint-lib/schema/` |
| `node-types.json` | Node type definitions | `hiivmind-blueprint-lib/schema/` |
| `consequence-definition.json` | Consequence YAML files | `hiivmind-blueprint-lib/schema/` |
| `precondition-definition.json` | Precondition YAML files | `hiivmind-blueprint-lib/schema/` |
| `intent-mapping.json` | intent-mapping.yaml files | `hiivmind-blueprint-lib/schema/` |
| `logging.json` | Workflow execution logs | `hiivmind-blueprint-lib/schema/` |
| `logging-config.json` | Plugin logging.yaml | `hiivmind-blueprint-lib/schema/` |

### Validation Commands

Schemas use `$ref` composition. Use `--base-uri` to resolve relative refs locally:

```bash
LIB_SCHEMA="file:///path/to/hiivmind-blueprint-lib/schema/"
SCHEMA_DIR="/path/to/hiivmind-blueprint-lib/schema"

# Validate a workflow file
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/workflow.json" \
  path/to/workflow.yaml

# Validate intent mapping
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/intent-mapping.json" \
  path/to/intent-mapping.yaml

# Validate logging config
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/logging-config.json" \
  .hiivmind/blueprint/logging.yaml

# Validate consequence definitions
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/consequence-definition.json" \
  consequences/core/*.yaml

# Validate precondition definitions
check-jsonschema --base-uri "$LIB_SCHEMA" \
  --schemafile "$SCHEMA_DIR/precondition-definition.json" \
  preconditions/core/*.yaml

# Verify a schema is valid JSON Schema
check-jsonschema --check-metaschema "$SCHEMA_DIR/workflow.json"
```

### Validating hiivmind-blueprint-lib Files

```bash
# From hiivmind-blueprint-lib directory
check-jsonschema --base-uri "file://$(pwd)/schema/" \
  --schemafile schema/workflow.json \
  workflows/core/intent-detection.yaml
```

### YAML Gotchas

When writing YAML that will be validated against JSON Schema:

| Issue | Problem | Solution |
|-------|---------|----------|
| Numeric strings | `version: 1.0` becomes float | Quote: `version: "1.0"` |
| Yes/No values | `enabled: yes` becomes boolean | Quote: `enabled: "yes"` |

Example - conditional node branches use semantic key names to avoid YAML boolean parsing issues:
```yaml
branches:
  on_true: next_node_a    # Semantic key - no quoting needed
  on_false: next_node_b   # Semantic key - no quoting needed
```

## External Type Definitions

Type definitions (consequences and preconditions) are externalized in `hiivmind-blueprint-lib` for versioning and reuse.

### Repository: hiivmind-blueprint-lib

The canonical type definitions are published at:
- **GitHub**: `hiivmind/hiivmind-blueprint-lib`

### Using External Definitions

Workflows reference external types via raw GitHub URLs:

```yaml
# workflow.yaml
definitions:
  source: hiivmind/hiivmind-blueprint-lib@v2.0.0

nodes:
  clone_source:
    type: action
    actions:
      - type: clone_repo          # Resolved from external definitions
        url: "${source.url}"
```

### URL Construction

```
hiivmind/hiivmind-blueprint-lib@v2.0.0
  → https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.0.0/
```

### Version Pinning

| Reference | Behavior |
|-----------|----------|
| `@v2.0.0` | Exact version (recommended for production) |
| `@v2.0` | Latest patch in v2.0.x |
| `@v2` | Latest minor in v2.x.x (development) |

### Type Inventory

| Category | Count | Examples |
|----------|-------|----------|
| Consequences | 43 | set_state, clone_repo, web_fetch, parse_intent_flags |
| Preconditions | 27 | file_exists, flag_set, all_of, evaluate_expression |
| Workflows | 1 | intent-detection |
| Node Types | 5 | action, conditional, user_prompt, validation_gate, reference |

See `lib/blueprint/patterns/type-resolution.md` for implementation details.

### Logging Configuration (v1.3+)

Logging configuration follows a 4-tier priority hierarchy:

```
1. Runtime flags (--log-level=debug)           ← Highest priority
2. Workflow initial_state.logging              ← Skill-specific
3. Plugin .hiivmind/blueprint/logging.yaml     ← Plugin-wide
4. Remote defaults from lib (always fetched)   ← Framework defaults
```

Key features:
- **Auto-injection**: Engine injects `init_log`, `log_node`, `finalize_log`, `write_log` based on `auto.*` flags
- **Sub-workflow inheritance**: Sub-workflows inherit parent's logging config by default
- **Override support**: Pass `context.logging` in reference nodes to override for specific sub-workflows

See `lib/workflow/logging-config-loader.md` for the loading protocol.

### Referencing Remote Workflows (v1.2+)

Gateway workflows can reference sub-workflows from the lib:

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.0.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
  next_node: execute_dynamic_route
```

See `lib/workflow/workflow-loader.md` for the loading protocol.

## Target Plugin Structure

When generating workflows for a target plugin, Blueprint creates this structure:

```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Workflow execution semantics (copied)
│       └── logging.yaml           # Plugin-wide logging defaults (optional, v1.3+)
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # Thin loader referencing engine
│       └── workflow.yaml
```

See `lib/blueprint/patterns/plugin-structure.md` for full documentation.

## Self-Dogfooding

This plugin uses its own patterns:

- `/hiivmind-blueprint` gateway command has `workflow.yaml` + `intent-mapping.yaml`
- Each skill follows the thin loader pattern it generates
- Gateway uses 3VL intent detection to route requests

## Plugin Development Resources

When working on plugin structure, use the `plugin-dev` skills for guidance:

| Skill | Use When |
|-------|----------|
| `plugin-dev:plugin-structure` | Plugin manifest, directory layout |
| `plugin-dev:skill-development` | Writing SKILL.md files, descriptions |
| `plugin-dev:command-development` | Slash commands, YAML frontmatter |
