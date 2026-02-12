#!/bin/bash
# session-capture.sh
#
# SessionStart hook for capturing Claude Code session context.
# Enables blueprint logging to link workflow logs to conversation transcripts.
#
# Installation:
#   1. Copy this file to a stable location (e.g., ~/.claude/hooks/)
#   2. Add to ~/.claude/settings.json or plugin's settings.json:
#      {
#        "hooks": {
#          "SessionStart": [{
#            "type": "command",
#            "command": "/path/to/session-capture.sh"
#          }]
#        }
#      }
#
# What it does:
#   - Reads session_id and transcript_path from hook input (JSON on stdin)
#   - Exports them as environment variables via CLAUDE_ENV_FILE
#   - Variables persist for the entire Claude Code session
#
# Environment variables exported:
#   - BLUEPRINT_SESSION_ID: UUID of current Claude Code session
#   - BLUEPRINT_TRANSCRIPT_PATH: Full path to conversation .jsonl file
#
# Usage in workflows:
#   The init_log consequence automatically reads these variables when available.
#   No workflow changes needed - session tracking is opt-in via hook installation.

set -euo pipefail

# Read hook input from stdin
INPUT=$(cat)

# Extract session info using jq
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Export to session environment if CLAUDE_ENV_FILE is set
if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  # Only export if we got valid values
  if [[ -n "$SESSION_ID" ]]; then
    echo "export BLUEPRINT_SESSION_ID='$SESSION_ID'" >> "$CLAUDE_ENV_FILE"
  fi

  if [[ -n "$TRANSCRIPT_PATH" ]]; then
    echo "export BLUEPRINT_TRANSCRIPT_PATH='$TRANSCRIPT_PATH'" >> "$CLAUDE_ENV_FILE"
  fi
fi

# Hook should exit 0 to indicate success
exit 0
