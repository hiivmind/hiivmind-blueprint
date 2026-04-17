---
name: bp-extract
description: >
  This skill should be used when the user asks to "extract workflow", "formalize prose",
  "convert prose to workflow", "extract phase to yaml", "create workflow from skill",
  "formalize phase", "prose to workflow". Triggers on "extract", "formalize",
  "prose to workflow", "convert prose", "extract phase".
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

# Extract Workflow from Prose

Unified prose-to-workflow extraction pipeline. Analyzes a skill's prose phases, scores
extraction candidates, lets the user select which phases to formalize, generates workflow
YAML definitions, validates the result, and updates the SKILL.md to delegate to the new
workflow.

> **Node Generation Procedure:** `patterns/node-generation-procedure.md`
> **Consequence Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/consequences-catalog.md`
> **Precondition Catalog:** `${CLAUDE_PLUGIN_ROOT}/references/preconditions-catalog.md`
> **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/node-mapping.md`
> **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/patterns/skill-analysis.md`

---

## Overview

This skill is the extraction arm of the blueprint journey. After `bp-assess` identifies
a skill's position on the coverage spectrum and presents extraction as an option, this
skill handles the full pipeline:

1. Analyze the skill's phases and score extraction candidates
2. Let the user select which phase(s) to extract
3. Map prose elements to workflow nodes
4. Generate workflow YAML in `workflows/`
5. Validate the generated workflow
6. Update SKILL.md to delegate to the new workflow

**Pipeline position:**

```
bp-assess                  (identify coverage position, present options)
        |
bp-extract           <---  THIS SKILL (extract prose phases to workflows)
        |
bp-maintain                (ongoing validation, health checks)
```

**Modes:**

| Flag | Effect |
|------|--------|
| `--analyze-only` | Stop after Phase 3 (Score) — display candidates and exit |
| `--phase <id>` | Skip Phase 4 (Select) — extract the specified phase directly |
| `--skip-validation` | Skip Phase 6 (Validate) — write workflow without validation |

---

## Phase 1: Mode Detection

Parse invocation arguments to determine extraction behavior.

### Step 1.1: Parse Flags

Inspect invocation arguments for mode flags and target path:

```pseudocode
PARSE_MODE(args):
  computed.analyze_only = false
  computed.target_phase_id = null
  computed.skip_validation = false
  computed.skill_path = null

  IF args contains "--analyze-only":
    computed.analyze_only = true

  IF args contains "--phase <id>":
    computed.target_phase_id = extract_value(args, "--phase")

  IF args contains "--skip-validation":
    computed.skip_validation = true

  IF args contains "--skill <path>":
    computed.skill_path = extract_path(args, "--skill")
  ELIF args contains a bare path:
    computed.skill_path = resolve_skill_path(args)
  ELIF input.skill_path IS DEFINED:
    computed.skill_path = input.skill_path

  IF input.phase_id IS DEFINED AND computed.target_phase_id IS null:
    computed.target_phase_id = input.phase_id
