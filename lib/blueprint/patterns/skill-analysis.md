# Skill Analysis Pattern

Techniques for analyzing existing prose-based SKILL.md files to extract structural information for workflow conversion.

---

## Overview

Skill analysis produces a structured report containing:
- **Phases** - Major execution stages
- **Actions** - Discrete operations (tool calls, computations)
- **Conditionals** - Branching points with conditions
- **State variables** - Data that flows between phases
- **User interactions** - Points requiring user input

---

## Analysis Process

```
┌─────────────────────────────────────────────────────────────────┐
│  Step 1: READ SKILL.MD                                          │
│  - Parse frontmatter (name, description, allowed-tools)         │
│  - Extract body content                                         │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 2: IDENTIFY PHASES                                        │
│  - Look for numbered sections, headings                         │
│  - Detect "Phase", "Step", "Stage" language                     │
│  - Group contiguous instructions                                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 3: EXTRACT CONDITIONALS                                   │
│  - Find "if", "when", "unless", "otherwise"                     │
│  - Map condition to branches                                    │
│  - Note which phases are affected                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 4: IDENTIFY ACTIONS                                       │
│  - Tool references (Read, Write, Bash, etc.)                    │
│  - Data transformations                                         │
│  - State mutations                                              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 5: MAP STATE FLOW                                         │
│  - Input parameters                                             │
│  - Computed values                                              │
│  - Values passed between phases                                 │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│  Step 6: PRODUCE ANALYSIS REPORT                                │
│  - Structured YAML output                                       │
│  - Complexity classification                                    │
│  - Conversion recommendations                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase Detection

### Indicators

| Pattern | Example | Confidence |
|---------|---------|------------|
| Numbered heading | `## Step 1: Initialize` | High |
| Phase/Stage keyword | `### Phase: Validation` | High |
| Sequential numbering | `1. First, ...`, `2. Then, ...` | Medium |
| Temporal markers | `First`, `Next`, `Finally` | Medium |
| Section breaks | `---` between sections | Low |

### Heuristics

```
FUNCTION detect_phases(content):
  phases = []
  current_phase = null

  FOR each line IN content:
    # Check for explicit phase markers
    IF line matches /^#{1,3}\s*(Step|Phase|Stage)\s*\d*[:.]?\s*(.+)/i:
      IF current_phase:
        phases.append(current_phase)
      current_phase = {
        id: slugify(match[2]),
        title: match[2],
        start_line: line_number,
        content: []
      }

    # Check for numbered headings
    ELSE IF line matches /^#{1,3}\s*\d+[.):]\s*(.+)/:
      IF current_phase:
        phases.append(current_phase)
      current_phase = {
        id: slugify(match[1]),
        title: match[1],
        start_line: line_number,
        content: []
      }

    # Accumulate content
    IF current_phase:
      current_phase.content.append(line)

  IF current_phase:
    phases.append(current_phase)

  RETURN phases
```

---

## Conditional Detection

### Language Patterns

| Pattern | Type | Example |
|---------|------|---------|
| `If ... then ...` | if-then | "If config exists, read it" |
| `If ... otherwise ...` | if-else | "If git, clone; otherwise fetch" |
| `When ...` | conditional | "When the user selects..." |
| `Unless ...` | negated | "Unless skipped, run tests" |
| `Based on ...` | switch | "Based on source type:" |
| `Depending on ...` | switch | "Depending on the result" |

### Extraction Algorithm

```
FUNCTION extract_conditionals(phase_content):
  conditionals = []

  # Regex patterns for conditional language
  patterns = [
    /if\s+(.+?)\s*[,:]?\s*then\s+(.+)/i,
    /if\s+(.+?)\s*[,:]?\s*otherwise\s+(.+)/i,
    /when\s+(.+?)\s*[,:]?\s*(.+)/i,
    /unless\s+(.+?)\s*[,:]?\s*(.+)/i,
    /based on\s+(.+?)\s*[,:]/i,
    /depending on\s+(.+?)\s*[,:]/i
  ]

  FOR each line, line_number IN phase_content:
    FOR each pattern IN patterns:
      IF line matches pattern:
        conditional = {
          location: "line {line_number}",
          type: infer_type(pattern),
          condition: match[1],
          prose: line
        }

        # Look for branches in following lines
        conditional.branches = extract_branches(phase_content, line_number)

        conditionals.append(conditional)

  RETURN conditionals
```

### Branch Extraction

```
FUNCTION extract_branches(content, start_line):
  branches = []
  indent_level = get_indent(content[start_line])

  FOR line_number = start_line + 1 TO len(content):
    line = content[line_number]
    line_indent = get_indent(line)

    # Stop at same or lower indent
    IF line_indent <= indent_level AND not is_continuation(line):
      BREAK

    # Check for branch indicators
    IF line matches /^\s*[-•]\s*(.+)/:
      branches.append({
        description: match[1],
        line: line_number
      })

    ELSE IF line matches /^\s*(otherwise|else|if not|alternatively)[,:]\s*(.+)/i:
      branches.append({
        type: "else",
        description: match[2],
        line: line_number
      })

  RETURN branches
```

---

## Action Identification

### Tool References

Look for Claude Code tool mentions:

| Tool | Patterns |
|------|----------|
| Read | `Read`, `read file`, `read the`, `reading` |
| Write | `Write`, `write to`, `create file`, `writing` |
| Edit | `Edit`, `modify`, `update file`, `change` |
| Bash | `Bash`, `run command`, `execute`, `shell` |
| Glob | `Glob`, `find files`, `search for files` |
| Grep | `Grep`, `search content`, `find in files` |
| AskUserQuestion | `ask`, `prompt`, `user input`, `select` |
| WebFetch | `fetch`, `download`, `HTTP`, `URL` |

