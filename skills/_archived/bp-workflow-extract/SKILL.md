---
name: bp-workflow-extract
description: >
  This skill should be used when the user asks to "extract workflow from skill",
  "convert prose phase to workflow", "formalize phase", "create workflow from phase",
  "extract phase to yaml", or needs to take a specific prose phase from an existing
  skill and generate a workflow definition for it. Triggers on "extract workflow",
  "extract phase", "formalize", "prose to workflow", "create workflow from phase",
  or after running bp-skill-analyze.
allowed-tools: Read, Write, Edit, Glob, Bash, AskUserQuestion
inputs:
  - name: skill_path
    type: string
    required: false
    description: Path to the skill directory or SKILL.md
  - name: phase_id
    type: string
    required: false
    description: ID of the phase to extract (prompted if not provided)
outputs:
  - name: workflow_file
    type: string
    description: Path to the generated workflow file
  - name: updated_skill
    type: boolean
    description: Whether SKILL.md was updated with workflow reference
---

# Extract Workflow from Prose Phase

Extract specific prose phases from an existing skill and generate individual workflow
definitions in the skill's `workflows/` subdirectory. Unlike the old `bp-prose-migrate`
(which replaced entire skills), this skill targets individual phases and preserves the
overall skill structure.

> **Node Generation Procedure:** `patterns/node-generation-procedure.md` (local to this skill)
> **Consequence Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
> **Precondition Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
> **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`

---

## Overview

This skill is the extraction counterpart to `bp-skill-analyze`. After analysis identifies
prose phases with high extraction scores, this skill:

1. Validates the analysis and identifies extraction candidates
2. Lets the user select which phase(s) to extract
3. Analyzes the selected phase's internal structure (conditionals, actions, state)
4. Generates a workflow YAML file in `workflows/`
5. Updates the SKILL.md to reference the new workflow
6. Validates the result

**Pipeline position:**

```
bp-skill-analyze           (identify extraction candidates)
        |
bp-workflow-extract  <---  THIS SKILL (extract specific phases)
        |
bp-skill-validate          (verify the result)
```

**Key difference from old bp-prose-migrate:** This skill does NOT replace the entire
SKILL.md. It extracts individual phases into self-contained workflow files while
preserving all other prose phases and the skill's overall orchestration structure.

---

## Phase 1: Validate and Select

### Step 1.1: Load Analysis

Check if `computed.analysis` exists (from a prior `bp-skill-analyze` run) or load
from a path:

```pseudocode
LOAD_ANALYSIS():
  IF computed.analysis IS DEFINED AND computed.analysis.phases IS DEFINED:
    # Analysis already in state from bp-skill-analyze
    computed.skill_name = computed.analysis.skill_name
    computed.skill_path = computed.analysis.skill_path
  ELIF args.skill_path IS DEFINED:
    # Read the SKILL.md and run a lightweight analysis
    computed.skill_path = resolve_skill_path(args.skill_path)
    computed.skill_content = Read(computed.skill_path)
    computed.analysis = lightweight_analysis(computed.skill_content)
  ELSE:
    # Ask user for skill path
    ASK_FOR_SKILL_PATH()
```

If no analysis exists, the skill performs a lightweight inline analysis focused on
phase identification and extraction scoring (subset of `bp-skill-analyze`).

### Step 1.2: Identify Extraction Candidates

Filter phases that are prose-type and have sufficient extraction scores:

```pseudocode
IDENTIFY_CANDIDATES():
  computed.candidates = []

  FOR phase IN computed.analysis.phases:
    IF phase.type != "prose":
      CONTINUE

    IF phase.extraction_score IS NOT DEFINED:
      # Calculate extraction score inline
      phase.extraction_score = calculate_extraction_score(phase)
      phase.extraction_recommendation = recommend_extraction(phase.extraction_score)

    IF phase.extraction_score >= 3:
      computed.candidates.append(phase)

  IF len(computed.candidates) == 0:
    DISPLAY "No prose phases meet the extraction threshold (score >= 3)."
    DISPLAY "Phase scores:"
    FOR phase IN computed.analysis.phases:
      IF phase.type == "prose":
        DISPLAY "  - " + phase.title + ": " + str(phase.extraction_score)
    EXIT