```

### Step 1.2: Resolve Skill Path

If `computed.skill_path` is not set after flag parsing, prompt the user:

```json
{
  "questions": [{
    "question": "Which skill should I extract workflows from?",
    "header": "Target Skill",
    "multiSelect": false,
    "options": [
      {"label": "Provide path", "description": "I'll give you the skill directory or SKILL.md path"},
      {"label": "Search current plugin", "description": "Look for skills in this plugin's skills/ directory"}
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_SKILL_TARGET(response):
  SWITCH response:
    CASE "Provide path":
      # Ask user for the path via follow-up prompt
      computed.skill_path = resolve_skill_path(user_provided_path)

    CASE "Search current plugin":
      candidates = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
      IF len(candidates) == 1:
        computed.skill_path = candidates[0]
      ELSE:
        # Present candidates as AskUserQuestion options
        options = [{ label: basename(parent(c)), description: c } for c in candidates]
        computed.skill_path = selected_candidate

  # Resolve directory vs file
  IF is_directory(computed.skill_path):
    computed.skill_path = computed.skill_path + "/SKILL.md"

  computed.skill_dir = parent_directory(computed.skill_path)
  computed.skill_content = Read(computed.skill_path)
```

---

## Phase 2: Analyze

Locate the skill, parse its structure, and classify phases as prose or workflow-backed.

### Step 2.1: Parse Frontmatter

Extract metadata from the SKILL.md YAML frontmatter:

```pseudocode
PARSE_FRONTMATTER():
  frontmatter = content between first "---" and second "---"
  parsed = parse_yaml(frontmatter)

  computed.frontmatter = {
    name: parsed.name,
    description: parsed.description,
    allowed_tools: split(parsed["allowed-tools"], ", "),
    inputs: parsed.inputs OR [],
    outputs: parsed.outputs OR [],
    workflows_declared: parsed.workflows OR []
  }

  computed.skill_name = parsed.name
```

If frontmatter is missing or malformed, warn but continue using the directory name as
fallback for `computed.skill_name`.

### Step 2.2: Discover Existing Workflows

Check for workflow files already present in the skill's directory:

```pseudocode
DISCOVER_WORKFLOWS():
  # Check for workflows/ subdirectory
  workflow_files = Glob(computed.skill_dir + "/workflows/*.yaml")

  # Also check for legacy layout (bare workflow.yaml at skill root)
  legacy_workflow = Glob(computed.skill_dir + "/workflow.yaml")

  computed.workflow_files = []

  FOR wf_path IN workflow_files:
    content = Read(wf_path)
    computed.workflow_files.append({
      path: wf_path,
      filename: basename(wf_path),
      name: extract_field(content, "name"),
      layout: "modern"
    })

  FOR wf_path IN legacy_workflow:
    content = Read(wf_path)
    computed.workflow_files.append({
      path: wf_path,
      filename: basename(wf_path),
      name: extract_field(content, "name"),
      layout: "legacy"
    })
```

### Step 2.3: Identify Phases

Scan the SKILL.md body for phase boundaries:

| Pattern | Example | Confidence |
|---------|---------|------------|
| Numbered heading | `## Phase 1: Initialize` | High |
| Phase/Stage keyword | `### Phase: Validation` | High |
| Sequential numbering | `1. First...`, `2. Then...` | Medium |
| Temporal markers | `First`, `Next`, `Finally` | Medium |

```pseudocode
IDENTIFY_PHASES():
  computed.phases = []
  body = content_after_frontmatter(computed.skill_content)

  FOR line_num, line IN enumerate(body_lines):
    confidence = detect_phase_marker(line)
    IF confidence:
      phase = {
        id: slugify(extracted_title),
        title: extracted_title,
        prose_location: "lines {start}-{end}",
        confidence: confidence
      }
      computed.phases.append(phase)

  IF len(computed.phases) == 0:
    # Treat entire body as single phase
    computed.phases = [{
      id: "main",
      title: "Main",
      prose_location: "lines 1-{total}",
      confidence: "low"
    }]
```

### Step 2.4: Classify Phase Types

For each phase, determine whether it is prose-driven or workflow-backed:

```pseudocode
CLASSIFY_PHASES():
  FOR phase IN computed.phases:
    phase_content = get_lines(body, phase.prose_location)

    # Check for workflow delegation markers
    workflow_refs = find_patterns(phase_content, [
      /Execute\s+`?workflows\/[^`]+\.yaml`?/,
      /Run\s+`?workflows\/[^`]+\.yaml`?/,
      /workflow\.yaml/,
      /execution guide.*Init.*Execute.*Complete/
    ])

    IF len(workflow_refs) > 0:
      phase.type = "workflow"
      phase.workflow_file = extract_workflow_filename(workflow_refs[0])
      match = find(computed.workflow_files, wf => wf.filename == phase.workflow_file)
      IF match:
        phase.workflow_data = match
    ELSE:
      phase.type = "prose"
```

### Step 2.5: Classify Coverage

```pseudocode
CLASSIFY_COVERAGE():
  prose_count = count(p for p in computed.phases if p.type == "prose")
  workflow_count = count(p for p in computed.phases if p.type == "workflow")

  IF workflow_count == 0:
    computed.coverage = "prose"
  ELIF prose_count == 0:
    computed.coverage = "full"
  ELSE:
    computed.coverage = "partial"

  IF computed.coverage == "full":
    DISPLAY "All phases in this skill are already workflow-backed."
    DISPLAY "No prose phases available for extraction."
    EXIT
```

---

## Phase 3: Score

Assess each prose phase's complexity and calculate extraction scores.

### Step 3.1: Analyze Prose Phase Structure

For each prose-type phase, extract structural metrics:

```pseudocode
ANALYZE_PROSE_PHASE(phase):
  content = get_lines(body, phase.prose_location)

  # Count conditionals
  phase.conditionals = count_patterns(content, [
    /If\s+.*then/i, /When\s+/i, /Based on/i,
    /Depending on/i, /Unless/i, /Either.*or/i
  ])

  # Count tool references
  phase.tool_calls = 0
  phase.tools_used = set()
  FOR tool, patterns IN TOOL_PATTERNS:
    hits = count_patterns(content, patterns)
    IF hits > 0:
      phase.tool_calls += hits
      phase.tools_used.add(tool)

  # Count user interactions
  phase.user_interactions = count_patterns(content, [
    /AskUserQuestion/i, /ask.*user/i, /prompt.*user/i,
    /get.*input/i, /confirm.*with.*user/i
  ])

  # Count state variables
  phase.state_variables = count_unique_patterns(content, [
    /computed\.\w+/, /\$\{[^}]+\}/, /state\.\w+/
  ])

  # Lines of prose
  phase.prose_lines = count_non_empty_lines(content)
```

### Step 3.2: Calculate Extraction Scores

Score each prose phase to determine extraction suitability:

```pseudocode
function calculate_extraction_score(phase):
  score = 0

  # High conditional density suggests workflow control flow
  IF phase.conditionals >= 5: score += 3
  ELIF phase.conditionals >= 3: score += 2

  # FSM-like state transitions (explicit phase/state management)
  IF has_fsm_pattern(phase): score += 3

  # Loop with break condition (iteration pattern)
  IF has_loop_pattern(phase): score += 2

  # Multiple user prompts with branching (interaction graph)
  IF phase.user_interactions >= 2: score += 2

  # Validation gate pattern (multiple assertions grouped)
  IF has_validation_pattern(phase): score += 2

  # Linear tool call sequence only (simple but benefits from formalization)
  IF phase.conditionals == 0 AND phase.tool_calls > 0: score += 1

  RETURN score


function recommend_extraction(score):
  IF score <= 2: RETURN "leave_as_prose"
  IF score <= 4: RETURN "consider_extraction"
  RETURN "strong_candidate"
```

### Step 3.3: Assess Prose Complexity

Classify each phase's overall complexity:

```pseudocode
function assess_prose_complexity(phase):
  factors = {
    conditionals: classify(phase.conditionals, [1, 4]),      # 0-1=low, 2-4=med, 5+=high
    tool_variety: classify(len(phase.tools_used), [2, 4]),
    user_interactions: classify(phase.user_interactions, [1, 3]),
    state_variables: classify(phase.state_variables, [3, 7]),
    prose_lines: classify(phase.prose_lines, [30, 80])
  }
  avg = mean(factors.values)
  IF avg < 1.5: RETURN "low"
  IF avg <= 2.5: RETURN "medium"
  RETURN "high"
```

### Step 3.4: Rank Candidates

Build the ranked list of extraction candidates:

```pseudocode
RANK_CANDIDATES():
  FOR phase IN computed.phases:
    IF phase.type == "prose":
      phase.extraction_score = calculate_extraction_score(phase)
      phase.extraction_recommendation = recommend_extraction(phase.extraction_score)
      phase.complexity = assess_prose_complexity(phase)

  computed.candidates = [
    p for p in computed.phases
    if p.type == "prose" AND p.extraction_score >= 3
  ]
  computed.candidates.sort(key=lambda p: p.extraction_score, reverse=True)
```

### Step 3.5: Handle Analyze-Only Mode

If `computed.analyze_only == true`, display candidates and stop:

```pseudocode
IF computed.analyze_only:
  DISPLAY "## Extraction Candidates: " + computed.skill_name
  DISPLAY ""
  DISPLAY "**Coverage:** " + computed.coverage
  DISPLAY ""

  IF len(computed.candidates) > 0:
    DISPLAY "| Phase | Score | Recommendation | Conditionals | Tools | User Prompts | Lines |"
    DISPLAY "|-------|-------|----------------|--------------|-------|--------------|-------|"
    FOR phase IN computed.candidates:
      DISPLAY "| " + phase.title + " | " + str(phase.extraction_score) +
        " | " + phase.extraction_recommendation +
        " | " + str(phase.conditionals) +
        " | " + str(len(phase.tools_used)) +
        " | " + str(phase.user_interactions) +
        " | " + str(phase.prose_lines) + " |"
  ELSE:
    DISPLAY "No prose phases meet the extraction threshold (score >= 3)."
    DISPLAY ""
    DISPLAY "All prose phase scores:"
    FOR phase IN computed.phases:
      IF phase.type == "prose":
        DISPLAY "  - " + phase.title + ": " + str(phase.extraction_score) +
          " (" + phase.extraction_recommendation + ")"

  EXIT
```

---

## Phase 4: Select

Present extraction candidates and let the user choose which phase(s) to extract.

### Step 4.1: Check for Direct Phase Selection

If `computed.target_phase_id` was provided via `--phase` flag or `phase_id` input, skip
the interactive selection:

```pseudocode
CHECK_DIRECT_SELECTION():
  IF computed.target_phase_id IS NOT null:
    match = find(computed.phases, p => p.id == computed.target_phase_id)
    IF match IS null:
      DISPLAY "Phase ID '" + computed.target_phase_id + "' not found."
      DISPLAY "Available phases:"
      FOR p IN computed.phases:
        IF p.type == "prose":
          DISPLAY "  - " + p.id + " (" + p.title + ")"
      EXIT

    IF match.type != "prose":
      DISPLAY "Phase '" + match.title + "' is already workflow-backed."
      EXIT

    computed.selected_phases = [match]
    SKIP to Phase 5
```

### Step 4.2: Check Candidate Availability

```pseudocode
CHECK_CANDIDATES():
  IF len(computed.candidates) == 0:
    DISPLAY "No prose phases meet the extraction threshold (score >= 3)."
    DISPLAY ""
    DISPLAY "Phase scores:"
    FOR phase IN computed.phases:
      IF phase.type == "prose":
        DISPLAY "  - " + phase.title + ": " + str(phase.extraction_score)
    EXIT
```

### Step 4.3: Present Candidates

```json
{
  "questions": [{
    "question": "Which prose phase(s) should I extract into workflow definitions?",
    "header": "Extraction Candidates",
    "multiSelect": true,
    "options": [
      {
        "label": "{phase.title}",
        "description": "Score: {phase.extraction_score} | {phase.extraction_recommendation} | {phase.conditionals} conditionals, {len(phase.tools_used)} tools, {phase.user_interactions} prompts"
      }
    ]
  }]
}
```

### Step 4.4: Preview Extraction

After selection, show what extraction will produce before proceeding:

```pseudocode
PREVIEW_EXTRACTION():
  FOR phase IN computed.selected_phases:
    DISPLAY "### Preview: " + phase.title
    DISPLAY ""
    DISPLAY "| Aspect | Value |"
    DISPLAY "|--------|-------|"
    DISPLAY "| Extraction score | " + str(phase.extraction_score) + " |"
    DISPLAY "| Estimated nodes | " + str(estimate_node_count(phase)) + " |"
    DISPLAY "| Shape | " + determine_shape(phase) + " |"
    DISPLAY "| Output file | workflows/" + kebab_case(phase.title) + ".yaml |"
    DISPLAY ""
```

Store selected phases in `computed.selected_phases`.

---

## Phase 5: Extract

Analyze each selected phase's internal structure and generate workflow YAML.

### Step 5.1: Analyze Phase Internals

For each selected phase, perform deep structural analysis:

```pseudocode
ANALYZE_PHASE_INTERNALS(phase):
  content = get_lines(computed.skill_content, phase.prose_location)
  phase.full_content = content

  # Extract conditionals with branch targets
  phase.conditional_details = extract_conditionals(content)

  # Extract actions mapped to consequence types
  phase.actions = extract_actions(content)

  # Extract user interaction points
  phase.interaction_details = extract_user_interactions(content)

  # Extract state variable references
  phase.state_reads = extract_state_reads(content)     # ${computed.X} references
  phase.state_writes = extract_state_writes(content)   # store_as / mutate_state targets

  # Determine start conditions
  phase.preconditions = infer_preconditions(phase.state_reads, computed.phases)
```

### Step 5.2: Determine Workflow Shape

Based on internal analysis, classify the workflow's node structure:

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

  phase.estimated_nodes = estimate_node_count(phase)
```

### Step 5.3: Map Nodes

Use the node-generation-procedure pattern to create workflow nodes. Refer to
`patterns/node-generation-procedure.md` for the complete consequence type selection
guide, precondition type selection guide, and node type decision tree.

```pseudocode
MAP_NODES(phase):
  computed.workflow_nodes = {}
  node_order = []

  # Map each action to an action node
  FOR action IN phase.actions:
    IF action.is_conditional:
      # Create conditional + branch nodes
      cond_node = create_conditional_node(action.condition)
      computed.workflow_nodes[cond_node.id] = cond_node
      node_order.append(cond_node.id)

      true_node = create_action_node(action.true_branch)
      computed.workflow_nodes[true_node.id] = true_node
      node_order.append(true_node.id)

      IF action.false_branch:
        false_node = create_action_node(action.false_branch)
        computed.workflow_nodes[false_node.id] = false_node
        node_order.append(false_node.id)
    ELSE:
      node = create_action_node(action)
      computed.workflow_nodes[node.id] = node
      node_order.append(node.id)

  # Map user interactions to user_prompt nodes
  FOR interaction IN phase.interaction_details:
    prompt_node = create_user_prompt_node(interaction)
    computed.workflow_nodes[prompt_node.id] = prompt_node
    node_order.append(prompt_node.id)

  # Wire transitions (on_success, on_failure, branches, on_response)
  wire_transitions(computed.workflow_nodes, node_order)

  computed.workflow_start_node = node_order[0]
```

### Step 5.4: Build Workflow Scaffold

Assemble the complete workflow structure:

```pseudocode
BUILD_SCAFFOLD(phase):
  workflow_id = computed.skill_name + "-" + kebab_case(phase.title)
  computed.workflow_filename = kebab_case(phase.title) + ".yaml"

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
    },
    start_node: computed.workflow_start_node,
    nodes: computed.workflow_nodes,
    endings: {
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
  }

  # Add summary fields from state_writes to the success ending
  IF len(phase.state_writes) > 0:
    computed.workflow.endings.success.summary = {}
    FOR var IN phase.state_writes:
      computed.workflow.endings.success.summary[var] = "${computed." + var + "}"
```

### Step 5.5: Write Workflow File

```pseudocode
WRITE_WORKFLOW(phase):
  workflows_dir = computed.skill_dir + "/workflows"
  Bash("mkdir -p " + workflows_dir)

  workflow_content = render_workflow_yaml(computed.workflow)

  header = "# Generated by bp-extract\n"
  header += "# Extracted from: " + phase.title + " phase of " + computed.skill_name + "\n"
  header += "# Generated: " + current_iso_timestamp() + "\n\n"

  output_path = workflows_dir + "/" + computed.workflow_filename
  Write(output_path, header + workflow_content)
  computed.files_created.append(output_path)

  DISPLAY "Created: " + output_path
```

---

## Phase 6: Validate

Run structural validation on the generated workflow. Skipped if `--skip-validation` was set.

### Step 6.1: Check Skip Flag

```pseudocode
IF computed.skip_validation:
  DISPLAY "Validation skipped (--skip-validation flag set)."
  SKIP to Phase 7
```

### Step 6.2: Schema Validation

Verify the generated workflow has all required fields and valid node types:

```pseudocode
VALIDATE_SCHEMA():
  computed.validation_issues = []

  # Required top-level fields
  FOR field IN ["name", "start_node", "nodes", "endings"]:
    IF field NOT IN computed.workflow:
      computed.validation_issues.append({
        severity: "error",
        dimension: "schema",
        message: "Missing required field: " + field
      })

  # start_node references valid node
  IF computed.workflow.start_node NOT IN computed.workflow.nodes:
    computed.validation_issues.append({
      severity: "error",
      dimension: "schema",
      message: "start_node '" + computed.workflow.start_node + "' not found in nodes"
    })

  # Node type validation
  VALID_NODE_TYPES = ["action", "conditional", "user_prompt"]
  FOR node_id, node IN computed.workflow.nodes:
    IF "type" NOT IN node:
      computed.validation_issues.append({
        severity: "error",
        dimension: "schema",
        node: node_id,
        message: "Node '" + node_id + "' missing required field 'type'"
      })
    ELIF node.type NOT IN VALID_NODE_TYPES:
      computed.validation_issues.append({
        severity: "error",
        dimension: "schema",
        node: node_id,
        message: "Node '" + node_id + "' has invalid type '" + node.type + "'"
      })

  # Transition target validation
  valid_targets = set(computed.workflow.nodes.keys()) | set(computed.workflow.endings.keys())
  FOR node_id, node IN computed.workflow.nodes:
    targets = get_all_transition_targets(node)
    FOR target IN targets:
      IF target starts with "${":
        CONTINUE  # Dynamic target, cannot validate statically
      IF target NOT IN valid_targets:
        computed.validation_issues.append({
          severity: "error",
          dimension: "schema",
          node: node_id,
          message: "Transition target '" + target + "' not found in nodes or endings"
        })
```

### Step 6.3: Graph Validation

Check reachability and detect cycles:

```pseudocode
VALIDATE_GRAPH():
  # BFS reachability from start_node
  visited = {computed.workflow.start_node}
  queue = [computed.workflow.start_node]
  WHILE queue is not empty:
    current = queue.pop_front()
    IF current NOT IN computed.workflow.nodes:
      CONTINUE
    FOR target IN get_all_transition_targets(computed.workflow.nodes[current]):
      IF target starts with "${":
        CONTINUE
      IF target NOT IN visited:
        visited.add(target)
        IF target IN computed.workflow.nodes:
          queue.append(target)

  orphans = set(computed.workflow.nodes.keys()) - visited
  FOR orphan IN orphans:
    computed.validation_issues.append({
      severity: "error",
      dimension: "graph",
      node: orphan,
      message: "Orphan node '" + orphan + "' not reachable from start_node"
    })

  # Cycle detection (DFS with 3-color marking)
  # Back edge to GRAY node = cycle
  # Cycle without break condition = error (infinite loop)
  # Cycle with break condition = info (bounded loop)
  cycles = detect_cycles_dfs(computed.workflow.nodes)
  FOR cycle IN cycles:
    has_break = any(node has transition outside cycle for node in cycle)
    IF has_break:
      computed.validation_issues.append({
        severity: "info",
        dimension: "graph",
        message: "Bounded loop detected: " + join(cycle, " -> ")
      })
    ELSE:
      computed.validation_issues.append({
        severity: "error",
        dimension: "graph",
        message: "Infinite loop detected (no break condition): " + join(cycle, " -> ")
      })
```

### Step 6.4: Type Validation

Verify precondition and consequence types exist in the catalog:

```pseudocode
VALIDATE_TYPES():
  # Check consequence types in action nodes
  FOR node_id, node IN computed.workflow.nodes:
    IF node.type == "action":
      FOR action IN node.actions:
        IF action.type NOT IN VALID_CONSEQUENCE_TYPES:
          computed.validation_issues.append({
            severity: "warning",
            dimension: "types",
            node: node_id,
            message: "Unknown consequence type '" + action.type + "'"
          })

    # Check precondition types in conditional nodes
    IF node.type == "conditional":
      IF node.condition.type NOT IN VALID_PRECONDITION_TYPES:
        computed.validation_issues.append({
          severity: "warning",
          dimension: "types",
          node: node_id,
          message: "Unknown precondition type '" + node.condition.type + "'"
        })
```

### Step 6.5: State Consistency

Verify state variable references match definitions:

```pseudocode
VALIDATE_STATE():
  # Collect all initialized variables from initial_state
  initialized_vars = collect_keys_recursive(computed.workflow.initial_state)

  # Collect all runtime setters (mutate_state, set_flag, store_as)
  set_vars = {}
  FOR node_id, node IN computed.workflow.nodes:
    IF node.type == "action":
      FOR action IN node.actions:
        IF action.type == "mutate_state":
          set_vars[action.field] = node_id

  # Check all ${...} interpolation references
  all_refs = find_all_interpolations(computed.workflow)
  WELL_KNOWN = {"computed", "flags", "arguments", "user_responses",
                "phase", "prompts", "output", "logging"}
  known = initialized_vars | set(set_vars.keys()) | WELL_KNOWN

  FOR ref IN all_refs:
    IF ref.base_var NOT IN known:
      computed.validation_issues.append({
        severity: "warning",
        dimension: "state",
        message: "Variable '${" + ref.var_name + "}' may be undefined"
      })
```

### Step 6.6: Report Validation Results

```pseudocode
REPORT_VALIDATION():
  errors = [i for i in computed.validation_issues if i.severity == "error"]
  warnings = [i for i in computed.validation_issues if i.severity == "warning"]
  infos = [i for i in computed.validation_issues if i.severity == "info"]

  computed.validation_passed = len(errors) == 0

  IF computed.validation_passed:
    DISPLAY "Validation passed (" + str(len(warnings)) + " warnings, " +
      str(len(infos)) + " info)."
  ELSE:
    DISPLAY "Validation FAILED: " + str(len(errors)) + " error(s)."

  IF len(errors) > 0:
    DISPLAY ""
    DISPLAY "**Errors:**"
    FOR issue IN errors:
      DISPLAY "  - [" + issue.dimension + "] " + issue.message

  IF len(warnings) > 0:
    DISPLAY ""
    DISPLAY "**Warnings:**"
    FOR issue IN warnings:
      DISPLAY "  - [" + issue.dimension + "] " + issue.message

  # Offer to fix issues
  IF NOT computed.validation_passed:
    ASK: "Validation found errors. Would you like me to attempt auto-fixes?"
    IF user_confirms:
      attempt_auto_fix(computed.validation_issues)
      # Re-validate after fixes
      GOTO Step 6.2
```

---

## Phase 7: Update

Rewrite the extracted prose phase in SKILL.md to reference the new workflow.

### Step 7.1: Update Frontmatter

Add the new workflow to the `workflows:` list in SKILL.md frontmatter:

```pseudocode
UPDATE_FRONTMATTER():
  skill_content = Read(computed.skill_path)
  frontmatter = extract_frontmatter(skill_content)

  # Add workflows list if not present
  IF "workflows" NOT IN frontmatter:
    frontmatter.workflows = []

  # Add new workflow reference
  workflow_ref = "workflows/" + computed.workflow_filename
  IF workflow_ref NOT IN frontmatter.workflows:
    frontmatter.workflows.append(workflow_ref)

  updated_content = replace_frontmatter(skill_content, frontmatter)
```

### Step 7.2: Replace Prose with Workflow Delegation

Replace the extracted prose phase content with a delegation block:

```pseudocode
UPDATE_PHASE_CONTENT():
  skill_directory = basename(computed.skill_dir)

  new_content = "Execute `workflows/" + computed.workflow_filename
    + "` following the execution guide:\n\n"
  new_content += "1. Read `.hiivmind/blueprint/definitions.yaml` — build type registry\n"
  new_content += "2. Read `${CLAUDE_PLUGIN_ROOT}/skills/"
    + skill_directory + "/workflows/" + computed.workflow_filename + "`\n"
  new_content += "3. Follow `.hiivmind/blueprint/execution-guide.md` (Init -> Execute -> Complete)\n"

  # Document state handoff
  IF len(phase.state_reads) > 0:
    new_content += "\n**Reads:** " + join(phase.state_reads, ", ") + "\n"
  IF len(phase.state_writes) > 0:
    new_content += "**Writes:** " + join(phase.state_writes, ", ") + "\n"

  # Replace the original prose content
  updated_content = replace_phase_content(
    updated_content,
    phase.prose_location,
    new_content
  )

  Write(computed.skill_path, updated_content)
  computed.files_updated.append(computed.skill_path)
```

### Step 7.3: Display Before/After Summary

```pseudocode
DISPLAY_SUMMARY():
  DISPLAY "## Extraction Complete: " + phase.title
  DISPLAY ""
  DISPLAY "**Skill:** " + computed.skill_name
  DISPLAY "**Workflow file:** workflows/" + computed.workflow_filename
  DISPLAY "**Coverage change:** " + computed.coverage + " -> " + new_coverage
  DISPLAY ""
  DISPLAY "### Generated Workflow"
  DISPLAY ""
  DISPLAY "| Metric | Value |"
  DISPLAY "|--------|-------|"
  DISPLAY "| Nodes | " + str(len(computed.workflow.nodes)) + " |"
  DISPLAY "| Endings | " + str(len(computed.workflow.endings)) + " |"
  DISPLAY "| Start node | " + computed.workflow.start_node + " |"
  DISPLAY "| Shape | " + phase.shape + " |"
  DISPLAY "| State reads | " + join(phase.state_reads, ", ") + " |"
  DISPLAY "| State writes | " + join(phase.state_writes, ", ") + " |"
  DISPLAY ""
  DISPLAY "### Files Modified"
  DISPLAY ""
  DISPLAY "| File | Action |"
  DISPLAY "|------|--------|"
  FOR file IN computed.files_created:
    DISPLAY "| `" + file + "` | Created |"
  FOR file IN computed.files_updated:
    DISPLAY "| `" + file + "` | Updated |"
  DISPLAY ""
  DISPLAY "### Validation"
  DISPLAY ""
  IF computed.skip_validation:
    DISPLAY "Validation was skipped."
  ELIF computed.validation_passed:
    DISPLAY "All checks passed."
  ELSE:
    DISPLAY str(len([i for i in computed.validation_issues if i.severity == "error"])) + " error(s) found — review above."
```

### Step 7.4: Offer Next Actions

```json
{
  "questions": [{
    "question": "Extraction complete. What would you like to do next?",
    "header": "Next Steps",
    "multiSelect": false,
    "options": [
      {"label": "Extract another phase", "description": "Extract another prose phase from the same skill"},
      {"label": "Validate full skill", "description": "Run comprehensive validation (bp-maintain)"},
      {"label": "View updated SKILL.md", "description": "Show the updated SKILL.md content"},
      {"label": "Visualize workflow", "description": "Generate a visual diagram of the new workflow (bp-visualize)"},
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
      # Filter remaining candidates and restart from Phase 4
      remaining = [c for c in computed.candidates if c NOT IN computed.selected_phases]
      IF len(remaining) > 0:
        computed.candidates = remaining
        GOTO Phase 4, Step 4.2
      ELSE:
        DISPLAY "No remaining prose phases with score >= 3."

    CASE "Validate full skill":
      DISPLAY "To run comprehensive validation, invoke:"
      DISPLAY "  bp-maintain --skill " + computed.skill_path

    CASE "View updated SKILL.md":
      content = Read(computed.skill_path)
      DISPLAY content

    CASE "Visualize workflow":
      DISPLAY "To visualize the workflow, invoke:"
      DISPLAY "  bp-visualize " + computed.files_created[-1]

    CASE "Done":
      DISPLAY "Extraction complete. " + str(len(computed.files_created)) + " file(s) created."
      EXIT
```

---

## State Flow

```
Phase 1            Phase 2            Phase 3              Phase 4            Phase 5          Phase 6          Phase 7
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
computed           computed           computed              computed           computed         computed         computed
.analyze_only ->   .frontmatter ->    .candidates ->        .selected    ->    .workflow ->     .validation ->   .files_created
computed           computed           computed                _phases           computed         _issues          computed
.target_phase_id   .phases            .coverage                                .workflow_nodes  computed         .files_updated
computed           computed           (extraction_score,                        computed         .validation
.skip_validation   .workflow_files      extraction_rec,                         .workflow         _passed
computed           computed             complexity per                           _filename
.skill_path        .skill_name          prose phase)                            computed
computed           computed                                                     .workflow
.skill_content     .coverage                                                     _start_node
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

- **Assess coverage position:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- **Enhance prose structure:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-enhance/SKILL.md`
- **Maintain workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/SKILL.md`
- **Build new skills:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
- **Visualize workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-visualize/SKILL.md`
