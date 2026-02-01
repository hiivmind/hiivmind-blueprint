---
name: hiivmind-blueprint
description: >
  Unified entry point for hiivmind-blueprint operations - describe what you need
  in natural language or select from the menu. Converts prose-based skills to
  deterministic YAML workflows.
arguments:
  - name: request
    description: What you want to do (optional - shows menu if omitted)
    required: false
---

# hiivmind-blueprint Gateway

Execute this workflow for intelligent routing to the appropriate skill.

> **Workflow:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/workflow.yaml`
> **Intent Mapping:** `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/intent-mapping.yaml`

---

## Usage

```
/hiivmind-blueprint                    # Show interactive menu
/hiivmind-blueprint [request]          # Route by natural language intent
/hiivmind-blueprint --help             # Show full help
/hiivmind-blueprint [flags] [request]  # With runtime flags
```

## Quick Examples

- `/hiivmind-blueprint init` → Initialize blueprint project
- `/hiivmind-blueprint discover` → Find skills to convert
- `/hiivmind-blueprint analyze my-skill` → Analyze a skill
- `/hiivmind-blueprint convert` → Convert skill to workflow
- `/hiivmind-blueprint generate` → Write workflow files
- `/hiivmind-blueprint gateway` → Generate gateway command
- `/hiivmind-blueprint upgrade` → Upgrade existing workflows
- `/hiivmind-blueprint visualize` → Generate Mermaid diagram
- `/hiivmind-blueprint validate` → Check workflow for issues

---

## Runtime Flags

Flags modify workflow execution behavior. They are **per-invocation only** and reset for each command.

### Display Flags

| Flag | Effect |
|------|--------|
| `--verbose`, `-v` | Show all node details and condition evaluations |
| `--quiet`, `-q` | Only user prompts and final result |
| `--terse` | Batch summaries only (non-interactive nodes) |
| `--debug` | Full state dumps after each node |
| `--no-display` | Silent mode (no terminal output) |

### Logging Flags

| Flag | Effect |
|------|--------|
| `--log-level=X` | Set logging level: `error`, `warn`, `info`, `debug`, `trace` |
| `--log-format=X` | Output format: `json`, `yaml`, `pretty` |
| `--log-dir=X` | Override log directory |
| `--trace` | Shorthand for `--log-level=trace` |
| `--no-log` | Disable all file logging |
| `--ci` | CI mode: structured output, no progress indicators |

### Flag Examples

```
/hiivmind-blueprint --verbose analyze my-skill
/hiivmind-blueprint --quiet convert
/hiivmind-blueprint --log-level=debug validate workflow.yaml
```

---

## Help Commands

| Command | Description |
|---------|-------------|
| `/hiivmind-blueprint --help` | Show full command reference |
| `/hiivmind-blueprint -h` | Short form of --help |
| `/hiivmind-blueprint help` | Same as --help |
| `/hiivmind-blueprint help [skill]` | Help for specific skill |

### Configuration Help

| Command | Description |
|---------|-------------|
| `/hiivmind-blueprint help logging` | Logging levels, flags, and priority hierarchy |
| `/hiivmind-blueprint help display` | Display verbosity and batch mode options |
| `/hiivmind-blueprint help prompts` | Prompt modes and match strategies |
| `/hiivmind-blueprint help flags` | Quick reference for all runtime flags |



---

## Intent Detection

This gateway uses 3VL (3-valued logic) intent detection with **dynamic routing**:

| Value | Meaning | Example |
|-------|---------|---------|
| **T** (True) | Keyword matched | "init" → has_init: T |
| **F** (False) | Negative keyword matched | "don't init" → has_init: F |
| **U** (Unknown) | No match either way | (default state) |

### How Intent Resolution Works

1. **Parse input** against flag keywords → `computed.intent_flags`
2. **Match rules** in priority order → `computed.intent_matches`
3. **Check for clear winner** (2+ point lead)
4. **Dynamic route** to `${computed.matched_action}` → skill execution

This gateway uses O(1) dynamic routing instead of N conditional nodes.

If no clear winner, disambiguation is offered.

### Safety Handling

This gateway includes a standard `error_safety` ending for requests that Claude's built-in safety detects as harmful. The workflow will:

1. Exit cleanly via the `error_safety` ending
2. Display a brief, non-judgmental message
3. Offer recovery guidance

No custom jailbreak detection is implemented—Claude's native safety handles this automatically.

---

## Execution Protocol

**MANDATORY:** This gateway requires loading and following remote execution semantics.

### Phase 1: Initialize

1. Parse command-line arguments and flags
2. Read `workflow.yaml` from `${CLAUDE_PLUGIN_ROOT}/commands/hiivmind-blueprint/`
3. Read `intent-mapping.yaml` from same directory

### Phase 2: Load Remote Semantics

**Fetching Protocol (try in order):**
1. gh api (primary): `gh api repos/{owner}/{repo}/contents/{path}?ref={version} --jq '.content' | base64 -d`
2. raw URL (fallback): `https://raw.githubusercontent.com/{owner}/{repo}/{version}/{path}`

**Fetch these files from hiivmind-blueprint-lib@v2.0.0:**

| File | Path | Purpose |
|------|------|---------|
| traversal.yaml | execution/traversal.yaml | Core loop |
| state.yaml | execution/state.yaml | State management |
| workflow-loader.yaml | resolution/workflow-loader.yaml | Reference node loading |

### Phase 3: Execute Gateway Workflow

Follow `traversal.yaml` EXACTLY:
1. Initialize state per `state.yaml`
2. Start at `start_node` from workflow.yaml
3. Execute each node per `execute_node()` pseudocode
4. For `reference` nodes, load sub-workflows per `workflow-loader.yaml`
5. Dispatch to matched skill via `invoke_skill` consequence

**The fetched YAML files define execution behavior. Follow them precisely.**

---

## Reference Documentation

- **Type Definitions:** [hiivmind-blueprint-lib](https://github.com/hiivmind/hiivmind-blueprint-lib/tree/v2.0.0)

---

## Related Skills

- Initialize: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-init/SKILL.md`
- Discover: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-discover/SKILL.md`
- Analyze: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-analyze/SKILL.md`
- Convert: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-convert/SKILL.md`
- Generate: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-generate/SKILL.md`
- Gateway: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-gateway/SKILL.md`
- Upgrade: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-upgrade/SKILL.md`
- Visualize: `${CLAUDE_PLUGIN_ROOT}/skills/hiivmind-blueprint-visualize/SKILL.md`
