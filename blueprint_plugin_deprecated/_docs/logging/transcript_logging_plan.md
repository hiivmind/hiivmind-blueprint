# Plan: Add Session Tracking to Blueprint Logging

## Goal

Enhance the blueprint logging system to capture Claude Code session context, enabling:
- Linking workflow logs to the Claude transcript that executed them
- Mid-session log updates at critical decision points
- Full traceability between workflow outcomes and the conversation that produced them

---

## Research Findings

### How Claude Code Exposes Session Info

Session data is **only accessible via hooks**. A `SessionStart` hook receives:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/.claude/projects/.../uuid.jsonl",
  "cwd": "/path/to/project",
  "permission_mode": "default",
  "hook_event_name": "SessionStart"
}
```

**Key insight:** Using `CLAUDE_ENV_FILE`, hooks can export environment variables that persist for the entire session:
- `$SESSION_ID` - UUID of current session
- `$TRANSCRIPT_PATH` - Full path to `.jsonl` transcript file

---

## Design

### Enhanced Log Schema

Add session tracking to `metadata`:

```yaml
metadata:
  workflow_name: string
  workflow_version: string
  skill_name: string | null
  plugin_name: string | null
  execution_path: string

  # NEW: Session tracking
  session:
    id: string | null           # Claude Code session UUID
    transcript_path: string | null  # Path to conversation .jsonl
    invocation_index: number    # Which skill invocation in this session (1-based)
    snapshot_points: []          # Mid-session snapshot markers
```

### Invocation Tracking

To track invocation order across multiple skill calls in one session:

**Session state file:** `.logs/.session-state.yaml`

```yaml
# Created/updated by init_log
current_session:
  id: "608e490e-d5b2-420f-89e0-e64d2e858764"
  invocation_count: 3
  invocations:
    - index: 1
      skill: "skill-a"
      log_path: ".logs/skill-a-20240124-153000.yaml"
      timestamp: "2024-01-24T15:30:00Z"
    - index: 2
      skill: "skill-b"
      log_path: ".logs/skill-b-20240124-153500.yaml"
      timestamp: "2024-01-24T15:35:00Z"
    - index: 3
      skill: "skill-a"
      log_path: ".logs/skill-a-20240124-154000.yaml"
      timestamp: "2024-01-24T15:40:00Z"
```

**Behavior:**
1. `init_log` reads `.logs/.session-state.yaml`
2. If `current_session.id` matches `$BLUEPRINT_SESSION_ID`: increment `invocation_count`
3. If different session ID: reset state for new session
4. Record this invocation in the list
5. Set `session.invocation_index` in current log

### Snapshot Points (Mid-Session Updates)

For critical decision points, workflows can record snapshots:

```yaml
snapshot_points:
  - timestamp: ISO8601
    node: string              # Node that triggered snapshot
    description: string       # What decision was made
    log_path: string          # Path to log at that point (if written)
```

### New Consequence: `log_session_snapshot`

```yaml
- type: log_session_snapshot
  description: "User confirmed destructive operation"
  write_intermediate: true  # Optional: write log to file at this point
```

**Effect:**
1. Records current state to `snapshot_points`
2. If `write_intermediate: true`, writes current log to `.logs/{skill}-{timestamp}-snapshot-{n}.yaml`
3. Useful for long-running workflows where you want checkpoints

---

## Implementation

### Phase 1: Create SessionStart Hook Template

**File:** `templates/hooks/session-capture.sh`

```bash
#!/bin/bash
# Capture session context for blueprint logging
# Install in: ~/.claude/settings.json or plugin settings.json

# Read hook input
INPUT=$(cat)

# Extract session info
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')

# Export to session environment
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "export BLUEPRINT_SESSION_ID='$SESSION_ID'" >> "$CLAUDE_ENV_FILE"
  echo "export BLUEPRINT_TRANSCRIPT_PATH='$TRANSCRIPT_PATH'" >> "$CLAUDE_ENV_FILE"
fi
```

### Phase 2: Update Logging Schema

**File:** `lib/workflow/logging-schema.md`

Add `session` field to metadata section with documentation.

### Phase 3: Update init_log Consequence

**File:** `lib/workflow/consequences/extensions/logging.md`

Modify `init_log` to capture session context:

```yaml
- type: init_log
  workflow_name: "${workflow.id}"
  # Session info auto-captured from environment if available
