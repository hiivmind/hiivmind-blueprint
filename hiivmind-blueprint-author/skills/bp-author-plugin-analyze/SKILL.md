---
name: bp-author-plugin-analyze
description: >
  This skill should be used when the user asks to "analyze plugin health", "plugin-wide analysis",
  "assess plugin quality", "cross-skill metrics", "plugin health check", "dependency analysis",
  or needs to understand the overall health and quality of a plugin. Triggers on "plugin analyze",
  "analyze plugin", "plugin health", "health check", "plugin quality", "cross-skill analysis".
allowed-tools: Read, Glob, Grep, AskUserQuestion
---

# Plugin-Wide Health Analysis

Perform comprehensive read-only analysis across all skills in a plugin. Produces cross-skill
metrics, dependency maps, intent coverage checks, version consistency audits, and an overall
health dashboard with scored recommendations.

> **Health Scoring Algorithm:** `patterns/health-scoring-algorithm.md`
> **Cross-Skill Metrics:** `patterns/cross-skill-metrics.md`
> **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

---

## Overview

This skill examines an **entire plugin** -- all skills, workflows, gateway, and shared
configuration -- to produce a holistic quality assessment. It is the plugin-level counterpart
to `bp-author-skill-analyze` (single workflow) and `bp-author-prose-analyze` (single SKILL.md).

The analysis produces seven categories of output:

| Category | What It Measures |
|----------|-----------------|
| Inventory | Full skill inventory with classifications |
| Cross-skill metrics | Total nodes, average complexity, shared patterns, duplicates |
| Dependencies | Subflow references, shared state, external lib alignment |
| Intent coverage | Gateway routing completeness, keyword overlap, unrouted skills |
| Version consistency | Lib version alignment, deprecated type usage, schema version |
| Health dashboard | Weighted overall score with per-category breakdowns |
| Recommendations | Priority-ranked improvements across all dimensions |

All results are stored in `computed.*` namespaces and rendered as a final dashboard report.

---

## Phase 1: Discover

Locate and classify every skill in the target plugin. This phase reuses the logic from
`bp-author-plugin-discover` but runs non-interactively against the current plugin root.

### Step 1.1: Invoke Plugin Discover Logic

Use Glob to find all SKILL.md files across both `skills/` and `skills-prose/` directories.
Classify each skill by checking for workflow.yaml siblings and analyzing content indicators.

```pseudocode
DISCOVER_SKILLS():
  # Locate all SKILL.md files in the plugin
  skill_files = Glob("${CLAUDE_PLUGIN_ROOT}/skills/*/SKILL.md")
  skill_files += Glob("${CLAUDE_PLUGIN_ROOT}/skills-prose/*/SKILL.md")

  # Deduplicate by absolute path
  skill_files = deduplicate(skill_files)

  IF len(skill_files) == 0:
    DISPLAY "ERROR: No SKILL.md files found under ${CLAUDE_PLUGIN_ROOT}/skills/ or skills-prose/."
    DISPLAY "Verify the plugin directory is correct and contains skill definitions."
    EXIT

  computed.plugin_root = CLAUDE_PLUGIN_ROOT
  computed.plugin_name = basename(CLAUDE_PLUGIN_ROOT)
```

### Step 1.2: Get Full Inventory with Classifications

For each discovered SKILL.md, read the file, check for a sibling workflow.yaml, and classify:

```pseudocode
CLASSIFY_ALL():
  computed.inventory = []

  FOR file IN skill_files:
    content = Read(file.path)
    skill = {
      name:       extract_frontmatter_field(content, "name"),
      path:       file.path,
      directory:  parent_directory(file.path),
      location:   "skills" if "/skills/" in file.path else "skills-prose"
    }

    # Check for workflow sibling
    workflow_path = skill.directory + "/workflow.yaml"
    skill.has_workflow = file_exists(workflow_path)
    IF skill.has_workflow:
      skill.workflow_path = workflow_path

    # Classify: prose | workflow | hybrid | simple
    skill.classification = classify_skill(skill, content)
    skill.line_count = count_lines(content)

    computed.inventory.append(skill)

  computed.inventory_summary = {
    total:    len(computed.inventory),
    prose:    count(s for s in computed.inventory if s.classification == "prose"),
    workflow: count(s for s in computed.inventory if s.classification == "workflow"),
    hybrid:   count(s for s in computed.inventory if s.classification == "hybrid"),
    simple:   count(s for s in computed.inventory if s.classification == "simple")
  }
```

Store the full inventory in `computed.inventory` and summary counts in
`computed.inventory_summary`.

---

## Phase 2: Cross-Skill Metrics

Compute aggregate metrics across all workflows in the plugin. Only skills that have a
`workflow.yaml` (classifications `workflow` or `hybrid`) are included in workflow metrics.

### Step 2.1: Total Nodes Across All Workflows

Read each workflow.yaml and count the nodes defined in each:

