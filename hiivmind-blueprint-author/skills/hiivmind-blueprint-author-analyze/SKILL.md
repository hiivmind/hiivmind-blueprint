---
name: hiivmind-blueprint-author-analyze
description: >
  This skill should be used when the user asks to "analyze a skill", "examine SKILL.md structure",
  "understand skill complexity", "extract phases from skill", "what does this skill do",
  "check if skill can be converted", or needs to understand an existing skill's structure before
  conversion. Triggers on "analyze skill", "blueprint analyze", "hiivmind-blueprint analyze",
  "skill analysis", "examine skill", or when user provides a path to a SKILL.md file.
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Analyze Skill

Deep analysis of an existing prose-based SKILL.md file to extract structural information for workflow conversion.

> **Pattern Documentation:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

---

## Overview

This skill analyzes a prose-based SKILL.md and produces:
- **Phases** - Major execution stages identified in the skill
- **Actions** - Discrete tool calls and operations
- **Conditionals** - Branching points with conditions
- **State variables** - Data flowing between phases
- **User interactions** - Points requiring user input
- **Complexity classification** - Low/medium/high rating

---

## Phase 1: Locate Skill

### Step 1.1: Determine Target Skill

If user provided a path:
1. Validate the path exists
2. Read the SKILL.md file
3. Store in `computed.skill_content`

If no path provided:
1. **Ask user** which skill to analyze:
   - Present AskUserQuestion:
     ```json
     {
       "questions": [{
         "question": "Which skill would you like me to analyze?",
         "header": "Target",
         "multiSelect": false,
         "options": [
           {"label": "Provide path", "description": "I'll give you the SKILL.md path"},
           {"label": "Search current directory", "description": "Look for skills in this repo"},
           {"label": "Search installed plugins", "description": "Find installed Claude Code skills"}
         ]
       }]
     }
     ```
2. Based on response:
   - **Provide path**: Ask for the path, then read file
   - **Search current directory**: Glob for `**/SKILL.md`, present list
   - **Search installed plugins**: Check `~/.claude/skills/` and `.claude-plugin/skills/`

### Step 1.2: Parse Frontmatter

Extract from SKILL.md frontmatter:
- `name` - Skill identifier
- `description` - Trigger description
- `allowed-tools` - Tools the skill can use

Store in:
```yaml
computed:
  skill_name: "extracted name"
  original_description: "extracted description"
  allowed_tools: ["Read", "Write", ...]
```

---

## Phase 2: Structural Analysis

### Step 2.1: Identify Phases

Scan the skill content for phase markers:

**High-confidence indicators:**
- `## Step 1:`, `### Phase:`, `## Stage 1`
- Numbered headings with colons
- Explicit "Phase" or "Step" keywords

**Medium-confidence indicators:**
- Sequential numbered lists: `1. First...`, `2. Then...`
- Temporal markers: `First`, `Next`, `Finally`

**Low-confidence indicators:**
- Horizontal rules (`---`) between sections
- Major heading changes

For each detected phase, record:
```yaml
phases:
  - id: "slugified_phase_name"
    title: "Original Phase Title"
    prose_location: "lines X-Y"
    content_lines: [array of line numbers]
```

### Step 2.2: Extract Conditionals

Within each phase, look for conditional language:

| Pattern | Type | Branches |
|---------|------|----------|
| `If ... then ...` | if-then | 1 (implied else) |
| `If ... otherwise ...` | if-else | 2 explicit |
| `When ...` | conditional | varies |
| `Based on ...` | switch | 2+ options |
| `Depending on ...` | switch | 2+ options |

For each conditional, record:
```yaml
conditionals:
  - location: "line N in phase_id"
    type: "if-else"
    condition_text: "file exists"
    branches:
      - description: "proceed with processing"
      - description: "create new file"
    affects_phases: ["phase_id"]
```

### Step 2.3: Identify Actions

Scan for tool references and operations:

**Tool Patterns:**
| Tool | Detection Patterns |
|------|-------------------|
| Read | "read file", "read the", "load", "open" |
| Write | "write to", "create file", "save", "output" |
| Edit | "edit", "modify", "update file", "change" |
| Bash | "run command", "execute", "shell", "bash" |
| Glob | "find files", "search for files", "glob" |
| Grep | "search content", "find in files", "grep" |
| AskUserQuestion | "ask user", "prompt", "get input", "select" |
| WebFetch | "fetch URL", "download", "HTTP", "web" |

For each action, record:
```yaml
actions:
  - phase: "phase_id"
    line: N
    tool: "Read"
    description: "Read the config.yaml file"
    conditional: false  # or true if inside a conditional
    condition: null  # or "if file exists"
```

### Step 2.4: Detect State Variables

Identify data that flows through the skill:

**Sources:**
- User input from AskUserQuestion
- File contents from Read
- Computed/derived values
- External data (git SHAs, timestamps)