### Action Extraction

```
FUNCTION extract_actions(phase_content):
  actions = []

  tool_patterns = {
    "Read": [/read\s+(\S+)/i, /read\s+the\s+file/i],
    "Write": [/write\s+to\s+(\S+)/i, /create\s+(\S+)/i],
    "Edit": [/edit\s+(\S+)/i, /modify\s+(\S+)/i],
    "Bash": [/run\s+(.+)/i, /execute\s+(.+)/i],
    "Glob": [/find\s+files/i, /glob\s+(.+)/i],
    "Grep": [/search\s+for\s+["'](.+)["']/i, /grep\s+(.+)/i],
    "AskUserQuestion": [/ask\s+(the\s+)?user/i, /prompt\s+for/i],
    "WebFetch": [/fetch\s+(https?:\/\/\S+)/i, /download/i]
  }

  FOR each line, line_number IN phase_content:
    FOR each tool, patterns IN tool_patterns:
      FOR each pattern IN patterns:
        IF line matches pattern:
          actions.append({
            tool: tool,
            description: line.trim(),
            line: line_number,
            parameters: extract_parameters(line, pattern)
          })

  RETURN actions
```

---

## State Variable Detection

### Sources of State

| Source | Example |
|--------|---------|
| Frontmatter | `arguments`, `CLAUDE_PLUGIN_ROOT` |
| User input | Response from AskUserQuestion |
| File reads | Config parsed from YAML |
| Computations | Derived values |
| External | Git SHA, timestamps |

### Detection Algorithm

```
FUNCTION detect_state_variables(phases):
  variables = {}

  FOR each phase IN phases:
    FOR each line IN phase.content:
      # Check for variable assignment patterns
      IF line matches /store\s+(?:as|in|to)\s+(\w+)/i:
        variables[match[1]] = {
          source: "computed",
          defined_in: phase.id
        }

      IF line matches /(\w+)\s*=\s*(.+)/i:
        variables[match[1]] = {
          source: "assignment",
          defined_in: phase.id
        }

      # Check for variable usage
      IF line matches /\$\{(\w+(?:\.\w+)*)\}/:
        var_name = match[1].split('.')[0]
        IF var_name NOT IN variables:
          variables[var_name] = {
            source: "external",
            first_used: phase.id
          }

  # Track where each variable is used
  FOR each phase IN phases:
    FOR each line IN phase.content:
      FOR each var_name IN variables:
        IF line.contains(var_name):
          IF "used_in" NOT IN variables[var_name]:
            variables[var_name].used_in = []
          variables[var_name].used_in.append(phase.id)

  RETURN variables
```

---

## Complexity Classification

### Scoring Factors

| Factor | Low (1) | Medium (2) | High (3) |
|--------|---------|------------|----------|
| Phase count | 1-3 | 4-6 | 7+ |
| Conditionals | 0-1 | 2-4 | 5+ |
| Branching depth | Linear | 2 levels | 3+ levels |
| Tool variety | 1-2 tools | 3-4 tools | 5+ tools |
| User interactions | 0-1 | 2-3 | 4+ |
| State variables | 1-3 | 4-7 | 8+ |

### Classification Algorithm

```
FUNCTION classify_complexity(analysis):
  score = 0

  # Phase count
  IF analysis.phases.length <= 3:
    score += 1
  ELSE IF analysis.phases.length <= 6:
    score += 2
  ELSE:
    score += 3

  # Conditional count
  total_conditionals = sum(p.conditionals.length for p in analysis.phases)
  IF total_conditionals <= 1:
    score += 1
  ELSE IF total_conditionals <= 4:
    score += 2
  ELSE:
    score += 3

  # ... similar for other factors ...

  # Classify
  average = score / 6  # Number of factors
  IF average < 1.5:
    RETURN "low"
  ELSE IF average < 2.5:
    RETURN "medium"
  ELSE:
    RETURN "high"
```

---

## Analysis Output Format

```yaml
analysis:
  skill_name: "example-skill"
  frontmatter:
    name: "hiivmind-corpus-example"
    description: "Example skill description"
    allowed_tools:
      - Read
      - Write
      - AskUserQuestion

  complexity: "medium"

  phases:
    - id: "validate_input"
      title: "Validate Input"
      prose_location: "lines 15-28"
      actions:
        - tool: Read
          description: "Read config.yaml"
          conditional: false
          line: 17
        - tool: custom
          description: "Validate format"
          conditional: true
          condition: "if file has header"
          line: 22
      conditionals:
        - location: "line 20"
          type: "if-else"
          condition: "file has header"
          branches:
            - description: "proceed with validation"
            - description: "return error"

    - id: "process_file"
      title: "Process File"
      prose_location: "lines 30-55"
      actions:
        - tool: Read
          description: "Read source file"
          line: 32
        - tool: Write
          description: "Write output"
          line: 50

  state_variables:
    - name: "config"
      source: "file_read"
      defined_in: "validate_input"
      used_in: ["validate_input", "process_file"]
    - name: "output_path"
      source: "computed"
      defined_in: "process_file"
      used_in: ["process_file"]

  user_interactions:
    - phase: "validate_input"
      type: "confirmation"
      question: "Proceed with processing?"
      line: 25

  conversion_recommendations:
    approach: "standard_workflow"
    estimated_nodes: 8
    notes:
      - "Two phases map cleanly to workflow phases"
      - "Single conditional can be a conditional node"
      - "Consider checkpoint before write operation"
```

---

## Related Documentation

- **Node Mapping:** `lib/blueprint/patterns/node-mapping.md`
- **Workflow Generation:** `lib/blueprint/patterns/workflow-generation.md`
- **Workflow Schema:** `lib/workflow/schema.md`
