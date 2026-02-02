# Extension Consequences

> **ARCHIVED:** This document is preserved for reference. The authoritative sources are:
> - `lib/consequences/definitions/extensions/file-system.yaml`
> - `lib/consequences/definitions/extensions/git.yaml`
> - `lib/consequences/definitions/extensions/web.yaml`
> - `lib/consequences/definitions/extensions/scripting.yaml`

---

Domain-specific consequences that extend the core workflow operations. Extensions are designed to be replaceable and composable for different use cases.

## Quick Reference

| Consequence Type | YAML Definition | Description |
|------------------|-----------------|-------------|
| `read_file` | extensions/file-system.yaml | Read arbitrary file |
| `write_file` | extensions/file-system.yaml | Write content to file |
| `create_directory` | extensions/file-system.yaml | Create directory |
| `delete_file` | extensions/file-system.yaml | Delete file |
| `clone_repo` | extensions/git.yaml | Clone git repository |
| `get_sha` | extensions/git.yaml | Get HEAD commit SHA |
| `git_pull` | extensions/git.yaml | Pull latest changes |
| `git_fetch` | extensions/git.yaml | Fetch remote refs |
| `web_fetch` | extensions/web.yaml | Fetch URL content |
| `cache_web_content` | extensions/web.yaml | Save fetched content |
| `run_script` | extensions/scripting.yaml | Execute script with auto-detected interpreter |
| `run_python` | extensions/scripting.yaml | Execute Python script |
| `run_bash` | extensions/scripting.yaml | Execute Bash script |

---

## Related Documentation

- **YAML Definitions:** `lib/consequences/definitions/extensions/`
- **Core consequences:** `lib/consequences/definitions/core/`
