# Skills Verification Checklist

Automated and manual checks for validating skills in `skills/`. These checks ensure structural consistency, verify frontmatter completeness, validate workflow references, and enforce the handoff contracts between skills.

Run from the `skills/` directory.

---

## Quick Run (All Automated Checks)

```bash
# From skills/ directory
checks_passed=0; checks_total=16
for check in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
  # (see individual check scripts below)
done
echo "$checks_passed/$checks_total automated checks passed"
```

---

## Check 1: Valid YAML Frontmatter

Every SKILL.md must have `name`, `description`, and `allowed-tools` in its YAML frontmatter.

**Why:** Frontmatter is parsed by the plugin system for skill registration and routing. Missing fields cause silent failures.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  has_name=$(head -20 "$f" | grep -c "^name:")
  has_desc=$(head -20 "$f" | grep -c "^description:")
  has_tools=$(head -20 "$f" | grep -c "^allowed-tools:")
  if [ "$has_name" -gt 0 ] && [ "$has_desc" -gt 0 ] && [ "$has_tools" -gt 0 ]; then
    echo "PASS: $skill"
  else
    echo "FAIL: $skill (name:$has_name desc:$has_desc tools:$has_tools)"
  fi
done
```

**Common fixes:**
- Missing `allowed-tools` — add the tools the skill needs (Read, Write, Glob, Grep, AskUserQuestion, etc.)
- Description too short — should include trigger keywords for intent matching

---

## Check 2: Phase Structure (>=4 phases with numbered steps)

Every SKILL.md must have at least 4 `## Phase N:` sections with `### Step N.M:` sub-sections.

**Why:** The phased procedure structure is the core architectural pattern. Skills with fewer than 4 phases are likely too thin or missing important stages (gathering, analysis, execution, reporting).

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  phases=$(grep -c "^## Phase" "$f")
  steps=$(grep -c "^### Step" "$f")
  if [ "$phases" -ge 4 ]; then
    echo "PASS: $skill (phases:$phases steps:$steps)"
  else
    echo "FAIL: $skill (phases:$phases steps:$steps)"
  fi
done
```

**Expected range:** 4-7 phases, 7-22 steps per skill.

---

## Check 3: AskUserQuestion JSON Examples

Every SKILL.md must contain at least one full AskUserQuestion JSON example using the `"questions"` key, with response handling.

**Why:** Prose skills guide Claude through interactive procedures. The JSON examples must use the exact AskUserQuestion tool schema so Claude produces valid tool calls.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  auq=$(grep -c "AskUserQuestion" "$f")
  json=$(grep -c '"questions"' "$f")
  if [ "$auq" -ge 1 ] && [ "$json" -ge 1 ]; then
    echo "PASS: $skill (mentions:$auq json_examples:$json)"
  else
    echo "FAIL: $skill (mentions:$auq json_examples:$json)"
  fi
done
```

**Required format:**
```json
{
  "questions": [{
    "question": "What would you like to do?",
    "header": "Action",
    "options": [
      {"label": "Option A", "description": "Does X"},
      {"label": "Option B", "description": "Does Y"}
    ],
    "multiSelect": false
  }]
}
```

**Common failure:** Skills reference AskUserQuestion in prose but use informal descriptions instead of JSON examples. Fix by expanding at least one user prompt into the full JSON structure with a response-handling pseudocode block.

---

## Check 4: Pseudocode Blocks

Every SKILL.md must contain at least one ` ```pseudocode ` code block.

**Why:** Algorithmic logic must use the `pseudocode` language tag, not `python`, `yaml`, or bare fences. This signals to Claude that the block is procedural guidance, not executable code or data structure.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  pseudo=$(grep -c '```pseudocode' "$f")
  if [ "$pseudo" -ge 1 ]; then
    echo "PASS: $skill (pseudocode_blocks:$pseudo)"
  else
    echo "FAIL: $skill (pseudocode_blocks:0)"
  fi