```pseudocode
TOTAL_NODES():
  computed.cross_metrics.workflows = []
  computed.cross_metrics.total_nodes = 0
  computed.cross_metrics.total_endings = 0
  computed.cross_metrics.total_actions = 0

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)
    nodes = extract_yaml_section(content, "nodes")
    endings = extract_yaml_section(content, "endings")

    node_count = count_keys(nodes)
    ending_count = count_keys(endings)
    action_count = 0
    FOR node_id, node IN nodes:
      IF node.type == "action":
        action_count += len(node.actions)

    workflow_entry = {
      name:         skill.name,
      path:         skill.workflow_path,
      node_count:   node_count,
      ending_count: ending_count,
      action_count: action_count
    }
    computed.cross_metrics.workflows.append(workflow_entry)
    computed.cross_metrics.total_nodes += node_count
    computed.cross_metrics.total_endings += ending_count
    computed.cross_metrics.total_actions += action_count
```

### Step 2.2: Average Complexity

Compute the mean cyclomatic complexity across all workflows:

```pseudocode
AVERAGE_COMPLEXITY():
  complexities = []

  FOR wf IN computed.cross_metrics.workflows:
    content = Read(wf.path)
    nodes = extract_yaml_section(content, "nodes")
    endings = extract_yaml_section(content, "endings")

    # Count edges
    edges = 0
    FOR node_id, node IN nodes:
      SWITCH node.type:
        CASE "action":
          edges += 1  # on_success
          IF node.on_failure is defined:
            edges += 1
        CASE "conditional":
          edges += 2  # on_true + on_false
        CASE "user_prompt":
          edges += len(node.on_response)
        CASE "reference":
          edges += 1

    nodes_count = count_keys(nodes) + count_keys(endings)
    cc = edges - nodes_count + 2  # M = E - N + 2P (P=1)
    wf.cyclomatic_complexity = cc
    complexities.append(cc)

  IF len(complexities) > 0:
    computed.cross_metrics.avg_complexity = round(sum(complexities) / len(complexities), 2)
    computed.cross_metrics.max_complexity = max(complexities)
    computed.cross_metrics.min_complexity = min(complexities)
  ELSE:
    computed.cross_metrics.avg_complexity = 0
    computed.cross_metrics.max_complexity = 0
    computed.cross_metrics.min_complexity = 0
```

### Step 2.3: Shared Pattern Detection

Find node structures that appear in multiple workflows. Build a signature for each node
based on its type, action count, and transition shape, then identify signatures that
recur across workflows.

```pseudocode
function detect_shared_patterns(workflows):
  patterns = {}
  FOR workflow IN workflows:
    content = Read(workflow.path)
    nodes = extract_yaml_section(content, "nodes")
    FOR node_id, node IN nodes:
      # Build a structural signature
      IF node.type == "action":
        transitions_shape = "s" + ("+f" if node.on_failure else "")
        signature = f"action:{len(node.actions)}:{transitions_shape}"
      ELIF node.type == "conditional":
        signature = f"conditional:{node.condition.type}:t+f"
      ELIF node.type == "user_prompt":
        option_count = len(node.on_response)
        signature = f"user_prompt:{option_count}"
      ELIF node.type == "reference":
        signature = f"reference:1"

      IF signature NOT IN patterns:
        patterns[signature] = []
      patterns[signature].append({
        workflow: workflow.name,
        node_id: node_id
      })

  shared = {k: v for k, v in patterns.items() if len(set(e.workflow for e in v)) > 1}
  computed.cross_metrics.shared_patterns = shared
  computed.cross_metrics.shared_pattern_count = len(shared)
  return shared
```

### Step 2.4: Duplicate/Similar Node Detection

Identify nodes across workflows with very similar structure (structural similarity >80%).
These are candidates for extraction into shared subflows.

> **Detail:** See `patterns/cross-skill-metrics.md` for the full similarity scoring
> algorithm, structural fingerprinting, and adjacency list construction.

```pseudocode
function detect_duplicates(workflows):
  all_nodes = []
  FOR workflow IN workflows:
    content = Read(workflow.path)
    nodes = extract_yaml_section(content, "nodes")
    FOR node_id, node IN nodes:
      fingerprint = {
        type:            node.type,
        action_count:    len(node.actions) if node.type == "action" else 0,
        action_types:    sorted([a.type for a in node.actions]) if node.type == "action" else [],
        condition_type:  node.condition.type if node.type == "conditional" else null,
        option_count:    len(node.on_response) if node.type == "user_prompt" else 0,
        has_failure:     hasattr(node, "on_failure") and node.on_failure is not null
      }
      all_nodes.append({
        workflow: workflow.name,
        node_id: node_id,
        fingerprint: fingerprint
      })

  # Compare all pairs across workflows
  duplicates = []
  FOR i IN range(len(all_nodes)):
    FOR j IN range(i + 1, len(all_nodes)):
      IF all_nodes[i].workflow == all_nodes[j].workflow:
        CONTINUE  # Only cross-workflow duplicates
      sim = compute_similarity(all_nodes[i].fingerprint, all_nodes[j].fingerprint)
      IF sim >= 0.80:
        duplicates.append({
          node_a: { workflow: all_nodes[i].workflow, node_id: all_nodes[i].node_id },
          node_b: { workflow: all_nodes[j].workflow, node_id: all_nodes[j].node_id },
          similarity: round(sim, 2)
        })

  computed.cross_metrics.duplicates = duplicates
  computed.cross_metrics.duplicate_count = len(duplicates)
```

