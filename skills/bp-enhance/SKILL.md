---
name: bp-enhance
description: >
  This skill should be used when the user asks to "enhance a skill", "improve skill structure",
  "add pseudocode", "add state management", "tighten prose", "add guards",
  "strengthen skill", "add checkpoints", "improve without workflow". Triggers on
  "enhance", "improve", "add structure", "pseudocode", "state management",
  "strengthen", "tighten", "guards", "checkpoints".
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion
inputs:
  - name: skill_path
    type: string
    required: false
    description: Path to the skill directory or SKILL.md (prompted if not provided)
outputs:
  - name: enhancements_applied
    type: array
    description: List of enhancement types applied to the skill
  - name: updated_skill
    type: boolean
    description: Whether SKILL.md was modified
---

# Enhance Skill Structure

Add structure to prose-based skills — pseudocode blocks, state management, precondition guards,
phase boundary contracts, checkpoints, error handling — WITHOUT converting to workflow YAML.
This is the "prose territory" improvement path: tighter prose, not more formalization.

> **Phase Detection Algorithm:** `${CLAUDE_PLUGIN_ROOT}/patterns/phase-detection-algorithm.md`
> **Complexity Scoring Algorithm:** `${CLAUDE_PLUGIN_ROOT}/patterns/complexity-scoring-algorithm.md`
> **Quality Indicators:** `${CLAUDE_PLUGIN_ROOT}/patterns/quality-indicators.md`

---

## Overview

This skill operates on a single SKILL.md file and improves its internal structure while
preserving the prose orchestration approach. It does NOT create workflow YAML files.

| What It Does | What It Does NOT Do |
|-------------|---------------------|
| Adds pseudocode blocks for complex logic | Convert phases to workflow YAML |
| Introduces computed.* state management | Change the skill's phase count or scope |
| Adds precondition guards at phase boundaries | Remove existing prose instructions |
| Clarifies phase input/output contracts | Alter the skill's external interface |
| Adds checkpoint/restore patterns | Replace natural-language with rigid schemas |
| Adds error handling and recovery paths | Second-guess the author's design choices |
| Completes frontmatter input/output declarations | |

**Enhancement types:**

| Type | What It Adds | When Recommended |
|------|-------------|------------------|
| `state_management` | computed.* namespace, flag definitions | No state refs found, >2 phases |
| `pseudocode_blocks` | Structured logic for complex phases | Phase has >3 conditionals, no pseudocode |
| `precondition_guards` | Entry conditions for phases | Phases depend on prior phase output, no guards |
| `phase_boundaries` | Clearer phase separation with inputs/outputs | Phases lack clear contracts |
| `checkpoint_patterns` | Save/restore points | >4 phases, long-running operations |
| `error_handling` | Failure modes and recovery paths | No error handling, external tool calls |
| `io_contracts` | Explicit frontmatter declarations | Missing inputs/outputs in frontmatter |

---

## Phase 1: Mode Detection

Parse invocation arguments to determine enhancement behavior.

### Step 1.1: Parse Arguments

```pseudocode
PARSE_MODE(args):
  computed.mode = "interactive"
  computed.skill_path = null
  computed.analyze_only = false
  computed.requested_enhancement = null

  IF args contains "--analyze-only":
    computed.analyze_only = true

  IF args contains "--enhancement <type>":
    type = extract_value(args, "--enhancement")
    IF type IN ENHANCEMENT_CATALOG:
      computed.requested_enhancement = type
      computed.mode = "targeted"
    ELSE:
      DISPLAY "Unknown enhancement type: " + type
      DISPLAY "Valid types: state_management, pseudocode_blocks, precondition_guards,"
      DISPLAY "  phase_boundaries, checkpoint_patterns, error_handling, io_contracts"
      EXIT

  IF args contains a path (bare argument or --skill <path>):
    computed.skill_path = extract_path(args)

  IF computed.analyze_only AND computed.requested_enhancement:
    DISPLAY "Warning: --analyze-only and --enhancement are mutually exclusive."
    DISPLAY "Running in analyze-only mode (--analyze-only takes precedence)."
    computed.requested_enhancement = null
    computed.mode = "interactive"
```

### Step 1.2: Resolve Skill Path

If `computed.skill_path` is not set, prompt the user:

