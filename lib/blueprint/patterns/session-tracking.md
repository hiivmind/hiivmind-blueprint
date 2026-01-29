# Session Tracking Pattern

Capture Claude Code session context in workflow logs for traceability between workflow outcomes and conversation transcripts.

---

## Architecture

```
Claude Code Session (session_id, transcript_path)
        │
        ▼
SessionStart Hook (session-capture.sh)
  Exports: BLUEPRINT_SESSION_ID, BLUEPRINT_TRANSCRIPT_PATH
        │
        ▼
Workflow Execution
  ├── Skill A (index: 1) → Log A
  ├── Skill B (index: 2) → Log B
  └── Skill C (index: 3) → Log C
        │
        ▼
.logs/.session-state.yaml (tracks current session invocations)
```

---

## Session Metadata in Logs

When the hook is installed, `init_log` automatically captures:

```yaml
metadata:
  session:
    id: "608e490e-d5b2-420f-89e0-e64d2e858764"
    transcript_path: "/home/user/.claude/projects/.../608e490e-....jsonl"
    invocation_index: 2   # Second skill in this session
    snapshot_points: []
```

---

## Mid-Session Snapshots

Use `log_session_snapshot` at critical decision points:

```yaml
- type: log_session_snapshot
  description: "User confirmed file deletion"
  write_intermediate: true  # Save log checkpoint
```

**When to use:**
- Before destructive operations
- After user confirmations
- At phase boundaries in long workflows

---

## Session State File

`.logs/.session-state.yaml` tracks current session:

```yaml
current_session:
  id: "608e490e-d5b2-420f-89e0-e64d2e858764"
  invocation_count: 3
  invocations:
    - index: 1
      skill: "corpus-refresh"
      log_path: ".logs/corpus-refresh-20240124-153000.yaml"
    - index: 2
      skill: "my-workflow"
      log_path: ".logs/my-workflow-20240124-153500.yaml"
```

---

## Log ↔ Transcript Correlation

**Log to transcript:** Each log contains `session.transcript_path`

**Transcript to logs:**
```bash
SESSION_ID="608e490e-d5b2-420f-89e0-e64d2e858764"
grep -l "id: $SESSION_ID" .logs/*.yaml
```

---

## Installation

See `docs/session-tracking-guide.md` for:
- Hook script setup
- Claude Code settings configuration
- Troubleshooting

---

## Related Documentation

- **Hook Template:** `templates/hooks/session-capture.sh`
- **Logging Configuration:** `lib/blueprint/patterns/logging-configuration.md`