Store all cross-skill metrics in `computed.cross_metrics`.

---

## Phase 3: Dependency Analysis

Map the relationships between skills, identifying subflow references, shared state,
and external library alignment.

### Step 3.1: Subflow/Reference Dependencies Between Skills

Scan all workflows for `reference` nodes that point to other skills or subflows:

```pseudocode
BUILD_DEPENDENCY_GRAPH():
  computed.dependencies.graph = {}  # adjacency list: skill_name -> [referenced skills]
  computed.dependencies.references = []

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)
    nodes = extract_yaml_section(content, "nodes")
    computed.dependencies.graph[skill.name] = []

    FOR node_id, node IN nodes:
      # Check reference nodes
      IF node.type == "reference":
        ref_target = node.doc if hasattr(node, "doc") else node.workflow
        computed.dependencies.references.append({
          source_skill: skill.name,
          source_node:  node_id,
          target:       ref_target,
          type:         "subflow_reference"
        })
        # Extract the skill name from the reference path
        target_skill = extract_skill_name_from_path(ref_target)
        IF target_skill:
          computed.dependencies.graph[skill.name].append(target_skill)

      # Check invoke_skill consequences in action nodes
      IF node.type == "action":
        FOR action IN node.actions:
          IF action.type == "invoke_skill":
            computed.dependencies.references.append({
              source_skill: skill.name,
              source_node:  node_id,
              target:       action.skill,
              type:         "invoke_skill"
            })
            computed.dependencies.graph[skill.name].append(action.skill)

  # Deduplicate edges
  FOR skill_name IN computed.dependencies.graph:
    computed.dependencies.graph[skill_name] = deduplicate(computed.dependencies.graph[skill_name])
```

### Step 3.2: Shared State Variables

Find state variable names that appear in multiple workflows, suggesting coupling or
shared concerns:

```pseudocode
SHARED_STATE_ANALYSIS():
  computed.dependencies.state_vars = {}  # var_name -> [workflow names]

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)

    # Extract all ${...} interpolation references
    refs = extract_all_matches(content, /\$\{([^}]+)\}/)

    # Extract all mutate_state/set_flag field names
    state_fields = extract_all_matches(content, /field:\s*["']?(\w[\w.]+)/)
    flag_fields = extract_all_matches(content, /flag:\s*["']?(\w[\w.]+)/)

    all_vars = deduplicate(refs + state_fields + flag_fields)

    FOR var IN all_vars:
      IF var NOT IN computed.dependencies.state_vars:
        computed.dependencies.state_vars[var] = []
      computed.dependencies.state_vars[var].append(skill.name)

  # Filter to shared variables (appearing in 2+ workflows)
  computed.dependencies.shared_state = {
    k: v for k, v in computed.dependencies.state_vars.items()
    if len(set(v)) > 1
  }
  computed.dependencies.shared_state_count = len(computed.dependencies.shared_state)
```

### Step 3.3: External Reference Alignment

Verify that all workflows reference the same version of `hiivmind-blueprint-lib` and
check alignment with the plugin-level `BLUEPRINT_LIB_VERSION.yaml`:

```pseudocode
LIB_VERSION_ALIGNMENT():
  # Read the plugin-level version reference
  version_file = Read("${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml")
  computed.dependencies.expected_lib_ref = extract_field(version_file, "lib_ref")
  computed.dependencies.expected_lib_version = extract_field(version_file, "lib_version")
  computed.dependencies.expected_schema_version = extract_field(version_file, "schema_version")

  computed.dependencies.version_mismatches = []

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)
    definitions_source = extract_yaml_field(content, "definitions.source")

    IF definitions_source is not null:
      IF definitions_source != computed.dependencies.expected_lib_ref:
        computed.dependencies.version_mismatches.append({
          skill:    skill.name,
          expected: computed.dependencies.expected_lib_ref,
          actual:   definitions_source,
          path:     skill.workflow_path
        })
```

Store the complete dependency analysis in `computed.dependencies`.

---

## Phase 4: Intent Coverage

Analyze gateway routing to determine whether all skills are reachable through the
gateway command and whether there are keyword conflicts between skills.

### Step 4.1: Check Gateway Routing Coverage

Locate the gateway command and its intent-mapping configuration:

```pseudocode
CHECK_GATEWAY():
  # Look for gateway command files
  gateway_candidates = Glob("${CLAUDE_PLUGIN_ROOT}/commands/*/intent-mapping.yaml")
  gateway_commands = Glob("${CLAUDE_PLUGIN_ROOT}/commands/*/*.md")

  IF len(gateway_candidates) == 0:
    computed.intent_coverage = {
      gateway_found: false,
      message: "No gateway intent-mapping.yaml found. Skipping intent coverage analysis."
    }
    RETURN  # Skip Phase 4 entirely

  computed.intent_coverage.gateway_found = true
  computed.intent_coverage.gateway_path = gateway_candidates[0]

  # Read the intent mapping
  intent_content = Read(gateway_candidates[0])
  computed.intent_coverage.routes = extract_all_routes(intent_content)

  # Extract all routed skill names from the intent mapping
  routed_skills = set()
  FOR route IN computed.intent_coverage.routes:
    routed_skills.add(route.target_skill)

  computed.intent_coverage.routed_skills = list(routed_skills)
```

