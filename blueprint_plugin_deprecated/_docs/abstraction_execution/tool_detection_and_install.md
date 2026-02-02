# Migrate Capabilities to blueprint-lib + Add install_tool

## Summary

Migrate capability detection patterns from `hiivmind-blueprint/lib/consequences/capabilities/` to `hiivmind-blueprint-lib` as proper precondition/consequence definitions, then add a new `install_tool` consequence.

## Source Analysis

**Files to migrate:**
- `detector.yaml` - Runtime capability detection functions
- `registry.yaml` - Tool catalog with version patterns, install hints, auth checks

**Content in detector.yaml:**
| Function | Purpose | Migrate As |
|----------|---------|------------|
| `tool_version_gte` | Check tool version meets minimum | Precondition |
| `tool_authenticated` | Check tool is authenticated (gh, aws, etc) | Precondition |
| `tool_daemon_ready` | Check daemon is running (docker, etc) | Precondition |
| `network_available` | Check network connectivity | Precondition |
| `available_tools_in` | List available tools from category | N/A (runtime query) |

**Content in registry.yaml:**
- Tool catalog with 30+ tools across 9 categories
- Includes: version_pattern, install_hint, requires_auth, auth_check, requires_daemon, daemon_check, platforms
- Use as reference data for preconditions

## Implementation Plan

### 1. Extend `preconditions/core/tool.yaml`

Add to existing file (`hiivmind-blueprint-lib/preconditions/core/tool.yaml`):

```yaml
# New preconditions to add:

- type: tool_version_gte
  description:
    brief: Check if tool version meets minimum requirement
    detail: |
      Evaluates to true if the installed tool version is >= min_version.
      Uses version pattern from registry or --version output.
  parameters:
    - name: tool
      type: string
      required: true
    - name: min_version
      type: string
      required: true
      pattern: "^\\d+\\.\\d+(\\.\\d+)?$"
  # ... evaluation, examples

- type: tool_authenticated
  description:
    brief: Check if tool requiring authentication is authenticated
    detail: |
      For tools like gh, aws, gcloud that require authentication.
      Returns true if tool is available AND authenticated.
  parameters:
    - name: tool
      type: string
      required: true
  # ... evaluation, examples

- type: tool_daemon_ready
  description:
    brief: Check if tool's required daemon is running
    detail: |
      For daemon-based tools like docker. Returns true if
      tool is available AND daemon is accessible.
  parameters:
    - name: tool
      type: string
      required: true
  # ... evaluation, examples
```

### 2. Create `preconditions/extensions/network.yaml`

New file for network-related preconditions:

```yaml
schema_version: "1.0"
category: extensions/network
description: Network connectivity preconditions

preconditions:
  - type: network_available
    description:
      brief: Check if network access is available
      detail: |
        Checks general connectivity or specific host reachability.
    parameters:
      - name: target
        type: string
        required: false
        description: Specific URL to check (defaults to github.com)
    # ... evaluation, examples
```

### 3. Create `consequences/extensions/package.yaml`

New file for package management consequences:

```yaml
schema_version: "1.1"
category: extensions/package
description: Package and tool installation consequences

consequences:
  - type: install_tool
    description:
      brief: Install a CLI tool if not already available
      detail: |
        Attempts to install a tool using appropriate package manager.
        Uses registry hints for installation commands.
    parameters:
      - name: tool
        type: string
        required: true
      - name: install_command
        type: string
        required: false
        description: Override auto-detected install command
    payload:
      kind: side_effect
      tool: Bash
      requires:
        network: true
      provides:
        features:
          - tool_installation
      effect: |
        if tool_available(tool):
          return  # Already installed

        cmd = install_command or registry.lookup(tool).install_hint
        Bash(cmd)

        if not tool_available(tool):
          error("Installation failed for " + tool)
    # ... examples
```

### 4. Create `lib/tool-registry.yaml` (Reference Data)

Migrate `registry.yaml` as reference data for preconditions:

