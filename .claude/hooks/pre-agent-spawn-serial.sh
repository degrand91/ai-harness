#!/usr/bin/env bash
#
# PreToolUse hook — enforces serial execution for subagent spawns.
#
# Three classes of subagent:
#   - explorer / scout        read-only recon. Always allowed, any number at once.
#   - validators              read-only, adversarial: scrutiny-validator,
#                             scrutiny-validator-external, user-testing-validator.
#                             Allowed together (Scrutiny + User-Testing on the
#                             same feature is the one parallelism the feature loop
#                             permits — CLAUDE.md §6), but NOT while a worker is
#                             in flight: they validate a commit, and a worker
#                             moves HEAD.
#   - everything else         a worker (or any writing role). One at a time, and
#                             not while a validator is still reading the tree it
#                             would change.
#
# State file: .claude/hooks/agent-spawn-state.json
#   { in_flight_non_explorer, explorer_count, validator_count, updated_at }
# Stale-lock: if a lock is held but updated_at is >600s ago, reset. The release
# hook normally clears it; staleness only matters after a crash.
#
# Input: JSON on stdin from Claude Code hook system.
#   { "tool_name": "Agent", "tool_input": { "subagent_type": "worker" } }

# NOT `set -e`: a payload this hook cannot parse must fail OPEN. Blocking a
# legitimate spawn because jq hiccuped is worse than the theoretical concurrent
# spawn it would prevent, and an unparseable payload does not occur in practice.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"

# Not an Agent spawn — not our concern.
if [ "$TOOL_NAME" != "Agent" ]; then
  exit 0
fi

SUBAGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"

STATE_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/agent-spawn-state.json"

# ---------------------------------------------------------------------------
# Helper: write state atomically via temp file + mv
# ---------------------------------------------------------------------------
write_state() {
  local in_flight="$1"
  local explorer_count="$2"
  local validator_count="$3"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local tmp
  tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")"
  printf '{"in_flight_non_explorer":%s,"explorer_count":%d,"validator_count":%d,"updated_at":"%s"}\n' \
    "$in_flight" "$explorer_count" "$validator_count" "$now" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# ---------------------------------------------------------------------------
# Read or initialise state
# ---------------------------------------------------------------------------
if [ ! -f "$STATE_FILE" ]; then
  write_state false 0 0
fi

# A corrupt state file is reset rather than inherited: `false`/`0` is the safe
# reading, since it only ever permits a spawn the operator asked for.
IN_FLIGHT="$(jq -r '.in_flight_non_explorer // false' "$STATE_FILE" 2>/dev/null || echo false)"
EXPLORER_COUNT="$(jq -r '.explorer_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
VALIDATOR_COUNT="$(jq -r '.validator_count // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
UPDATED_AT="$(jq -r '.updated_at // empty' "$STATE_FILE" 2>/dev/null || true)"
case "$IN_FLIGHT" in true|false) ;; *) IN_FLIGHT=false ;; esac
case "$EXPLORER_COUNT" in ''|*[!0-9]*) EXPLORER_COUNT=0 ;; esac
case "$VALIDATOR_COUNT" in ''|*[!0-9]*) VALIDATOR_COUNT=0 ;; esac

# ---------------------------------------------------------------------------
# Stale-lock check: reset held locks if updated_at > 600s ago
# ---------------------------------------------------------------------------
if { [ "$IN_FLIGHT" = "true" ] || [ "$VALIDATOR_COUNT" -gt 0 ]; } && [ -n "$UPDATED_AT" ]; then
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
    write_state false "$EXPLORER_COUNT" 0
    IN_FLIGHT=false
    VALIDATOR_COUNT=0
  fi
fi

case "$SUBAGENT_TYPE" in
  explorer|scout)
    # Read-only recon: always allow; just count.
    write_state "$IN_FLIGHT" $(( EXPLORER_COUNT + 1 )) "$VALIDATOR_COUNT"
    exit 0
    ;;
  scrutiny-validator|scrutiny-validator-external|user-testing-validator)
    if [ "$IN_FLIGHT" = "true" ]; then
      printf '[pre-agent-spawn-serial] Refusing to spawn %s while a worker is in flight: validators read a commit, and a worker moves HEAD. Wait for the handoff.\n' "$SUBAGENT_TYPE" >&2
      exit 2
    fi
    write_state "$IN_FLIGHT" "$EXPLORER_COUNT" $(( VALIDATOR_COUNT + 1 ))
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Worker (or any other writing role): enforce the serial rule
# ---------------------------------------------------------------------------
if [ "$IN_FLIGHT" = "true" ]; then
  printf '[pre-agent-spawn-serial] Refusing concurrent non-explorer subagent spawn. Already in-flight non-explorer subagent. Only explorers and validators may run concurrently. See protocols/serial-execution.md.\n' >&2
  exit 2
fi
if [ "$VALIDATOR_COUNT" -gt 0 ]; then
  printf '[pre-agent-spawn-serial] Refusing to spawn %s: %d validator(s) still reading the tree it would change. Wait for their verdicts.\n' "${SUBAGENT_TYPE:-subagent}" "$VALIDATOR_COUNT" >&2
  exit 2
fi

write_state true "$EXPLORER_COUNT" "$VALIDATOR_COUNT"
exit 0