### Step 4.2: Keyword Overlap Between Skills

Analyze the trigger keywords in each skill's frontmatter description to detect
overlapping vocabulary that could cause routing confusion:

```pseudocode
KEYWORD_OVERLAP():
  computed.intent_coverage.keyword_map = {}  # keyword -> [skill names]

  FOR skill IN computed.inventory:
    content = Read(skill.path)
    description = extract_frontmatter_field(content, "description")

    # Extract trigger keywords (quoted phrases and standalone trigger words)
    keywords = extract_all_matches(description, /"([^"]+)"/)
    keywords += extract_all_matches(description, /Triggers on (.+)\.?$/)

    FOR keyword IN keywords:
      normalized = keyword.lower().strip()
      IF normalized NOT IN computed.intent_coverage.keyword_map:
        computed.intent_coverage.keyword_map[normalized] = []
      computed.intent_coverage.keyword_map[normalized].append(skill.name)

  # Find overlapping keywords (appear in 2+ skills)
  computed.intent_coverage.keyword_overlaps = {
    k: v for k, v in computed.intent_coverage.keyword_map.items()
    if len(set(v)) > 1
  }
  computed.intent_coverage.overlap_count = len(computed.intent_coverage.keyword_overlaps)
```

### Step 4.3: Unrouted Skills

Identify skills that are not reachable through the gateway:

```pseudocode
UNROUTED_SKILLS():
  IF NOT computed.intent_coverage.gateway_found:
    RETURN

  all_skill_names = set(s.name for s in computed.inventory)
  routed = set(computed.intent_coverage.routed_skills)

  computed.intent_coverage.unrouted = list(all_skill_names - routed)
  computed.intent_coverage.unrouted_count = len(computed.intent_coverage.unrouted)

  IF computed.intent_coverage.unrouted_count > 0:
    computed.intent_coverage.unrouted_warning = (
      f"{computed.intent_coverage.unrouted_count} skill(s) are not reachable "
      f"through the gateway: {', '.join(computed.intent_coverage.unrouted)}"
    )
```

Skip this entire phase if no gateway was found in Step 4.1.

---

## Phase 5: Version Consistency

Audit all workflows for consistent use of library versions, schema versions, and
detection of deprecated patterns.

### Step 5.1: All Workflows Reference Same Lib Version

Check `definitions.source` across every workflow.yaml file to ensure they all point
to the same `hiivmind-blueprint-lib` version:

```pseudocode
LIB_VERSION_CONSISTENCY():
  computed.version_consistency.lib_versions = {}  # version_string -> [skill names]

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)
    source = extract_yaml_field(content, "definitions.source")

    IF source is null:
      source = "none"

    IF source NOT IN computed.version_consistency.lib_versions:
      computed.version_consistency.lib_versions[source] = []
    computed.version_consistency.lib_versions[source].append(skill.name)

  version_count = len(computed.version_consistency.lib_versions)
  computed.version_consistency.lib_version_consistent = (version_count <= 1)

  IF version_count > 1:
    computed.version_consistency.lib_version_warning = (
      f"Found {version_count} different lib versions across workflows. "
      f"Expected all to reference {computed.dependencies.expected_lib_ref}."
    )
```

### Step 5.2: Deprecated Type Usage Across Plugin

Scan all workflows for deprecated v2.x consequence and precondition types:

```pseudocode
DEPRECATED_TYPE_SCAN():
  DEPRECATED_CONSEQUENCES = [
    "read_file", "write_file", "create_directory", "delete_file",
    "clone_repo", "git_pull", "git_fetch", "get_sha",
    "web_fetch", "cache_web_content",
    "run_script", "run_python", "run_bash",
    "set_state", "append_state", "clear_state", "merge_state",
    "log_event", "log_warning", "log_error",
    "display_message", "display_table"
  ]

  DEPRECATED_PRECONDITIONS = [
    "flag_set", "flag_not_set", "state_equals", "state_not_null", "state_is_null",
    "file_exists", "directory_exists", "config_exists", "index_exists",
    "tool_available", "tool_version_gte", "tool_authenticated", "tool_daemon_ready",
    "source_exists", "source_cloned", "source_has_updates",
    "log_initialized", "log_finalized", "log_level_enabled",
    "fetch_succeeded", "fetch_returned_content",
    "count_equals", "count_above", "count_below"
  ]

  computed.version_consistency.deprecated_usage = []

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)

    FOR dep_type IN DEPRECATED_CONSEQUENCES:
      IF Grep(content, f"type:\\s*{dep_type}"):
        computed.version_consistency.deprecated_usage.append({
          skill:     skill.name,
          type:      dep_type,
          category:  "consequence",
          path:      skill.workflow_path
        })

    FOR dep_type IN DEPRECATED_PRECONDITIONS:
      IF Grep(content, f"type:\\s*{dep_type}"):
        computed.version_consistency.deprecated_usage.append({
          skill:     skill.name,
          type:      dep_type,
          category:  "precondition",
          path:      skill.workflow_path
        })

  computed.version_consistency.deprecated_count = len(computed.version_consistency.deprecated_usage)
```