```

### Step 1.3: User Selects Phase(s)

If a specific `phase_id` was provided in args, use it. Otherwise ask:

```json
{
  "questions": [{
    "question": "Which prose phase(s) should I extract into workflow definitions?",
    "header": "Extract",
    "multiSelect": true,
    "options": [
      {
        "label": "{phase.title}",
        "description": "Score: {phase.extraction_score} — {phase.extraction_recommendation}"
      }
    ]
  }]
}
```

Store selected phases in `computed.selected_phases`.

---

## Phase 2: Analyze Phase Structure

For each selected phase, perform deep structural analysis to build the workflow graph.

### Step 2.1: Extract Phase Content

```pseudocode
EXTRACT_PHASE_CONTENT(phase):
  content = get_lines(computed.skill_content, phase.prose_location)
  phase.full_content = content
```

### Step 2.2: Identify Internal Structure

Parse the prose phase for workflow-mappable elements:

```pseudocode
ANALYZE_PHASE_INTERNALS(phase):
  content = phase.full_content

  # Extract conditionals with branch targets
  phase.conditionals = extract_conditionals(content)

  # Extract actions mapped to consequence types
  phase.actions = extract_actions(content)

  # Extract user interaction points
  phase.user_interactions = extract_user_interactions(content)

  # Extract state variables (inputs from earlier phases, outputs for later phases)
  phase.state_reads = extract_state_reads(content)     # ${computed.X} references
  phase.state_writes = extract_state_writes(content)   # store_as / mutate_state targets

  # Determine start conditions (what must be true before this phase runs)
  phase.preconditions = infer_preconditions(phase.state_reads, computed.analysis)
```

### Step 2.3: Determine Workflow Shape

Based on the internal analysis, decide the workflow's node structure:

```pseudocode
DETERMINE_SHAPE(phase):
  IF phase.conditionals == 0 AND phase.user_interactions == 0:
    phase.shape = "linear"        # Simple action chain
  ELIF phase.user_interactions > 0:
    phase.shape = "interactive"   # User prompts with routing
  ELIF phase.conditionals >= 3:
    phase.shape = "branching"     # Multiple decision points
  ELSE:
    phase.shape = "simple_branch" # Single conditional with branches

  # Estimate node count
  phase.estimated_nodes = estimate_node_count(phase)
```

---

## Phase 3: Generate Workflow

### Step 3.1: Build Workflow Scaffold

```pseudocode
BUILD_SCAFFOLD(phase):
  workflow_id = computed.skill_name + "-" + kebab_case(phase.title)
  workflow_filename = kebab_case(phase.title) + ".yaml"

  computed.workflow = {
    name: workflow_id,
    version: "1.0.0",
    description: "Workflow for " + phase.title + " phase of " + computed.skill_name,
    entry_preconditions: phase.preconditions,
    initial_state: {
      phase: "start",
      flags: { initialized: false },
      computed: {},
      output: {
        level: "normal",
        log_enabled: true,
        log_format: "yaml",
        log_location: ".logs/"
      },
      prompts: {
        interface: "auto",
        modes: {
          claude_code: "interactive",
          web: "forms",
          api: "structured",
          agent: "autonomous"
        }
      }
    }
  }
```

### Step 3.2: Map Nodes

Use the node-generation-procedure pattern to create nodes:

```pseudocode
MAP_NODES(phase):
  computed.workflow.nodes = {}
  node_order = []

  # Map each action to an action node
  FOR action IN phase.actions:
    IF action.is_conditional:
      # Create conditional + branch nodes
      cond_node = create_conditional_node(action.condition)
      computed.workflow.nodes[cond_node.id] = cond_node
      node_order.append(cond_node.id)

      true_node = create_action_node(action.true_branch)
      computed.workflow.nodes[true_node.id] = true_node
      node_order.append(true_node.id)

      IF action.false_branch:
        false_node = create_action_node(action.false_branch)
        computed.workflow.nodes[false_node.id] = false_node
        node_order.append(false_node.id)
    ELSE:
      node = create_action_node(action)
      computed.workflow.nodes[node.id] = node
      node_order.append(node.id)

  # Map user interactions to user_prompt nodes
  FOR interaction IN phase.user_interactions:
    prompt_node = create_user_prompt_node(interaction)
    computed.workflow.nodes[prompt_node.id] = prompt_node
    node_order.append(prompt_node.id)

  # Wire transitions
  wire_transitions(computed.workflow.nodes, node_order)

  computed.workflow.start_node = node_order[0]