```json
{
  "questions": [{
    "question": "Which skill would you like to enhance?",
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
HANDLE_TARGET(response):
  SWITCH response:
    CASE "Provide path":
      # Ask for path via follow-up prompt
      computed.skill_path = resolve_skill_path(user_provided_path)

    CASE "Search current plugin":
      candidates = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
      # Present candidates as AskUserQuestion with each skill name as an option
      computed.skill_path = selected_candidate_path
```

### Step 1.3: Load Skill Content

```pseudocode
LOAD_SKILL():
  IF is_directory(computed.skill_path):
    computed.skill_path = computed.skill_path + "/SKILL.md"

  computed.skill_content = Read(computed.skill_path)
  computed.skill_dir = parent_directory(computed.skill_path)
  computed.skill_name = basename(computed.skill_dir)

  # Parse frontmatter
  frontmatter = content between first "---" and second "---"
  parsed = parse_yaml(frontmatter)

  computed.frontmatter = {
    name: parsed.name,
    description: parsed.description,
    allowed_tools: split(parsed["allowed-tools"], ", "),
    inputs_defined: "inputs" IN parsed AND len(parsed.inputs) > 0,
    outputs_defined: "outputs" IN parsed AND len(parsed.outputs) > 0,
    inputs: parsed.inputs OR [],
    outputs: parsed.outputs OR []
  }
```

---

## Phase 2: Analyze

Examine the skill's current structure to identify enhancement opportunities.

### Step 2.1: Identify Phases

Use the phase detection algorithm from `${CLAUDE_PLUGIN_ROOT}/patterns/phase-detection-algorithm.md`:

```pseudocode
IDENTIFY_PHASES():
  body = content_after_frontmatter(computed.skill_content)
  computed.phases = []

  FOR line_num, line IN enumerate(body_lines):
    confidence = detect_phase_marker(line)
    IF confidence:
      phase = {
        id: slugify(extracted_title),
        title: extracted_title,
        line_start: line_num,
        line_end: null,  # filled in below
        confidence: confidence
      }
      computed.phases.append(phase)

  # Fill in line_end for each phase (start of next phase or end of body)
  FOR i IN range(len(computed.phases)):
    IF i + 1 < len(computed.phases):
      computed.phases[i].line_end = computed.phases[i + 1].line_start - 1
    ELSE:
      computed.phases[i].line_end = len(body_lines)

  IF len(computed.phases) == 0:
    computed.phases = [{
      id: "main",
      title: "Main",
      line_start: 1,
      line_end: len(body_lines),
      confidence: "low"
    }]
```

### Step 2.2: Analyze Current Structure

For each phase, measure existing structural elements:

