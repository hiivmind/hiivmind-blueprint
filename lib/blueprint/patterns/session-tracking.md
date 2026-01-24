# Session Tracking Pattern

Capture Claude Code session context in workflow logs for full traceability between workflow outcomes and the conversation that produced them.

---

## Overview

Session tracking enables:
- **Log correlation:** Link workflow logs to their originating Claude Code transcript
- **Invocation ordering:** Know which skill ran first, second, etc. in a session
- **Mid-session checkpoints:** Record critical decisions with optional intermediate logs
- **Post-hoc analysis:** Navigate from log → transcript to understand why decisions were made

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Claude Code Session                        │
│                    (session_id, transcript_path)                │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
              ┌─────────────────────────────┐
              │   SessionStart Hook         │
              │   (session-capture.sh)      │
              │                             │
              │   Exports:                  │
              │   • BLUEPRINT_SESSION_ID    │
              │   • BLUEPRINT_TRANSCRIPT_PATH│
              └───────────────┬─────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                         Workflow Execution                       │
│                                                                  │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐        │
│  │  Skill A    │     │  Skill B    │     │  Skill C    │        │
│  │  index: 1   │────▶│  index: 2   │────▶│  index: 3   │        │
│  └──────┬──────┘     └──────┬──────┘     └──────┬──────┘        │
│         │                   │                   │                │
│         ▼                   ▼                   ▼                │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐        │
│  │   Log A     │     │   Log B     │     │   Log C     │        │
│  │ session.id  │     │ session.id  │     │ session.id  │        │
│  │ index: 1    │     │ index: 2    │     │ index: 3    │        │
│  └─────────────┘     └─────────────┘     └─────────────┘        │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │  .logs/.session-state.yaml                                   ││
│  │  current_session:                                            ││
│  │    id: "608e490e..."                                         ││
│  │    invocation_count: 3                                       ││
│  │    invocations: [skill-a, skill-b, skill-c]                  ││
│  └──────────────────────────────────────────────────────────────┘│
└──────────────────────────────────────────────────────────────────┘
```

---

## Installation

### Step 1: Copy the Hook Script

Copy the template to a stable location:

```bash
# Create hooks directory
mkdir -p ~/.claude/hooks

# Copy template
cp templates/hooks/session-capture.sh ~/.claude/hooks/

# Verify it's executable
chmod +x ~/.claude/hooks/session-capture.sh
```

### Step 2: Configure Claude Code

Add the hook to your settings:

**User-level** (`~/.claude/settings.json`):
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

**Plugin-level** (`.claude-plugin/settings.json`):
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

Start a new Claude Code session and verify the environment variables are set:

```bash
# In Claude Code, check environment
echo $BLUEPRINT_SESSION_ID
echo $BLUEPRINT_TRANSCRIPT_PATH
```

If both variables show values, session tracking is active.

---

## Usage

### Basic Session Tracking

No workflow changes needed. When the hook is installed, `init_log` automatically captures session context:

```yaml
# This workflow automatically gets session tracking
phases:
  - id: init
    nodes:
      - id: start
        type: action
        consequences:
          - type: init_log
            workflow_name: "my-workflow"
            # session.id and session.transcript_path auto-populated
```

The resulting log contains:

```yaml
metadata:
  workflow_name: my-workflow
  session:
    id: "608e490e-d5b2-420f-89e0-e64d2e858764"
    transcript_path: "/home/user/.claude/projects/.../608e490e-....jsonl"
    invocation_index: 2   # Second skill called in this session
    snapshot_points: []
```

### Mid-Session Snapshots

Use `log_session_snapshot` at critical decision points:

```yaml
- id: confirm_destructive
  type: user-prompt
  prompt: "This will delete all files. Continue?"
  consequences:
    - type: log_session_snapshot
      description: "User confirmed file deletion"
      write_intermediate: true  # Save log checkpoint

- id: perform_deletion
  type: action
  # ... dangerous operation
```

This creates:
1. A snapshot entry in `session.snapshot_points`
2. An intermediate log file (if `write_intermediate: true`)

### Querying Session State

The `.logs/.session-state.yaml` file provides session-level visibility:

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
    - index: 3
      skill: "corpus-enhance"
      log_path: ".logs/corpus-enhance-20240124-154000.yaml"
      timestamp: "2024-01-24T15:40:00Z"
```

**Common queries:**

```bash
# What skills ran in current session?
yq '.current_session.invocations[].skill' .logs/.session-state.yaml

# Get all log paths from session
yq '.current_session.invocations[].log_path' .logs/.session-state.yaml

# Find logs from a specific session ID
grep -l "id: 608e490e" .logs/*.yaml
```

