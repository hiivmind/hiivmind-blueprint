# DEPRECATED: Logging Moved to Core

> **Logging consequences are now core.** See: [../core/logging.md](../core/logging.md)

---

## Migration

Logging was promoted from an extension to a core consequence in hiivmind-blueprint v1.1.0.

**Why?**
- Logging is fundamental to workflow execution and debugging
- All skills benefit from consistent logging infrastructure
- Validation checks can now enforce logging best practices

**What to do:**
- Update any references from `extensions/logging.md` to `core/logging.md`
- Run `hiivmind-blueprint-validate` to check for deprecated references
- Run `hiivmind-blueprint-upgrade` to automatically migrate workflows

---

## All Logging Consequences

The following consequences are now documented in [core/logging.md](../core/logging.md):

| Consequence | Purpose |
|-------------|---------|
| `init_log` | Initialize log structure |
| `log_node` | Record node execution |
| `log_event` | Log domain-specific event |
| `log_warning` | Add warning to log |
| `log_error` | Add error with context |
| `log_session_snapshot` | Record mid-session checkpoint |
| `finalize_log` | Complete log with timing |
| `write_log` | Write log to file |
| `apply_log_retention` | Clean up old log files |
| `output_ci_summary` | Format output for CI |

---

## Related Documentation

- **Core Logging:** [../core/logging.md](../core/logging.md)
- **Configuration:** `lib/blueprint/patterns/logging-configuration.md`
- **Schema:** `lib/workflow/logging-schema.md`
