#!/usr/bin/env bash
# Every human-facing script must answer --help, and must refuse an unknown flag
# rather than doing something surprising with it.
#
# Found by asking what `--help` actually did: `watch.sh --help` PARKED, hanging
# the terminal for up to eight hours, because anything that was not exactly
# `--once` meant "keep parking". The crew scripts treated `--help` as a task id
# and reported "no such task", which is a confusing way to answer a reasonable
# question.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
HUMAN_FACING=(
  scripts/doctor.sh scripts/project.sh scripts/fleet.sh scripts/inbox.sh
  scripts/hold.sh scripts/lease.sh scripts/learnings-curate.sh
  scripts/memory-budget.sh scripts/feature-dispatch.sh scripts/pr-poll.sh
  scripts/status.sh scripts/notify.sh scripts/fleet-html.sh scripts/watch.sh
  scripts/crew/peek.sh scripts/crew/send.sh scripts/crew/attach.sh
  scripts/crew/teardown.sh scripts/crew/reconcile.sh scripts/crew/brief.sh
  scripts/crew/spawn.sh
)

# A help path must answer QUICKLY. A script that parks instead is the bug that
# prompted this file, and a test that waits for it would hang the suite too.
help_within() {  # <script> <seconds>
  local s="$1" limit="$2" out; out="$(mktemp)"
  ( CLAUDE_PROJECT_DIR="$home" bash "$HARNESS_ROOT/$s" --help >"$out" 2>&1 ) &
  local pid=$! n=0
  while kill -0 $pid 2>/dev/null && [ "$n" -lt "$limit" ]; do sleep 1; n=$((n+1)); done
  if kill -0 $pid 2>/dev/null; then
    kill -9 $pid 2>/dev/null; rm -f "$out"; return 1
  fi
  wait $pid 2>/dev/null
  HELP_OUT="$(cat "$out")"; rm -f "$out"; export HELP_OUT
  return 0
}

for s in "${HUMAN_FACING[@]}"; do
  it "$(basename "$s") answers --help without hanging"
  if ! help_within "$s" 5; then
    _fail "$s did not return within 5s — it is treating --help as work"
    continue
  fi
  [ -n "$HELP_OUT" ] || _fail "$s printed nothing for --help"
  case "$HELP_OUT" in
    *"no such task"*|*"unknown option"*)
      _fail "$s treated --help as an argument: $HELP_OUT" ;;
  esac
done

it "watch.sh refuses an unknown flag instead of parking on it"
# The specific bug: only `--once` was recognised, and everything else fell
# through to the poll loop.
rc=0
( CLAUDE_PROJECT_DIR="$home" bash "$HARNESS_ROOT/scripts/watch.sh" --bogus >/dev/null 2>&1 ) & pid=$!
n=0; while kill -0 $pid 2>/dev/null && [ $n -lt 5 ]; do sleep 1; n=$((n+1)); done
if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; _fail "watch.sh parked on an unknown flag"
else wait $pid 2>/dev/null || rc=$?; assert_rc 2 "$rc"; fi

it "help text names the script it belongs to"
for s in scripts/crew/peek.sh scripts/watch.sh scripts/hold.sh; do
  help_within "$s" 5 || { _fail "$s hung"; continue; }
  assert_contains "$HELP_OUT" "$(basename "$s")"
done

finish
