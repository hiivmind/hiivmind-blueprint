---
name: hiivmind-blueprint-ops-upgrade
description: >
  Upgrade workflow.yaml files to latest schema version. Triggers on "upgrade workflow",
  "migrate workflow schema", "update workflow to latest", "fix deprecated workflow",
  "modernize workflow.yaml", "normalize SKILL.md", "thin out SKILL.md", "reduce SKILL.md size",
  "upgrade gateway", "upgrade command", "migrate gateway command", "upgrade intent mapping",
  "remove priority from intent", "migrate intent-mapping.yaml", "fix deprecated intent patterns",
  "blueprint upgrade", "hiivmind-blueprint upgrade", "migrate schema", "update workflow version".
  Supports --target=skills|gateway|auto to select scope.
allowed-tools: Read, Write, Edit, Glob, Grep, AskUserQuestion
---

# Upgrade Workflow

Migrate existing workflow.yaml files to the latest schema version with deprecation fixes and new features.

**Supports both skill workflows (`skills/`) and gateway commands (`commands/`).**

---

## Prerequisites

**Check these dependencies before execution:**

| Tool | Required | Check | Install |
|------|----------|-------|---------|
| `jq` | **Mandatory** | `command -v jq` | `brew install jq` / `apt install jq` |
| `yq` | **Mandatory** | `command -v yq` | `brew install yq` / [github.com/mikefarah/yq](https://github.com/mikefarah/yq) |
| `gh` | Recommended | `command -v gh` | `brew install gh` / `apt install gh` |

If mandatory tools are missing, exit with error listing the install commands above.

---

## Initial State - Paths

Detect and set path variables:

```pseudocode
workflow_path = "${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-upgrade/workflow.yaml"

# Check file existence and set state
if file_exists(workflow_path):
    state.workflow_available = true
    state.workflow_path = workflow_path
else:
    state.workflow_available = false
    # ERROR: workflow.yaml is required
```

---

## Target Types

| Target | Directory | Template | Threshold | Extra Preserved Sections |
|--------|-----------|----------|---------------|--------------------------|
| `skills` | `skills/` | `SKILL.md.template` (~60 lines) | 120 lines | - |
| `gateway` | `commands/` | `gateway-command.md.template` (~160 lines) | 200 lines | skill_tables, help_commands |

---

## Schema Versions

| Version | Key Features | Breaking Changes |
|---------|--------------|------------------|
| 1.0.0 | Initial schema | - |
| 1.1.0 | Added `validation_gate` node type | None |
| 1.2.0 | Added `reference` node type | None |
| 2.0.0 | New consequence format | `set_state` syntax changed |
| 2.1.0 | External definitions, `.hiivmind/blueprint/` structure | Lock file location changed |
| 2.2.0 | Remote execution references | Local engine.md removed, SKILL.md files use raw GitHub URLs |
| 2.3.0 | Intent mapping: priority field removed | `priority` field no longer used by 3VL ranking |

---

## Usage

```
/hiivmind-blueprint-ops upgrade              # Auto-detect target type (ask if both found)
/hiivmind-blueprint-ops upgrade skills       # Upgrade skill workflows only
/hiivmind-blueprint-ops upgrade gateway      # Upgrade gateway workflows only
/hiivmind-blueprint-ops upgrade --check      # Check for updates without applying
/hiivmind-blueprint-ops upgrade --schema-only    # Only upgrade workflow schema
/hiivmind-blueprint-ops upgrade --refs-only      # Only migrate execution references
/hiivmind-blueprint-ops upgrade --normalize-only # Only normalize oversized SKILL.md files
/hiivmind-blueprint-ops upgrade --skip-normalize # Skip SKILL.md normalization
/hiivmind-blueprint-ops upgrade --intent-only    # Only upgrade intent-mapping.yaml files
```

---

## Execution Protocol

**See:** `.hiivmind/blueprint/engine_entrypoint.md` (Engine v1.0.0) for full protocol.

### Quick Summary

1. **Bootstrap:** Extract `v2.1.0` from workflow.yaml definitions.source
2. **Fetch Semantics:** Load execution rules from hiivmind-blueprint-lib@v2.1.0
3. **Load Local Files:** Read and validate workflow.yaml
4. **Execute:** Run workflow per traversal semantics (initialize → execute → complete)

**Verification Checkpoint:**
Before proceeding to Phase 3, verify:
- `_semantics.bootstrap.phases` has 5 items ending with "execute"
- `_semantics.bootstrap.required_sections` has exactly 4 items
- `_semantics.traversal.phases` equals `["initialize", "execute", "complete"]`

If verification fails, retry fetch.

---

## Execution Reference

Execution semantics from [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib) (version: v2.1.0):

| Semantic | Source |
|----------|--------|
| Core loop | [traversal.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/traversal.yaml) |
| State | [state.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/state.yaml) |
| Consequences | [consequence-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/consequence-dispatch.yaml) |
| Preconditions | [precondition-dispatch.yaml](https://raw.githubusercontent.com/hiivmind/hiivmind-blueprint-lib/v2.1.0/execution/precondition-dispatch.yaml) |

---

## Reference Documentation

- **Workflow:** `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-upgrade/workflow.yaml`
- **Type Definitions:** [hiivmind-blueprint-lib@v2.1.0](https://github.com/hiivmind/hiivmind-blueprint-lib/tree/v2.1.0)
- **Version Config:** `${CLAUDE_PLUGIN_ROOT}/BLUEPRINT_LIB_VERSION.yaml`

---

## Related Skills

**This Plugin (hiivmind-blueprint-ops):**
- Validate workflow: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-validate/SKILL.md`
- Library validation: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-lib-validation/SKILL.md`
- Intent validation: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-ops-intent-validator/SKILL.md`

**Cross-Plugin (hiivmind-blueprint-author):**
- Initialize project: `/hiivmind-blueprint-author init`
- Convert skill: `/hiivmind-blueprint-author convert`
- Generate gateway: `/hiivmind-blueprint-author gateway`
- Visualize workflow: `/hiivmind-blueprint-author visualize`