### Step 5.3: Schema Version Alignment

Verify all workflows use a consistent schema version and that it matches the
plugin-level expected version:

```pseudocode
SCHEMA_VERSION_CHECK():
  computed.version_consistency.schema_versions = {}  # version -> [skill names]

  workflow_skills = [s for s in computed.inventory if s.has_workflow]

  FOR skill IN workflow_skills:
    content = Read(skill.workflow_path)
    version_field = extract_yaml_field(content, "version")

    IF version_field is null:
      version_field = "unversioned"

    IF version_field NOT IN computed.version_consistency.schema_versions:
      computed.version_consistency.schema_versions[version_field] = []
    computed.version_consistency.schema_versions[version_field].append(skill.name)

  schema_count = len(computed.version_consistency.schema_versions)
  computed.version_consistency.schema_version_consistent = (schema_count <= 1)

  IF schema_count > 1:
    computed.version_consistency.schema_version_warning = (
      f"Found {schema_count} different schema versions. "
      f"Consider aligning all workflows to a single version."
    )
```

Store all version consistency results in `computed.version_consistency`.

---

## Phase 6: Health Dashboard

Compute an overall health score and per-category breakdown using a weighted combination
of all analysis dimensions.

### Step 6.1: Overall Score (0-100)

Calculate the overall plugin health score as a weighted combination of four category scores.

> **Detail:** See `patterns/health-scoring-algorithm.md` for the complete formula,
> category definitions, threshold calibration, and worked examples.

```pseudocode
COMPUTE_OVERALL_SCORE():
  # Weight allocation
  WEIGHTS = {
    completeness:    0.30,
    quality:         0.25,
    consistency:     0.25,
    maintainability: 0.20
  }

  # Completeness: % of skills with workflows, gateway coverage, error handling
  skills_with_workflows = computed.inventory_summary.workflow + computed.inventory_summary.hybrid
  total_skills = computed.inventory_summary.total
  workflow_pct = (skills_with_workflows / total_skills * 100) if total_skills > 0 else 0

  gateway_coverage_pct = 0
  IF computed.intent_coverage.gateway_found:
    routed = len(computed.intent_coverage.routed_skills)
    gateway_coverage_pct = (routed / total_skills * 100) if total_skills > 0 else 0

  computed.scores.completeness = round((workflow_pct * 0.6 + gateway_coverage_pct * 0.4))

  # Quality: avg description coverage, error handling, naming consistency
  quality_factors = []
  FOR wf IN computed.cross_metrics.workflows:
    content = Read(wf.path)
    nodes = extract_yaml_section(content, "nodes")
    nodes_with_desc = count(n for n in nodes if "description" in n)
    desc_pct = (nodes_with_desc / len(nodes) * 100) if len(nodes) > 0 else 100
    quality_factors.append(desc_pct)

  computed.scores.quality = round(average(quality_factors)) if len(quality_factors) > 0 else 50

  # Consistency: version alignment, type consistency, naming conventions
  consistency_deductions = 0
  IF NOT computed.version_consistency.lib_version_consistent:
    consistency_deductions += 25
  IF NOT computed.version_consistency.schema_version_consistent:
    consistency_deductions += 15
  IF computed.version_consistency.deprecated_count > 0:
    consistency_deductions += min(computed.version_consistency.deprecated_count * 5, 30)
  IF computed.intent_coverage.gateway_found AND computed.intent_coverage.overlap_count > 0:
    consistency_deductions += min(computed.intent_coverage.overlap_count * 5, 15)

  computed.scores.consistency = max(0, 100 - consistency_deductions)

  # Maintainability: avg complexity, subflow usage, documentation coverage
  IF computed.cross_metrics.avg_complexity > 0:
    # Lower complexity = higher score. CC of 1-3 = 100, 4-6 = 75, 7-10 = 50, 11+ = 25
    IF computed.cross_metrics.avg_complexity <= 3:
      complexity_score = 100
    ELIF computed.cross_metrics.avg_complexity <= 6:
      complexity_score = 75
    ELIF computed.cross_metrics.avg_complexity <= 10:
      complexity_score = 50
    ELSE:
      complexity_score = 25
  ELSE:
    complexity_score = 50  # No workflows to measure

  computed.scores.maintainability = complexity_score

  # Weighted overall
  computed.scores.overall = round(
    computed.scores.completeness * WEIGHTS.completeness
    + computed.scores.quality * WEIGHTS.quality
    + computed.scores.consistency * WEIGHTS.consistency
    + computed.scores.maintainability * WEIGHTS.maintainability
  )
```

### Step 6.2: Per-Category Scores

Store each category score with a descriptive label and contributing factors:

```pseudocode
CATEGORY_BREAKDOWN():
  computed.scores.categories = [
    {
      name: "Completeness",
      score: computed.scores.completeness,
      weight: 0.30,
      factors: [
        f"{skills_with_workflows}/{total_skills} skills have workflows",
        f"Gateway coverage: {gateway_coverage_pct}%"
      ]
    },
    {
      name: "Quality",
      score: computed.scores.quality,
      weight: 0.25,
      factors: [
        f"Average description coverage across workflows",
        f"{computed.cross_metrics.duplicate_count} duplicate nodes detected"
      ]
    },
    {
      name: "Consistency",
      score: computed.scores.consistency,
      weight: 0.25,
      factors: [
        f"Lib version consistent: {computed.version_consistency.lib_version_consistent}",
        f"Schema version consistent: {computed.version_consistency.schema_version_consistent}",
        f"{computed.version_consistency.deprecated_count} deprecated types found"
      ]
    },
    {
      name: "Maintainability",
      score: computed.scores.maintainability,
      weight: 0.20,
      factors: [
        f"Avg cyclomatic complexity: {computed.cross_metrics.avg_complexity}",
        f"Total nodes: {computed.cross_metrics.total_nodes}",
        f"Shared patterns: {computed.cross_metrics.shared_pattern_count}"
      ]
    }
  ]
```

### Step 6.3: Traffic Light Indicators

Assign a traffic light color to each category and the overall score:

```pseudocode
TRAFFIC_LIGHTS():
  function traffic_light(score):
    IF score >= 80:
      return "Green"
    ELIF score >= 50:
      return "Yellow"
    ELSE:
      return "Red"

  computed.scores.overall_light = traffic_light(computed.scores.overall)

  FOR category IN computed.scores.categories:
    category.light = traffic_light(category.score)
```

### Step 6.4: Trend Comparison

Check for a previous analysis report in the `.hiivmind/` directory. If one exists,
compare the current scores against the previous run to show improvement or regression:

```pseudocode
TREND_COMPARISON():
  previous_report_path = "${CLAUDE_PLUGIN_ROOT}/.hiivmind/plugin-analysis-history.yaml"

  IF file_exists(previous_report_path):
    previous = Read(previous_report_path)
    prev_overall = extract_field(previous, "overall_score")
    prev_timestamp = extract_field(previous, "timestamp")

    computed.scores.trend = {
      previous_score:    prev_overall,
      previous_timestamp: prev_timestamp,
      delta:             computed.scores.overall - prev_overall,
      direction:         "improved" if computed.scores.overall > prev_overall
                         else "regressed" if computed.scores.overall < prev_overall
                         else "unchanged"
    }
  ELSE:
    computed.scores.trend = {
      previous_score:    null,
      previous_timestamp: null,
      delta:             null,
      direction:         "first_run"
    }
```

Store all scoring data in `computed.scores`.

---

## Phase 7: Recommendations

Generate a priority-ranked list of improvements extracted from all analysis dimensions.

### Step 7.1: Priority-Ranked Improvements

Collect actionable recommendations from every analysis phase:

```pseudocode
GENERATE_RECOMMENDATIONS():
  computed.recommendations = []

  # From Phase 2: Cross-skill metrics
  IF computed.cross_metrics.duplicate_count > 0:
    computed.recommendations.append({
      priority: "medium",
      category: "maintainability",
      message: f"Extract {computed.cross_metrics.duplicate_count} duplicate node pattern(s) into shared subflows.",
      source: "cross-skill-metrics"
    })

  IF computed.cross_metrics.avg_complexity > 6:
    computed.recommendations.append({
      priority: "high",
      category: "maintainability",
      message: f"Average cyclomatic complexity is {computed.cross_metrics.avg_complexity}. Simplify complex workflows or decompose into subflows.",
      source: "cross-skill-metrics"
    })

  # From Phase 3: Dependencies
  IF len(computed.dependencies.version_mismatches) > 0:
    mismatched_skills = [m.skill for m in computed.dependencies.version_mismatches]
    computed.recommendations.append({
      priority: "high",
      category: "consistency",
      message: f"Update lib version in {', '.join(mismatched_skills)} to match {computed.dependencies.expected_lib_ref}.",
      source: "dependency-analysis"
    })

  IF computed.dependencies.shared_state_count > 5:
    computed.recommendations.append({
      priority: "medium",
      category: "maintainability",
      message: f"{computed.dependencies.shared_state_count} state variables are shared across workflows. Review for unnecessary coupling.",
      source: "dependency-analysis"
    })

  # From Phase 4: Intent coverage
  IF computed.intent_coverage.gateway_found:
    IF computed.intent_coverage.unrouted_count > 0:
      computed.recommendations.append({
        priority: "high",
        category: "completeness",
        message: f"Add gateway routes for {computed.intent_coverage.unrouted_count} unrouted skill(s): {', '.join(computed.intent_coverage.unrouted)}.",
        source: "intent-coverage"
      })

    IF computed.intent_coverage.overlap_count > 0:
      overlapping = list(computed.intent_coverage.keyword_overlaps.keys())[:5]
      computed.recommendations.append({
        priority: "medium",
        category: "consistency",
        message: f"Resolve keyword overlap for: {', '.join(overlapping)}. Overlapping triggers may cause routing ambiguity.",
        source: "intent-coverage"
      })
  ELSE:
    IF computed.inventory_summary.total > 2:
      computed.recommendations.append({
        priority: "medium",
        category: "completeness",
        message: "No gateway found. Create a gateway command to route users to the correct skill.",
        source: "intent-coverage"
      })

  # From Phase 5: Version consistency
  IF computed.version_consistency.deprecated_count > 0:
    computed.recommendations.append({
      priority: "high",
      category: "consistency",
      message: f"Upgrade {computed.version_consistency.deprecated_count} deprecated type usage(s) to v3.0.0 equivalents.",
      source: "version-consistency"
    })

  IF NOT computed.version_consistency.lib_version_consistent:
    computed.recommendations.append({
      priority: "high",
      category: "consistency",
      message: "Align all workflows to the same lib version defined in BLUEPRINT_LIB_VERSION.yaml.",
      source: "version-consistency"
    })

  # From Phase 1: Inventory
  IF computed.inventory_summary.prose > 0:
    computed.recommendations.append({
      priority: "low",
      category: "completeness",
      message: f"Convert {computed.inventory_summary.prose} prose-based skill(s) to workflow format.",
      source: "inventory"
    })

  IF computed.inventory_summary.hybrid > 0:
    computed.recommendations.append({
      priority: "medium",
      category: "quality",
      message: f"Review {computed.inventory_summary.hybrid} hybrid skill(s) and strip residual prose from converted workflows.",
      source: "inventory"
    })

  # Sort by priority
  priority_order = { "high": 0, "medium": 1, "low": 2 }
  computed.recommendations = sorted(computed.recommendations, key=lambda r: priority_order[r.priority])

  computed.recommendations_summary = {
    total:  len(computed.recommendations),
    high:   count(r for r in computed.recommendations if r.priority == "high"),
    medium: count(r for r in computed.recommendations if r.priority == "medium"),
    low:    count(r for r in computed.recommendations if r.priority == "low")
  }
```