done
```

**What should be `pseudocode`:**
- IF/ELSE conditionals
- FOR/WHILE loops
- Function definitions (FUNCTION_NAME():)
- Variable assignments with logic
- Algorithm procedures

**What should NOT be `pseudocode`:**
- JSON data structures (use `json`)
- YAML examples (use `yaml`)
- Mermaid diagrams (use `mermaid`)
- Shell commands (use `bash`)
- Markdown examples (use `markdown`)

---

## Check 5: State Management (computed.*)

Every SKILL.md must reference `computed.*` for inter-phase state management.

**Why:** `computed.*` is the namespace convention for data flowing between phases. Without it, skills can't carry analysis results forward to generation/reporting phases.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  computed=$(grep -c 'computed\.' "$f")
  if [ "$computed" -ge 1 ]; then
    echo "PASS: $skill (refs:$computed)"
  else
    echo "FAIL: $skill (refs:0)"
  fi
done
```

**Expected range:** 20-250 `computed.*` references per skill.

---

## Check 6: Pattern File References Resolve

Every `patterns/*.md` reference in a SKILL.md must resolve to an actual file in that skill's `patterns/` directory.

**Why:** Broken pattern references mean Claude will fail to find supplementary material during execution. This check excludes `${CLAUDE_PLUGIN_ROOT}/lib/patterns/` paths, which are shared library references (validated by checks 9-10).

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  ok=1
  for ref in $(grep -oE 'patterns/[a-z0-9_-]+\.md' "$f" | sort -u); do
    # Skip if line contains CLAUDE_PLUGIN_ROOT (shared lib pattern)
    line=$(grep -n "$ref" "$f" | grep -v 'CLAUDE_PLUGIN_ROOT' | head -1)
    if [ -n "$line" ] && [ ! -f "$skill/$ref" ]; then
      echo "FAIL: $skill/$ref not found"
      ok=0
    fi
  done
  [ "$ok" -eq 1 ] && echo "PASS: $skill"