```

### Step 3.3: Generate Endings

```pseudocode
BUILD_ENDINGS(phase):
  computed.workflow.endings = {
    success: {
      type: "success",
      message: phase.title + " completed successfully"
    },
    error_execution: {
      type: "error",
      message: phase.title + " failed",
      recovery: "Check the error details and retry"
    },
    cancelled: {
      type: "cancelled",
      message: "Operation cancelled by user"
    },
    error_safety: {
      type: "error",
      category: "safety",
      message: "I can't help with that request.",
      recovery: { suggestion: "Please rephrase your request." }
    }
  }

  # Add summary fields from state_writes
  IF len(phase.state_writes) > 0:
    computed.workflow.endings.success.summary = {}
    FOR var IN phase.state_writes:
      computed.workflow.endings.success.summary[var] = "${computed." + var + "}"
```

### Step 3.4: Write Workflow File

```pseudocode
WRITE_WORKFLOW(phase):
  skill_dir = parent_directory(computed.skill_path)
  workflows_dir = skill_dir + "/workflows"
  Bash("mkdir -p " + workflows_dir)

  workflow_content = render_workflow_yaml(computed.workflow)

  header = "# Generated by bp-workflow-extract\n"
  header += "# Extracted from: " + phase.title + " phase of " + computed.skill_name + "\n"
  header += "# Generated: " + current_iso_timestamp() + "\n\n"

  output_path = workflows_dir + "/" + workflow_filename
  Write(output_path, header + workflow_content)
  computed.files_created.append(output_path)

  DISPLAY "Created: " + output_path
```

---

## Phase 4: Update SKILL.md

### Step 4.1: Update Frontmatter

Add the new workflow to the `workflows:` list in the SKILL.md frontmatter:

```pseudocode
UPDATE_FRONTMATTER():
  skill_content = Read(computed.skill_path)

  # Parse existing frontmatter
  frontmatter = extract_frontmatter(skill_content)

  # Add workflows list if not present
  IF "workflows" NOT IN frontmatter:
    frontmatter.workflows = []

  # Add new workflow reference
  workflow_ref = "workflows/" + workflow_filename
  IF workflow_ref NOT IN frontmatter.workflows:
    frontmatter.workflows.append(workflow_ref)

  # Write back with updated frontmatter
  updated_content = replace_frontmatter(skill_content, frontmatter)
```

### Step 4.2: Update Phase Content

Replace the prose phase content with a workflow delegation block:

```pseudocode
UPDATE_PHASE_CONTENT():
  # Build the new phase content
  new_content = "Execute `workflows/" + workflow_filename
    + "` following the execution guide:\n\n"
  new_content += "1. Read `.hiivmind/blueprint/definitions.yaml` — build type registry\n"
  new_content += "2. Read `${CLAUDE_PLUGIN_ROOT}/skills/"
    + skill_directory + "/workflows/" + workflow_filename + "`\n"
  new_content += "3. Follow `.hiivmind/blueprint/execution-guide.md` (Init → Execute → Complete)\n"

  # Add state handoff documentation
  IF len(phase.state_reads) > 0:
    new_content += "\n**Reads:** " + join(phase.state_reads, ", ") + "\n"
  IF len(phase.state_writes) > 0:
    new_content += "**Writes:** " + join(phase.state_writes, ", ") + "\n"

  # Replace the original prose content in SKILL.md
  updated_content = replace_phase_content(
    updated_content,
    phase.prose_location,
    new_content
  )

  Write(computed.skill_path, updated_content)
  computed.files_updated.append(computed.skill_path)

  DISPLAY "Updated: " + computed.skill_path + " (phase " + phase.title + " now delegates to workflow)"
