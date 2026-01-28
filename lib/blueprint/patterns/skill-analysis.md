# Skill Analysis Pattern

Analyze prose-based SKILL.md files to extract structural information for workflow conversion.

---

## Analysis Output

The analysis produces:

- **Phases** - Major execution stages
- **Actions** - Tool calls, computations
- **Conditionals** - Branching points
- **State variables** - Data flow between phases
- **User interactions** - Points requiring input

---

## Phase Detection

| Pattern | Example | Confidence |
|---------|---------|------------|
| Numbered heading | `## Step 1: Initialize` | High |
| Phase/Stage keyword | `### Phase: Validation` | High |
| Sequential numbering | `1. First...`, `2. Then...` | Medium |
| Temporal markers | `First`, `Next`, `Finally` | Medium |

---

## Conditional Detection

| Pattern | Type |
|---------|------|
| `If ... then ...` | if-then |
| `If ... otherwise ...` | if-else |
| `When ...` | conditional |
| `Unless ...` | negated |
| `Based on ...` | switch |

---

## Action Identification

| Prose Tool | Maps To |
|------------|---------|
| Read, read file | `read_file` |
| Write, create file | `write_file` |
| Edit, modify | `edit_file` |
| Bash, run command | `run_command` |
| Ask user, prompt | `user_prompt` node |
| Fetch, download | `web_fetch` |

---

## Complexity Classification

| Factor | Low | Medium | High |
|--------|-----|--------|------|
| Phases | 1-3 | 4-6 | 7+ |
| Conditionals | 0-1 | 2-4 | 5+ |
| Tool variety | 1-2 | 3-4 | 5+ |
| User interactions | 0-1 | 2-3 | 4+ |
| State variables | 1-3 | 4-7 | 8+ |

**Classification:** Average factor scores: <1.5 = low, <2.5 = medium, ≥2.5 = high

---

## Analysis Output Format

```yaml
analysis:
  skill_name: "example-skill"
  frontmatter:
    name: "hiivmind-corpus-example"
    description: "Example skill description"
    allowed_tools: [Read, Write, AskUserQuestion]

  complexity: "medium"

  phases:
    - id: "validate_input"
      title: "Validate Input"
      prose_location: "lines 15-28"
      actions:
        - tool: Read
          description: "Read config.yaml"
          line: 17
      conditionals:
        - location: "line 20"
          type: "if-else"
          condition: "file has header"

  state_variables:
    - name: "config"
      source: "file_read"
      defined_in: "validate_input"
      used_in: ["validate_input", "process_file"]

  user_interactions:
    - phase: "validate_input"
      type: "confirmation"
      question: "Proceed with processing?"

  conversion_recommendations:
    approach: "standard_workflow"
    estimated_nodes: 8
    logging_recommendation: "enable"
```

---

## Related Documentation

- **Node Mapping:** `lib/blueprint/patterns/node-mapping.md`
- **Workflow Generation:** `lib/blueprint/patterns/workflow-generation.md`
