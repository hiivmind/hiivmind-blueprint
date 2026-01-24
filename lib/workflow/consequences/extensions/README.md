# Extension Consequences

Domain-specific consequences that extend the core workflow operations. Extensions are designed to be replaceable and composable for different use cases.

---

## Overview

While [core consequences](../core/) provide fundamental workflow operations, extensions add domain-specific functionality:

| Extension | Purpose | Consequence Count |
|-----------|---------|-------------------|
| [file-system.md](file-system.md) | Generic file operations | 4 |
| [git.md](git.md) | Git repository operations | 4 |
| [web.md](web.md) | Web content operations | 2 |
| [logging.md](logging.md) | Workflow execution logging | 9 |

**Total extension consequences:** 19

---

## Quick Reference

| Consequence Type | File | Description |
|------------------|------|-------------|
| `read_file` | [file-system.md](file-system.md) | Read arbitrary file |
| `write_file` | [file-system.md](file-system.md) | Write content to file |
| `create_directory` | [file-system.md](file-system.md) | Create directory |
| `delete_file` | [file-system.md](file-system.md) | Delete file |
| `clone_repo` | [git.md](git.md) | Clone git repository |
| `get_sha` | [git.md](git.md) | Get HEAD commit SHA |
| `git_pull` | [git.md](git.md) | Pull latest changes |
| `git_fetch` | [git.md](git.md) | Fetch remote refs |
| `web_fetch` | [web.md](web.md) | Fetch URL content |
| `cache_web_content` | [web.md](web.md) | Save fetched content |
| `init_log` | [logging.md](logging.md) | Initialize log structure |
| `log_node` | [logging.md](logging.md) | Record node execution |
| `log_event` | [logging.md](logging.md) | Log domain-specific event |
| `log_warning` | [logging.md](logging.md) | Add warning message |
| `log_error` | [logging.md](logging.md) | Add error with context |
| `finalize_log` | [logging.md](logging.md) | Complete log with outcome |
| `write_log` | [logging.md](logging.md) | Write log to file |
| `apply_log_retention` | [logging.md](logging.md) | Clean up old logs |
| `output_ci_summary` | [logging.md](logging.md) | CI environment output |

---

## Design Philosophy

Extensions are designed to be:

1. **Replaceable** - Different domains may need different implementations
2. **Self-contained** - Each extension handles its own domain
3. **Composable** - Extensions work with core consequences
4. **Pattern-based** - Reference lib patterns for algorithms

---

## Adding New Extensions

To add a new extension domain:

1. **Create domain file** - `lib/workflow/consequences/extensions/{domain}.md`
2. **Follow template structure:**
   ```markdown
   # {Domain} Consequences

   Brief description of the domain.

   ---

   ## {consequence_type}

   Description.

   ```yaml
   - type: {consequence_type}
     param: value
   ```

   **Parameters:**
   | Name | Type | Required | Description |
   |------|------|----------|-------------|
   ...

   **Effect:**
   ```
   pseudocode
   ```

   ---

   ## Related Documentation

   - **Parent:** [README.md](README.md) - Extension overview
   - **Core:** [../core/](../core/) - Core consequences
   ...
   ```
3. **Update this README** - Add to tables above
4. **Update parent README** - `../README.md`

---

## Domain-Specific Extensions

Plugins converted by hiivmind-blueprint may define their own extension consequences. See `lib/blueprint/patterns/consequence-extensions.md` for guidance on:

- When to use extensions vs core consequences
- Template structure for extension domains
- Examples of domain-specific extensions

---

## Related Documentation

- **Parent:** [../README.md](../README.md) - Consequence taxonomy
- **Core consequences:** [../core/](../core/) - Fundamental workflow operations
- **Shared patterns:** [../core/shared.md](../core/shared.md) - Interpolation, parameters
- **Extension meta-pattern:** `lib/blueprint/patterns/consequence-extensions.md`
