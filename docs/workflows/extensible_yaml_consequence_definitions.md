# Plan: Enhance Consequence Definition Extensibility

## Context

The YAML consequence definitions we just created work well for Claude's built-in tools, but lack critical extensibility features for external tools (Docker, `gh`, `just`, `kubectl`, etc.). GitHub Actions provides a mature model we can learn from.

## Key Insights from GitHub Actions

### What They Do Well

| Pattern | Description | Blueprint Analog |
|---------|-------------|------------------|
| `runs.using` | Declare runtime: `node20`, `docker`, `composite` | We have `payload.kind` but no runtime |
| `runs.steps[].shell` | Specify shell: `bash`, `pwsh`, `python` | We assume bash |
| Input schemas | `type: choice`, `required`, `default` | We have types but no validation |
| Output declarations | Explicit `outputs:` with descriptions | We infer from `store_as` |
| Step IDs | Reference via `${{ steps.id.outputs.x }}` | We use `${computed.x}` |
| Versioning | `owner/repo@v2` distribution model | We have `remote_sources` (unused) |
| Composite actions | Reusable multi-step templates | We lack this entirely |

### What We're Missing

1. **Tool Requirements** - No way to declare that `clone_repo` needs `git` CLI
2. **Environment Specs** - No shell type, working directory, env vars
3. **Capability Discovery** - No way to know what tools a system has
4. **Timeout/Resources** - No execution constraints
5. **Alternative Implementations** - Can't say "use `gh` if available, else `git`"

## Proposed Schema Enhancements

### 1. Add `requires` Block to Payload

```yaml
payload:
  kind: tool_call
  tool: Bash

  # NEW: Declare what this consequence needs
  requires:
    tools:
      - name: git
        min_version: "2.0"
        check_command: "git --version"
      - name: gh
        optional: true  # Enhanced features if available
        min_version: "2.0"

    shell: bash  # bash | sh | zsh | pwsh | python

    environment:
      - GITHUB_TOKEN  # Required env vars

    network: true  # Needs network access

    timeout_seconds: 300

    working_directory: "${repo_path}"  # Can be interpolated
```

### 2. Add `execution` Block for Runtime Context

```yaml
# Per-consequence execution context (optional, for advanced cases)
execution:
  runtime: bash           # bash | python | node
  working_directory: "."  # Relative to repo root

  # Resource constraints
  constraints:
    timeout: 300
    max_memory: "1G"
    max_output: "10M"
```

Note: Most consequences won't need this - `requires` covers the common cases. `execution` is for fine-grained control when needed.

### 3. Add `provides` Block for Capability Discovery

```yaml
# What this consequence offers
provides:
  features:
    - shallow_clone
    - sparse_checkout

  outputs:
    - field: computed.repo_path
      type: string
      description: "Path to cloned repository"

    - field: computed.sha
      type: string
      pattern: "^[a-f0-9]{40}$"
      description: "Full commit SHA"
```

### 4. Add `alternatives` for Graceful Degradation

```yaml
# If primary tool unavailable, try alternatives
alternatives:
  - condition: "tool_available('gh')"
    effect: |
      gh repo clone ${url} ${dest}

  - condition: "tool_available('git')"
    effect: |
      git clone --depth 1 ${url} ${dest}

  - fallback: true
    error: "Neither 'gh' nor 'git' available"
```

### 5. Support Script References

For complex logic, consequences can reference repo scripts instead of embedding pseudocode:

```yaml
# Script reference pattern
- type: scrape_docs
  description:
    brief: "Scrape documentation from website"

  parameters:
    - name: url
      type: string
      required: true
    - name: output_dir
      type: string
      required: true

  payload:
    kind: tool_call
    tool: Bash

    requires:
      tools:
        - name: python3
          min_version: "3.9"
      dependencies:
        - "pip:beautifulsoup4"  # Optional: document Python deps

    # NEW: Reference to implementation script
    script:
      path: "lib/tools/scraper.py"
      entrypoint: "main"  # Optional function name
      args:
        - "--url=${url}"
        - "--output=${output_dir}"

    # Pseudocode remains for documentation
    effect: |
      python3 lib/tools/scraper.py --url=${url} --output=${output_dir}
```

**Why script references over task runners:**
- Scripts are version-controlled with the workflow
- No external tool dependency (just Python/Bash)
- Full programming language power when needed
- Pseudocode documents intent, script implements it

## Implementation Approach

### Phase 1: Schema Extension (Non-Breaking)

Add new optional fields to `consequence-definition.json`:
- `payload.requires` - Tool dependencies
- `payload.execution` - Runtime context
- `payload.provides` - Capability declaration
- `payload.alternatives` - Fallback strategies

**Files to modify:**
- `lib/consequences/schema/consequence-definition.json`

### Phase 2: Enhance Core Consequences

Add `requires` blocks to existing consequences:
- `extensions/git.yaml` - Add `requires.tools: [git]`
- `extensions/web.yaml` - Add `requires.network: true`
- `core/logging.yaml` - Add `requires.tools: [mkdir]` where needed

**Files to modify:**
- All 11 definition YAML files

### Phase 3: Add Script Execution Extension