```pseudocode
ANALYZE_STRUCTURE():
  computed.current_structure = {
    phase_count: len(computed.phases),
    pseudocode_blocks: [],
    state_refs: [],
    precondition_guards: [],
    phase_contracts: [],
    checkpoints: [],
    error_handlers: [],
    io_contracts: {
      inputs_declared: computed.frontmatter.inputs_defined,
      outputs_declared: computed.frontmatter.outputs_defined
    }
  }

  FOR phase IN computed.phases:
    content = get_lines(body, phase.line_start, phase.line_end)

    # Count pseudocode blocks
    pseudocode_blocks = find_fenced_blocks(content, "pseudocode")
    FOR block IN pseudocode_blocks:
      computed.current_structure.pseudocode_blocks.append({
        phase: phase.id,
        line: block.start_line,
        length: block.line_count
      })

    # Count state management references
    state_patterns = find_all_patterns(content, [
      /computed\.\w+/,
      /flags\.\w+/,
      /state\.\w+/
    ])
    FOR ref IN state_patterns:
      computed.current_structure.state_refs.append({
        phase: phase.id,
        reference: ref.matched_text,
        line: ref.line_num
      })

    # Check for precondition guards
    guard_patterns = find_all_patterns(content, [
      /GUARD:|PRECONDITION:|REQUIRES:/i,
      /IF\s+computed\.\w+\s+(is|==|!=)\s+null.*EXIT/i,
      /Assert|Verify.*before\s+proceed/i
    ])
    FOR guard IN guard_patterns:
      computed.current_structure.precondition_guards.append({
        phase: phase.id,
        guard_text: guard.matched_text,
        line: guard.line_num
      })

    # Check phase boundary clarity
    has_input_declaration = matches_any(content, [
      /inputs?:|receives?:|expects?:/i,
      /from\s+phase\s+\d/i
    ])
    has_output_declaration = matches_any(content, [
      /outputs?:|produces?:|sets?:/i,
      /stored?\s+in\s+computed\./i
    ])
    computed.current_structure.phase_contracts.append({
      phase: phase.id,
      has_input_spec: has_input_declaration,
      has_output_spec: has_output_declaration
    })

    # Check checkpoint usage
    checkpoint_patterns = find_all_patterns(content, [
      /CHECKPOINT:|SAVE_STATE:|RESTORE:/i,
      /checkpoint|save.*progress|resume/i
    ])
    FOR cp IN checkpoint_patterns:
      computed.current_structure.checkpoints.append({
        phase: phase.id,
        text: cp.matched_text,
        line: cp.line_num
      })

    # Check error handling
    error_patterns = find_all_patterns(content, [
      /ERROR:|FAILURE:|FALLBACK:/i,
      /IF.*fail|IF.*error/i,
      /on_error|on_failure|recovery/i,
      /DISPLAY.*error|warn.*user/i
    ])
    FOR err IN error_patterns:
      computed.current_structure.error_handlers.append({
        phase: phase.id,
        text: err.matched_text,
        line: err.line_num
      })

    # Per-phase complexity metrics (for recommendation targeting)
    phase.conditionals = count_patterns(content, [
      /If\s+.*then/i, /When\s+/i, /Based on/i,
      /Depending on/i, /Unless/i, /Either.*or/i
    ])
    phase.tool_calls = count_tool_references(content)
    phase.has_pseudocode = len(pseudocode_blocks) > 0
    phase.has_state_refs = len(state_patterns) > 0
    phase.has_guards = len(guard_patterns) > 0
    phase.has_error_handling = len(error_patterns) > 0
    phase.prose_lines = count_non_empty_lines(content)
```

### Step 2.3: Compute Structure Summary

```pseudocode
SUMMARIZE_STRUCTURE():
  s = computed.current_structure

  computed.structure_summary = {
    total_pseudocode_blocks: len(s.pseudocode_blocks),
    total_state_refs: len(s.state_refs),
    unique_state_vars: count_unique(ref.reference for ref in s.state_refs),
    total_guards: len(s.precondition_guards),
    phases_with_input_spec: count(c for c in s.phase_contracts if c.has_input_spec),
    phases_with_output_spec: count(c for c in s.phase_contracts if c.has_output_spec),
    total_checkpoints: len(s.checkpoints),
    total_error_handlers: len(s.error_handlers),
    phases_with_pseudocode: count_unique(b.phase for b in s.pseudocode_blocks),
    phases_without_pseudocode: s.phase_count - count_unique(b.phase for b in s.pseudocode_blocks)
  }
```

---

## Phase 3: Recommend

Generate contextual enhancement recommendations based on the Phase 2 analysis.

### Step 3.1: Evaluate Each Enhancement Type

