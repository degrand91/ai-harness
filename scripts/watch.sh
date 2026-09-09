#!/usr/bin/env bash
# watch.sh - park on fleet state and report the first thing worth waking for.
#
# Usage: watch.sh [--once]
#
# Called by .claude/hooks/stop-watch-rearm.sh in the FOREGROUND of that hook's
# process tree (never with `&`), so Claude's teardown kills the loop with the
# hook. Prints ONE line to stdout naming the wake reason, or nothing.
#
# Exit: 0 = nothing to wake for (parked to the cap, or told to stand down)
#       2 = wake, reason on stdout
#
# WHAT IT WAKES FOR, in priority order:
#   1. a crewmate reached a terminal or blocked ledger line
#   2. a crewmate has been silent past the stall threshold
#   3. the loop has an agent-owned next action and nobody is blocking it
#
# WHAT IT NEVER WAKES FOR:
#   - a blocking decision is open: the captain owns it, and waking to do more
#     work is the wrong move
#   - the mission is `paused`: the captain asked to take over
#   - away mode is active: the AFK daemon owns the watcher
#   - state/.watch-off exists: the kill switch
#
# Tuning: HARNESS_WATCH_POLL (30) HARNESS_WATCH_GRACE (300)
#         HARNESS_STALL_SECONDS (1200) HARNESS_MAX_PARK (28800)
#         HARNESS_LOOP_ACTIVE_SECONDS (86400)

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
STATE="$HARNESS_ROOT/state"
MISSIONS="$HARNESS_ROOT/missions"

# shellcheck source=lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh"
# shellcheck source=lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"
# shellcheck source=lib/holds.sh
. "$CODE_ROOT/scripts/lib/holds.sh"

POLL="${HARNESS_WATCH_POLL:-30}"
GRACE="${HARNESS_WATCH_GRACE:-300}"
STALL="${HARNESS_STALL_SECONDS:-1200}"
MAX_PARK="${HARNESS_MAX_PARK:-28800}"
# HARNESS_WATCH_ONCE bounds the loop to a single pass. The rearm hook invokes
# this without --once (parking is the whole point in production), so the test
# suite needs a way to bound it from the environment — the same affordance as
# HARNESS_CREW_BACKEND=fake.
ONCE="${HARNESS_WATCH_ONCE:-0}"
[ "${1:-}" = "--once" ] && ONCE=1
case "$ONCE" in ''|*[!0-9]*) ONCE=0 ;; esac

stand_down() { [ -f "$STATE/.watch-off" ] || [ -f "$STATE/.afk" ]; }

# Is any mission blocked on the captain right now?
blocking_hold_open() {
  local md
  for md in "$MISSIONS"/*/; do
    [ -d "$md" ] || continue
    [ "$(holds_count_blocking "${md%/}")" -gt 0 ] 2>/dev/null && return 0
  done
  return 1
}

# First crewmate whose ledger says something the supervisor must act on.
crew_event() {
  local t last
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    last="$(crew_ledger_last "$HARNESS_ROOT" "$t")"
    case "$last" in
      done|failed|blocked)
        printf '%s %s %s' "$t" "$last" "$(crew_ledger_note "$HARNESS_ROOT" "$t")"
        return 0 ;;
    esac
  done < <(crew_list "$HARNESS_ROOT")
  return 1
}

# A crewmate that is alive but has written nothing for too long.
crew_stalled() {
  local t pid age lf now; now="$(date -u +%s)"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    crew_is_terminal "$HARNESS_ROOT" "$t" && continue
    pid="$(crew_meta_get "$HARNESS_ROOT" "$t" runner_pid 2>/dev/null || true)"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue
    lf="$STATE/$t.ledger"
    [ -f "$lf" ] || continue
    age=$(( now - $(file_mtime_epoch "$lf") ))
    if [ "$age" -gt "$STALL" ]; then printf '%s %s' "$t" "$age"; return 0; fi
  done < <(crew_list "$HARNESS_ROOT")
  return 1
}

# A mission that is executing with a pending feature and nothing in flight.
loop_has_next() {
  local md mid state pend live
  for md in "$MISSIONS"/*/; do
    [ -d "$md" ] || continue
    mid="$(basename "$md")"
    case "$mid" in .*) continue ;; esac
    [ -f "$md/status.json" ] || continue
    state="$(status_state "$md/status.json" 2>/dev/null || true)"
    [ "$state" = "executing" ] || continue
    # Same recency bound as the turn-end guard: a mission untouched for a day
    # is not a loop waiting to be continued, and auto-continuing one abandoned
    # months ago is the worst thing this script could do.
    last="$(mission_last_activity "${md%/}" 2>/dev/null || echo 0)"
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    [ "$last" -gt 0 ] || continue
    [ $(( $(date -u +%s) - last )) -lt "${HARNESS_LOOP_ACTIVE_SECONDS:-86400}" ] || continue

    pend="$(jq -r '[.features[]? | select(.state == "pending")] | length' "$md/status.json" 2>/dev/null || echo 0)"
    case "$pend" in ''|*[!0-9]*) pend=0 ;; esac
    [ "$pend" -gt 0 ] || continue
    live=0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      [ "$(crew_meta_get "$HARNESS_ROOT" "$t" mission 2>/dev/null)" = "$mid" ] || continue
      crew_is_terminal "$HARNESS_ROOT" "$t" || live=1
    done < <(crew_list "$HARNESS_ROOT")
    [ "$live" -eq 1 ] && continue
    printf '%s %s' "$mid" "$pend"
    return 0
  done
  return 1
}

START="$(date -u +%s)"
CONT_SINCE=0

while :; do
  stand_down && exit 0

  if ev="$(crew_event)"; then
    printf 'crew %s\n' "$ev"; exit 2
  fi

  if ! blocking_hold_open; then
    if st="$(crew_stalled)"; then
      printf 'stall %s\n' "$st"; exit 2
    fi
    if nx="$(loop_has_next)"; then
      # Grace before a continuation wake, so a captain about to type is not
      # talked over. Event wakes above are immediate; this one is not urgent.
      [ "$CONT_SINCE" -eq 0 ] && CONT_SINCE="$(date -u +%s)"
      if [ $(( $(date -u +%s) - CONT_SINCE )) -ge "$GRACE" ]; then
        printf 'continue %s\n' "$nx"; exit 2
      fi
    else
      CONT_SINCE=0
    fi
  else
    CONT_SINCE=0
  fi

  [ "$ONCE" -eq 1 ] && exit 0
  [ $(( $(date -u +%s) - START )) -ge "$MAX_PARK" ] && exit 0
  sleep "$POLL"
done
