# Validation Report Format

> **ARCHIVED:** This document is preserved for reference. This specification will be used by:
> - **format_validation_report** consequence type

---

Output format specification for `hiivmind-blueprint-validate` reports.

## Design Principles

1. **Scannable** - Status icons (checkmark/warning/error) visible at a glance
2. **Hierarchical** - Summary first, details below
3. **Actionable** - Each error includes suggested fix
4. **Terminal-friendly** - Box drawing characters for structure

---

## Status Icons

| Icon | Meaning | When Used |
|------|---------|-----------|
| checkmark | All passed | No errors or warnings in category |
| warning | Warnings | No errors but has warnings |
| error | Errors | Has one or more errors |
| circle | Skipped | Category not run (mode selection) |

---

## Severity Levels

| Severity | Icon | Meaning | Blocks Usage |
|----------|------|---------|--------------|
| Error | error | Workflow will fail at runtime | Yes |
| Warning | warning | Potential issue, may work | No |
| Info | info | Observation, best practice | No |

---

## Category Descriptions

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

## Related Documentation

- **Validation Queries:** `lib/workflow/legacy/validation-queries.md`
- **Validate Skill:** `skills/hiivmind-blueprint-validate/SKILL.md`
