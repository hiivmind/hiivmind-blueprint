# Batch Execution Protocol

> **Used by:** `SKILL.md` Phase 4
> **Supplements:** `${CLAUDE_PLUGIN_ROOT}/lib/patterns/skill-analysis.md`

This document defines the progress tracking, error handling, partial result handling, retry
logic, and output aggregation conventions used during batch execution of operations across
multiple skills in a plugin.

---

## Progress Display Format

During batch execution, progress is displayed after each skill completes. The format ensures
the user always knows where they are in the batch and what happened so far.

### Per-Skill Progress Line

```
### [N/TOTAL] (XX%) Processing: skill-name
  Result: pass | Running: P passed, F failed, S skipped
```

Where:
- `N` is the current skill number (1-indexed)
- `TOTAL` is `computed.batch.total`
- `XX%` is `((N-1) / TOTAL) * 100`, rounded to the nearest integer
- `skill-name` is `computed.filtered_skills[N-1].name`
- `pass`/`fail`/`skip`/`error` is the outcome of the current skill
- `P`, `F`, `S` are the running cumulative counts

### Update Frequency

Progress is displayed once per skill, immediately after the operation completes for that
skill. There is no sub-operation progress (e.g., no per-validation-dimension progress
within a validate run). This keeps the output concise and avoids overwhelming the user
with detail during batch mode.

### Batch Header

Before the loop begins, display a header confirming the batch parameters:

```
## Executing Batch: {computed.selected_operation}

**Skills:** {computed.batch.total}
**Error mode:** {computed.error_mode}

---
```

---

## Error Accumulation Strategy

### Continue Mode (`computed.error_mode == "continue"`)

When error mode is "continue", failed skills are recorded but execution proceeds to the
next skill. All errors are accumulated in `computed.batch.results[]` and reported in
Phase 5.

```pseudocode
ON_ERROR(skill, error):
  computed.batch.results.append({
    skill: skill.name,
    status: "error",
    details: str(error)
  })
  computed.batch.failed += 1
  computed.batch.completed += 1
  # Continue to next skill -- do NOT break
```

### Stop Mode (`computed.error_mode == "stop_on_first"`)

When error mode is "stop on first", the loop breaks immediately on the first failure
or error. Remaining skills are not processed.

```pseudocode
ON_ERROR(skill, error):
  computed.batch.results.append({
    skill: skill.name,
    status: "error",
    details: str(error)
  })
  computed.batch.failed += 1
  computed.batch.completed += 1
  BREAK  # Exit the batch loop
```

Remaining (unprocessed) skills are NOT added to results. The Phase 5 report should note
how many skills were not reached:

```pseudocode
not_reached = computed.batch.total - computed.batch.completed
IF not_reached > 0:
  DISPLAY "**Note:** {not_reached} skill(s) were not processed due to early termination."
```

### Error Categorization

Errors fall into two categories:

| Category | Examples | Status |
|----------|----------|--------|
| **Operation failure** | Validation found errors, upgrade failed verification, migration produced invalid output | `fail` |
| **Unexpected error** | File not found, permission denied, malformed YAML that cannot be parsed, Read tool error | `error` |

The distinction matters for retry logic: `fail` results are deterministic (re-running will
produce the same result unless the underlying file changes), while `error` results may be
transient and worth retrying.

---

## Partial Result Handling

If a batch is interrupted (e.g., user cancels, stop-on-first triggers, or an unrecoverable
error occurs), the results collected so far are preserved in `computed.batch.results[]`.

### What Is Preserved

- All results for skills that completed (pass, fail, error, skip)
- The cumulative counters (passed, failed, skipped, completed)
- The original `computed.filtered_skills` list (so unprocessed skills can be identified)

### What Happens Next

When a batch is interrupted:

1. Display the partial results using the same Phase 5 report format
2. Compute the list of unprocessed skills:
   ```pseudocode
   processed_names = [r.skill for r in computed.batch.results]
   unprocessed = [s for s in computed.filtered_skills if s.name not in processed_names]
   ```
3. Offer to resume:
   - **Resume**: Set `computed.filtered_skills = unprocessed` and restart Phase 4
   - **Report partial**: Show the Phase 5 report with what was completed
   - **Abort**: Discard results and exit

---

## Retry Logic

Retry is offered as a post-batch action (Phase 5, Step 5.4 "Re-run failed"), not as an
inline retry during execution. This keeps the batch loop simple and deterministic.

### Retry Scope

When the user selects "Re-run failed":

```pseudocode
RETRY_BATCH():
  # Collect names of failed/errored skills
  retry_names = [r.skill for r in computed.batch.results if r.status in ("fail", "error")]

  # Rebuild the filtered list from the original inventory
  computed.filtered_skills = [
    s for s in computed.inventory
    if s.name in retry_names
  ]

  # Reset counters but preserve previous results for comparison
  computed.batch.previous_results = computed.batch.results
  computed.batch.total = len(computed.filtered_skills)
  computed.batch.completed = 0
  computed.batch.passed = 0
  computed.batch.failed = 0
  computed.batch.skipped = 0
  computed.batch.results = []

  # Re-execute the batch loop
  GOTO Phase 4, Step 4.2
```

### Retry Reporting

After a retry run, the Phase 5 report should show improvement:

```pseudocode
DISPLAY_RETRY_COMPARISON():
  prev_failed = len([r for r in computed.batch.previous_results if r.status in ("fail", "error")])
  curr_failed = computed.batch.failed

  DISPLAY "### Retry Results"
  DISPLAY "**Previously failed:** {prev_failed}"
  DISPLAY "**Still failing:** {curr_failed}"
  DISPLAY "**Resolved:** {prev_failed - curr_failed}"
```

---

## Output Aggregation Format

### Results Array Structure

Each entry in `computed.batch.results[]` follows this schema:

```yaml
- skill: "skill-name"           # String: name of the skill
  status: "pass|fail|skip|error" # String: outcome category
  details: "summary text"       # String: human-readable one-line summary
  issues:                        # Array (optional): only present for fail/error
    - severity: "error|warning|info"
      dimension: "schema|graph|types|state"  # Only for validate
      message: "description of the issue"
```

### Aggregation Rules

When computing summary statistics, apply these rules:

- **Success rate denominator** excludes skipped skills: `passed / (total - skipped)`
- **If all skills were skipped** (e.g., wrong filter for the operation), success rate is "N/A"
- **Issue counts** are aggregated across all failed skills for the "Issues Requiring Attention" section
- **Duplicate issues** (same message across multiple skills) are grouped with a count suffix:
  `"Missing on_failure transition (3 skills)"`

### Report File Format

When exporting to a file (Step 5.4 "Export report"), the report is written as markdown with
the following structure:

```markdown
# Batch Report: {operation}

**Date:** {timestamp}
**Plugin:** {plugin_path}
**Operation:** {operation}
**Error mode:** {error_mode}

## Summary

| Metric | Count |
|--------|-------|
| Total | {total} |
| Passed | {passed} |
| Failed | {failed} |
| Skipped | {skipped} |
| Success Rate | {rate}% |

## Per-Skill Results

| # | Skill | Status | Details |
|---|-------|--------|---------|
{results table}

## Issues

{grouped issues with details}
```

---

## Related Documentation

- **SKILL.md:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/SKILL.md`
- **Classification Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-assess/patterns/classification-algorithm.md`
- **Schema Validation Rules:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/patterns/schema-validation-rules.md`
- **Graph Validation Algorithm:** `${CLAUDE_PLUGIN_ROOT}/skills/bp-maintain/patterns/graph-validation-algorithm.md`