```pseudocode
GENERATE_RECOMMENDATIONS():
  computed.recommendations = []

  # --- state_management ---
  IF computed.structure_summary.total_state_refs == 0
     AND computed.current_structure.phase_count > 2:
    computed.recommendations.append({
      type: "state_management",
      rationale: "Skill has " + str(computed.current_structure.phase_count) +
                 " phases but no computed.* state references. Adding a state " +
                 "namespace makes data flow between phases explicit.",
      impact: "high",
      example: generate_state_management_example()
    })

  # --- pseudocode_blocks ---
  FOR phase IN computed.phases:
    IF phase.conditionals > 3 AND NOT phase.has_pseudocode:
      computed.recommendations.append({
        type: "pseudocode_blocks",
        target_phase: phase.id,
        rationale: "Phase '" + phase.title + "' has " + str(phase.conditionals) +
                   " conditionals but no pseudocode block. Pseudocode makes " +
                   "branching logic unambiguous.",
        impact: "high",
        example: generate_pseudocode_example(phase)
      })

  # --- precondition_guards ---
  FOR i, phase IN enumerate(computed.phases):
    IF i > 0 AND NOT phase.has_guards:
      prior = computed.phases[i - 1]
      prior_contract = find(computed.current_structure.phase_contracts,
                            c => c.phase == prior.id)
      IF prior_contract AND prior_contract.has_output_spec:
        computed.recommendations.append({
          type: "precondition_guards",
          target_phase: phase.id,
          rationale: "Phase '" + phase.title + "' depends on output from '" +
                     prior.title + "' but has no entry guard. A precondition " +
                     "guard catches missing prerequisites early.",
          impact: "medium",
          example: generate_guard_example(phase, prior)
        })

  # --- phase_boundaries ---
  phases_missing_contracts = [
    c for c in computed.current_structure.phase_contracts
    if NOT c.has_input_spec OR NOT c.has_output_spec
  ]
  IF len(phases_missing_contracts) > computed.current_structure.phase_count / 2:
    computed.recommendations.append({
      type: "phase_boundaries",
      rationale: str(len(phases_missing_contracts)) + " of " +
                 str(computed.current_structure.phase_count) +
                 " phases lack clear input/output contracts. Adding contracts " +
                 "makes each phase self-documenting.",
      impact: "medium",
      example: generate_boundary_example()
    })

  # --- checkpoint_patterns ---
  IF computed.current_structure.phase_count > 4
     AND computed.structure_summary.total_checkpoints == 0:
    has_long_running = any(p.tool_calls > 3 OR p.prose_lines > 60
                          for p in computed.phases)
    IF has_long_running:
      computed.recommendations.append({
        type: "checkpoint_patterns",
        rationale: "Skill has " + str(computed.current_structure.phase_count) +
                   " phases with long-running operations but no checkpoints. " +
                   "Checkpoints allow resuming from a known-good state on failure.",
        impact: "medium",
        example: generate_checkpoint_example()
      })

  # --- error_handling ---
  phases_without_errors = [p for p in computed.phases
                           if NOT p.has_error_handling AND p.tool_calls > 0]
  IF len(phases_without_errors) > 0:
    computed.recommendations.append({
      type: "error_handling",
      target_phases: [p.id for p in phases_without_errors],
      rationale: str(len(phases_without_errors)) + " phase(s) invoke external " +
                 "tools but have no error handling. Adding failure modes and " +
                 "recovery paths prevents silent failures.",
      impact: "high",
      example: generate_error_handling_example(phases_without_errors[0])
    })

  # --- io_contracts ---
  IF NOT computed.frontmatter.inputs_defined OR NOT computed.frontmatter.outputs_defined:
    missing = []
    IF NOT computed.frontmatter.inputs_defined: missing.append("inputs")
    IF NOT computed.frontmatter.outputs_defined: missing.append("outputs")
    computed.recommendations.append({
      type: "io_contracts",
      rationale: "Frontmatter is missing " + join(missing, " and ") +
                 " declarations. Explicit I/O contracts let callers " +
                 "understand the skill's interface without reading the body.",
      impact: "medium",
      example: generate_io_contract_example()
    })
```

### Step 3.2: Generate Concrete Examples

Each recommendation includes a concrete pseudocode example showing what the enhancement
would look like when applied to the target skill.