```

---

## Phase 5: Validate

### Step 5.1: Validate Generated Workflow

Run structural validation on the generated workflow:

```pseudocode
VALIDATE_WORKFLOW():
  errors = []

  # Check start_node exists
  IF computed.workflow.start_node NOT IN computed.workflow.nodes:
    errors.append("start_node not found in nodes")

  # Check all transitions target valid nodes or endings
  valid_targets = set(computed.workflow.nodes.keys()) | set(computed.workflow.endings.keys())
  FOR node_id, node IN computed.workflow.nodes:
    targets = get_all_transition_targets(node)
    FOR target IN targets:
      IF target NOT IN valid_targets:
        errors.append("Node '" + node_id + "' targets '" + target + "' which does not exist")

  # Check reachability
  reachable = bfs_reachable(computed.workflow.start_node, computed.workflow.nodes, computed.workflow.endings)
  orphans = set(computed.workflow.nodes.keys()) - reachable
  IF len(orphans) > 0:
    errors.append("Orphan nodes: " + join(orphans, ", "))

  computed.validation = {
    passed: len(errors) == 0,
    errors: errors
  }

  IF NOT computed.validation.passed:
    DISPLAY "Validation errors:"
    FOR error IN errors:
      DISPLAY "  - " + error
```

### Step 5.2: Verify SKILL.md Consistency

```pseudocode
VERIFY_CONSISTENCY():
  updated_skill = Read(computed.skill_path)

  # Check frontmatter includes the workflow reference
  frontmatter = extract_frontmatter(updated_skill)
  ASSERT "workflows/" + workflow_filename IN frontmatter.workflows

  # Check the phase content now references the workflow
  ASSERT "workflows/" + workflow_filename IN updated_skill
```

---

## Phase 6: Report

### Step 6.1: Display Summary

```
## Extraction Complete: {phase.title}

**Skill:** {computed.skill_name}
**Workflow file:** workflows/{workflow_filename}
**Coverage change:** {old_coverage} → {new_coverage}

### Generated Workflow

| Metric | Value |
|--------|-------|
| Nodes | {len(computed.workflow.nodes)} |
| Endings | {len(computed.workflow.endings)} |
| Start node | {computed.workflow.start_node} |
| State reads | {join(phase.state_reads)} |
| State writes | {join(phase.state_writes)} |

### Files Modified

| File | Action |
|------|--------|
{for file in computed.files_created}
| `{file}` | Created |
{/for}
{for file in computed.files_updated}
| `{file}` | Updated |
{/for}

### Validation

{computed.validation.passed ? "All checks passed" : "Errors found — review above"}
```

### Step 6.2: Offer Next Actions

```json
{
  "questions": [{
    "question": "What would you like to do next?",
    "header": "Next",
    "multiSelect": false,
    "options": [
      {"label": "Extract another phase", "description": "Extract another prose phase from the same skill"},
      {"label": "Validate skill", "description": "Run full skill validation"},
      {"label": "View updated SKILL.md", "description": "Show the updated SKILL.md"},
      {"label": "Done", "description": "Extraction complete"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_NEXT(response):
  SWITCH response:
    CASE "Extract another phase":
      # Re-run with remaining candidates
      GOTO Phase 1, Step 1.2

    CASE "Validate skill":
      DISPLAY "To validate, invoke:"
      DISPLAY "  Skill(skill: 'bp-skill-validate', args: '" + computed.skill_path + "')"

    CASE "View updated SKILL.md":
      content = Read(computed.skill_path)
      DISPLAY content

    CASE "Done":
      DISPLAY "Extraction complete. " + str(len(computed.files_created)) + " files created."
      EXIT
```

---

## Reference Documentation

- **Node Generation Procedure:** `patterns/node-generation-procedure.md` (local to this skill)
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
- **Consequence Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
- **Precondition Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
- **Authoring Guide:** `${CLAUDE_PLUGIN_ROOT}/patterns/authoring-guide.md`

---

## Related Skills

- Skill analysis (find extraction candidates): `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-analyze/SKILL.md`
- Skill validation: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-validate/SKILL.md`
- Create new skill from scratch: `${CLAUDE_PLUGIN_ROOT}/skills/bp-skill-create/SKILL.md`
- Plugin-level analysis: `${CLAUDE_PLUGIN_ROOT}/skills/bp-plugin-analyze/SKILL.md`
