---
name: hiivmind-blueprint-discover
description: >
  This skill should be used when the user asks to "find skills", "list skills to convert",
  "show conversion status", "what skills need workflow", "discover prose skills",
  or needs to see which skills in a plugin are prose-based vs. workflow-based. Triggers on
  "discover skills", "blueprint discover", "hiivmind-blueprint discover", "list skills",
  "conversion status", "show skills", or when planning a conversion project.
allowed-tools: Read, Glob, Grep
---

# Discover Skills

Scan a plugin for skills and report their conversion status (prose, workflow, or complex).

---

## Overview

This skill scans for skills and classifies them:
- **Prose** - Traditional SKILL.md without workflow.yaml (can be converted)
- **Workflow** - Already has workflow.yaml (converted)
- **Complex** - Has workflow.yaml but may need upgrade
- **Hybrid** - Mixed patterns, needs review

---

## Phase 1: Locate Skills

### Step 1.1: Determine Search Scope

Check for skills in these locations:

1. **Current plugin:** `./skills/*/SKILL.md`
2. **User-level skills:** `~/.claude/skills/*/SKILL.md`
3. **Installed plugins:** `~/.claude/plugins/*/skills/*/SKILL.md`

### Step 1.2: Find All SKILL.md Files

Use Glob to find all skill files:

```
skill_files = Glob("skills/*/SKILL.md")
```

For each skill file found:
```yaml
skills:
  - path: "skills/example-skill/SKILL.md"
    directory: "skills/example-skill"
    name: "example-skill"
```

---

## Phase 2: Classify Skills

### Step 2.1: Check for Workflow

For each skill, check if workflow.yaml exists:

```
for skill in skills:
  workflow_path = "{skill.directory}/workflow.yaml"
  skill.has_workflow = file_exists(workflow_path)
```

### Step 2.2: Analyze SKILL.md Content

Read each SKILL.md and detect patterns:

**Workflow indicators (thin loader):**
- Contains `workflow.yaml` reference
- Has "Execute this workflow" language
- References `lib/workflow/`
- Minimal prose, mostly execution instructions

**Prose indicators (traditional):**
- Detailed step-by-step instructions
- Multiple sections with prose
- No workflow.yaml reference
- Contains conditional logic in prose

**Classification algorithm:**

```
function classify_skill(skill):
  content = read_file(skill.path)

  # Count indicators
  workflow_refs = count_matches(content, /workflow\.yaml|lib\/workflow/)
  prose_sections = count_matches(content, /^## (Step|Phase) \d/m)
  conditional_prose = count_matches(content, /\b(if|when|otherwise)\b/i)

  if skill.has_workflow:
    if workflow_refs > 2:
      return "workflow"  # Converted, thin loader
    else:
      return "complex"   # Has workflow but also prose
  else:
    if prose_sections > 3 or conditional_prose > 5:
      return "prose"     # Traditional, can convert
    else:
      return "simple"    # Too simple, may not need workflow
```

### Step 2.3: Estimate Complexity

For prose skills, estimate conversion complexity:

| Metric | Low | Medium | High |
|--------|-----|--------|------|
| Line count | < 100 | 100-300 | > 300 |
| Section count | 1-3 | 4-6 | 7+ |
| Conditionals | 0-2 | 3-5 | 6+ |
| User prompts | 0-1 | 2-3 | 4+ |

```yaml
skill:
  complexity: "medium"
  metrics:
    lines: 180
    sections: 5
    conditionals: 3
    user_prompts: 2
```

---

## Phase 3: Generate Report

### Step 3.1: Build Status Table

Create a summary table:

```
| Skill | Status | Complexity | Notes |
|-------|--------|------------|-------|
{for each skill}
| {name} | {status} | {complexity} | {notes} |
{/for}
```

**Status icons:**
- `workflow` → Converted
- `prose` → Ready to convert
- `complex` → Needs review
- `simple` → May not need workflow

### Step 3.2: Group by Status

Organize skills by conversion status:

```
## Discovery Results

### Ready to Convert ({count})
{for each prose skill}
- **{name}** - {complexity} complexity, ~{estimated_nodes} nodes
{/for}

### Already Converted ({count})
{for each workflow skill}
- **{name}** - Using workflow.yaml
{/for}

### Needs Review ({count})
{for each complex skill}
- **{name}** - {reason}
{/for}

### Too Simple ({count})
{for each simple skill}
- **{name}** - May not benefit from workflow conversion
{/for}
```

### Step 3.3: Conversion Recommendations

Based on the scan, provide recommendations:

```
## Recommendations

### Quick Wins
Skills that are good candidates for conversion:
{skills with medium complexity, 3-6 sections}

### Priority Conversions
Skills that would benefit most from deterministic workflows:
{skills with many conditionals or user prompts}

### Skip for Now
Skills that may not need conversion:
{simple skills with < 3 sections}
```

---

## Phase 4: Detailed Analysis (Optional)

### Step 4.1: Offer Deep Dive

If user wants more detail on a specific skill:

```json
{
  "questions": [{
    "question": "Would you like detailed analysis of any skill?",
    "header": "Details",
    "multiSelect": false,
    "options": [
      {"label": "Analyze specific skill", "description": "Run full analysis on one skill"},
      {"label": "Export report", "description": "Save discovery results to file"},
      {"label": "Done", "description": "No further action needed"}
    ]
  }]
}
```

### Step 4.2: Invoke Analysis

If user selects a skill for analysis:
- Invoke `hiivmind-blueprint-analyze` with the skill path
- Display detailed analysis results

---

## Output Format

### Console Output

```
## Skill Discovery: {plugin_name}

Scanned: {total_skills} skills
Location: {search_path}

### Status Summary

| Status | Count |
|--------|-------|
| Ready to convert | {prose_count} |
| Already converted | {workflow_count} |
| Needs review | {complex_count} |
| Too simple | {simple_count} |

### Skills by Status

#### Ready to Convert (prose)
| Skill | Complexity | Est. Nodes | Conditionals |
|-------|------------|------------|--------------|
{prose skills table}

#### Already Converted (workflow)
| Skill | Version | Nodes | Last Updated |
|-------|---------|-------|--------------|
{workflow skills table}

{if complex_count > 0}
#### Needs Review
| Skill | Issue | Recommendation |
|-------|-------|----------------|
{complex skills table}
{/if}

### Next Steps

To convert a skill:
1. `/hiivmind-blueprint analyze {skill_name}`
2. `/hiivmind-blueprint convert`
3. `/hiivmind-blueprint generate`

Or use the gateway command:
`/hiivmind-blueprint convert {skill_name}`
```

### Stored State

Results are stored for use by other skills:

```yaml
computed:
  discovery:
    timestamp: "2025-01-23T..."
    plugin_path: "/path/to/plugin"
    total_skills: 12
    skills:
      - name: "skill-a"
        path: "skills/skill-a/SKILL.md"
        status: "prose"
        complexity: "medium"
        estimated_nodes: 8
      - name: "skill-b"
        path: "skills/skill-b/SKILL.md"
        status: "workflow"
        workflow_version: "1.0.0"
    summary:
      prose: 5
      workflow: 4
      complex: 2
      simple: 1
```

---

## Reference Documentation

- **Skill Analysis:** `${CLAUDE_PLUGIN_ROOT}/lib/blueprint/patterns/skill-analysis.md`
- **Workflow Schema:** `${CLAUDE_PLUGIN_ROOT}/lib/workflow/schema.md`

---

## Related Skills

- Initialize project: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
- Analyze skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert skill: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Generate files: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
