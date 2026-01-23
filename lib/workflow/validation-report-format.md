# Validation Report Format

Output format specification for `hiivmind-blueprint-validate` reports.

---

## Design Principles

1. **Scannable** - Status icons (✓/⚠/✗) visible at a glance
2. **Hierarchical** - Summary first, details below
3. **Actionable** - Each error includes suggested fix
4. **Terminal-friendly** - Box drawing characters for structure

---

## Report Structure

```
══════════════════════════════════════
  Blueprint Workflow Validation Report
══════════════════════════════════════

{header section}

{summary section}

{errors section}

{warnings section}

{info section}

{footer}
```

---

## Header Section

```
Workflow: {workflow_name}
Version: {version}
Path: {workflow_path}
```

**Example:**

```
Workflow: add-source
Version: 1.0.0
Path: /home/user/plugin/skills/add-source/workflow.yaml
```

If intent-mapping.yaml is present:

```
Workflow: add-source
Version: 1.0.0
Path: /home/user/plugin/skills/add-source/workflow.yaml
Intent Mapping: intent-mapping.yaml (included in validation)
```

---

## Summary Section

```
Summary
───────
{status_icon} {category}: {passed}/{total} checks passed
{status_icon} {category}: {passed}/{total} checks passed ({warning_count} warning)
{status_icon} {category}: {passed}/{total} checks ({error_count} error)
...
```

**Status Icons:**

| Icon | Meaning | When Used |
|------|---------|-----------|
| `✓` | All passed | No errors or warnings in category |
| `⚠` | Warnings | No errors but has warnings |
| `✗` | Errors | Has one or more errors |
| `○` | Skipped | Category not run (mode selection) |

**Example Summary:**

```
Summary
───────
✓ Schema: 10/10 checks passed
⚠ Referential: 8/9 checks (1 warning)
✗ Graph: 6/8 checks (2 errors)
✓ Types: 15/15 checks passed
○ Intent: skipped (no intent-mapping.yaml)
```

---

## Errors Section

Only shown if errors exist.

```
Errors ({count})
────────────────
{for each error}
✗ [{category}] {check_name}: {node_id} (line {line})
  {description}
  Suggested fix: {fix}

{/for}
```

**Example:**

```
Errors (2)
──────────
✗ [Graph] Orphan node: legacy_handler (line 145)
  Node is not reachable from start_node
  Suggested fix: Remove node or add transition to it

✗ [Graph] Dead end: validate_input (line 52)
  Node has no outgoing transitions
  Suggested fix: Add on_success/on_failure or next_node
```

---

## Warnings Section

Only shown if warnings exist.

```
Warnings ({count})
──────────────────
{for each warning}
⚠ [{category}] {check_name}: {context} (line {line})
  {description}
  Suggested fix: {fix}

{/for}
```

**Example:**

```
Warnings (3)
────────────
⚠ [Referential] Reference doc may not exist: lib/patterns/old.md (line 89)
  File not found at expected path
  Suggested fix: Update doc path or create file

⚠ [User Prompt] Header exceeds 12 chars: ask_source_type (line 67)
  Header "Source Selection" is 16 characters
  Suggested fix: Shorten to 12 chars max (e.g., "Source")

⚠ [State] Unused initial_state field: legacy_mode (line 14)
  Field defined but never referenced
  Suggested fix: Remove from initial_state or add usage
```

---

## Info Section

Optional section for non-critical observations.

```
Info ({count})
──────────────
{for each info item}
ℹ [{category}] {observation}
  {details}

{/for}
```

**Example:**

```
Info (2)
────────
ℹ [Graph] Single-path workflow detected
  Only one path from start to success ending
  Consider: Adding alternative paths for error recovery

ℹ [State] 3 flags set but only 2 checked
  Flag 'debug_mode' is set but never evaluated
  Consider: Remove flag or add flag_set precondition
```

---

## Footer

```
─────────────────────────────
Passed Checks: {passed}/{total}
```

**With errors/warnings:**

```
─────────────────────────────
Passed Checks: 39/42
Errors: 2  Warnings: 1
```

**All passed:**

```
─────────────────────────────
Passed Checks: 42/42
✓ All validation checks passed
```

---

## Complete Example Report

### Report with Issues

```
══════════════════════════════════════
  Blueprint Workflow Validation Report
══════════════════════════════════════

Workflow: add-source
Version: 1.0.0
Path: /home/user/skills/add-source/workflow.yaml

Summary
───────
✓ Schema: 10/10 checks passed
⚠ Referential: 8/9 checks (1 warning)
✗ Graph: 6/8 checks (2 errors)
✓ Types: 15/15 checks passed
✓ State: 5/5 checks passed
⚠ User Prompt: 3/4 checks (1 warning)
✓ Endings: 4/4 checks passed
○ Intent: skipped (no intent-mapping.yaml)

Errors (2)
──────────
✗ [Graph] Orphan node: legacy_handler (line 145)
  Node is not reachable from start_node
  Suggested fix: Remove node or add transition to it

✗ [Graph] Dead end: validate_input (line 52)
  Node has no outgoing transitions
  Suggested fix: Add on_success/on_failure or next_node

Warnings (2)
────────────
⚠ [Referential] Reference doc may not exist: lib/patterns/old.md (line 89)
  File not found at expected path
  Suggested fix: Update doc path or create file

⚠ [User Prompt] Header exceeds 12 chars: ask_source_type (line 67)
  Header "Source Selection" is 16 characters
  Suggested fix: Shorten to 12 chars max (e.g., "Source")

─────────────────────────────
Passed Checks: 51/55
Errors: 2  Warnings: 2
```

