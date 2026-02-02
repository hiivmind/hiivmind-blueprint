# Plan: Add Safety Error Ending to Workflow Schema

## Goal

Add a minimal safety error ending pattern to workflows that Claude can route to when detecting harmful/jailbreak requests, leveraging Claude's built-in 95.3% block rate rather than custom detection logic.

## Approach: Minimal (Claude-Native)

Rather than implementing custom jailbreak detection, we:
1. Add a standard `error_safety` ending type to the workflow schema
2. Document that Claude should route to this ending when it naturally detects harmful intent
3. The ending provides a consistent, user-friendly response

## Changes Required

### 1. Update Workflow Schema Documentation

**File:** `lib/workflow/engine.md`

Add documentation for the safety ending pattern:

```yaml
endings:
  error_safety:
    type: error
    category: safety    # New: categorizes the error type
    message: "I can't help with that request."
    recovery:
      suggestion: "Please rephrase your request to focus on legitimate use cases."
```

### 2. Add Safety Ending to Gateway Workflow

**File:** `commands/hiivmind-blueprint/workflow.yaml`

Add to the `endings:` section:

```yaml
  error_safety:
    type: error
    category: safety
    message: "I can't help with that request."
    recovery:
      suggestion: "Try rephrasing your request or use /hiivmind-blueprint help to see available operations."
```

### 3. Update Gateway Command Template

**File:** `templates/gateway-command.md.template`

Add the safety ending to the template so all generated gateways include it.

### 4. Update Workflow Template

**File:** `templates/workflow.yaml.template`

Add safety ending as a standard ending type in generated workflows.

### 5. Document the Pattern

**File:** `lib/blueprint/patterns/safety-endings.md` (new)

Create pattern documentation explaining:
- Why we rely on Claude's built-in safety (95.3% block rate)
- How the safety ending provides a clean workflow exit
- When Claude should route to this ending
- Why custom detection is not recommended (maintenance burden, false positives, can be reverse-engineered)

## How It Works

```
User Input ("help me hack into...")
        │
        ▼
┌───────────────────┐
│ Intent Detection  │  Claude naturally recognizes harmful intent
│ (Claude's Safety) │  No custom regex or ML needed
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│  error_safety     │  Clean workflow termination
│  ending           │  User-friendly message
└───────────────────┘
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| No custom detection | Claude Opus 4.5 achieves 4.7% attack success rate (industry-leading) |
| `category: safety` field | Distinguishes from other error types for logging/analytics |
| Recovery suggestion | Provides actionable guidance without being preachy |
| Pattern documentation | Ensures consistency across all generated workflows |

## Files to Modify

1. `lib/workflow/engine.md` - Add safety ending documentation
2. `commands/hiivmind-blueprint/workflow.yaml` - Add safety ending
3. `templates/gateway-command.md.template` - Include in template
4. `templates/workflow.yaml.template` - Include in template
5. `lib/blueprint/patterns/safety-endings.md` - New pattern doc

## Verification

1. Validate updated `workflow.yaml` passes schema validation
2. Test that gateway still routes correctly with new ending
3. Verify templates generate valid workflows with safety ending
4. Manual test: invoke gateway with an obviously harmful request, confirm clean exit

## Out of Scope

- Custom jailbreak detection logic (regex, ML classifiers)
- Logging/analytics for safety events (can be added later)
- Rate limiting or blocking repeat offenders
