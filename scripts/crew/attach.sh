#!/usr/bin/env bash
# attach.sh - take over a stopped crewmate's session by hand.
#
# Usage: attach.sh <task>
#
# The human rescue. A crewmate that wrote `blocked:` has exited; this resumes
# ITS session interactively, in ITS worktree, so the captain can see exactly
# what it saw and unstick it.
#
# REFUSED WHILE THE RUNNER IS ALIVE. Two processes driving one session would
# interleave turns unpredictably; use send.sh to steer a running crewmate.
# After detaching, the supervisor re-briefs from the handoff — not from the
# captain's transcript, which it cannot see.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"

TASK="${1:-}"
[ -n "$TASK" ] || { printf 'usage: attach.sh <task>\n' >&2; exit 2; }
crew_meta_get "$HARNESS_ROOT" "$TASK" task >/dev/null 2>&1 \
  || { printf 'attach.sh: no such task "%s"\n' "$TASK" >&2; exit 1; }

PID="$(crew_meta_get "$HARNESS_ROOT" "$TASK" runner_pid || true)"
case "$PID" in
  ''|*[!0-9]*) ;;
  *) if kill -0 "$PID" 2>/dev/null; then
       printf 'attach.sh: %s is still running (runner %s). Steer it instead:\n  ./scripts/crew/send.sh %s "<message>"\n' "$TASK" "$PID" "$TASK" >&2
       exit 2
     fi ;;
esac

WT="$(crew_meta_get "$HARNESS_ROOT" "$TASK" worktree)"
SID="$(crew_meta_get "$HARNESS_ROOT" "$TASK" session_id)"
[ -d "$WT" ] || { printf 'attach.sh: worktree is gone: %s\n' "$WT" >&2; exit 1; }
[ -n "$SID" ] || { printf 'attach.sh: no session recorded for %s; nothing to resume\n' "$TASK" >&2; exit 1; }

printf 'Resuming %s in %s\nWhen you are done, the supervisor re-briefs from the handoff.\n\n' "$TASK" "$WT"
cd "$WT" || exit 1
exec claude --resume "$SID"
