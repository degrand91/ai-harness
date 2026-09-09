#!/usr/bin/env bash
# peek.sh - a bounded look at what a crewmate is doing.
#
# Usage: peek.sh <task> [lines=40]
#
# BOUNDED BY DEFAULT so a peek can never blow the supervisor's context window.
# Shows the ledger tail (what the crewmate says about itself) and then the
# window tail (what it is actually printing). The ledger first: it is the
# contract, the pane is only evidence.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"
# shellcheck source=backend.sh
. "$CODE_ROOT/scripts/crew/backend.sh"

case "${1:-}" in
  -h|--help) sed -n '2,12{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
esac

TASK="${1:-}"; LINES="${2:-40}"
[ -n "$TASK" ] || { printf 'usage: peek.sh <task> [lines]\n' >&2; exit 2; }
crew_meta_get "$HARNESS_ROOT" "$TASK" task >/dev/null 2>&1 \
  || { printf 'peek.sh: no such task "%s"\n' "$TASK" >&2; exit 1; }

printf '== %s (%s on %s) ==\n' "$TASK" \
  "$(crew_meta_get "$HARNESS_ROOT" "$TASK" mode)" \
  "$(crew_meta_get "$HARNESS_ROOT" "$TASK" project)"
printf '\n-- ledger (last %s) --\n' "$LINES"
tail -n "$LINES" "$HARNESS_ROOT/state/$TASK.ledger" 2>/dev/null || printf '(no ledger yet)\n'
printf '\n-- window (last %s) --\n' "$LINES"
backend_capture "$TASK" "$LINES" 2>/dev/null || printf '(no window)\n'