```pseudocode
function generate_state_management_example():
  RETURN """
  ## State Flow

  ```
  Phase 1           Phase 2              Phase 3
  ─────────────────────────────────────────────────
  computed.target -> computed.analysis -> computed.result
  computed.mode      computed.metrics     computed.report
  ```

  At Phase 1, initialize the state namespace:

  ```pseudocode
  INIT_STATE():
    computed.target = null
    computed.mode = null
    computed.analysis = null
  ```
  """


function generate_pseudocode_example(phase):
  RETURN """
  Add to Phase '{phase.title}':

  ```pseudocode
  PROCESS_{upper(phase.id)}():
    IF condition_a:
      computed.result = handle_case_a()
    ELIF condition_b AND condition_c:
      computed.result = handle_case_b()
    ELSE:
      computed.result = default_handler()
      DISPLAY "Falling back to default: " + computed.result
  ```
  """


function generate_guard_example(phase, prior_phase):
  RETURN """
  Add at the start of Phase '{phase.title}':

  ```pseudocode
  GUARD_{upper(phase.id)}():
    IF computed.{prior_phase.id}_output IS null:
      DISPLAY "Cannot proceed: Phase '{prior_phase.title}' has not completed."
      DISPLAY "Required state: computed.{prior_phase.id}_output"
      EXIT
  ```
  """


function generate_boundary_example():
  RETURN """
  Add to each phase heading:

  ## Phase N: Title

  **Inputs:** `computed.prior_result` (from Phase N-1)
  **Outputs:** `computed.this_result` (used by Phase N+1)

  This pattern makes data flow visible at a glance without reading
  the phase body.
  """


function generate_checkpoint_example():
  RETURN """
  Add after critical operations:

  ```pseudocode
  CHECKPOINT_AFTER_ANALYSIS():
    computed.checkpoint = {
      phase: "analysis",
      timestamp: current_iso_timestamp(),
      state: {
        target: computed.target,
        metrics: computed.metrics
      }
    }
    # On re-invocation, check for checkpoint:
    IF computed.checkpoint AND computed.checkpoint.phase == "analysis":
      DISPLAY "Resuming from analysis checkpoint."
      RESTORE computed.target, computed.metrics FROM computed.checkpoint.state
      SKIP to Phase 3
  ```
  """


function generate_error_handling_example(phase):
  RETURN """
  Add to Phase '{phase.title}' around tool calls:

  ```pseudocode
  HANDLE_{upper(phase.id)}_ERRORS():
    result = Read(computed.target_path)
    IF result IS error:
      DISPLAY "Failed to read " + computed.target_path + ": " + result.message
      IF result.type == "file_not_found":
        DISPLAY "Verify the path exists and try again."
        EXIT
      ELIF result.type == "permission_denied":
        DISPLAY "Check file permissions on " + computed.target_path
        EXIT
      ELSE:
        DISPLAY "Unexpected error — aborting."
        EXIT
  ```
  """


function generate_io_contract_example():
  RETURN """
  Add to the YAML frontmatter:

  ```yaml
  inputs:
    - name: target_path
      type: string
      required: false
      description: Path to the target (prompted if not provided)
  outputs:
    - name: result
      type: object
      description: The operation result
  ```
  """
```

### Step 3.3: Display Recommendations

Present the recommendations with their examples:

```
## Enhancement Recommendations: {computed.skill_name}

**Current structure:**
- Phases: {computed.current_structure.phase_count}
- Pseudocode blocks: {computed.structure_summary.total_pseudocode_blocks}
- State references: {computed.structure_summary.unique_state_vars} unique variables
- Precondition guards: {computed.structure_summary.total_guards}
- Checkpoints: {computed.structure_summary.total_checkpoints}
- Error handlers: {computed.structure_summary.total_error_handlers}
- I/O contracts: inputs={yes/no}, outputs={yes/no}

### Recommendations ({count})

{for i, rec in enumerate(computed.recommendations)}
#### {i+1}. {rec.type} [{rec.impact} impact]

{rec.rationale}

{rec.example}

---
{/for}
```

IF `computed.analyze_only == true`: display recommendations and STOP. Do not proceed to
Phase 4.

---

## Phase 4: Select

Determine which enhancements to apply.

### Step 4.1: Select Enhancements

If `computed.mode == "targeted"` (the `--enhancement` flag was set):

```pseudocode
HANDLE_TARGETED():
  matching = [r for r in computed.recommendations
              if r.type == computed.requested_enhancement]
  IF len(matching) > 0:
    computed.selected_enhancements = matching
  ELSE:
    DISPLAY "Enhancement type '" + computed.requested_enhancement +
            "' was requested but no recommendation was generated for it."
    DISPLAY "This means the skill already has adequate coverage for this type,"
    DISPLAY "or the prerequisites for this enhancement are not met."
    EXIT
```

If `computed.mode == "interactive"`, present recommendations as a multi-select:

```json
{
  "questions": [{
    "question": "Which enhancements would you like to apply?",
    "header": "Select Enhancements",
    "multiSelect": true,
    "options": [
      {
        "label": "state_management",
        "description": "Add computed.* namespace and state flow diagram [high impact]"
      },
      {
        "label": "pseudocode_blocks",
        "description": "Add pseudocode for complex conditional logic [high impact]"
      },
      {
        "label": "precondition_guards",
        "description": "Add entry guards at phase boundaries [medium impact]"
      },
      {
        "label": "phase_boundaries",
        "description": "Add input/output contracts to phase headings [medium impact]"
      },
      {
        "label": "checkpoint_patterns",
        "description": "Add save/restore points for long-running operations [medium impact]"
      },
      {
        "label": "error_handling",
        "description": "Add failure modes and recovery paths [high impact]"
      },
      {
        "label": "io_contracts",
        "description": "Add inputs/outputs declarations to frontmatter [medium impact]"
      }
    ]
  }]
}
```

