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
│   ├── consequences/                 # Consequence type definitions (extracted to hiivmind-blueprint-types)
│   │   ├── definitions/
│   │   │   ├── index.yaml            # Master registry (49 types)
│   │   │   ├── core/                 # 30 core consequences
│   │   │   │   ├── state.yaml        # set_flag, set_state, append_state, clear_state, merge_state
│   │   │   │   ├── evaluation.yaml   # evaluate, compute
│   │   │   │   ├── interaction.yaml  # display_message, display_table
│   │   │   │   ├── control.yaml      # create_checkpoint, rollback_checkpoint, spawn_agent
│   │   │   │   ├── skill.yaml        # invoke_pattern, invoke_skill
│   │   │   │   ├── utility.yaml      # set_timestamp, compute_hash
│   │   │   │   ├── intent.yaml       # evaluate_keywords, parse_intent_flags, match_3vl_rules, dynamic_route
│   │   │   │   └── logging.yaml      # init_log, log_node, log_event, etc. (10 types)
│   │   │   └── extensions/           # 19 extension consequences
│   │   │       ├── file-system.yaml  # read_file, write_file, create_directory, delete_file
│   │   │       ├── git.yaml          # clone_repo, get_sha, git_pull, git_fetch
│   │   │       ├── web.yaml          # web_fetch, cache_web_content
│   │   │       ├── scripting.yaml    # run_script, run_python, run_bash
│   │   │       └── validation.yaml   # validate_yaml_schema, validate_node_references, etc. (6 types)
│   │   └── schema/
│   │       └── consequence-definition.json
│   │
│   ├── preconditions/                # Precondition type definitions (extracted to hiivmind-blueprint-types)
│   │   ├── definitions/
│   │   │   ├── index.yaml            # Master registry (33 types)
│   │   │   ├── core/                 # 22 core preconditions
│   │   │   │   ├── filesystem.yaml   # config_exists, file_exists, directory_exists, etc.
│   │   │   │   ├── state.yaml        # flag_set, state_equals, count_above, etc.
│   │   │   │   ├── tool.yaml         # tool_available, python_module_available
│   │   │   │   ├── composite.yaml    # all_of, any_of, none_of
│   │   │   │   ├── expression.yaml   # evaluate_expression
│   │   │   │   └── logging.yaml      # log_initialized, log_level_enabled, log_finalized
│   │   │   └── extensions/           # 11 extension preconditions
│   │   │       ├── source.yaml       # source_exists, source_cloned, source_has_updates
│   │   │       ├── web.yaml          # fetch_succeeded, fetch_returned_content
│   │   │       └── validation.yaml   # schema_valid, references_valid, types_exist, etc. (6 types)
│   │   └── schema/
│   │       └── precondition-definition.json
│   │
│   ├── workflow/                     # Workflow reference documentation
│   │   ├── engine.md                 # Comprehensive workflow execution reference (schema + state + execution)
│   │   ├── type-loader.md            # External type definitions loader
│   │   └── legacy/                   # Archived redundant documentation
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
│   ├── types/                        # Embedded type definitions fallback (NEW)
│   │   ├── bundle.yaml               # Aggregated types (43 consequences, 27 preconditions)
│   │   └── README.md                 # Embedded types documentation
│   │
│   ├── schema/                       # JSON Schema definitions
│   │   ├── workflow-schema.json      # Formal workflow.yaml schema (v2.1 with definitions)
│   │   ├── logging-schema.json       # Workflow execution log structure
│   │   ├── intent-mapping-schema.json
│   │   └── types-lock-schema.json    # Lock file validation schema
│   │
│   ├── intent_detection/             # 3VL intent detection framework
│   │   ├── framework.md              # 3VL concepts and rules
│   │   ├── execution.md              # Intent resolution semantics
│   │   └── variables.md              # Variable extraction patterns
│   │
│   └── blueprint/patterns/           # Blueprint-specific patterns
│       ├── skill-analysis.md         # How to analyze SKILL.md structure
│       ├── node-mapping.md           # Map prose → workflow nodes
│       ├── workflow-generation.md    # Generate workflow.yaml
│       ├── type-resolution.md        # External type resolution protocol
│       ├── plugin-structure.md       # .hiivmind/blueprint/ layout
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

### Intent Detection Library

Gateway commands use `lib/intent_detection/`:

```markdown
## Route User Request

**See:** `lib/intent_detection/framework.md` - 3VL resolution

Evaluate intent rules in priority order...
```

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
| Complexity classification | analyze, discover | Thresholds aligned |
| Validation queries | validate | Match engine.md and type definitions |
| Report format | validate | Consistent status icons and structure |
| JSON Schema definitions | validate, upgrade | Match YAML schema docs, all types included |
| Logging configuration | analyze, convert, generate, validate | Config/usage alignment |

## External Type Definitions

Type definitions (consequences and preconditions) can be externalized for versioning and reuse.

### Repository: hiivmind-blueprint-types

The canonical type definitions are published at:
- **GitHub**: `hiivmind/hiivmind-blueprint-types`
- **Bundle**: `https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml`

### Using External Definitions

Workflows can reference external types:

```yaml
# workflow.yaml
definitions:
  source: https://github.com/hiivmind/hiivmind-blueprint-types/releases/download/v1.0.0/bundle.yaml

nodes:
  clone_source:
    type: action
    actions:
      - type: clone_repo          # Resolved from external definitions
        url: "${source.url}"
```

### Source Options

| Format | Example | Usage |
|--------|---------|-------|
| URL | `https://github.com/.../bundle.yaml` | Direct fetch |
| Local | `source: local` + `path: ./vendor/...` | Embedded |
| Shorthand | `hiivmind/hiivmind-blueprint-types@v1.0.0` | GitHub release |

### Hybrid Model

Both external and embedded definitions are supported:

- **External** (default for new workflows): Reference by URL
- **Embedded** (for offline/airgapped): Bundle in `vendor/` directory

### Version Pinning

| Reference | Behavior |
|-----------|----------|
| `@v1.0.0` | Exact version (recommended for production) |
| `@v1.0` | Latest patch in v1.0.x |
| `@v1` | Latest minor in v1.x.x (development) |

### Type Inventory (v1.1.0)

| Category | Count | Examples |
|----------|-------|----------|
| Consequences | 49 | set_state, clone_repo, web_fetch, validate_yaml_schema |
| Preconditions | 33 | file_exists, flag_set, all_of, schema_valid |
| Node Types | 5 | action, conditional, user_prompt, validation_gate, reference |

See `lib/blueprint/patterns/type-resolution.md` for implementation details.

## Target Plugin Structure

When generating workflows for a target plugin, Blueprint creates this structure:

```
{target_plugin}/
├── .hiivmind/
│   └── blueprint/
│       ├── engine.md              # Workflow execution semantics (copied)
│       └── types.lock             # Pinned versions and SHAs
├── skills/
│   └── my-skill/
│       ├── SKILL.md               # Thin loader referencing engine
│       └── workflow.yaml
```

### Lock File Format

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
  hiivmind/hiivmind-blueprint-types:
    requested: "@v1"
    resolved: "v1.3.2"
    sha256: "def456..."
    fetched_at: "2026-01-27T05:30:00Z"
```

### Global Cache

Types and engine versions are cached at user level:

```
~/.claude/cache/hiivmind/blueprint/
├── types/{owner}/{repo}/{version}/
│   ├── bundle.yaml
│   └── metadata.yaml
└── engine/{version}/
    └── engine.md
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
