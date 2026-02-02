# Safety Endings Pattern

Standard pattern for handling requests that Claude's built-in safety identifies as harmful.

---

## Design Philosophy

This pattern leverages Claude's native safety mechanisms rather than implementing custom jailbreak detection:

| Approach | Block Rate | Maintenance | False Positives |
|----------|------------|-------------|-----------------|
| Claude's built-in safety | ~95.3% | Zero | Low |
| Custom regex patterns | Variable | High | High |
| ML-based detection | Variable | High | Medium |

**Decision:** Rely on Claude's continuously-updated safety training rather than fragile, reverse-engineerable custom logic.

---

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

When Claude detects a request it cannot fulfill for safety reasons, it should route to the `error_safety` ending. This provides:

1. **Clean workflow exit** - Proper termination vs. mid-workflow refusal
2. **Consistent messaging** - Same tone across all skills
3. **Recovery guidance** - Actionable next steps without being preachy
4. **Logging/analytics** - The `category: safety` field enables tracking

---

## Ending Schema

```yaml
endings:
  error_safety:
    type: error
    category: safety           # Distinguishes from other error types
    message: "I can't help with that request."
    recovery:
      suggestion: "Please rephrase your request to focus on legitimate use cases."
```

### Field Reference

| Field | Purpose |
|-------|---------|
| `type: error` | Standard error ending type |
| `category: safety` | Classification for logging/analytics |
| `message` | Brief, non-judgmental refusal |
| `recovery.suggestion` | Actionable guidance |

---

## When Claude Routes to Safety Ending

Claude's training includes extensive safety alignment. The workflow should route to `error_safety` when Claude would naturally refuse, including:

- Requests for harmful code (malware, exploits)
- Social engineering assistance
- Privacy violations
- Generating harmful content
- Jailbreak attempts

**Note:** Claude makes this determination based on its training, not workflow logic. The ending merely provides a clean exit path.

---

## Why Not Custom Detection?

Custom jailbreak detection has significant drawbacks:

| Issue | Problem |
|-------|---------|
| **Maintenance burden** | Attack patterns evolve constantly |
| **False positives** | Legitimate security research blocked |
| **Reverse engineering** | Published patterns become bypass guides |
| **Brittleness** | Regex/keyword matching easily circumvented |
| **Redundancy** | Duplicates Claude's existing safety layer |

Claude's safety is:
- Continuously updated by Anthropic
- Trained on diverse attack patterns
- Context-aware (not just keyword matching)
- Tested against red-team attacks

---

## Implementation in Workflows

### Gateway Workflows

Gateways should include the safety ending. No explicit routing is needed—Claude will route there when appropriate:

```yaml
# In workflow.yaml
endings:
  success:
    type: success
    message: "Request completed"

  error_safety:
    type: error
    category: safety
    message: "I can't help with that request."
    recovery:
      suggestion: "Try rephrasing your request or use /{{plugin_name}} help."
```

### Individual Skills

Skills that perform sensitive operations (file system, network, code execution) may include the safety ending as a clean exit:

```yaml
endings:
  success:
    type: success
    message: "Operation completed"

  error_safety:
    type: error
    category: safety
    message: "I can't help with that request."
    recovery:
      suggestion: "This skill is designed for legitimate {{domain}} operations."
```

---

## Tone Guidelines

The safety message should be:

| Do | Don't |
|----|-------|
| Brief and direct | Lecture or moralize |
| Non-judgmental | Accuse the user |
| Offer alternatives | Simply refuse |
| Use consistent wording | Vary message per skill |

**Standard message:** "I can't help with that request."

This phrasing:
- Doesn't assume intent
- Doesn't explain why (which could inform bypasses)
- Matches Claude's natural refusal style

---

## Analytics and Logging

The `category: safety` field enables downstream analysis:

```yaml
# Example log entry
{
  "workflow": "my-skill",
  "ending": "error_safety",
  "ending_type": "error",
  "ending_category": "safety",
  "timestamp": "2026-01-29T10:30:00Z"
}
```

This allows:
- Tracking safety event frequency
- Identifying workflows receiving more harmful requests
- Measuring safety endpoint effectiveness

**Note:** Input content should NOT be logged for safety events to avoid storing potentially harmful text.

---

## Testing

Safety endings should be tested to ensure proper workflow termination:

```yaml
# Test: Safety ending exists and has correct structure
- description: "Safety ending is properly configured"
  assertions:
    - endings.error_safety.type == "error"
    - endings.error_safety.category == "safety"
    - endings.error_safety.message != null
    - endings.error_safety.recovery.suggestion != null
```

**Do not test with actual harmful inputs.** The goal is verifying the ending structure, not triggering Claude's safety.

---

## Related Documentation

- **Engine Reference:** `lib/workflow/engine.md` - Ending schema and categories
- **Workflow Template:** `templates/workflow.yaml.template` - Standard endings
- **Gateway Template:** `templates/gateway-command.md.template` - Gateway safety section