Display the full health dashboard:

```
## Plugin Health Report: {computed.plugin_name}

**Plugin Root:** {computed.plugin_root}
**Total Skills:** {computed.inventory_summary.total}
**Overall Health:** {computed.scores.overall}/100 [{computed.scores.overall_light}]
{IF computed.scores.trend.direction != "first_run":}
**Trend:** {computed.scores.trend.direction} ({computed.scores.trend.delta:+d} from {computed.scores.trend.previous_score} on {computed.scores.trend.previous_timestamp})
{/IF}

---

### Inventory

| Classification | Count |
|----------------|-------|
| Workflow-based | {computed.inventory_summary.workflow} |
| Prose-based    | {computed.inventory_summary.prose} |
| Hybrid         | {computed.inventory_summary.hybrid} |
| Simple         | {computed.inventory_summary.simple} |
| **Total**      | **{computed.inventory_summary.total}** |

### Category Scores

| Category | Score | Light | Weight | Key Factors |
|----------|-------|-------|--------|-------------|
| Completeness | {computed.scores.completeness}/100 | {category.light} | 30% | {factors} |
| Quality | {computed.scores.quality}/100 | {category.light} | 25% | {factors} |
| Consistency | {computed.scores.consistency}/100 | {category.light} | 25% | {factors} |
| Maintainability | {computed.scores.maintainability}/100 | {category.light} | 20% | {factors} |
| **Overall** | **{computed.scores.overall}/100** | **{computed.scores.overall_light}** | | |

### Cross-Skill Metrics

| Metric | Value |
|--------|-------|
| Total nodes across all workflows | {computed.cross_metrics.total_nodes} |
| Total endings | {computed.cross_metrics.total_endings} |
| Total actions | {computed.cross_metrics.total_actions} |
| Average cyclomatic complexity | {computed.cross_metrics.avg_complexity} |
| Max cyclomatic complexity | {computed.cross_metrics.max_complexity} |
| Shared patterns | {computed.cross_metrics.shared_pattern_count} |
| Duplicate node pairs | {computed.cross_metrics.duplicate_count} |

### Per-Workflow Summary

| Workflow | Nodes | Endings | Actions | CC |
|----------|-------|---------|---------|-----|
{for wf in computed.cross_metrics.workflows:}
| {wf.name} | {wf.node_count} | {wf.ending_count} | {wf.action_count} | {wf.cyclomatic_complexity} |
{/for}

### Dependencies

| Relationship | Count | Details |
|-------------|-------|---------|
| Subflow references | {len(computed.dependencies.references)} | {cross-skill reference list} |
| Shared state variables | {computed.dependencies.shared_state_count} | {shared var names} |
| Lib version mismatches | {len(computed.dependencies.version_mismatches)} | {mismatched skills} |

{IF computed.intent_coverage.gateway_found:}
### Intent Coverage

| Metric | Value |
|--------|-------|
| Gateway | Found ({computed.intent_coverage.gateway_path}) |
| Routed skills | {len(computed.intent_coverage.routed_skills)} |
| Unrouted skills | {computed.intent_coverage.unrouted_count} |
| Keyword overlaps | {computed.intent_coverage.overlap_count} |

{IF computed.intent_coverage.unrouted_count > 0:}
**Unrouted skills:** {', '.join(computed.intent_coverage.unrouted)}
{/IF}
{ELSE:}
### Intent Coverage

No gateway command found. Intent coverage analysis skipped.
{/IF}

### Version Consistency

| Check | Status |
|-------|--------|
| Lib version aligned | {computed.version_consistency.lib_version_consistent} |
| Schema version aligned | {computed.version_consistency.schema_version_consistent} |
| Deprecated types | {computed.version_consistency.deprecated_count} found |

### Recommendations ({computed.recommendations_summary.total})

{computed.recommendations_summary.high} high, {computed.recommendations_summary.medium} medium, {computed.recommendations_summary.low} low

{for i, rec in enumerate(computed.recommendations):}
{i+1}. **[{rec.priority}]** [{rec.category}] {rec.message}
{/for}
```

