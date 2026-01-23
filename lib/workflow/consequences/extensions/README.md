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

**Total extension consequences:** 10

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