### Clean Report

```
══════════════════════════════════════
  Blueprint Workflow Validation Report
══════════════════════════════════════

Workflow: hiivmind-blueprint-gateway
Version: 1.0.0
Path: /home/user/commands/hiivmind-blueprint/workflow.yaml
Intent Mapping: intent-mapping.yaml (included in validation)

Summary
───────
✓ Schema: 10/10 checks passed
✓ Referential: 9/9 checks passed
✓ Graph: 8/8 checks passed
✓ Types: 15/15 checks passed
✓ State: 5/5 checks passed
✓ User Prompt: 4/4 checks passed
✓ Endings: 4/4 checks passed
✓ Intent: 4/4 checks passed

─────────────────────────────
Passed Checks: 59/59
✓ All validation checks passed
```

---

## Category Descriptions

For display in report or help text:

| Category | Full Name | Description |
|----------|-----------|-------------|
| Schema | Schema Validation | Required fields, node types, structure |
| Referential | Referential Integrity | Node references, transitions, endings |
| Graph | Graph Analysis | Reachability, dead ends, cycles |
| Types | Type Validation | Precondition/consequence type validity |
| State | State Validation | Variable references, unused state |
| User Prompt | User Prompt Validation | Option handlers, header length, counts |
| Endings | Ending Validation | Success/error types, message variables |
| Intent | Intent Mapping | Flag/rule validation (3VL) |

---

## Severity Levels

| Severity | Icon | Meaning | Blocks Usage |
|----------|------|---------|--------------|
| Error | `✗` | Workflow will fail at runtime | Yes |
| Warning | `⚠` | Potential issue, may work | No |
| Info | `ℹ` | Observation, best practice | No |

---

## Line Number Attribution

When possible, include line numbers for issues:

```
✗ [Schema] Missing required field: on_failure (line 45)
```

If line number unavailable:

```
✗ [Schema] Missing required field: on_failure
  In node: process_input
```

---

## Suggested Fixes

Each issue should include an actionable fix:

| Issue Type | Fix Pattern |
|------------|-------------|
| Missing field | "Add {field} to {location}" |
| Invalid reference | "Change '{invalid}' to valid node/ending or add it" |
| Orphan node | "Remove node or add transition to it" |
| Dead end | "Add on_success/on_failure or next_node" |
| Invalid type | "Use known type from {reference}.md" |
| Header too long | "Shorten to 12 chars max (e.g., '{suggestion}')" |
| Missing handler | "Add handler for '{option_id}' in on_response" |

---

## ASCII Art Alternatives

For terminals without Unicode support:

| Unicode | ASCII |
|---------|-------|
| `═` | `=` |
| `─` | `-` |
| `✓` | `[OK]` |
| `⚠` | `[WARN]` |
| `✗` | `[ERR]` |
| `ℹ` | `[INFO]` |
| `○` | `[-]` |

**ASCII Example:**

```
======================================
  Blueprint Workflow Validation Report
======================================

Workflow: add-source
Version: 1.0.0
Path: /home/user/skills/add-source/workflow.yaml

Summary
-------
[OK] Schema: 10/10 checks passed
[WARN] Referential: 8/9 checks (1 warning)
[ERR] Graph: 6/8 checks (2 errors)
```

---

## JSON Output Format

For programmatic consumption:

```json
{
  "workflow": {
    "name": "add-source",
    "version": "1.0.0",
    "path": "/home/user/skills/add-source/workflow.yaml"
  },
  "summary": {
    "total_checks": 55,
    "passed": 51,
    "errors": 2,
    "warnings": 2,
    "info": 0
  },
  "categories": {
    "schema": {"passed": 10, "total": 10, "status": "passed"},
    "referential": {"passed": 8, "total": 9, "status": "warning"},
    "graph": {"passed": 6, "total": 8, "status": "error"}
  },
  "issues": [
    {
      "id": 19,
      "category": "graph",
      "severity": "error",
      "check": "orphan_node",
      "node": "legacy_handler",
      "line": 145,
      "message": "Node is not reachable from start_node",
      "fix": "Remove node or add transition to it"
    }
  ]
}
```

---

## Related Documentation

- **Validation Queries:** `lib/workflow/validation-queries.md`
- **Validate Skill:** `skills/hiivmind-blueprint-validate/SKILL.md`
- **Schema:** `lib/workflow/schema.md`