### Step 7.2: Offer Next Actions

After presenting the report, ask what the user wants to do with the findings:

```json
{
  "questions": [{
    "question": "What would you like to do with these findings?",
    "header": "Action",
    "multiSelect": false,
    "options": [
      {
        "label": "Batch validate all",
        "description": "Run validation on every workflow in the plugin"
      },
      {
        "label": "Batch upgrade",
        "description": "Upgrade all workflows to latest schema and lib version"
      },
      {
        "label": "Fix top issue",
        "description": "Address the highest-priority recommendation"
      },
      {
        "label": "Export report",
        "description": "Save full analysis to file"
      }
    ]
  }]
}
```

**Response handling:**

```pseudocode
HANDLE_ACTION_RESPONSE(response):
  SWITCH response:
    CASE "Batch validate all":
      DISPLAY "To batch validate all workflows, invoke:"
      DISPLAY "  Skill(skill: 'bp-author-plugin-batch', args: 'validate')"
      DISPLAY "This will run schema, graph, type, and state validation on every workflow.yaml."

    CASE "Batch upgrade":
      DISPLAY "To batch upgrade all workflows, invoke:"
      DISPLAY "  Skill(skill: 'bp-author-skill-upgrade', args: 'batch')"
      DISPLAY "This will upgrade deprecated types and align lib versions across all workflows."

    CASE "Fix top issue":
      top_rec = computed.recommendations[0]
      DISPLAY "Top recommendation:"
      DISPLAY "  [{top_rec.priority}] [{top_rec.category}] {top_rec.message}"
      DISPLAY ""
      IF top_rec.category == "consistency" AND "lib version" in top_rec.message:
        DISPLAY "To fix, invoke:"
        DISPLAY "  Skill(skill: 'bp-author-skill-upgrade', args: '{affected_workflow_path}')"
      ELIF top_rec.category == "completeness" AND "gateway" in top_rec.message:
        DISPLAY "To fix, invoke:"
        DISPLAY "  Skill(skill: 'bp-author-gateway-create')"
      ELSE:
        DISPLAY "Review the recommendation above and apply the suggested fix manually,"
        DISPLAY "or invoke the appropriate skill for the affected workflow."

    CASE "Export report":
      report_path = "${CLAUDE_PLUGIN_ROOT}/.hiivmind/plugin-analysis-report.md"
      history_path = "${CLAUDE_PLUGIN_ROOT}/.hiivmind/plugin-analysis-history.yaml"
      DISPLAY "Analysis report saved to {report_path}."
      DISPLAY "Score history updated at {history_path}."
      DISPLAY "Run this analysis again to track improvement over time."
```

---

## State Flow

```
Phase 1              Phase 2                   Phase 3                Phase 4
───────────────────────────────────────────────────────────────────────────────
computed.inventory → computed.cross_metrics  → computed.dependencies → computed.intent_coverage
computed.inventory   computed.cross_metrics     computed.dependencies   computed.intent_coverage
  _summary             .workflows               .graph                  .gateway_found
                       .total_nodes             .references             .routed_skills
                       .avg_complexity          .shared_state           .keyword_overlaps
                       .shared_patterns         .version_mismatches     .unrouted
                       .duplicates

Phase 5                   Phase 6              Phase 7
───────────────────────────────────────────────────────────────────────────────
computed.version       → computed.scores     → computed.recommendations
  _consistency            .completeness         (sorted by priority)
  .lib_versions           .quality            computed.recommendations
  .deprecated_usage       .consistency          _summary
  .schema_versions        .maintainability
                          .overall
                          .trend
```

---

## Reference Documentation

- **Health Scoring Algorithm:** `patterns/health-scoring-algorithm.md` (local to this skill)
- **Cross-Skill Metrics:** `patterns/cross-skill-metrics.md` (local to this skill)
- **Classification Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/patterns/classification-algorithm.md`
- **Skill Analysis Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`
- **Node Mapping Pattern:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/node-mapping.md`
- **Workflow Template:** `${CLAUDE_PLUGIN_ROOT}/templates/workflow.yaml.template`
- **Blueprint Lib Version:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`

---

## Related Skills

- Plugin discovery: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-discover/SKILL.md`
- Plugin batch operations: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-plugin-batch/SKILL.md`
- Single workflow analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-analyze/SKILL.md`
- Prose skill analysis: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-prose-analyze/SKILL.md`
- Workflow validation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-validate/SKILL.md`
- Workflow upgrade: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-skill-upgrade/SKILL.md`
- Gateway creation: `${CLAUDE_PLUGIN_ROOT}/skills-prose/bp-author-gateway-create/SKILL.md`