```

**Effect update:**
```
# Read or initialize session state
session_state_path = ".logs/.session-state.yaml"
session_state = read_yaml(session_state_path) ?? { current_session: null }

current_id = env.BLUEPRINT_SESSION_ID
if session_state.current_session?.id != current_id:
  # New session - reset state
  session_state.current_session = {
    id: current_id,
    invocation_count: 0,
    invocations: []
  }

# Increment and record
session_state.current_session.invocation_count += 1
index = session_state.current_session.invocation_count

session_state.current_session.invocations.push({
  index: index,
  skill: skill_name,
  log_path: computed_log_path,
  timestamp: now_iso8601()
})

write_yaml(session_state_path, session_state)

# Set in log metadata
state.log.metadata.session = {
  id: current_id ?? null,
  transcript_path: env.BLUEPRINT_TRANSCRIPT_PATH ?? null,
  invocation_index: index,
  snapshot_points: []
}
```

### Phase 4: Add log_session_snapshot Consequence

**File:** `lib/workflow/consequences/extensions/logging.md` (append)

New consequence for mid-session logging.

### Phase 5: Document Hook Setup Pattern

**File:** `lib/blueprint/patterns/session-tracking.md`

Document:
- How to install the SessionStart hook
- When to use snapshot points
- How to correlate logs with transcripts

---

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `templates/hooks/session-capture.sh` | CREATE | Hook script template |
| `lib/workflow/logging-schema.md` | MODIFY | Add session metadata field, document session state file |
| `lib/workflow/consequences/extensions/logging.md` | MODIFY | Update init_log with invocation tracking, add log_session_snapshot |
| `lib/blueprint/patterns/session-tracking.md` | CREATE | Setup and usage documentation |

**Runtime artifact:** `.logs/.session-state.yaml` - Created/maintained by init_log to track invocations across a session

---

## Usage Examples

### Basic Session Tracking

```yaml
# Automatic if hook is installed - no workflow changes needed
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

### Mid-Session Snapshots

```yaml
- id: confirm_destructive
  type: user-prompt
  prompt: "This will delete all files. Continue?"
  consequences:
    - type: log_session_snapshot
      description: "User confirmed file deletion"
      write_intermediate: true

- id: perform_deletion
  type: action
  # ... dangerous operation
```

### Correlating Logs to Transcripts

After execution, the log contains:
```yaml
metadata:
  workflow_name: my-workflow
  session:
    id: "608e490e-d5b2-420f-89e0-e64d2e858764"
    transcript_path: "/home/user/.claude/projects/.../608e490e-....jsonl"
    invocation_index: 2   # This was the 2nd skill called in this session
    snapshot_points:
      - timestamp: "2024-01-24T15:30:00Z"
        node: "confirm_destructive"
        description: "User confirmed file deletion"
```

### Session State File

The `.logs/.session-state.yaml` provides a session-level view:
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

This enables queries like:
- "What skills ran in this session?" → Read session state
- "Show me all logs from session X" → Filter by session.id
- "What was the sequence of operations?" → Order by invocation_index

---

## Verification

1. **Hook installation test**: Verify `$BLUEPRINT_SESSION_ID` and `$BLUEPRINT_TRANSCRIPT_PATH` are set after session start
2. **Log capture test**: Run workflow, verify session metadata in log including invocation_index
3. **Multi-invocation test**: Call 3 skills in sequence, verify:
   - All logs have same session.id
   - invocation_index increments (1, 2, 3)
   - `.logs/.session-state.yaml` contains all 3 invocations
4. **Session rollover test**: Start new session, verify invocation_index resets to 1
5. **Snapshot test**: Test `log_session_snapshot` writes intermediate logs
6. **Correlation test**: Can navigate from log → transcript using recorded path

---

## Alternative Considered: Real-Time Transcript Access

Could the workflow read the transcript file mid-session?

**Yes, but with caveats:**
- Transcript is appended in real-time as conversation progresses
- Could `tail -f` or read latest entries
- But reading your own transcript feels recursive/fragile

**Recommendation:** Record transcript path in log metadata, let humans correlate afterward. Don't try to parse transcript during execution.
