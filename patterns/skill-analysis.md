# Skill Analysis Pattern

Analyze any skill's structure to understand its phases, workflow coverage, and formalization opportunities.

---

## Analysis Output

The analysis produces:

- **Phases** - Major execution stages (prose and workflow-backed)
- **Coverage** - How much of the skill is formalized into workflows
- **Complexity** - Per-phase and aggregate complexity assessment
- **Workflow extraction candidates** - Prose phases that would benefit from workflow formalization
- **Inputs/Outputs** - Completeness of declared inputs and outputs

---

## Phase Identification

Scan the SKILL.md body for phase boundaries:

| Pattern | Example | Confidence |
|---------|---------|------------|
| Numbered heading | `## Phase 1: Initialize` | High |
| Phase/Stage keyword | `### Phase: Validation` | High |
| Sequential numbering | `1. First...`, `2. Then...` | Medium |
| Temporal markers | `First`, `Next`, `Finally` | Medium |

For each phase, determine its type:

| Phase Type | Detection |
|------------|-----------|
| **Prose** | Contains tool calls, pseudocode, AskUserQuestion blocks |
| **Workflow-backed** | Contains `Execute workflows/*.yaml` or similar delegation |

---

## Coverage Classification

| Coverage | Meaning | Detection |
|----------|---------|-----------|
| `none` | All phases are prose, no workflow files | `workflows:` absent from frontmatter, no `workflows/` directory |
| `partial` | Mix of prose and workflow-backed phases | Some phases delegate to workflows, others are prose |
| `full` | All substantive phases delegate to workflows | Every phase in Execution section references a workflow file |

---

## Phase-Level Complexity

For each phase, assess complexity independently:

### Prose Phase Complexity

| Factor | Low | Medium | High |
|--------|-----|--------|------|
| Conditionals | 0-1 | 2-4 | 5+ |
| Tool variety | 1-2 | 3-4 | 5+ |
| User interactions | 0-1 | 2-3 | 4+ |
| State variables | 1-3 | 4-7 | 8+ |
| Lines of prose | < 30 | 30-80 | 80+ |

### Workflow Phase Complexity

| Factor | Low | Medium | High |
|--------|-----|--------|------|
| Node count | 1-5 | 6-12 | 13+ |
| Branch depth | 1 | 2 | 3+ |
| Cyclomatic complexity | 1-3 | 4-8 | 9+ |

---

## Workflow Extraction Candidates

A prose phase is a candidate for workflow extraction when it exhibits:

| Signal | Score | Why |
|--------|-------|-----|
| 5+ conditional branches | +3 | Deterministic routing prevents LLM drift |
| FSM-like state transitions | +3 | Node graph maps naturally |
| Loop with explicit break condition | +2 | Workflow graph enforces termination |
| Multiple user prompts with branching | +2 | Response handlers route deterministically |
| Validation gate (multiple assertions) | +2 | Audit mode evaluates ALL conditions |
| Linear tool call sequence | +1 | Simple action chain, low benefit |

**Extraction score thresholds:**
- **0-2:** Leave as prose (low benefit)
- **3-4:** Consider extraction (moderate benefit)
- **5+:** Strong extraction candidate (high benefit)

---

## Analysis Output Format

```yaml
analysis:
  skill_name: "example-skill"
  skill_path: "/path/to/SKILL.md"

  frontmatter:
    name: "example-skill"
    description: "..."
    allowed_tools: [Read, Write, AskUserQuestion]
    inputs_defined: true
    outputs_defined: true
    workflows_declared: ["workflows/validate.yaml"]

  coverage: "partial"     # none | partial | full

  phases:
    - id: "gather"
      title: "Phase 1: Gather"
      type: "prose"
      prose_location: "lines 15-45"
      complexity: "low"
      conditionals: 1
      tool_calls: 3
      user_interactions: 0
      extraction_score: 1
      extraction_recommendation: "leave_as_prose"

    - id: "validate"
      title: "Phase 2: Validate"
      type: "workflow"
      workflow_file: "workflows/validate.yaml"
      node_count: 8
      complexity: "medium"

    - id: "report"
      title: "Phase 3: Report"
      type: "prose"
      prose_location: "lines 52-80"
      complexity: "medium"
      conditionals: 3
      extraction_score: 4
      extraction_recommendation: "consider_extraction"

  aggregate_complexity: "medium"

  recommendations:
    - type: "add_inputs"
      message: "Skill is missing inputs definition in frontmatter"
    - type: "extract_workflow"
      phase: "report"
      message: "Phase has 3 conditionals — consider extracting to workflow"
```

---

## Related Documentation

- **Authoring Guide:** `patterns/authoring-guide.md`
- **Node Mapping:** `patterns/node-mapping.md`
- **Execution Guide:** `patterns/execution-guide.md`
