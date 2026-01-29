# Skill Analysis Guide

Understand how hiivmind-blueprint analyzes prose SKILL.md files for workflow conversion.

## Running Analysis

```
/hiivmind-blueprint analyze path/to/SKILL.md
```

Or through the gateway:

```
/hiivmind-blueprint analyze my-skill
```

## What Gets Analyzed

### 1. Frontmatter Parsing

Extracts YAML frontmatter:

```yaml
---
name: my-skill
description: >
  Does something useful
allowed-tools: Read, Write, AskUserQuestion
---
```

**Extracted:**
- `name` - Skill identifier
- `description` - Used for workflow description
- `allowed_tools` - Suggests needed consequences

### 2. Phase Detection

Identifies major execution stages by looking for:

| Pattern | Confidence |
|---------|------------|
| `## Step 1: Initialize` | High |
| `### Phase: Validation` | High |
| `1. First, ...` | Medium |
| `First`, `Next`, `Finally` | Medium |

**Example prose:**
```markdown
## Phase 1: Load Configuration

Read config.yaml and validate the schema.

## Phase 2: Process Sources

For each source, clone and index.
```

**Detected:**
- Phase 1: `load_configuration` (lines 1-5)
- Phase 2: `process_sources` (lines 7-10)

### 3. Conditional Detection

Finds branching points:

| Prose Pattern | Detected Type |
|---------------|---------------|
| "If X then Y" | if-then |
| "If X otherwise Y" | if-else |
| "When X, do Y" | conditional |
| "Unless X, do Y" | negated |
| "Based on X:" | switch (multi-branch) |

**Example:**
```markdown
If the config exists, read it; otherwise create a template.
```

**Detected:**
```yaml
conditionals:
  - location: "line 15"
    type: "if-else"
    condition: "config exists"
    branches:
      - "read it"
      - "create a template"
```

### 4. Action Extraction

Maps tool references to workflow actions:

| Prose | Detected Tool |
|-------|---------------|
| "Read the config file" | Read |
| "Write the output" | Write |
| "Ask the user" | AskUserQuestion |
| "Run git clone" | Bash |
| "Fetch the URL" | WebFetch |

**Example:**
```markdown
Read config.yaml and store the contents.
```

**Detected:**
```yaml
actions:
  - tool: Read
    description: "Read config.yaml and store the contents"
    line: 12
```

### 5. State Variable Tracking

Identifies data flow:

| Source | Detection |
|--------|-----------|
| `store as X` | Computed value |
| `${variable}` | Reference |
| User response | User input |
| External (git, timestamp) | External |

**Example:**
```markdown
Read config.yaml and store as `config`.
Use ${config.sources} for iteration.
```

**Detected:**
```yaml
state_variables:
  - name: "config"
    source: "computed"
    defined_in: "load_config"
    used_in: ["load_config", "process_sources"]
```

### 6. User Interaction Detection

Finds points requiring user input:

**Example:**
```markdown
Ask user what type of source to add:
- Git repository
- Local files
- Web pages
```

**Detected:**
```yaml
user_interactions:
  - phase: "add_source"
    type: "selection"
    question: "What type of source to add"
    options: 3
```

## Complexity Classification

Analysis produces a complexity score:

| Factor | Low | Medium | High |
|--------|-----|--------|------|
| Phases | 1-3 | 4-6 | 7+ |
| Conditionals | 0-1 | 2-4 | 5+ |
| Tool variety | 1-2 | 3-4 | 5+ |
| User interactions | 0-1 | 2-3 | 4+ |
| State variables | 1-3 | 4-7 | 8+ |

**Classification:**
- Average < 1.5 → `low`
- Average < 2.5 → `medium`
- Average ≥ 2.5 → `high`

### Complexity Implications

| Complexity | Conversion Approach |
|------------|---------------------|
| Low | Automatic conversion reliable |
| Medium | Automatic with manual review |
| High | Manual assistance recommended |

## Analysis Output Format

```yaml
analysis:
  skill_name: "corpus-refresh"
  frontmatter:
    name: "hiivmind-corpus-refresh"
    description: "Check sources for updates"
    allowed_tools: [Read, Write, Bash, AskUserQuestion]

  complexity: "medium"

  phases:
    - id: "check_config"
      title: "Check Configuration"
      prose_location: "lines 10-25"
      actions:
        - tool: Read
          description: "Read config.yaml"
          line: 12
      conditionals: []

    - id: "scan_sources"
      title: "Scan Sources"
      prose_location: "lines 27-60"
      actions:
        - tool: Bash
          description: "Run git fetch"
          line: 35
      conditionals:
        - location: "line 42"
          type: "if-else"
          condition: "source has updates"

  state_variables:
    - name: "config"
      source: "file_read"
      defined_in: "check_config"
      used_in: ["check_config", "scan_sources"]

  user_interactions:
    - phase: "scan_sources"
      type: "confirmation"
      question: "Pull updates?"

  conversion_recommendations:
    approach: "standard_workflow"
    estimated_nodes: 12
    logging_recommendation: "enable"
    notes:
      - "Multiple source iteration may need spawn_agent"
      - "Consider checkpoints before git pulls"
```

## Using Analysis Output

The analysis feeds into the convert skill:

```
/hiivmind-blueprint convert
```

Or save analysis for review:

```
/hiivmind-blueprint analyze my-skill --save analysis.yaml
```

## Tips

1. **Clear phase markers help:** Use `## Phase X:` or `## Step X:` in prose
2. **Explicit conditions help:** Write "If X then Y; otherwise Z"
3. **Tool mentions help:** Reference tools by name when possible
4. **State assignment helps:** Use "store as X" or "save to X"

## Next Steps

- [Workflow Authoring Guide](workflow-authoring-guide.md) - Manual workflow creation
- [Getting Started](getting-started.md) - Full conversion workflow
