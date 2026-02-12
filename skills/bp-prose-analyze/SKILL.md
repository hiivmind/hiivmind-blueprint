---
name: bp-prose-analyze
description: >
  This skill should be used when the user asks to "analyze a skill", "examine SKILL.md structure",
  "understand skill complexity", "extract phases from skill", "what does this skill do",
  "check if skill can be converted", "assess skill for migration", or needs to understand an
  existing prose skill's structure before conversion. Triggers on "analyze skill", "prose analyze",
  "skill analysis", "examine skill", "assess skill", "pre-migration analysis".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Analyze Prose Skill

Deep structural analysis of an existing prose-based SKILL.md to extract phases, conditionals, actions, state variables, user interactions, and complexity. Produces analysis YAML for use by `bp-prose-migrate`.

> **Pattern Documentation:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

---

## Overview

This skill reads a prose SKILL.md and produces a structured analysis containing:
- **Phases** - Major execution stages identified by heading patterns and temporal markers
- **Conditionals** - Branching points with condition text and branch descriptions
- **Actions** - Discrete tool calls and operations mapped to allowed-tools
- **State variables** - Data flowing between phases via `computed.*` references
- **User interactions** - Points requiring user input via AskUserQuestion
- **Complexity classification** - Weighted Low/Medium/High rating with numeric score
- **Logging patterns** - Detected audit/logging intent and conversion recommendation

The output analysis YAML is the **handoff contract** consumed by `bp-prose-migrate`.

---

## Phase 1: Locate Skill

### Step 1.1: Determine Target Skill

If user provided a path in the invocation arguments:
1. Validate the path exists using Read
2. Confirm the file contains YAML frontmatter (starts with `---`)
3. Store the full content in `computed.skill_content`
4. Store the resolved absolute path in `computed.skill_path`

If no path was provided:
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
2. Based on user response:
   - **Provide path**: Ask for the path via follow-up prompt, then Read the file. If the file does not exist or is not a valid SKILL.md, report the error and re-prompt.
   - **Search current directory**: Glob for `**/SKILL.md` within the current working directory. Present the discovered list to the user as a numbered selection. If no SKILL.md files found, inform the user and offer to search installed plugins instead.
   - **Search installed plugins**: Check `~/.claude/skills/` and `.claude-plugin/skills/` for SKILL.md files. Present the discovered list. If neither location contains skills, report this and ask for a manual path.
3. Read the selected SKILL.md and store in `computed.skill_content`.

### Step 1.2: Parse Frontmatter

Extract from the SKILL.md YAML frontmatter block (between the opening `---` and closing `---`):
- `name` - Skill identifier string
- `description` - Trigger description text
- `allowed-tools` - Comma-separated tool list

Pseudocode:
```pseudocode
frontmatter_lines = content between first "---" and second "---"
parsed = parse_yaml(frontmatter_lines)
computed.skill_name = parsed.name
computed.original_description = parsed.description
computed.allowed_tools = split(parsed["allowed-tools"], ", ")
```

If the frontmatter is missing or malformed, warn the user but continue analysis using the filename as a fallback identifier.

---

## Phase 2: Structural Analysis

This phase performs five sequential sub-steps against `computed.skill_content`. Each sub-step appends results into `computed.*` state variables that feed the complexity assessment and final report.

### Step 2.1: Identify Phases

Scan the skill content line-by-line for phase boundary markers at three confidence levels:

**High-confidence indicators:**
- `## Phase N:` or `## Phase N -` headings (regex: `^##\s+Phase\s+\d+`)
- `### Step N.N:` sub-phase headings (regex: `^###\s+Step\s+\d+\.\d+`)
- `## Stage N` headings (regex: `^##\s+Stage\s+\d+`)
- Any numbered markdown heading with a colon (regex: `^#{2,3}\s+.*\d+.*:`)

