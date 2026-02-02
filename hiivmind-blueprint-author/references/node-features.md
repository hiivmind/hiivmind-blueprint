# Node Features Reference

Complete reference for all 4 node types available in hiivmind-blueprint-lib v2.1.0.

> **Examples:** `hiivmind/hiivmind-blueprint-lib@v2.1.0/examples/nodes.yaml`
> **Definitions:** `hiivmind/hiivmind-blueprint-lib@v2.1.0/nodes/workflow_nodes.yaml`

---

## Overview

Workflows are composed of 4 node types:

| Type | Purpose | Key Fields |
|------|---------|------------|
| `action` | Execute operations | `actions`, `on_success`, `on_failure` |
| `conditional` | Branch on conditions | `condition`, `branches`, `audit` |
| `user_prompt` | Get user input | `prompt`, `on_response` |
| `reference` | Delegate to doc/workflow | `doc`/`workflow`, `context`, `next_node` |

---

## action

Execute a sequence of consequences and route based on success/failure.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `"action"` |
| `description` | No | Human-readable purpose |
| `actions` | Yes | Array of consequences to execute |
| `on_success` | Yes | Node/ending when all succeed |
| `on_failure` | Yes | Node/ending when any fails |

### Execution Behavior

- Actions execute sequentially
- First failure short-circuits remaining actions
- Results stored via `store_as` in each consequence

---

## conditional

Branch based on precondition evaluation, with optional audit mode.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `"conditional"` |
| `description` | No | Human-readable purpose |
| `condition` | Yes | Single precondition (often composite) |
| `branches.on_true` | Yes | Node/ending when true |
| `branches.on_false` | Yes | Node/ending when false |
| `audit` | No | Audit mode configuration |

### Audit Mode (v2.0.0+)

Replaces deprecated `validation_gate`. Evaluates ALL conditions without short-circuit.

| Audit Field | Required | Default | Description |
|-------------|----------|---------|-------------|
| `enabled` | No | `false` | Enable audit mode |
| `output` | No | `computed.audit_results` | State path for results |
| `messages` | No | - | Error messages by precondition type |

**Audit Output Structure:**
```yaml
computed.audit_results:
  passed: false
  total: 3
  passed_count: 1
  failed_count: 2
  results:
    - { index: 0, condition: {...}, passed: true }
    - { index: 1, condition: {...}, passed: false, message: "..." }
```

---

## user_prompt

Present a question and route based on user response.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `"user_prompt"` |
| `description` | No | Human-readable purpose |
| `prompt.question` | Yes | Question text |
| `prompt.header` | Yes | Short label (max 12 chars) |
| `prompt.options` | Yes* | Static option array |
| `prompt.options_from_state` | Yes* | Dynamic options path |
| `prompt.option_mapping` | With dynamic | Transform mapping |
| `on_response` | Yes | Handlers by option ID |

*One of `options` or `options_from_state` required.

### Static Options

```yaml
options:
  - id: git
    label: "Git repository"
    description: "Clone a repo"
```

### Dynamic Options

```yaml
options_from_state: computed.candidates
option_mapping:
  id: name
  label: name
  description: desc
on_response:
  selected:
    next_node: handle_selection
  other:
    next_node: handle_custom
```

### Response Handlers

| Handler | When Used | Available Data |
|---------|-----------|----------------|
| `{option_id}` | Static option selected | `user_responses.{node}.handler_id` |
| `selected` | Dynamic option selected | `user_responses.{node}.selected` (original item) |
| `other` | Custom text entered | `user_responses.{node}.text` |

---

## reference

Delegate to a local document or remote workflow.

### Fields

| Field | Required | Description |
|-------|----------|-------------|
| `type` | Yes | `"reference"` |
| `doc` | Yes* | Local document path |
| `workflow` | Yes* | Remote workflow reference |
| `section` | No | Section heading (doc only) |
| `context` | No | Variables for sub-execution |
| `next_node` | Yes | Node after completion |

*One of `doc` or `workflow` required.

### Local Document Reference

```yaml
clone_repo:
  type: reference
  doc: "lib/patterns/git.md"
  section: "Clone Repository"
  context:
    repo_url: "${computed.repo_url}"
  next_node: verify_clone
```

### Remote Workflow Reference (v2.1.0+)

```yaml
detect_intent:
  type: reference
  workflow: hiivmind/hiivmind-blueprint-lib@v2.1.0:intent-detection
  context:
    arguments: "${arguments}"
    intent_flags: "${intent_flags}"
    intent_rules: "${intent_rules}"
  next_node: "${computed.dynamic_target}"
```

**Key Differences from `invoke_skill`:**
- `reference` shares state with parent workflow
- `invoke_skill` isolates state (new conversation)

---

## Prompt Modes (v2.4.0+)

Configure in `initial_state.prompts`:

| Mode | Interface | Description |
|------|-----------|-------------|
| `interactive` | Claude Code | AskUserQuestion tool (default) |
| `tabular` | Text fallback | Markdown table with text matching |
| `forms` | Web | Rich HTML-like forms |
| `structured` | API | JSON schema for programmatic access |
| `autonomous` | Agent | LLM evaluates without user |

### Mode Configuration

```yaml
initial_state:
  prompts:
    interface: "auto"  # or explicit: claude_code, web, api, agent
    modes:
      claude_code: "interactive"
      web: "forms"
      api: "structured"
      agent: "autonomous"
    tabular:
      match_strategy: "prefix"  # exact, prefix, fuzzy
      other_handler: "prompt"   # prompt, route, fail
    autonomous:
      strategy: "best_match"
      confidence_threshold: 0.7
      context_fields:
        - computed.intent_flags
        - arguments
```

---

## Quick Reference

### Node Type Selection

```
Analyze Element Type
       │
┌──────┴──────┐──────────┐
▼             ▼          ▼
Tool Call  Conditional  User Input
    │          │            │
    ▼          ▼            ▼
 ACTION   CONDITIONAL   USER_PROMPT
```

### Transition Types

| Node Type | Transition Field(s) |
|-----------|---------------------|
| action | `on_success`, `on_failure` |
| conditional | `branches.on_true`, `branches.on_false` |
| user_prompt | `on_response.{id}.next_node` |
| reference | `next_node` |

---

## Related Documentation

- **Examples:** `hiivmind/hiivmind-blueprint-lib@v2.1.0/examples/nodes.yaml`
- **Definitions:** `hiivmind/hiivmind-blueprint-lib@v2.1.0/nodes/workflow_nodes.yaml`
- **Node Mapping Pattern:** `lib/patterns/node-mapping.md`
- **Prompt Modes:** `references/prompt-modes.md`
