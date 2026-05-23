#!/usr/bin/env bash
#
# PostToolUse hook for Write/Edit. If the edited file lives inside a
# missions/<id>/ folder (anywhere except the mission's own log.md), append a
# one-line entry to that mission's log.md. Idempotent enough — duplicate
# entries on rapid rewrites are acceptable noise.
#
# Input: JSON on stdin with .tool_input.file_path.

set -euo pipefail

INPUT="$(cat)"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
[ -z "$FILE_PATH" ] && exit 0

# Only react inside the harness's missions/ tree.
case "$FILE_PATH" in
  *"/harness/missions/"*) ;;
  *) exit 0 ;;
esac

# Derive mission id (first segment after /missions/).
MISSION_ID="$(printf '%s' "$FILE_PATH" | sed -E 's@.*/harness/missions/([^/]+)/.*@\1@')"
[ -z "$MISSION_ID" ] && exit 0

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-/Users/stefanodegrandis/projects/ai/harness}"
LOG_FILE="${HARNESS_ROOT}/missions/${MISSION_ID}/log.md"

# Don't recursively log log.md edits.
case "$FILE_PATH" in
  "$LOG_FILE") exit 0 ;;
esac

[ ! -f "$LOG_FILE" ] && exit 0

# Compute a short relative path for the log line.
REL="${FILE_PATH#${HARNESS_ROOT}/missions/${MISSION_ID}/}"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SESSION="${CLAUDE_SESSION_ID:-unknown}"
printf '[%s] [session=%s] state mutation — %s edited\n' "$NOW" "$SESSION" "$REL" >> "$LOG_FILE"

exit 0