done
```

**Common failure:** SKILL.md references a pattern file that was renamed or never created. Fix by creating the missing file or updating the reference.

---

## Check 7: Workflow Files in workflows/ Subdirectory

Workflow YAML files must reside in `workflows/` subdirectories within their skill directory, not as bare siblings of SKILL.md. A bare `workflow.yaml` next to SKILL.md indicates legacy layout.

**Why:** The new convention places workflow definitions in `skills/my-skill/workflows/*.yaml`. A bare `workflow.yaml` at the skill root is legacy layout that should be migrated.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  legacy=$([ -f "$skill/workflow.yaml" ] && echo 1 || echo 0)
  proper=$(find "$skill/workflows" -name "*.yaml" -type f 2>/dev/null | wc -l)
  if [ "$legacy" -eq 0 ]; then
    echo "PASS: $skill (workflows_dir:$proper)"
  else
    echo "WARN: $skill has legacy workflow.yaml at root (migrate to workflows/ subdirectory)"
  fi
done
```

**Migration:** Use `bp-maintain` to migrate from bare `workflow.yaml` to `workflows/workflow.yaml`.

---

## Check 8: No Dogfooding Sections

No SKILL.md may contain `## Execution Protocol` or `## Initial State Schema` as section headings.

**Why:** These sections indicate the skill was incorrectly modeled after an old thin-loader template. Skills are prose orchestrators; workflow execution details belong in `workflows/*.yaml` files.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  ep=$(grep -c "^## Execution Protocol" "$f")
  iss=$(grep -c "^## Initial State Schema" "$f")
  if [ "$ep" -eq 0 ] && [ "$iss" -eq 0 ]; then
    echo "PASS: $skill"
  else
    echo "FAIL: $skill (Execution Protocol:$ep Initial State Schema:$iss)"
  fi
done
```

**Known false positives:** Skills that *detect* these patterns in other files (e.g., `bp-plugin-discover` classifying skills) will contain the strings inside pseudocode or regex patterns — but not as `##` section headings. The `^##` anchor avoids this.

---

## Check 9: lib/patterns/ References Use CLAUDE_PLUGIN_ROOT

All references to `lib/patterns/` must use the `${CLAUDE_PLUGIN_ROOT}/lib/patterns/` prefix.

**Why:** Without the prefix, references resolve relative to the skill directory instead of the plugin root, breaking when skills are loaded from different contexts.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  bad=$(grep -n 'lib/patterns/' "$f" | grep -v 'CLAUDE_PLUGIN_ROOT')
  if [ -z "$bad" ]; then
    echo "PASS: $skill"
  else
    echo "FAIL: $skill"
    echo "$bad"
  fi
done
```

---

## Check 10: templates/ References Use CLAUDE_PLUGIN_ROOT

All references to `templates/` (the shared template directory) must use the `${CLAUDE_PLUGIN_ROOT}/templates/` prefix.

**Why:** Same as check 9 — templates must resolve from plugin root, not relative to the skill.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  # Match templates/ refs, exclude local patterns/ refs and comments
  bad=$(grep -n 'templates/' "$f" | grep -v 'CLAUDE_PLUGIN_ROOT' | grep -v 'patterns/' | grep -v '^#')
  if [ -z "$bad" ]; then
    echo "PASS: $skill"
  else
    echo "FAIL: $skill"
    echo "$bad"
  fi
done
```

**Note:** Local `patterns/` references (e.g., `patterns/classification-algorithm.md`) are intentionally relative — they live inside the skill directory. This check only validates `templates/` references, which point to shared templates at plugin root.

---

## Check 11: Handoff Documentation (journey skill cross-references)

Journey skills that form pipelines must reference each other, documenting handoff contracts (e.g., `computed.analysis` between assessment and extraction phases).

**Why:** Journey skills hand off structured state to downstream skills. The handoff schema must be documented in both directions so either skill can be updated independently without breaking the contract.

**Automated:**
```bash
# Example: bp-assess and bp-extract should cross-reference each other
ae=$(grep -c "bp-extract" bp-assess/SKILL.md 2>/dev/null || echo 0)
ea=$(grep -c "bp-assess" bp-extract/SKILL.md 2>/dev/null || echo 0)
echo "bp-assess references bp-extract: $ae times"
echo "bp-extract references bp-assess: $ea times"
if [ "$ae" -ge 1 ] && [ "$ea" -ge 1 ]; then
  echo "PASS"
else
  echo "FAIL"
fi
```

**Deeper validation (manual):** Check that handoff schemas (e.g., analysis output fields) are documented in both the producing and consuming skill.

---

## Check 12: Frontmatter Completeness (inputs/outputs)

SKILL.md frontmatter should define `inputs:` and `outputs:` arrays when the skill accepts parameters or produces structured results.

**Why:** Explicit inputs/outputs make skills composable and self-documenting. Missing declarations force callers to read the full SKILL.md to understand the interface.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  has_inputs=$(head -30 "$f" | grep -c "^inputs:")
  has_outputs=$(head -30 "$f" | grep -c "^outputs:")
  if [ "$has_inputs" -ge 1 ] && [ "$has_outputs" -ge 1 ]; then
    echo "PASS: $skill (inputs:yes outputs:yes)"
  elif [ "$has_inputs" -ge 1 ] || [ "$has_outputs" -ge 1 ]; then
    echo "WARN: $skill (inputs:$has_inputs outputs:$has_outputs) — partial declaration"
  else
    echo "INFO: $skill (no inputs/outputs declared)"
  fi
done
```

**Note:** Not all skills require explicit inputs/outputs (e.g., discovery skills that interactively gather context). This check reports INFO, not FAIL, for missing declarations.

---

## Check 13: Declared Workflows Exist on Disk

Any `workflows:` entries in SKILL.md frontmatter must have corresponding files on disk.

**Why:** A declared workflow that doesn't exist will cause execution failures when the skill tries to load it.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  # Extract workflows: entries from frontmatter
  workflows=$(sed -n '/^---$/,/^---$/p' "$f" | grep -oE 'workflows/[a-z0-9_-]+\.yaml')
  if [ -z "$workflows" ]; then
    continue  # No workflows declared
  fi
  ok=1
  for wf in $workflows; do
    if [ ! -f "$skill/$wf" ]; then
      echo "FAIL: $skill/$wf declared but not found"
      ok=0
    fi
  done
  [ "$ok" -eq 1 ] && echo "PASS: $skill (all declared workflows exist)"
done
```

---

## Check 14: End-to-End Quality Read (Manual)

Read 3 representative skills end-to-end and verify prose quality matches `skills_old/` exemplars.

**Recommended skills:**
1. `bp-assess` — the core assessment/analysis journey skill
2. `bp-build` — the build journey skill
3. `bp-gateway` — the gateway/routing skill

**Quality criteria:**
- Phases flow logically (gathering → analysis → execution → reporting)
- Pseudocode is clear and implementable
- AskUserQuestion prompts have sensible options with descriptions
- `computed.*` state flows forward correctly between phases
- Pattern file references add value (heavy material offloaded from SKILL.md)
- Related Skills section cross-references are accurate
- No orphan concepts (everything referenced is defined somewhere)

---

## Check 15: Mode Detection Phase

Every journey skill should have a Phase 1: Mode Detection that parses invocation flags (except `bp-visualize`, which may handle this differently). Mode flags should be stored in `computed.mode.*` or `computed.mode`.

**Why:** Journey skills support multiple modes of operation (e.g., `--full`, `--quick`, `--interactive`). A dedicated mode detection phase at the start ensures consistent flag parsing and prevents mode logic from being scattered across later phases.

**Automated:**
```bash
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  # Skip bp-visualize (handles mode differently) and _archived skills
  [[ "$skill" == "bp-visualize" || "$skill" == _archived* ]] && continue
  mode_phase=$(grep -ci 'mode detection\|mode.*detection' "$f")
  mode_computed=$(grep -c 'computed\.mode' "$f")
  if [ "$mode_phase" -ge 1 ] && [ "$mode_computed" -ge 1 ]; then
    echo "PASS: $skill (mode_phase:$mode_phase mode_state:$mode_computed)"
  else
    echo "FAIL: $skill (mode_phase:$mode_phase mode_state:$mode_computed)"
  fi
done
```

**Common fixes:**
- Add a `## Phase 1: Mode Detection` section that parses invocation flags
- Store parsed mode in `computed.mode` or `computed.mode.*` namespace

---

## Check 16: Journey Handoffs

Related Skills and Next Actions sections should reference journey skill names (`bp-build`, `bp-assess`, `bp-enhance`, `bp-extract`, `bp-maintain`, `bp-visualize`, `bp-gateway`) and NOT reference archived skill names.

**Why:** Journey skills replace the old fine-grained skills. Handoff documentation must point users to the correct active skills, not archived ones that are no longer invocable.

**Automated:**
```bash
journey_skills="bp-build|bp-assess|bp-enhance|bp-extract|bp-maintain|bp-visualize|bp-gateway"
archived_skills="bp-skill-create|bp-skill-analyze|bp-skill-validate|bp-skill-refactor|bp-skill-upgrade|bp-workflow-extract|bp-plugin-discover|bp-plugin-analyze|bp-plugin-batch|bp-gateway-create|bp-gateway-validate|bp-intent-create|bp-intent-validate"
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  [[ "$skill" == _archived* ]] && continue
  journey_refs=$(grep -cE "($journey_skills)" "$f")
  archived_refs=$(grep -cE "($archived_skills)" "$f")
  if [ "$archived_refs" -eq 0 ]; then
    echo "PASS: $skill (journey_refs:$journey_refs archived_refs:0)"
  else
    echo "FAIL: $skill (journey_refs:$journey_refs archived_refs:$archived_refs)"
  fi
done
```

**Common fixes:**
- Replace references to archived skill names with their journey equivalents
- Update Related Skills / Next Actions sections to use journey skill names

---

## Check 17: No Archived Skill References

Active skills (not in `_archived/`) must not reference archived skill names as invocable skills. Archived names: `bp-skill-create`, `bp-skill-analyze`, `bp-skill-validate`, `bp-skill-refactor`, `bp-skill-upgrade`, `bp-workflow-extract`, `bp-plugin-discover`, `bp-plugin-analyze`, `bp-plugin-batch`, `bp-gateway-create`, `bp-gateway-validate`, `bp-intent-create`, `bp-intent-validate`.

**Why:** Referencing archived skills as invocable creates dead-end handoffs. Users following these references will get "skill not found" errors.

**Automated:**
```bash
archived="bp-skill-create bp-skill-analyze bp-skill-validate bp-skill-refactor bp-skill-upgrade bp-workflow-extract bp-plugin-discover bp-plugin-analyze bp-plugin-batch bp-gateway-create bp-gateway-validate bp-intent-create bp-intent-validate"
for dir in */; do
  skill="${dir%/}"; f="$skill/SKILL.md"
  [ -f "$f" ] || continue
  [[ "$skill" == _archived* ]] && continue
  ok=1
  for old in $archived; do
    hits=$(grep -c "$old" "$f")
    if [ "$hits" -gt 0 ]; then
      echo "FAIL: $skill references archived skill '$old' ($hits times)"
      ok=0
    fi
  done
  [ "$ok" -eq 1 ] && echo "PASS: $skill"