NOTE: Only present options that have matching recommendations from Phase 3. Filter the
options list to include only types present in `computed.recommendations`.

```pseudocode
HANDLE_SELECTION(response):
  selected_types = parse_multi_select(response)
  computed.selected_enhancements = [
    r for r in computed.recommendations
    if r.type IN selected_types
  ]

  IF len(computed.selected_enhancements) == 0:
    DISPLAY "No enhancements selected. Exiting."
    EXIT
```

---

## Phase 5: Apply

Apply each selected enhancement to the SKILL.md file.

### Step 5.1: Plan Application Order

Enhancements are applied in a specific order to avoid conflicts:

```pseudocode
APPLICATION_ORDER = [
  "io_contracts",           # Frontmatter changes first (top of file)
  "state_management",       # State flow section (typically after overview)
  "phase_boundaries",       # Phase heading annotations
  "precondition_guards",    # Added at phase starts
  "pseudocode_blocks",      # Added within phase bodies
  "error_handling",         # Added within phase bodies
  "checkpoint_patterns"     # Added at phase ends
]

PLAN_APPLICATION():
  computed.application_plan = sorted(
    computed.selected_enhancements,
    key=lambda e: APPLICATION_ORDER.index(e.type)
  )
  computed.enhancements_applied = []
```

### Step 5.2: Apply Each Enhancement

For each enhancement in the application plan:

```pseudocode
APPLY_ENHANCEMENTS():
  FOR enhancement IN computed.application_plan:
    # Generate the content to insert or modify
    content = generate_enhancement_content(enhancement)

    # Determine insertion point
    location = determine_insertion_point(enhancement, computed.skill_content)

    # Show diff-style preview
    DISPLAY "--- Enhancement: " + enhancement.type + " ---"
    DISPLAY ""
    DISPLAY "Location: " + location.description
    DISPLAY ""
    DISPLAY "Content to add:"
    DISPLAY "```"
    DISPLAY content
    DISPLAY "```"
    DISPLAY ""

    # Apply via Edit tool
    SWITCH enhancement.type:
      CASE "io_contracts":
        # Edit the frontmatter section to add inputs/outputs
        Edit(computed.skill_path,
          old_string=existing_frontmatter_closing,
          new_string=io_declarations + frontmatter_closing)

      CASE "state_management":
        # Insert State Flow section after Overview (or after frontmatter)
        Edit(computed.skill_path,
          old_string=first_phase_heading,
          new_string=state_flow_section + "\n\n" + first_phase_heading)

      CASE "phase_boundaries":
        # Annotate each phase heading with Inputs/Outputs
        FOR phase IN computed.phases:
          phase_heading = get_phase_heading_line(phase)
          Edit(computed.skill_path,
            old_string=phase_heading,
            new_string=phase_heading + "\n\n" + boundary_annotation(phase))

      CASE "precondition_guards":
        # Insert guard block after the phase heading
        target = enhancement.target_phase
        phase_heading = get_phase_heading_line(target)
        Edit(computed.skill_path,
          old_string=first_content_after(phase_heading),
          new_string=guard_block + "\n\n" + first_content_after(phase_heading))

      CASE "pseudocode_blocks":
        # Insert pseudocode block into the target phase
        target = enhancement.target_phase
        insertion_point = find_best_insertion_point(target)
        Edit(computed.skill_path,
          old_string=insertion_point,
          new_string=insertion_point + "\n\n" + pseudocode_block)

      CASE "error_handling":
        # Insert error handling around tool calls in target phases
        FOR target IN enhancement.target_phases:
          tool_call_section = find_tool_call_section(target)
          Edit(computed.skill_path,
            old_string=tool_call_section,
            new_string=wrapped_with_error_handling(tool_call_section))

      CASE "checkpoint_patterns":
        # Insert checkpoint block at end of long-running phases
        FOR phase IN computed.phases:
          IF phase.tool_calls > 3 OR phase.prose_lines > 60:
            phase_end = get_phase_end_marker(phase)
            Edit(computed.skill_path,
              old_string=phase_end,
              new_string=checkpoint_block(phase) + "\n\n" + phase_end)

    # Track applied enhancement
    computed.enhancements_applied.append(enhancement.type)

    # Re-read the file after each edit to keep content in sync
    computed.skill_content = Read(computed.skill_path)
