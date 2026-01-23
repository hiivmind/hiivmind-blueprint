# Git Consequences

Consequences for git repository operations.

---

## clone_repo

Clone git repository.

```yaml
- type: clone_repo
  url: "${source_url}"
  dest: ".source/${computed.source_id}"
  branch: "${computed.branch}"
  depth: 1
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `url` | string | Yes | Repository URL |
| `dest` | string | Yes | Destination path |
| `branch` | string | No | Branch to clone (default: default branch) |
| `depth` | number | No | Shallow clone depth (default: 1) |

**Effect:**
```bash
git clone --depth {depth} --branch {branch} {url} {dest}
```

**Notes:**
- Creates destination directory
- Shallow clone (depth: 1) is recommended for documentation indexing
- Fails if destination exists (use git_pull for updates)

---

## get_sha

Get HEAD commit SHA from repo.

```yaml
- type: get_sha
  repo_path: ".source/${computed.source_id}"
  store_as: computed.sha
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | string | Yes | Path to git repo |
| `store_as` | string | Yes | State field for SHA |

**Effect:**
```bash
sha=$(git -C {repo_path} rev-parse HEAD)
state.computed[store_as] = sha
```

**Notes:**
- Returns full 40-character SHA
- Fails if path is not a git repository

---

## git_pull

Pull latest changes.

```yaml
- type: git_pull
  repo_path: ".source/${computed.source_id}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | string | Yes | Path to git repo |

**Effect:**
```bash
git -C {repo_path} pull --ff-only
```

**Notes:**
- Uses fast-forward only to avoid merge conflicts
- Fails if local changes would be overwritten
- Fails if fast-forward not possible

---

## git_fetch

Fetch remote refs.

```yaml
- type: git_fetch
  repo_path: ".source/${computed.source_id}"
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | string | Yes | Path to git repo |

**Effect:**
```bash
git -C {repo_path} fetch
```

**Notes:**
- Updates remote tracking branches
- Does not modify working directory
- Use before comparing local vs remote SHA

---

## Common Patterns

### Clone and Get SHA

```yaml
actions:
  - type: clone_repo
    url: "${source_url}"
    dest: ".source/main"
    depth: 1
  - type: get_sha
    repo_path: ".source/main"
    store_as: computed.sha
```

### Check for Updates

```yaml
actions:
  - type: git_fetch
    repo_path: ".source/main"
  - type: get_sha
    repo_path: ".source/main"
    store_as: computed.remote_sha
  - type: evaluate
    expression: "computed.remote_sha != config.sources[0].last_commit_sha"
    set_flag: needs_update
```

### Pull and Re-index

```yaml
actions:
  - type: git_pull
    repo_path: ".source/main"
  - type: get_sha
    repo_path: ".source/main"
    store_as: computed.new_sha
  - type: set_state
    field: config.sources[0].last_commit_sha
    value: "${computed.new_sha}"
```

---

## Related Documentation

- **Parent:** [README.md](README.md) - Extension overview
- **Core consequences:** [../core/](../core/) - Fundamental workflow operations
- **Shared patterns:** [../core/shared.md](../core/shared.md) - Path interpolation