**Detection patterns:**
- `store as`, `save to`, `set`
- Variable assignments: `X = ...`
- References: `${variable}`, `the X from step 1`

For each variable:
```yaml
state_variables:
  - name: "config"
    source: "file_read"
    defined_in: "phase_id"
    used_in: ["phase1", "phase2"]
  - name: "user_choice"
    source: "user_input"
    defined_in: "ask_options"
    used_in: ["process_choice"]
```

---

## Phase 2.5: Detect Logging Patterns

### Step 2.5.1: Scan for Logging Intent

Look for prose patterns indicating logging requirements:

**High-confidence indicators:**
- "log execution", "log the", "record execution"
- "audit trail", "audit log", "execution history"
- "CI summary", "GitHub Actions", "CI output"
- "retain logs", "log retention", "keep logs"

**Medium-confidence indicators:**
- "track progress", "track execution"
- "debugging", "troubleshooting"
- "execution report", "summary report"

For each logging indicator found:
```yaml
logging_patterns:
  intent_present: true/false
  indicators:
    - pattern: "audit trail"
      location: "line 45"
      confidence: high
    - pattern: "CI summary"
      location: "line 82"
      confidence: high
```

### Step 2.5.2: Generate Logging Recommendation

Based on detected patterns:

| Indicators Found | Recommendation |
|------------------|----------------|
| 2+ high-confidence | `enable` - Auto-add logging config |
| 1 high or 2+ medium | `optional` - Ask user |
| None or low only | `skip` - No logging needed |

Store recommendation:
```yaml
conversion_recommendations:
  logging_recommendation: "enable"|"optional"|"skip"
  logging_indicators_count: N
```

---

## Phase 3: Complexity Assessment

### Step 3.1: Calculate Metrics

| Metric | Low | Medium | High |
|--------|-----|--------|------|
| Phase count | 1-3 | 4-6 | 7+ |
| Conditional count | 0-1 | 2-4 | 5+ |
| Branching depth | Linear | 2 levels | 3+ levels |
| Tool variety | 1-2 | 3-4 | 5+ |
| User interactions | 0-1 | 2-3 | 4+ |
| State variables | 1-3 | 4-7 | 8+ |

### Step 3.2: Classify Complexity

Based on weighted average of metrics:
- **Low** (< 1.5): Simple linear workflow, straightforward conversion
- **Medium** (1.5-2.5): Standard workflow with some branching
- **High** (> 2.5): Complex workflow, may need manual review

### Step 3.3: Generate Recommendations

Based on complexity, recommend:
- **Low**: Direct conversion, single action chain
- **Medium**: Standard workflow with conditional nodes
- **High**: Review complex patterns, consider breaking into sub-workflows

---

## Phase 4: Generate Report

### Step 4.1: Produce Analysis YAML

Output the complete analysis:

```yaml
analysis:
  skill_path: "/path/to/SKILL.md"
  skill_name: "example-skill"

  frontmatter:
    name: "hiivmind-corpus-example"
    description: "Original trigger description"
    allowed_tools:
      - Read
      - Write
      - AskUserQuestion

  complexity: "medium"
  complexity_score: 2.1

  metrics:
    phase_count: 4
    conditional_count: 3
    branching_depth: 2
    tool_variety: 3
    user_interactions: 2
    state_variables: 5

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
          condition_text: "file has header"
          branches: 2

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

  user_interactions:
    - phase: "validate_input"
      type: "confirmation"
      question: "Proceed with processing?"
      line: 25

  logging_patterns:
    intent_present: true
    indicators:
      - pattern: "audit trail"
        location: "line 45"
        confidence: "high"

  conversion_recommendations:
    approach: "standard_workflow"
    estimated_nodes: 8
    logging_recommendation: "enable"
    notes:
      - "Two phases map cleanly to workflow phases"
      - "Single conditional can be a conditional node"
      - "Consider checkpoint before write operation"
    warnings: []
```

### Step 4.2: Display Summary

Present a human-readable summary:

```
## Analysis Complete: {skill_name}

**Complexity:** {complexity} (score: {score})

### Phases Detected: {count}
{for each phase}
- **{title}** (lines {location})
  - {action_count} actions, {conditional_count} conditionals
{/for}

### Conversion Recommendation
{approach description}

**Estimated workflow nodes:** {count}

### Notes
{for each note}
- {note}
{/for}

{if warnings}
### Warnings
{for each warning}
- {warning}
{/for}
{/if}
```

---

## Output

The analysis is stored in conversation state and can be:
1. Passed to `hiivmind-blueprint-convert` for workflow generation
2. Displayed to user for review
3. Saved to a file if requested

---

## Reference Documentation

- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/skill-analysis.md`
- **Node Mapping:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/node-mapping.md`
- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/engine.md`

---

## Related Skills

- Convert to workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-convert/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-generate/SKILL.md`
- Discover skills: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-author-discover/SKILL.md`
