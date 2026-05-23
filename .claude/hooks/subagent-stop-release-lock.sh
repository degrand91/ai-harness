#!/usr/bin/env bash
#
# SubagentStop hook — releases the serial-spawn lock when a subagent finishes.
#
# - Non-explorer subagents: clears in_flight_non_explorer → false.
# - Explorer subagents: decrements explorer_count (floor at 0).
#
# Always exits 0 (non-blocking).

set -euo pipefail

INPUT="$(cat)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)"

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/agent-spawn-state.json"

# If state file doesn't exist there's nothing to release.
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

IN_FLIGHT="$(jq -r '.in_flight_non_explorer' "$STATE_FILE")"
EXPLORER_COUNT="$(jq -r '.explorer_count' "$STATE_FILE")"

# ---------------------------------------------------------------------------
# Helper: write state atomically via temp file + mv
# ---------------------------------------------------------------------------
write_state() {
  local in_flight="$1"
  local explorer_count="$2"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  printf '{"in_flight_non_explorer":%s,"explorer_count":%d,"updated_at":"%s"}\n' \
    "$in_flight" "$explorer_count" "$now" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

if [ "$AGENT_TYPE" = "explorer" ]; then
  # Decrement explorer_count, floor at 0
  NEW_COUNT=$(( EXPLORER_COUNT > 0 ? EXPLORER_COUNT - 1 : 0 ))
  write_state "$IN_FLIGHT" "$NEW_COUNT"
else
  # Non-explorer (or unknown): release the non-explorer lock
  write_state false "$EXPLORER_COUNT"
fi

exit 0
