# Logging Consequences

> **ARCHIVED:** This document is preserved for reference. The authoritative source is:
> - `lib/consequences/definitions/core/logging.yaml`

---

Core workflow execution logging for audit trails, debugging, and CI integration.

## Overview

| Consequence | Purpose |
|-------------|---------|
| `init_log` | Initialize log structure with workflow metadata and session context |
| `log_node` | Record node execution in history |
| `log_event` | Log structured domain-specific events |
| `log_warning` | Add warning message to log |
| `log_error` | Add error with context to log |
| `log_session_snapshot` | Record mid-session checkpoint with optional intermediate log |
| `finalize_log` | Complete log with timing and outcome |
| `write_log` | Write log to file in specified format |
| `apply_log_retention` | Clean up old log files per retention policy |
| `output_ci_summary` | Format output for CI environments |

**Total logging consequences:** 10

---

## Related Documentation

- **YAML Definition:** `lib/consequences/definitions/core/logging.yaml`
- **Configuration:** `lib/blueprint/patterns/logging-configuration.md` - Layered config
- **Schema:** `lib/workflow/logging-schema.md` - Log structure definition
- **Preconditions:** `lib/workflow/preconditions.md` - log_initialized, log_level_enabled
