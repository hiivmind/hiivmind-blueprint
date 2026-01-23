# Web Consequences

Consequences for fetching and caching web content.

---

## web_fetch

Fetch URL content.

```yaml
- type: web_fetch
  url: "${source_url}/llms.txt"
  store_as: computed.manifest_check
  allow_failure: true
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `url` | string | Yes | URL to fetch |
| `store_as` | string | Yes | State field for result |
| `allow_failure` | boolean | No | If true, 4xx/5xx doesn't fail action |
| `prompt` | string | No | Prompt for WebFetch tool |

**Effect:**
```
result = WebFetch(url, prompt)
state.computed[store_as] = {
  status: result.status,
  content: result.content,
  url: url
}
```

**Result structure:**
```yaml
computed.manifest_check:
  status: 200          # HTTP status code
  content: "..."       # Response body
  url: "https://..."   # Requested URL
```

**Notes:**
- Uses Claude's WebFetch tool
- HTML is converted to markdown automatically
- Prompt guides extraction if specified
- With `allow_failure: true`, HTTP errors populate result but don't fail

**Examples:**

Check for llms.txt manifest:
```yaml
- type: web_fetch
  url: "${base_url}/llms.txt"
  store_as: computed.manifest_check
  allow_failure: true
```

Fetch with extraction prompt:
```yaml
- type: web_fetch
  url: "${doc_url}"
  store_as: computed.page_content
  prompt: "Extract the main documentation content, excluding navigation and footers"
```

---

## cache_web_content

Save fetched content to cache file.

```yaml
- type: cache_web_content
  from: computed.fetch_result
  dest: ".cache/web/${source_id}/${computed.slug}.md"
  store_path_as: computed.cached_file
```

**Parameters:**
| Name | Type | Required | Description |
|------|------|----------|-------------|
| `from` | string | Yes | State field with fetch result |
| `dest` | string | Yes | Destination file path |
| `store_path_as` | string | No | State field to store path |

**Effect:**
```
content = get_state_value(from).content
write_file(dest, content)
if (store_path_as) set_state_value(store_path_as, dest)
```

**Notes:**
- Creates parent directories if needed
- Extracts `content` field from fetch result
- Optional `store_path_as` records where file was written

---

## Common Patterns

### Check for Manifest

```yaml
actions:
  - type: web_fetch
    url: "${base_url}/llms.txt"
    store_as: computed.manifest
    allow_failure: true
  - type: evaluate
    expression: "computed.manifest.status == 200"
    set_flag: has_manifest
```

### Fetch and Cache Page

```yaml
actions:
  - type: web_fetch
    url: "${doc_url}"
    store_as: computed.page
    prompt: "Extract main content"
  - type: cache_web_content
    from: computed.page
    dest: ".cache/web/${source_id}/${slug}.md"
    store_path_as: computed.cached_path
```

### Batch Fetch with Caching

```yaml
# For each URL in list
actions:
  - type: compute
    expression: "url.replace(/[^a-z0-9]/gi, '-')"
    store_as: computed.slug
  - type: web_fetch
    url: "${url}"
    store_as: computed.current_page
  - type: cache_web_content
    from: computed.current_page
    dest: ".cache/web/${source_id}/${computed.slug}.md"
```

---

## Related Documentation

- **Parent:** [README.md](README.md) - Extension overview
- **Core consequences:** [../core/](../core/) - Fundamental workflow operations
- **Shared patterns:** [../core/shared.md](../core/shared.md) - Path interpolation