**Medium-confidence indicators:**
- Sequential numbered lists with temporal markers: `1. First...`, `2. Then...`
- Standalone temporal markers at line start: `First,`, `Next,`, `Finally,`
- Bold-prefaced sequential items: `**Step 1:**`, `**Stage A:**`

**Low-confidence indicators:**
- Horizontal rules (`---`) between content sections (not frontmatter boundaries)
- Major heading level changes with unrelated content
- Large content gaps (5+ blank lines between sections)

For each detected phase, record:
```yaml
computed.phases:
  - id: "slugified_phase_name"
    title: "Original Phase Title"
    prose_location: "lines X-Y"
    confidence: "high|medium|low"
```

Pseudocode:
```pseudocode
phases = []
current_phase = null
for line_num, line in enumerate(content_lines):
  confidence = detect_phase_marker(line)
  if confidence:
    if current_phase: current_phase.end_line = line_num - 1; phases.append(current_phase)
    current_phase = new_phase(line, line_num, confidence)
if current_phase: phases.append(current_phase)
computed.phases = phases
```

If no phases detected, treat the entire skill body as a single phase with `confidence: "low"`.

> **Detail:** See `patterns/phase-detection-algorithm.md` for the complete indicator catalog with regex patterns, edge cases, and merging rules.

### Step 2.2: Extract Conditionals

Within each phase in `computed.phases`, scan for conditional language patterns:

| Pattern | Type | Branches |
|---------|------|----------|
| `If ... then ...` | if-then | 1 (implied else: no-op) |
| `If ... otherwise ...` | if-else | 2 explicit |
| `When ...` | conditional | varies (count explicit options) |
| `Based on ...` | switch | 2+ options (count listed items) |
| `Depending on ...` | switch | 2+ options (count listed items) |
| `Unless ...` | negated-if | 1 (inverted condition) |
| `Either ... or ...` | if-else | 2 explicit |

For each conditional found, record:
```yaml
computed.conditionals:
  - location: "line N in phase_id"
    type: "if-else"
    condition_text: "file exists"
    branches:
      - description: "proceed with processing"
      - description: "create new file"
    affects_phases: ["phase_id"]
```

Track the maximum nesting depth of conditionals within a single phase as `computed.max_branching_depth`. A conditional inside a branch of another conditional increases depth by 1.

### Step 2.3: Identify Actions

Scan each phase for references to tool operations:

| Tool | Detection Patterns |
|------|-------------------|
| Read | "read file", "load", "open", "parse", "examine" |
| Write | "write to", "create file", "save", "output to file" |
| Edit | "edit", "modify", "update file", "replace in" |
| Bash | "run command", "execute", "shell", "invoke CLI" |
| Glob | "find files", "search for files", "glob", "list matching" |
| Grep | "search content", "find in files", "grep", "search for pattern" |
| AskUserQuestion | "ask user", "prompt user", "get input", "select", "confirm with user" |
| WebFetch | "fetch URL", "download", "HTTP request" |

For each action, record:
```yaml
computed.actions:
  - phase: "phase_id"
    line: N
    tool: "Read"
    description: "Read the config.yaml file"
    conditional: false
    condition: null
```

If the action appears inside a conditional branch, set `conditional: true` and `condition` to the enclosing condition text.

Pseudocode:
```pseudocode
actions = []
for phase in computed.phases:
  active_condition = null
  for line_num, line in get_phase_lines(phase):
    if line matches conditional_start: active_condition = extract_condition(line)
    if line matches conditional_end: active_condition = null
    for tool, patterns in TOOL_PATTERNS:
      if any(p in line.lower() for p in patterns):
        actions.append({phase: phase.id, line: line_num, tool: tool,
          description: summarize(line), conditional: active_condition is not null,
          condition: active_condition})
computed.actions = actions
```

### Step 2.4: Detect State Variables

Identify data that flows between phases through the skill:

**Sources:** User input (AskUserQuestion), file reads (Read), computed/derived values, external data (git SHAs, timestamps).