---

## Correlating Logs to Transcripts

### From Log to Transcript

Each log contains the full transcript path:

```yaml
# In workflow log
metadata:
  session:
    transcript_path: "/home/user/.claude/projects/proj-abc/608e490e-d5b2-420f-89e0-e64d2e858764.jsonl"
```

Read the transcript to see the full conversation:

```bash
# View transcript (JSON lines format)
cat /home/user/.claude/projects/proj-abc/608e490e-...jsonl | jq -r '.content'
```

### From Transcript to Logs

If you have a transcript and want to find associated logs:

```bash
# Extract session ID from transcript filename
SESSION_ID="608e490e-d5b2-420f-89e0-e64d2e858764"

# Find all logs from this session
grep -l "id: $SESSION_ID" .logs/*.yaml
```

---

## Snapshot Points

### When to Use Snapshots

1. **Before destructive operations:**
   ```yaml
   - type: log_session_snapshot
     description: "About to delete ${computed.file_count} files"
     write_intermediate: true  # Preserve state before deletion
   ```

2. **After user confirmations:**
   ```yaml
   - type: log_session_snapshot
     description: "User confirmed: ${computed.user_choice}"
   ```

3. **At phase boundaries in long workflows:**
   ```yaml
   - type: log_session_snapshot
     description: "Phase 2 complete: indexed ${computed.count} entries"
     write_intermediate: true
   ```

4. **When branching on critical decisions:**
   ```yaml
   - type: log_session_snapshot
     description: "Selected strategy: ${computed.strategy}"
   ```

### Snapshot File Naming

When `write_intermediate: true`, intermediate logs are written with snapshot numbering:

```
.logs/
├── my-skill-20240124-153000.yaml              # Final log
├── my-skill-20240124-153000-snapshot-1.yaml   # First snapshot
├── my-skill-20240124-153000-snapshot-2.yaml   # Second snapshot
└── ...
```

### Analyzing Snapshots

The final log contains all snapshot metadata:

```yaml
metadata:
  session:
    snapshot_points:
      - timestamp: "2024-01-24T15:30:15Z"
        node: "confirm_delete"
        description: "User confirmed file deletion"
        log_path: ".logs/my-skill-20240124-153000-snapshot-1.yaml"

      - timestamp: "2024-01-24T15:30:45Z"
        node: "phase_complete"
        description: "Phase 1 complete: 50 files processed"
        log_path: ".logs/my-skill-20240124-153000-snapshot-2.yaml"
```

---

## Best Practices

### 1. Install Hook at User Level

For consistent tracking across all projects:

```json
// ~/.claude/settings.json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "~/.claude/hooks/session-capture.sh"
    }]
  }
}
```

### 2. Use Snapshots Sparingly

Snapshots are for significant moments, not every node:

**Good:**
- User confirmations
- Before destructive operations
- Major phase completions

**Avoid:**
- Every conditional branch
- Minor status checks
- Routine operations

### 3. Include Context in Descriptions

Make snapshot descriptions self-explanatory:

```yaml
# Good - includes relevant context
- type: log_session_snapshot
  description: "User chose 'force' mode for ${computed.file_count} files"

# Bad - lacks context
- type: log_session_snapshot
  description: "User confirmed"
```

### 4. Retention for Session State

The `.logs/.session-state.yaml` file resets on new sessions. It only tracks the current session. Historical session data is preserved in individual log files via `session.id`.

---

## Troubleshooting

### Environment Variables Not Set

**Symptom:** `$BLUEPRINT_SESSION_ID` is empty

**Causes:**
1. Hook not installed in settings.json
2. Script not executable
3. Script errors (check stderr)
4. `jq` not installed

**Debug:**
```bash
# Test hook manually
echo '{"session_id": "test", "transcript_path": "/tmp/test.jsonl"}' | ~/.claude/hooks/session-capture.sh

# Check if jq is available
which jq
```

### Session State File Missing

**Symptom:** `.logs/.session-state.yaml` doesn't exist

**Cause:** No workflow with logging has run yet in this project

**Solution:** Run any workflow with `init_log` consequence

### Invocation Index Always 1

**Symptom:** All logs show `invocation_index: 1`

**Causes:**
1. Hook not capturing session ID (variables empty)
2. Each workflow run is a new Claude Code session

**Debug:**
```bash
# Check if session ID is being captured
cat .logs/.session-state.yaml
```

---

## Related Documentation

- **Hook Template:** `templates/hooks/session-capture.sh`
- **Logging Schema:** `lib/workflow/logging-schema.md`
- **Logging Consequences:** `lib/workflow/consequences/extensions/logging.md`
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md`