```yaml
# Tool catalog with detection patterns and install hints
# Used by tool_version_gte, tool_authenticated, install_tool

schema_version: "1.0"
description: Known CLI tools with detection patterns

categories:
  vcs:
    git:
      check: "git --version"
      version_pattern: "git version (\\d+\\.\\d+)"
      install_hint: "apt install git / brew install git"
    gh:
      check: "gh --version"
      version_pattern: "gh version (\\d+\\.\\d+)"
      requires_auth: true
      auth_check: "gh auth status"
      install_hint: "apt install gh / brew install gh"
  # ... rest of registry
```

### 5. Update Index Files

**`preconditions/index.yaml`:**
- Add new types to `tool.yaml` entry
- Add new `extensions/network.yaml` source
- Update type_lookup and stats

**`consequences/index.yaml`:**
- Add new `extensions/package.yaml` source
- Update type_lookup and stats

### 6. Cleanup

After migration verified:
- Delete `hiivmind-blueprint/lib/consequences/capabilities/` folder
- Remove `lib/consequences/definitions/` if fully deprecated

## Files to Modify

| File | Action |
|------|--------|
| `hiivmind-blueprint-lib/preconditions/core/tool.yaml` | Add 3 new preconditions |
| `hiivmind-blueprint-lib/preconditions/extensions/network.yaml` | Create new file |
| `hiivmind-blueprint-lib/preconditions/index.yaml` | Update sources and type_lookup |
| `hiivmind-blueprint-lib/consequences/extensions/package.yaml` | Create new file |
| `hiivmind-blueprint-lib/consequences/index.yaml` | Update sources and type_lookup |
| `hiivmind-blueprint-lib/lib/tool-registry.yaml` | Create reference data |
| `hiivmind-blueprint/lib/consequences/capabilities/` | Delete after verification |

## Verification

1. **Schema validation:**
   ```bash
   cd hiivmind-blueprint-lib
   check-jsonschema --base-uri "file://$(pwd)/schema/" \
     --schemafile schema/precondition-definition.json \
     preconditions/core/tool.yaml

   check-jsonschema --base-uri "file://$(pwd)/schema/" \
     --schemafile schema/consequence-definition.json \
     consequences/extensions/package.yaml
   ```

2. **Manual verification:**
   - Each new precondition has at least one example
   - install_tool consequence references registry correctly
   - Index files have correct counts


Summary

  Successfully migrated capabilities from hiivmind-blueprint/lib/consequences/capabilities/ to hiivmind-blueprint-lib as proper precondition/consequence definitions.

  Files Created
  ┌───────────────────────────────────────┬────────────────────────────────────────────────────────┐
  │                 File                  │                      Description                       │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ preconditions/extensions/network.yaml │ network_available precondition for connectivity checks │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ consequences/extensions/package.yaml  │ install_tool consequence for tool installation         │
  ├───────────────────────────────────────┼────────────────────────────────────────────────────────┤
  │ lib/tool-registry.yaml                │ Reference data with 27 tools across 9 categories       │
  └───────────────────────────────────────┴────────────────────────────────────────────────────────┘
  Files Modified
  ┌──────────────────────────────┬────────────────────────────────────────────────────────────────────────────────┐
  │             File             │                                    Changes                                     │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ preconditions/core/tool.yaml │ Added 3 preconditions: tool_version_gte, tool_authenticated, tool_daemon_ready │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ preconditions/index.yaml     │ Added new types to sources, type_lookup, updated stats (28 → 32 types)         │
  ├──────────────────────────────┼────────────────────────────────────────────────────────────────────────────────┤
  │ consequences/index.yaml      │ Added extensions/package.yaml source, updated stats (43 → 44 types)            │
  └──────────────────────────────┴────────────────────────────────────────────────────────────────────────────────┘
  New Types Summary

  Preconditions (4 new):
  - tool_version_gte - Check if tool version ≥ minimum
  - tool_authenticated - Check if auth-requiring tool is authenticated (gh, aws, gcloud, az)
  - tool_daemon_ready - Check if daemon-requiring tool has its daemon running (docker)
  - network_available - Check network connectivity

  Consequences (1 new):
  - install_tool - Install a CLI tool using registry hints or custom command

  Cleanup Pending

  The original source files at hiivmind-blueprint/lib/consequences/capabilities/ (detector.yaml and registry.yaml) can now be deleted since this migration preserves their
  functionality in the proper schema-validated format.