```

### Step 5.3: Handle Apply Errors

```pseudocode
HANDLE_APPLY_ERROR(enhancement, error):
  DISPLAY "Failed to apply enhancement '" + enhancement.type + "': " + error.message
  DISPLAY ""
  DISPLAY "This can happen when:"
  DISPLAY "  - The insertion point text was not found (file structure changed)"
  DISPLAY "  - The Edit tool could not find a unique match for old_string"
  DISPLAY ""
  DISPLAY "The enhancement content has been displayed above. You can apply it manually."
  # Continue with remaining enhancements — do not abort the batch
```

---

## Phase 6: Verify

Re-analyze the modified skill and compare before/after metrics.

### Step 6.1: Re-Analyze

Re-run the analysis from Phase 2 on the modified SKILL.md:

```pseudocode
VERIFY():
  # Store pre-enhancement metrics
  computed.before_metrics = copy(computed.structure_summary)

  # Re-read and re-analyze
  computed.skill_content = Read(computed.skill_path)
  IDENTIFY_PHASES()       # Phase 2, Step 2.1
  ANALYZE_STRUCTURE()     # Phase 2, Step 2.2
  SUMMARIZE_STRUCTURE()   # Phase 2, Step 2.3

  computed.after_metrics = copy(computed.structure_summary)
```

### Step 6.2: Compare and Report

```pseudocode
COMPARE_METRICS():
  computed.improvement = {}

  metrics_to_compare = [
    "total_pseudocode_blocks",
    "unique_state_vars",
    "total_guards",
    "phases_with_input_spec",
    "phases_with_output_spec",
    "total_checkpoints",
    "total_error_handlers"
  ]

  FOR metric IN metrics_to_compare:
    before = computed.before_metrics[metric]
    after = computed.after_metrics[metric]
    computed.improvement[metric] = {
      before: before,
      after: after,
      delta: after - before
    }
```

Display the improvement summary:

```
## Enhancement Results: {computed.skill_name}

**Enhancements applied:** {join(computed.enhancements_applied, ", ")}
**Skill path:** {computed.skill_path}

### Before / After

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Pseudocode blocks | {before} | {after} | +{delta} |
| State variables | {before} | {after} | +{delta} |
| Precondition guards | {before} | {after} | +{delta} |
| Phases with input spec | {before}/{total} | {after}/{total} | +{delta} |
| Phases with output spec | {before}/{total} | {after}/{total} | +{delta} |
| Checkpoints | {before} | {after} | +{delta} |
| Error handlers | {before} | {after} | +{delta} |

{if all deltas == 0}
No measurable structural changes detected. Review the skill manually to
verify enhancements were applied correctly.
{else}
Structural improvements applied successfully.
{/if}
```

### Step 6.3: Set Outputs

```pseudocode
SET_OUTPUTS():
  outputs.enhancements_applied = computed.enhancements_applied
  outputs.updated_skill = len(computed.enhancements_applied) > 0
```

---

## State Flow

```
Phase 1            Phase 2                  Phase 3                Phase 4              Phase 5            Phase 6
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
computed.mode   -> computed.phases        -> computed              -> computed           -> computed         -> computed
computed          computed.current           .recommendations        .selected             .enhancements      .before_metrics
.skill_path       _structure               (with examples)           _enhancements         _applied          computed
computed          computed.structure                                computed                                  .after_metrics
.analyze_only     _summary                                          .application                             computed
computed          computed.frontmatter                               _plan                                    .improvement
.requested
_enhancement
```

---

## Reference Documentation

- **Phase Detection Algorithm:** `${CLAUDE_PLUGIN_ROOT}/patterns/phase-detection-algorithm.md`
- **Complexity Scoring Algorithm:** `${CLAUDE_PLUGIN_ROOT}/patterns/complexity-scoring-algorithm.md`
- **Quality Indicators:** `${CLAUDE_PLUGIN_ROOT}/patterns/quality-indicators.md`

---

## Related Skills

- **Assess skill coverage and fit:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- **Extract to workflows:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-extract/SKILL.md`
- **Build new skills:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-build/SKILL.md`