Create extension for script-based consequences:
```
lib/consequences/definitions/extensions/
├── scripting.yaml       # run_script, run_python, run_bash
└── containers.yaml      # docker, podman (future - deferred)
```

**Consequence types to add:**
- `run_script` - Execute any script with interpreter detection
- `run_python` - Execute Python script with args
- `run_bash` - Execute Bash script with args

**Example `run_python` consequence:**
```yaml
- type: run_python
  parameters:
    - name: script
      type: string
      required: true
      description: "Path to Python script (relative to repo root)"
    - name: args
      type: array
      required: false
    - name: store_as
      type: string
      required: false

  payload:
    kind: tool_call
    tool: Bash
    requires:
      tools:
        - name: python3
    effect: |
      python3 ${script} ${args.join(' ')}
```

### Phase 4: Capability Discovery System

Create runtime capability checking:
```yaml
# lib/consequences/capabilities/
├── detector.yaml        # How to detect tool availability
└── registry.yaml        # Known tools and their check commands
```

**Example detector:**
```yaml
tools:
  git:
    check: "git --version"
    version_pattern: "git version (\\d+\\.\\d+)"

  just:
    check: "just --version"
    version_pattern: "just (\\d+\\.\\d+)"

  docker:
    check: "docker version --format '{{.Server.Version}}'"
    requires_daemon: true
```

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `lib/consequences/schema/consequence-definition.json` | Modify | Add requires, execution, provides, alternatives, script |
| `lib/consequences/definitions/extensions/*.yaml` | Modify | Add requires blocks to existing consequences |
| `lib/consequences/definitions/extensions/scripting.yaml` | Create | run_script, run_python, run_bash |
| `lib/consequences/capabilities/detector.yaml` | Create | Tool detection rules |
| `lib/consequences/capabilities/registry.yaml` | Create | Known tools catalog |
| `lib/consequences/definitions/index.yaml` | Modify | Add scripting.yaml to sources |
| `lib/workflow/consequences/README.md` | Modify | Document new extensibility model |

## Example: Enhanced Consequence with Requirements

```yaml
- type: clone_repo
  description:
    brief: "Clone git repository"
    detail: |
      Clones a repository using git or gh CLI. Supports shallow clones
      and branch selection. Falls back gracefully based on available tools.

  parameters:
    - name: url
      type: string
      required: true
      pattern: "^(https?://|git@)"
    - name: dest
      type: string
      required: true
    - name: depth
      type: number
      default: 1

  payload:
    kind: tool_call
    tool: Bash

    requires:
      tools:
        - name: git
          min_version: "2.0"
        - name: gh
          optional: true
      network: true
      timeout_seconds: 300

    provides:
      outputs:
        - field: computed.repo_path
          type: string

    alternatives:
      - condition: "tool_available('gh') and url.startsWith('https://github.com')"
        effect: "gh repo clone ${url} ${dest} -- --depth ${depth}"
      - condition: "tool_available('git')"
        effect: "git clone --depth ${depth} ${url} ${dest}"

    effect: |
      git clone --depth ${depth} ${url} ${dest}
```

## Example: Script Reference for Complex Logic

```yaml
- type: scrape_documentation
  description:
    brief: "Scrape and parse documentation site"

  parameters:
    - name: url
      type: string
      required: true
    - name: output_dir
      type: string
      required: true
    - name: max_pages
      type: number
      default: 100

  payload:
    kind: tool_call
    tool: Bash

    requires:
      tools:
        - name: python3
          min_version: "3.9"

    # Reference implementation script
    script:
      path: "lib/tools/doc_scraper.py"
      args: ["--url", "${url}", "--output", "${output_dir}", "--max", "${max_pages}"]

    provides:
      outputs:
        - field: computed.pages_scraped
          type: number
        - field: computed.output_files
          type: array

    effect: |
      python3 lib/tools/doc_scraper.py --url ${url} --output ${output_dir} --max ${max_pages}
```

## Verification

1. **Schema validation** - JSON Schema validates new fields
2. **Backward compatibility** - Old definitions still valid (new fields optional)
3. **Tool detection** - Test capability detector with/without git, python, etc.
4. **Alternative execution** - Verify fallback chain (gh → git) works correctly
5. **Script execution** - Test `run_python` with sample script in `lib/tools/`

## Decisions Made

1. **Script references over task runners** - Use `payload.script` to reference repo scripts (e.g., `lib/tools/scraper.py`) instead of integrating task runners like `just` or `make`
2. **Containers deferred** - Docker/Podman support will come in a future phase
3. **Ordered fallback chain** - Alternatives execute in order until one succeeds

## Open Questions

1. **Scope of Phase 1** - Add all new schema fields at once, or incrementally?
2. **Remote consequences** - Activate the `remote_sources` pattern now?
3. **Script language detection** - Auto-detect from extension or require explicit `interpreter`?

## Notes

- This draws heavily from GitHub Actions' `action.yml` schema
- The `alternatives` pattern enables graceful degradation
- Script references keep implementation logic in version-controlled code
- Pseudocode documents intent; scripts implement when complexity warrants
- Capability detection at workflow-load time prevents runtime surprises
