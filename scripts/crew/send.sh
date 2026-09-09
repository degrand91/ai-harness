#!/usr/bin/env bash
# send.sh - steer a running crewmate.
#
# Usage: send.sh <task> <text>...   |   send.sh <task> -   (text on stdin)
#
# TWO DATA PLANES (fm-send.sh:16-19), made deterministic:
#   1. the steer is written to state/<task>.inbox/<ts>.md  — durable, first
#   2. SIGUSR1 to the run.sh process                        — best effort, second
#
# run.sh then interrupts its claude child, drains the inbox, and relaunches with
# --resume. The message survives even if the signal is missed: the next drain
# picks it up. No keystrokes, no composer detection, no guessing whether a TUI
# was ready to receive.
#
# REFUSES AN UNRESOLVED TARGET rather than searching for something plausible. A
# "successful" send to the wrong crewmate is worse than a loud failure.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"

TASK="${1:-}"; shift 2>/dev/null || true
[ -n "$TASK" ] || { printf 'usage: send.sh <task> <text>... | send.sh <task> -\n' >&2; exit 2; }
crew_meta_get "$HARNESS_ROOT" "$TASK" task >/dev/null 2>&1 \
  || { printf 'send.sh: no such task "%s" — refusing to guess at a target\n' "$TASK" >&2; exit 1; }

if [ "${1:-}" = "-" ]; then TEXT="$(cat)"; else TEXT="$*"; fi
TEXT="${TEXT#"${TEXT%%[![:space:]]*}"}"
[ -n "$TEXT" ] || { printf 'send.sh: refusing to send an empty steer\n' >&2; exit 2; }

INBOX="$HARNESS_ROOT/state/$TASK.inbox"
mkdir -p "$INBOX" || { printf 'send.sh: cannot write to %s\n' "$INBOX" >&2; exit 1; }
F="$INBOX/$(date -u +%Y%m%dT%H%M%SZ)-$$.md"
printf '%s\n' "$TEXT" > "$F" || { printf 'send.sh: could not record the steer\n' >&2; exit 1; }

crew_ledger_append "$HARNESS_ROOT" "$TASK" progress "steer queued"

PID="$(crew_meta_get "$HARNESS_ROOT" "$TASK" runner_pid 2>/dev/null || true)"
case "$PID" in
  ''|*[!0-9]*)
    printf 'Queued for %s. No runner recorded yet — it will be picked up at the next launch.\n' "$TASK" ;;
  *)
    if kill -USR1 "$PID" 2>/dev/null; then
      printf 'Sent to %s (runner %s interrupted; it will resume with your steer).\n' "$TASK" "$PID"
    else
      printf 'Queued for %s. The runner (%s) is not answering; the steer is on disk and will be read when it next launches.\n' "$TASK" "$PID"
    fi ;;
esac
