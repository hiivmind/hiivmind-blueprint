> **Used by:** `SKILL.md` Phase 2, Step 2.1
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

# Phase Detection Algorithm

Complete catalog of phase boundary indicators with regex patterns, edge case handling, and merging rules.

---

## Indicator Catalog

### High-Confidence Indicators

These patterns reliably indicate intentional phase boundaries in prose SKILL.md files.

| Indicator | Regex Pattern | Example |
|-----------|--------------|---------|
| Phase heading | `^##\s+Phase\s+\d+[:\s-]` | `## Phase 1: Initialize` |
| Step sub-heading | `^###\s+Step\s+\d+\.\d+[:\s-]` | `### Step 2.1: Validate Input` |
| Stage heading | `^##\s+Stage\s+\d+[:\s-]` | `## Stage 3: Generate Output` |
| Numbered heading with colon | `^#{2,3}\s+\d+[\.\)]\s*:?\s+\w` | `## 1: Setup Environment` |
| Explicit phase keyword | `^#{2,3}\s+(Phase|Stage|Step)\b` | `## Phase: Validation` |

When a high-confidence indicator is found, unconditionally create a new phase boundary at that line.

### Medium-Confidence Indicators

These patterns suggest phase boundaries but require contextual validation.

| Indicator | Regex Pattern | Context Required |
|-----------|--------------|------------------|
| Sequential numbered list | `^\d+\.\s+(First|Then|Next|After)` | Items must be 3+ lines apart |
| Temporal markers at line start | `^(First|Next|Then|Finally|After that),` | Must not be inside a list item |
| Bold-prefaced sequential items | `^\*\*(Step\s+\d+|Stage\s+[A-Z])\*\*:` | Must appear at paragraph start |
| Ordered transitions | `^(Before|After|Once)\s+.*:$` | Must precede a content block |

Validation rules for medium-confidence:
- Two or more medium-confidence indicators within 10 lines of each other should be treated as a single phase (the first indicator marks the boundary).
- A medium-confidence indicator immediately following a high-confidence indicator (within 3 lines) is a sub-step, not a separate phase.

### Low-Confidence Indicators

These patterns suggest structural separation but do not reliably indicate phase boundaries.

| Indicator | Regex Pattern | Context Required |
|-----------|--------------|------------------|
| Horizontal rule separator | `^---\s*$` | Must not be frontmatter delimiter |
| Major heading level change | `^##\s+` after `^##\s+` with gap | Content topics must differ |
| Large content gap | `^\s*$` repeated 5+ times | Must separate substantive content |
| Section without heading | Block of 10+ lines with no heading | Must contain action-like prose |

Low-confidence indicators are only used when no high or medium indicators exist in the document.

---

## Boundary Detection Algorithm

```
function detect_phases(content_lines):
  boundaries = []

  # Pass 1: Find all high-confidence boundaries
  for line_num, line in content_lines:
    if matches_high_confidence(line):
      boundaries.append({line: line_num, confidence: "high", title: extract_title(line)})

  # Pass 2: If no high-confidence found, scan for medium-confidence
  if len(boundaries) == 0:
    for line_num, line in content_lines:
      if matches_medium_confidence(line) and validate_context(line_num, content_lines):
        boundaries.append({line: line_num, confidence: "medium", title: extract_title(line)})

  # Pass 3: If still none, fall back to low-confidence
  if len(boundaries) == 0:
    for line_num, line in content_lines:
      if matches_low_confidence(line) and validate_low_context(line_num, content_lines):
        boundaries.append({line: line_num, confidence: "low", title: infer_title(line_num, content_lines)})

  # Pass 4: Merge adjacent low-confidence sections
  if all(b.confidence == "low" for b in boundaries):
    boundaries = merge_adjacent(boundaries, min_gap=10)

  # Build phase objects from boundaries
  phases = []
  for i, boundary in enumerate(boundaries):
    end = boundaries[i+1].line - 1 if i+1 < len(boundaries) else len(content_lines)
    phases.append({
      id: slugify(boundary.title),
      title: boundary.title,
      prose_location: f"lines {boundary.line}-{end}",
      confidence: boundary.confidence,
      content_lines: range(boundary.line, end + 1)
    })

  return phases
```

---

## Edge Cases

### No Phases Detected

When the document has no recognizable phase markers at any confidence level:
- Create a single phase spanning the entire body (after frontmatter)
- Set `confidence: "low"` and `title: "Main"` with `id: "main"`
- Add a note to `computed.analysis_warnings`: "No phase boundaries detected; treating entire skill body as single phase"

### Single Phase Detected

When exactly one phase boundary is found:
- The phase spans from the boundary to the end of the document
- Content before the boundary (after frontmatter) is treated as preamble and not assigned to a phase
- Record preamble line range in `computed.analysis_warnings` if it contains action-like content

### Nested Phases (Sub-Steps)

When `### Step N.N:` headings appear within a `## Phase N:` section:
- The parent phase contains the child steps
- Child steps are recorded as entries within the parent phase's `content_lines`, not as separate top-level phases
- For analysis purposes, count sub-steps separately from phases:
  ```yaml
  computed.phases:
    - id: "phase_1_validate"
      title: "Phase 1: Validate"
      prose_location: "lines 20-80"
      confidence: "high"
      sub_steps:
        - id: "step_1_1_read_config"
          title: "Step 1.1: Read Config"
          prose_location: "lines 22-40"
        - id: "step_1_2_check_format"
          title: "Step 1.2: Check Format"
          prose_location: "lines 42-80"
  ```

---

## Merging Rules

### Adjacent Low-Confidence Merge

When two low-confidence boundaries are separated by fewer than `min_gap` (default: 10) lines:
1. Merge into a single phase using the first boundary's line number
2. Title becomes the first boundary's inferred title
3. Content lines span both sections

### Topic-Based Merge

When a medium-confidence boundary's content appears topically related to the preceding section (shared keywords in first 3 lines):
1. Do not create a new phase
2. Extend the preceding phase's content lines to include this section
3. Record the merge in `computed.analysis_warnings`

---

## Examples

**High-confidence detection:**
```markdown
## Phase 1: Setup
Install required tools and validate environment.

## Phase 2: Process
Read input files and transform data.
```
Result: 2 phases, both `confidence: "high"`.

**Medium-confidence detection:**
```markdown
**Step 1:** First, read the configuration file and validate its structure.

**Step 2:** Next, transform the data according to the rules defined in config.

**Step 3:** Finally, write the output and report results.
```
Result: 3 phases, all `confidence: "medium"`.

**Low-confidence fallback:**
```markdown
Read the input file and check its format.

---

Transform each record according to the mapping table.

---

Write the results to the output directory.
```
Result: 3 phases, all `confidence: "low"`, separated by horizontal rules.
