# Skills-Prose Verification Checklist

Automated and manual checks for validating prose-based meta-skills in `skills-prose/`. These checks ensure structural consistency, prevent dogfooding (workflow execution patterns leaking into prose skills), and enforce the handoff contracts between skills.

Run from the `skills-prose/` directory.

---

## Quick Run (All Automated Checks)

```bash
# From skills-prose/ directory
checks_passed=0; checks_total=11
for check in 1 2 3 4 5 6 7 8 9 10 11; do
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

## Check 7: No workflow.yaml (No Dogfooding)

Zero `workflow.yaml` files must exist anywhere in `skills-prose/`.

**Why:** Prose skills are procedural guides for Claude, not workflow-engine-executed skills. The presence of a workflow.yaml indicates the skill was incorrectly structured as a dogfooded workflow skill.

**Automated:**
```bash
count=$(find . -name "workflow.yaml" -type f | wc -l)
if [ "$count" -eq 0 ]; then
  echo "PASS: 0 workflow.yaml files"
else
  echo "FAIL: $count workflow.yaml files found"
  find . -name "workflow.yaml" -type f
fi
```

---

## Check 8: No Dogfooding Sections

No SKILL.md may contain `## Execution Protocol` or `## Initial State Schema` as section headings.

**Why:** These sections belong to workflow-executed skills (produced by `templates/SKILL.md.template`), not prose meta-skills. Their presence indicates the skill was incorrectly modeled after the thin-loader template.

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

## Check 11: Handoff Documentation (prose-analyze <-> prose-migrate)

`bp-prose-analyze` and `bp-prose-migrate` must reference each other, documenting the `computed.analysis` handoff contract.

**Why:** These two skills form a pipeline. The analysis output schema must be documented in both directions so either skill can be updated independently without breaking the contract.

**Automated:**
```bash
pa=$(grep -c "prose-migrate" bp-prose-analyze/SKILL.md 2>/dev/null || echo 0)
pm=$(grep -c "prose-analyze" bp-prose-migrate/SKILL.md 2>/dev/null || echo 0)
echo "prose-analyze references prose-migrate: $pa times"
echo "prose-migrate references prose-analyze: $pm times"
if [ "$pa" -ge 1 ] && [ "$pm" -ge 1 ]; then
  echo "PASS"
else
  echo "FAIL"
fi
```

**Deeper validation (manual):** Check that `bp-prose-analyze/patterns/analysis-output-schema.md` defines the exact fields that `bp-prose-migrate` Phase 1 expects.

---

## Check 12: End-to-End Quality Read (Manual)

Read 3 representative skills end-to-end and verify prose quality matches `skills_old/` exemplars.

**Recommended skills:**
1. `bp-prose-analyze` — the core analysis skill, should match `skills_old/hiivmind-blueprint-author-analyze/SKILL.md` quality
2. `bp-gateway-create` — the most complex gateway skill, should match `skills_old/hiivmind-blueprint-author-gateway/SKILL.md` quality
3. `bp-plugin-discover` — the discovery skill, should match `skills_old/hiivmind-blueprint-author-discover/SKILL.md` quality

**Quality criteria:**
- Phases flow logically (gathering → analysis → execution → reporting)
- Pseudocode is clear and implementable
- AskUserQuestion prompts have sensible options with descriptions
- `computed.*` state flows forward correctly between phases
- Pattern file references add value (heavy material offloaded from SKILL.md)
- Related Skills section cross-references are accurate
- No orphan concepts (everything referenced is defined somewhere)

---

## Adding New Checks

To add a new verification check:

1. **Define the invariant** — what must always be true for valid prose skills
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
