# Plan: Convert navigate SKILL.md to workflow.yaml

## Summary

Convert the Fly.io corpus navigate skill from prose-based SKILL.md to a deterministic workflow.yaml.

**Skill path:** `/home/nathanielramm/git/hiivmind/hiivmind-corpus-flyio/skills/navigate/SKILL.md`

---

## Phase 1: Analysis Results

### Frontmatter Extraction
- **name:** `hiivmind-corpus-flyio-navigate`
- **description:** Navigate Fly.io documentation corpus (triggers on flyio, deployment, hosting, edge, machines, flyctl, etc.)
- **allowed-tools:** Read, Grep, Glob, AskUserQuestion (implied by the skill content)

### Phases Detected (6 phases)

| # | Phase ID | Title | Lines | Complexity |
|---|----------|-------|-------|------------|
| 1 | auto_trigger | Auto-Trigger Behavior | 14-28 | Low - documentation only |
| 2 | index_search | Index Search | 49-113 | High - multi-step with conditionals |
| 3 | tiered_navigation | Tiered Index Navigation | 116-134 | Medium - conditional logic |
| 4 | path_parsing | Path Format | 139-145 | Low - simple parsing |
| 5 | source_access | Source Access | 149-212 | High - multi-branch routing |
| 6 | large_files | Large Structured Files | 216-232 | Medium - conditional logic |

### Conditionals Detected (8)

1. **Index search hit quality** (lines 80-88)
   - Keyword match → use path immediately
   - Direct description hit → use path
   - Related hit → go to clarification
   - No hit → go to clarification

2. **Clarification required** (lines 91-113)
   - Present options via AskUserQuestion
   - Routes to: clarify request, show available, identify gap

3. **Tiered index check** (lines 127-134)
   - If section links to sub-index → read sub-index
   - Else → use direct path

4. **Check for local clone** (lines 177-180)
   - If `.source/{id}/` exists → read locally
   - Else → fetch from GitHub

5. **Source type routing** (lines 189-212)
   - git → local or GitHub
   - generated-docs → WebFetch
   - local → direct read
   - web → cache or fetch

6. **File size check** (lines 229-232)
   - File > 1000 lines → use Grep
   - Else → use Read

### Actions Detected (12)

| Tool | Description | Phase |
|------|-------------|-------|
| Read | Read index.md | index_search |
| Grep | Search indexes for terms | index_search |
| Read | Read sub-index | tiered_navigation |
| Glob | Check for local clone | source_access |
| Read | Read from local clone | source_access |
| WebFetch | Fetch from GitHub raw | source_access |
| WebFetch | Fetch generated-docs | source_access |
| Read | Read local uploads | source_access |
| Read | Read web cache | source_access |
| WebFetch | Fetch web content | source_access |
| Grep | Search large files | large_files |
| AskUserQuestion | Clarify when no match | index_search |

### State Variables (8)

| Variable | Source | Defined In | Used In |
|----------|--------|------------|---------|
| user_question | input | start | index_search |
| search_terms | computed | index_search | index_search |
| index_content | file_read | index_search | tiered_navigation |
| matched_entry | computed | index_search | path_parsing, source_access |
| source_id | parsed | path_parsing | source_access |
| relative_path | parsed | path_parsing | source_access |
| config | file_read | source_access | source_access |
| doc_content | file_read/web_fetch | source_access | output |

### Complexity Assessment

| Factor | Value | Score |
|--------|-------|-------|
| Phase count | 6 | Medium (2) |
| Conditional count | 8 | High (3) |
| Branching depth | 3 levels | High (3) |
| Tool variety | 4 (Read, Grep, Glob, AskUserQuestion, WebFetch) | Medium (2) |
| User interactions | 1 | Low (1) |
| State variables | 8 | High (3) |

**Overall complexity:** Medium-High (2.3)

**Logging recommendation:** Skip (no audit/CI indicators in prose)

---

## Phase 2: Workflow Structure Design

### Start Node
`extract_search_terms` - Parse user question to extract key concepts

### Node Map (18 nodes)

```
extract_search_terms (action)
  ↓
search_indexes (action)
  ↓
check_search_hit (conditional)
  ├── true (clear match) → parse_matched_path
  └── false (no/unclear match) → check_related_hit
        ├── true (related) → ask_user_clarify
        └── false (nothing) → ask_user_clarify

ask_user_clarify (user_prompt)
  ├── clarify → extract_search_terms (loop)
  ├── show_available → show_available_sections
  └── identify_gap → report_index_gap

show_available_sections (action) → success_with_suggestions
report_index_gap (action) → success_gap_identified

parse_matched_path (action)
  ↓
read_config (action)
  ↓
check_grep_marker (conditional)
  ├── true → grep_large_file
  └── false → route_source_type

route_source_type (conditional: git)
  ├── true → check_local_clone
  └── false → check_generated_docs

check_generated_docs (conditional)
  ├── true → fetch_generated_docs
  └── false → check_local_source

check_local_source (conditional)
  ├── true → read_local_uploads
  └── false → check_web_source

check_web_source (conditional)
  ├── true → check_web_cache
  └── false → error_unknown_source

check_local_clone (conditional)
  ├── true → read_local_source
  └── false → fetch_github_raw

read_local_source (action) → present_answer
fetch_github_raw (action) → present_answer
fetch_generated_docs (action) → present_answer
read_local_uploads (action) → present_answer
check_web_cache (conditional)
  ├── true → read_web_cache
  └── false → fetch_web_content

read_web_cache (action) → present_answer
fetch_web_content (action) → present_answer
grep_large_file (action) → present_answer

present_answer (action) → success
```

