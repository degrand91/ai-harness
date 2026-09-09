#!/usr/bin/env bash
# reconcile.sh - work out what happened to every crewmate while nobody watched.
#
# Usage: reconcile.sh [--quiet]
#
# LEDGER FIRST (fm-inactive-reconcile.sh:14-17). A task whose ledger ends in a
# complete `done:` or `failed:` line has STATED ITS OWN OUTCOME. Trust that
# before probing any process: the ledger is written by the crewmate itself and
# survives everything, while a pid is gone the moment the machine reboots.
#
# Only then does process liveness matter, and only to distinguish "still
# working" from "vanished". A vanished crewmate with no terminal line is
# reported as SUSPICIOUS, never silently marked failed — the difference between
# "it crashed" and "we lost track of it" is the captain's to judge, and a false
# `failed` throws away a worktree that may hold real work.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"
# shellcheck source=backend.sh
. "$CODE_ROOT/scripts/crew/backend.sh"

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1
say() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }

ANY=0; SUSPICIOUS=0
while IFS= read -r task; do
  [ -n "$task" ] || continue
  ANY=1
  last="$(crew_ledger_last "$HARNESS_ROOT" "$task")"
  note="$(crew_ledger_note "$HARNESS_ROOT" "$task")"
  pid="$(crew_meta_get "$HARNESS_ROOT" "$task" runner_pid 2>/dev/null || true)"
  alive=0
  case "$pid" in ''|*[!0-9]*) ;; *) kill -0 "$pid" 2>/dev/null && alive=1 ;; esac

  case "$last" in
    done)    say "  $task: done — $note (ready for validation and teardown)"; continue ;;
    failed)  say "  $task: failed — $note (tear down, or re-brief)"; continue ;;
    blocked) say "  $task: blocked — $note (attach: ./scripts/crew/attach.sh $task)"; continue ;;
  esac

  if [ "$alive" -eq 1 ]; then
    say "  $task: working (runner $pid, last: ${last:-none})"
  else
    SUSPICIOUS=$((SUSPICIOUS + 1))
    say "  $task: SUSPICIOUS — no runner, and the ledger never reached a terminal line (last: ${last:-none})"
    say "      worktree: $(crew_meta_get "$HARNESS_ROOT" "$task" worktree 2>/dev/null || echo '?')"
    say "      inspect with ./scripts/crew/peek.sh $task before tearing it down"
  fi
done < <(crew_list "$HARNESS_ROOT")

[ "$ANY" -eq 1 ] || say "No crewmates."
[ "$SUSPICIOUS" -gt 0 ] && exit 3
exit 0
