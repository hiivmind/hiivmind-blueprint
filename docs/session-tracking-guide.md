# Session Tracking Guide

Capture Claude Code session context in workflow logs for full traceability.

## Overview

Session tracking enables:
- **Log correlation:** Link logs to originating Claude Code transcript
- **Invocation ordering:** Know which skill ran first, second, etc.
- **Mid-session checkpoints:** Record critical decisions
- **Post-hoc analysis:** Navigate from log → transcript

## Installation

### Step 1: Copy the Hook Script

```bash
# Create hooks directory
mkdir -p ~/.claude/hooks

# Copy template (adjust path as needed)
cp /path/to/hiivmind-blueprint/templates/hooks/session-capture.sh ~/.claude/hooks/

# Make executable
chmod +x ~/.claude/hooks/session-capture.sh
```

### Step 2: Configure Claude Code

Add to your settings (`~/.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "~/.claude/hooks/session-capture.sh"
    }]
  }
}
```

**Plugin-level alternative** (`.claude-plugin/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-capture.sh"
    }]
  }
}
```

### Step 3: Verify Installation

Start a new Claude Code session and check:

```bash
echo $BLUEPRINT_SESSION_ID
echo $BLUEPRINT_TRANSCRIPT_PATH
```

Both should show values if tracking is active.

## How It Works

### Session Hook

The SessionStart hook:
1. Receives session_id and transcript_path from Claude Code
2. Exports `BLUEPRINT_SESSION_ID` and `BLUEPRINT_TRANSCRIPT_PATH`
3. These are available to all workflows in the session

### Automatic Capture

When `init_log` runs, it automatically captures session context:

```yaml
metadata:
  session:
    id: "608e490e-d5b2-420f-89e0-e64d2e858764"
    transcript_path: "/home/user/.claude/projects/.../608e490e-....jsonl"
    invocation_index: 2   # Second skill in this session
```

No workflow changes needed - it's automatic when the hook is installed.

## Session State File

The `.logs/.session-state.yaml` file tracks the current session:

```yaml
current_session:
  id: "608e490e-d5b2-420f-89e0-e64d2e858764"
  invocation_count: 3
  invocations:
    - index: 1
      skill: "corpus-refresh"
      log_path: ".logs/corpus-refresh-20240124-153000.yaml"
      timestamp: "2024-01-24T15:30:00Z"
    - index: 2
      skill: "my-workflow"
      log_path: ".logs/my-workflow-20240124-153500.yaml"
      timestamp: "2024-01-24T15:35:00Z"
```

### Query Session State

```bash
# What skills ran in current session?
yq '.current_session.invocations[].skill' .logs/.session-state.yaml

# Get all log paths
yq '.current_session.invocations[].log_path' .logs/.session-state.yaml
```

## Mid-Session Snapshots

Use `log_session_snapshot` for critical decision points:

```yaml
- id: confirm_delete
  type: user_prompt
  prompt: "Delete all files?"
  on_response:
    yes:
      consequence:
        - type: log_session_snapshot
          description: "User confirmed file deletion"
          write_intermediate: true
      next_node: perform_deletion
```

### When to Use Snapshots

| Scenario | Use Snapshot |
|----------|--------------|
| Before destructive operations | Yes (`write_intermediate: true`) |
| After user confirmations | Yes |
| Phase boundaries in long workflows | Yes (`write_intermediate: true`) |
| Critical branching decisions | Yes |
| Routine status checks | No |
| Every conditional | No |

### Snapshot Files

With `write_intermediate: true`, checkpoints are saved:

```
.logs/
├── my-skill-20240124-153000.yaml              # Final log
├── my-skill-20240124-153000-snapshot-1.yaml   # First snapshot
├── my-skill-20240124-153000-snapshot-2.yaml   # Second snapshot
```

## Log ↔ Transcript Correlation

### From Log to Transcript

Each log contains the full transcript path:

```yaml
metadata:
  session:
    transcript_path: "/home/user/.claude/projects/proj-abc/608e490e-....jsonl"
```

View the transcript:

```bash
cat /path/to/transcript.jsonl | jq -r '.content'
```

### From Transcript to Logs

```bash
SESSION_ID="608e490e-d5b2-420f-89e0-e64d2e858764"
grep -l "id: $SESSION_ID" .logs/*.yaml
```

## Troubleshooting

### Environment Variables Not Set

**Check:**
```bash
# Test hook manually
echo '{"session_id": "test", "transcript_path": "/tmp/test.jsonl"}' | ~/.claude/hooks/session-capture.sh

# Verify jq is available
which jq
```

**Common causes:**
- Hook not in settings.json
- Script not executable
- Missing `jq` dependency

### Invocation Index Always 1

**Causes:**
- Hook not capturing session ID
- Each workflow is a new session (intended behavior if separate sessions)

**Debug:**
```bash
cat .logs/.session-state.yaml
```

### Session State File Missing

Run any workflow with logging enabled to create it.

## Best Practices

1. **Install at user level:** Consistent tracking across all projects
2. **Use snapshots sparingly:** Only for significant moments
3. **Include context:** Make snapshot descriptions self-explanatory
4. **Gitignore logs:** Add `.logs/` to `.gitignore`

## Next Steps

- [Logging Reference](logging-reference.md) - Full logging configuration
- [Workflow Authoring Guide](workflow-authoring-guide.md) - Node types