**Detection patterns:**
- Explicit storage: `store as`, `save to`, `set`, `record`, `capture`
- Variable notation: `computed.X`, `${variable}`, `state.X`
- Cross-phase references: `the X from Step 1`, `using the previously loaded`

For each variable:
```yaml
computed.state_variables:
  - name: "config"
    source: "file_read"
    defined_in: "phase_id"
    used_in: ["phase_id_1", "phase_id_2"]
```

Cross-reference `computed.state_variables` with `computed.actions` and `computed.conditionals` to verify every referenced variable has a defined source. Flag undefined references in `computed.analysis_warnings`.

### Step 2.5: Detect Logging Patterns

Scan for prose indicators of logging or audit requirements:

**High-confidence:** "log execution", "audit trail", "CI summary", "retain logs", "execution record"
**Medium-confidence:** "track progress", "debugging", "execution report", "summary report"

For each indicator, record pattern, location, and confidence in `computed.logging_patterns`.

Generate recommendation:

| Indicators Found | Recommendation |
|------------------|----------------|
| 2+ high-confidence | `enable` - Include logging config in converted workflow |
| 1 high or 2+ medium | `optional` - Ask user during migration |
| None or low only | `skip` - No logging infrastructure needed |

Store in `computed.conversion_recommendations.logging_recommendation`.

---

## Phase 3: Complexity Assessment

### Step 3.1: Calculate Metrics

Derive counts from the Phase 2 analysis:

| Metric | Source | Low | Medium | High |
|--------|--------|-----|--------|------|
| Phase count | `len(computed.phases)` | 1-3 | 4-6 | 7+ |
| Conditional count | `len(computed.conditionals)` | 0-1 | 2-4 | 5+ |
| Branching depth | `computed.max_branching_depth` | 1 (linear) | 2 levels | 3+ levels |
| Tool variety | unique tools in `computed.actions` | 1-2 | 3-4 | 5+ |
| User interactions | AskUserQuestion count | 0-1 | 2-3 | 4+ |
| State variables | `len(computed.state_variables)` | 1-3 | 4-7 | 8+ |

### Step 3.2: Classify Complexity

Normalize each metric to a 1-3 scale (Low=1, Medium=2, High=3) and compute a weighted average:

```pseudocode
score = (phase_count_norm * 0.15) + (conditional_count_norm * 0.25) +
        (branching_depth_norm * 0.20) + (tool_variety_norm * 0.10) +
        (user_interactions_norm * 0.15) + (state_variables_norm * 0.15)
```

Classification thresholds:
- **Low** (score < 1.5): Simple linear workflow, straightforward conversion
- **Medium** (1.5 <= score <= 2.5): Standard workflow with branching and moderate state
- **High** (score > 2.5): Complex workflow, may require manual review or decomposition

Store in `computed.complexity` and `computed.complexity_score`.

> **Detail:** See `patterns/complexity-scoring.md` for the complete scoring formula with normalization rules and worked examples.

### Step 3.3: Generate Recommendations

Based on the classified complexity level:

- **Low**: Direct conversion, single action chain. Estimated nodes: `phase_count * 2 + conditional_count`. Approach: `simple_linear`
- **Medium**: Standard workflow with conditional routing. May benefit from subflow extraction. Estimated nodes: `phase_count * 3 + conditional_count * 2 + user_interactions`. Approach: `standard_workflow`
- **High**: Review for decomposition into multiple skills. Flag nested conditionals for manual review. Estimated nodes: `phase_count * 4 + conditional_count * 3 + user_interactions * 2`. Approach: `complex_with_subflows`

Store in:
```yaml
computed.conversion_recommendations:
  approach: "simple_linear|standard_workflow|complex_with_subflows"
  estimated_nodes: N
  notes: ["observation 1", ...]
  warnings: ["warning if any"]
```

---

## Phase 4: Generate Report

### Step 4.1: Produce Analysis YAML