### Endings (4)

1. **success** - Successfully answered with documentation
2. **success_with_suggestions** - Showed available sections
3. **success_gap_identified** - Reported index gap, suggested skills
4. **error_unknown_source** - Unknown source type

---

## Phase 3: Implementation Plan

### Step 1: Create workflow.yaml structure

```yaml
name: "hiivmind-corpus-flyio-navigate"
version: "1.0.0"
description: >
  Navigate Fly.io documentation corpus when questions involve
  Fly.io deployment, hosting, machines, apps, databases, networking,
  edge services, flyctl CLI, or the Fly.io platform.
  Triggers: flyio, fly.io, fly, deployment, hosting, edge, machines, flyctl.

entry_preconditions:
  - type: config_exists
    error_message: "No config.yaml found. This skill requires a corpus."

initial_state:
  phase: "search"
  user_question: null
  search_terms: []
  matched_entry: null
  source_id: null
  relative_path: null
  flags:
    has_match: false
    has_related: false
    is_large_file: false
    has_local_clone: false
    is_git_source: false
    is_generated_docs: false
    is_local_source: false
    is_web_source: false
  computed: {}

start_node: extract_search_terms
```

### Step 2: Implement core nodes

1. **extract_search_terms** - Parse question, extract keywords
2. **search_indexes** - Grep indexes for terms
3. **check_search_hit** - Evaluate match quality
4. **ask_user_clarify** - User prompt for clarification
5. **parse_matched_path** - Extract source_id:path
6. **read_config** - Load config.yaml
7. **route_source_type** - Branch by source type
8. **Source access nodes** - Git, generated-docs, local, web
9. **present_answer** - Format and display answer

### Step 3: Create thin SKILL.md loader

Replace prose SKILL.md with thin loader that reads workflow.yaml.

---

## Files to Create/Modify

| File | Action |
|------|--------|
| `skills/navigate/workflow.yaml` | **Create** - Full workflow definition |
| `skills/navigate/SKILL.md` | **Replace** - Thin loader pointing to workflow |

---

## Verification

1. **Structural validation:**
   - All node transitions exist
   - No orphan nodes
   - All paths reach endings

2. **Functional testing:**
   - Test with known Fly.io query (e.g., "how do I deploy an app?")
   - Verify index search finds correct entry
   - Verify source access retrieves correct file
   - Test clarification flow with ambiguous query

3. **Edge cases:**
   - Query with no matches
   - Query matching multiple entries
   - Large file handling (>1000 lines)
   - Missing local clone (fallback to GitHub)



## Post- Conversion
● The conversion is complete. Here's a summary of what was created:

  Files Created/Modified
  ┌───────────────────────────────┬──────────┬──────────────────────────────────────────────────────┐
  │             File              │  Action  │                     Description                      │
  ├───────────────────────────────┼──────────┼──────────────────────────────────────────────────────┤
  │ skills/navigate/workflow.yaml │ Created  │ Full workflow definition (25KB, 38 nodes, 7 endings) │
  ├───────────────────────────────┼──────────┼──────────────────────────────────────────────────────┤
  │ skills/navigate/SKILL.md      │ Replaced │ Thin loader pointing to workflow.yaml                │
  └───────────────────────────────┴──────────┴──────────────────────────────────────────────────────┘
  Workflow Structure

  Phases:
  1. Index Search - Extract terms, read indexes, search for matches
  2. Clarification - User prompts when no exact match found
  3. Path Extraction - Parse source_id:relative_path format
  4. Large File Check - Detect ⚡ GREP markers for grep-based search
  5. Source Access - Route by type (git, local, web, generated-docs)
  6. Present Answer - Display content with citations

  Endings:
  - success - Documentation retrieved successfully
  - success_with_suggestions - Available sections shown
  - success_gap_identified - Index gap reported with next steps
  - error_* - Various error conditions with recovery suggestions

  Verification

  Nodes: 38
  YAML: Valid
  Start: extract_search_terms
  End transitions: All point to valid endings

  The workflow handles all the logic from the original prose SKILL.md in a deterministic node-based structure, including:
  - Keyword vs direct vs related match prioritization
  - User clarification flow with rephrase/browse/gap-report options
  - Local clone detection with GitHub fallback
  - Large file grep support
  - Multi-source type routing (git, local, web, generated-docs)

✻ Crunched for 2m 55s
