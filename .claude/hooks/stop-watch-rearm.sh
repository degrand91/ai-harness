#!/usr/bin/env bash
#
# Stop hook, registered with "asyncRewake": true and a multi-hour timeout.
# Claude fires it in the BACKGROUND on every Stop; it parks on fleet state and,
# when something actionable happens, prints to stderr and exits 2 — which Claude
# delivers as "Stop hook feedback", waking an idle session. Zero tokens while
# parked.
#
# SCOPE, IDENTITY, SINGLE-FLIGHT — in that order, each exiting 0 silently:
#   scope     only a real harness checkout (missions/ and an orchestrator agent)
#   identity  only the session that owns state/session.lock (§0.3), so a second
#             session never arms or rewakes
#   flight    only one watcher per home; a live owner means we stand down
#
# The park loop runs in the FOREGROUND of this hook's process tree — never with
# `&` — so Claude's timeout or teardown kills the watcher along with the hook.
#
# THE CONTINUATION WAKE IS A BACKSTOP, not the main mechanism. The synchronous
# turn-end guard (stop-no-red-status.sh) refuses a blind stop while work is
# owed; this only covers the case where that guard has failed open.
#
# Never writes stdout. Exit 0 is always silent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
STATE="$HARNESS_ROOT/state"
LOCKF="$STATE/watch.lock"

INPUT="$(cat 2>/dev/null || true)"

# --- scope -------------------------------------------------------------------
# Both markers are checked on HARNESS_ROOT, the DATA root. Checking the code
# root would be meaningless: it is always this repo, so the hook would arm in
# any directory that merely happened to contain a `missions/` folder.
[ -d "$HARNESS_ROOT/missions" ] || exit 0
[ -f "$HARNESS_ROOT/.claude/agents/orchestrator.md" ] || exit 0
[ -f "$STATE/.watch-off" ] && exit 0
[ -f "$STATE/.afk" ] && exit 0

# --- identity ----------------------------------------------------------------
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || exit 0
# shellcheck source=../../scripts/lib/session-lock.sh
. "$CODE_ROOT/scripts/lib/session-lock.sh" 2>/dev/null || exit 0
lock_is_owner "$STATE/session.lock" "$SESSION_ID" || exit 0

# --- single flight -----------------------------------------------------------
mkdir -p "$STATE" 2>/dev/null || exit 0
if [ -f "$LOCKF" ]; then
  OWNER="$(cat "$LOCKF" 2>/dev/null || true)"
  case "$OWNER" in
    ''|*[!0-9]*) ;;
    *) kill -0 "$OWNER" 2>/dev/null && exit 0 ;;   # a live watcher already parks
  esac
fi
printf '%s' "$$" > "$LOCKF" 2>/dev/null || exit 0
trap 'rm -f "$LOCKF" 2>/dev/null || true' EXIT

# --- park --------------------------------------------------------------------
REASON="$("$CODE_ROOT/scripts/watch.sh" 2>/dev/null)"; RC=$?
[ "$RC" -eq 2 ] || exit 0
[ -n "$REASON" ] || exit 0

VERB="${REASON%% *}"
REST="${REASON#* }"

# A continuation wake is BOUNDED. Anything else is a real event and is not.
if [ "$VERB" = "continue" ]; then
  CAP="${HARNESS_MAX_AUTO_CONTINUE:-10}"
  N=0
  [ -f "$STATE/watch-epoch" ] && N="$(cat "$STATE/watch-epoch" 2>/dev/null || echo 0)"
  case "$N" in ''|*[!0-9]*) N=0 ;; esac
  if [ "$N" -ge "$CAP" ]; then
    # One notification, then silence until the captain speaks. UserPromptSubmit
    # clears the epoch, which is what "attended again" means.
    if [ ! -f "$STATE/.watch-capped" ]; then
      : > "$STATE/.watch-capped"
      "$CODE_ROOT/scripts/notify.sh" "Harness" "Auto-continue cap reached ($CAP). The loop is waiting for you." 2>/dev/null || true
    fi
    exit 0
  fi
  printf '%s' "$((N + 1))" > "$STATE/watch-epoch" 2>/dev/null || true
  rm -f "$STATE/.watch-capped" 2>/dev/null || true
fi

case "$VERB" in
  crew)     printf '[watcher] crewmate event: %s\nRun ./scripts/crew/reconcile.sh, then act on it.\n' "$REST" >&2 ;;
  stall)    printf '[watcher] crewmate stalled: %s (seconds since its last ledger line)\nPeek before deciding: ./scripts/crew/peek.sh %s\n' "$REST" "${REST%% *}" >&2 ;;
  continue) printf '[watcher] resume the feature loop: mission %s has pending features and nothing in flight.\n' "$REST" >&2 ;;
  *)        printf '[watcher] %s\n' "$REASON" >&2 ;;
esac
exit 2