Assemble the complete analysis from all `computed.*` state into a single structured document. This is the primary output and the handoff contract to `bp-prose-migrate`.

The output schema includes these top-level sections:
- `skill_path`, `skill_name` - Source identification
- `frontmatter` - Parsed name, description, allowed_tools
- `complexity`, `complexity_score` - Classification result
- `metrics` - Raw metric counts (phase_count through state_variables)
- `phases[]` - Each with id, title, prose_location, confidence, nested actions and conditionals
- `state_variables[]` - Each with name, source, defined_in, used_in
- `user_interactions[]` - Each with phase, type, question, line
- `logging_patterns` - intent_present flag and indicators array
- `conversion_recommendations` - approach, estimated_nodes, logging_recommendation, notes, warnings

Store the assembled structure in `computed.analysis`.

> **Detail:** See `patterns/analysis-output-schema.md` for the full field reference with types, required/optional status, and a complete YAML example.

### Step 4.2: Display Human-Readable Summary

Present a formatted summary to the user:

```
## Analysis Complete: {computed.skill_name}

**Complexity:** {computed.complexity} (score: {computed.complexity_score})
**Approach:** {computed.conversion_recommendations.approach}

### Phases Detected: {count}
{for each phase}
- **{title}** ({prose_location}) [{confidence} confidence]
  - {action_count} actions, {conditional_count} conditionals
{/for}

### State Flow
{for each var in computed.state_variables}
- `{name}` ({source}) - defined in {defined_in}, used in {used_in}
{/for}

### Conversion Recommendation
**Estimated workflow nodes:** {estimated_nodes}
{notes list}
{warnings list if any}
```

### Step 4.3: Offer Next Steps

Present the user with options for what to do with the analysis:

```json
{
  "questions": [{
    "question": "Analysis complete. What would you like to do next?",
    "header": "Next",
    "multiSelect": false,
    "options": [
      {"label": "Migrate to workflow (Recommended)", "description": "Convert this skill to workflow.yaml using bp-prose-migrate"},
      {"label": "Save analysis", "description": "Save the analysis YAML to a file"},
      {"label": "Analyze another", "description": "Run analysis on a different skill"},
      {"label": "Done", "description": "Review complete"}
    ]
  }]
}
```

Based on response:
- **Migrate to workflow**: Hand off `computed.analysis` to `bp-prose-migrate`. The analysis YAML is the input contract -- `bp-prose-migrate` expects the exact schema produced in Step 4.1.
- **Save analysis**: Write the analysis YAML to a file. Default path: `{skill_directory}/analysis.yaml`. Ask user to confirm or provide alternative path.
- **Analyze another**: Return to Phase 1, Step 1.1. Clear all `computed.*` state except `computed.analysis_history` (append current analysis for reference).
- **Done**: Display final summary and exit.

---

## State Flow

```
Phase 1                    Phase 2                         Phase 3              Phase 4
───────────────────────────────────────────────────────────────────────────────────────
computed.skill_content  →  computed.phases              →  computed.metrics  →  computed.analysis
computed.skill_path        computed.conditionals           computed.complexity   (assembled)
computed.skill_name        computed.actions                computed.complexity_score
computed.allowed_tools     computed.state_variables        computed.conversion_recommendations
                           computed.logging_patterns
                           computed.max_branching_depth                       └→ passed to
                           computed.analysis_warnings                           bp-prose-migrate
```

---

## Reference Documentation

- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Phase Detection Algorithm:** `patterns/phase-detection-algorithm.md`
- **Complexity Scoring:** `patterns/complexity-scoring.md`
- **Analysis Output Schema:** `patterns/analysis-output-schema.md`
- **Node Mapping:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`

---

## Related Skills

- **Migrate prose skill to workflow:** `bp-prose-migrate`
- **Discover installed plugins:** `bp-plugin-discover`
- **Analyze workflow-based skill:** `bp-skill-analyze`
