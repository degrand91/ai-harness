#!/usr/bin/env bash
#
# PreToolUse hook — enforces serial execution for non-explorer subagent spawns.
#
# Rules:
#   - Non-Agent tool calls: always pass through (exit 0).
#   - Explorer subagents: always pass through (exit 0); increment explorer_count.
#   - Non-explorer subagents: allowed only if in_flight_non_explorer is false;
#     otherwise blocked (exit 2).
#
# State file: .claude/hooks/agent-spawn-state.json
# Stale-lock: if in_flight_non_explorer=true but updated_at is >600s ago, reset.
#
# Input: JSON on stdin from Claude Code hook system.
#   { "tool_name": "Agent", "tool_input": { "subagent_type": "worker" } }

set -euo pipefail

INPUT="$(cat)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"

# Not an Agent spawn — not our concern.
if [ "$TOOL_NAME" != "Agent" ]; then
  exit 0
fi

SUBAGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)"

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/agent-spawn-state.json"

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

# ---------------------------------------------------------------------------
# Read or initialise state
# ---------------------------------------------------------------------------
if [ ! -f "$STATE_FILE" ]; then
  write_state false 0
fi

IN_FLIGHT="$(jq -r '.in_flight_non_explorer' "$STATE_FILE")"
EXPLORER_COUNT="$(jq -r '.explorer_count' "$STATE_FILE")"
UPDATED_AT="$(jq -r '.updated_at // empty' "$STATE_FILE")"

# ---------------------------------------------------------------------------
# Stale-lock check: reset if in_flight but updated_at > 600s ago
# ---------------------------------------------------------------------------
if [ "$IN_FLIGHT" = "true" ] && [ -n "$UPDATED_AT" ]; then
  NOW_EPOCH="$(date -u +%s)"
  # 'date -d' works on Linux; on macOS use 'date -jf' with TZ=UTC to avoid
  # timezone skew (the timestamp is always UTC but macOS parses it as local time
  # without TZ=UTC, producing an epoch that is offset by the local UTC delta).
  if date -d "$UPDATED_AT" +%s &>/dev/null 2>&1; then
    UPDATED_EPOCH="$(date -d "$UPDATED_AT" +%s)"
  else
    UPDATED_EPOCH="$(TZ=UTC date -jf '%Y-%m-%dT%H:%M:%SZ' "$UPDATED_AT" +%s 2>/dev/null || echo "$NOW_EPOCH")"
  fi
  AGE=$(( NOW_EPOCH - UPDATED_EPOCH ))
  if [ "$AGE" -gt 600 ]; then
    write_state false "$EXPLORER_COUNT"
    IN_FLIGHT=false
  fi
fi

# ---------------------------------------------------------------------------
# Explorer: always allow; just increment counter
# ---------------------------------------------------------------------------
if [ "$SUBAGENT_TYPE" = "explorer" ]; then
  NEW_COUNT=$(( EXPLORER_COUNT + 1 ))
  write_state "$IN_FLIGHT" "$NEW_COUNT"
  exit 0
fi

# ---------------------------------------------------------------------------
# Non-explorer: enforce serial rule
# ---------------------------------------------------------------------------
if [ "$IN_FLIGHT" = "true" ]; then
  printf '[pre-agent-spawn-serial] Refusing concurrent non-explorer subagent spawn. Already in-flight non-explorer subagent. Only '\''explorer'\'' subagents may run concurrently. See protocols/parallel-exploration.md.\n' >&2
  exit 2
fi

# Non-explorer, none in-flight: allow and lock
write_state true "$EXPLORER_COUNT"
exit 0