done
```

**Common fixes:**
- Replace `bp-skill-create` → `bp-build`
- Replace `bp-skill-analyze` → `bp-assess`
- Replace `bp-skill-validate` → `bp-assess`
- Replace `bp-skill-refactor` / `bp-skill-upgrade` → `bp-maintain`
- Replace `bp-workflow-extract` → `bp-extract`
- Replace `bp-plugin-discover` / `bp-plugin-analyze` / `bp-plugin-batch` → `bp-enhance`
- Replace `bp-gateway-create` / `bp-gateway-validate` → `bp-gateway`
- Replace `bp-intent-create` / `bp-intent-validate` → `bp-gateway`

---

## Adding New Checks

To add a new verification check:

1. **Define the invariant** — what must always be true for valid skills
2. **Write the shell script** — single-file iteration pattern:
   ```bash
   for dir in */; do
     skill="${dir%/}"; f="$skill/SKILL.md"
     [ -f "$f" ] || continue
     # ... your check logic ...
     echo "PASS: $skill" or echo "FAIL: $skill (reason)"
   done
   ```
3. **Document false positives** — skills that legitimately contain the flagged content
4. **Add to this file** with the check number, rationale, script, and common fixes

### Useful patterns for new checks

**Count occurrences of a pattern:**
```bash
count=$(grep -c 'PATTERN' "$f")
```

**Check section heading exists:**
```bash
has_section=$(grep -c '^## Section Name' "$f")
```

**Check pattern does NOT exist:**
```bash
bad=$(grep -n 'BAD_PATTERN' "$f")
[ -z "$bad" ] && echo "PASS" || echo "FAIL"
```

**Check file exists relative to skill:**
```bash
[ -f "$skill/path/to/file.md" ] && echo "PASS" || echo "FAIL"
```

**Cross-file reference check:**
```bash
# Ensure skill A references skill B and vice versa
a_refs_b=$(grep -c "skill-b" skill-a/SKILL.md)
b_refs_a=$(grep -c "skill-a" skill-b/SKILL.md)
```

---

## Run History

| Date | Result | Notes |
|------|--------|-------|
| 2026-02-06 | 11/11 automated PASS, 15 skills, 26 patterns, 41 .md total | Initial creation + fixes applied |
| 2026-02-24 | Updated for skill/workflow separation refactor | Checks 12-13 added, check 7 updated, skill renames applied |
| 2026-03-09 | Updated for journey-oriented redesign | Checks 15-17 added, checks 11/14 updated for journey skill names |
