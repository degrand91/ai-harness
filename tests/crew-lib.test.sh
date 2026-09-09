#!/usr/bin/env bash
# Tests for scripts/lib/crew.sh — the single owner of crewmate state.
#
# state/<task>.meta    what this crewmate is and where it lives
# state/<task>.ledger  append-only lines the crewmate and its hooks write
#
# The ledger is the contract between a crewmate and everything watching it. It
# is append-only and written by the crewmate's own process, so a supervisor that
# died mid-flight can reconstruct the outcome from disk alone.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
export CREW_STATE="$home/state"

it "writes and reads a task's meta"
crew_meta_write "$home" F001 project=alpha mission=m-1 feature=F001 worktree=/w/1 branch=hc/m-1/F001 mode=direct-PR yolo=off
assert_rc 0 $?
assert_eq "alpha"        "$(crew_meta_get "$home" F001 project)"
assert_eq "m-1"          "$(crew_meta_get "$home" F001 mission)"
assert_eq "/w/1"         "$(crew_meta_get "$home" F001 worktree)"
assert_eq "hc/m-1/F001"  "$(crew_meta_get "$home" F001 branch)"

it "returns empty for a field that was never set"
assert_eq "" "$(crew_meta_get "$home" F001 session_id)"

it "updates a field without losing the others"
crew_meta_set "$home" F001 session_id sess-xyz
assert_eq "sess-xyz" "$(crew_meta_get "$home" F001 session_id)"
assert_eq "alpha"    "$(crew_meta_get "$home" F001 project)"

it "refuses to read a task that has no meta"
out="$(crew_meta_get "$home" F999 project)"; rc=$?
assert_rc 1 "$rc"
assert_eq "" "$out"

it "lists live tasks"
crew_meta_write "$home" F002 project=alpha mission=m-1 feature=F002
listing="$(crew_list "$home")"
assert_contains "$listing" "F001"
assert_contains "$listing" "F002"

it "appends ledger lines in order"
crew_ledger_append "$home" F001 started "worktree ready"
crew_ledger_append "$home" F001 busy ""
crew_ledger_append "$home" F001 progress "wrote the failing test"
lines="$(cat "$home/state/F001.ledger")"
assert_contains "$lines" "started:"
assert_contains "$lines" "progress: wrote the failing test"

it "reports the last ledger verb"
assert_eq "progress" "$(crew_ledger_last "$home" F001)"

it "recognises terminal outcomes and nothing else"
crew_is_terminal "$home" F001; assert_rc 1 $?
crew_ledger_append "$home" F001 "done" "PR opened"
crew_is_terminal "$home" F001; assert_rc 0 $?
assert_eq "done" "$(crew_ledger_last "$home" F001)"

it "treats failed as terminal too"
crew_ledger_append "$home" F002 "failed" "exit 1"
crew_is_terminal "$home" F002; assert_rc 0 $?

it "does NOT treat blocked as terminal — a blocked crewmate is waiting, not finished"
crew_meta_write "$home" F003 project=alpha mission=m-1 feature=F003
crew_ledger_append "$home" F003 blocked "needs a credential"
crew_is_terminal "$home" F003; assert_rc 1 $?
assert_eq "blocked" "$(crew_ledger_last "$home" F003)"

it "reads the note attached to the last line"
assert_eq "needs a credential" "$(crew_ledger_note "$home" F003)"

it "a task with no ledger has no last verb, and is not terminal"
crew_meta_write "$home" F004 project=alpha mission=m-1 feature=F004
assert_eq "" "$(crew_ledger_last "$home" F004)"
crew_is_terminal "$home" F004; assert_rc 1 $?

it "ignores a torn final line rather than misreading it as an outcome"
# A process killed mid-write leaves a partial final line with no newline.
# Reading it as an outcome would invent a `done` that never happened.
crew_ledger_append "$home" F004 progress "fine"
printf '%s don' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$home/state/F004.ledger"
assert_eq "progress" "$(crew_ledger_last "$home" F004)"
crew_is_terminal "$home" F004; assert_rc 1 $?

it "ignores a torn line even when it would have been terminal"
crew_meta_write "$home" F005 project=alpha mission=m-1 feature=F005
crew_ledger_append "$home" F005 progress "still going"
printf '%s done: PR opened' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$home/state/F005.ledger"
crew_is_terminal "$home" F005; assert_rc 1 $?
crew_forget "$home" F005

it "counts live tasks for the concurrency limit"
assert_eq "4" "$(crew_count "$home")"

it "forgetting a task removes both its files"
crew_forget "$home" F004
assert_file_missing "$home/state/F004.meta"
assert_file_missing "$home/state/F004.ledger"
assert_eq "3" "$(crew_count "$home")"

it "refuses a task id that could escape the state directory"
crew_meta_write "$home" "../evil" project=x 2>/dev/null; assert_rc 2 $?
crew_meta_write "$home" "a/b" project=x 2>/dev/null; assert_rc 2 $?
assert_file_missing "$home/state/../evil.meta"

# --- outcome vs last line ---------------------------------------------------
it "reads the OUTCOME through lifecycle lines appended after it"
# The injected Stop and SessionEnd hooks fire AFTER the crewmate reports, so a
# successful run ends "done: / idle: / exited:". Reading the literal last line
# called that a failure and threw away finished work. Found by the first real
# crewmate; the fake backend can never catch it, because it writes no lifecycle
# lines at all.
crew_meta_write "$home" L1 project=p mission=m feature=L1
crew_ledger_append "$home" L1 progress "working"
crew_ledger_append "$home" L1 "done" "commit abc123"
crew_ledger_append "$home" L1 idle ""
crew_ledger_append "$home" L1 exited ""
assert_eq "exited" "$(crew_ledger_last "$home" L1)"
assert_eq "done"   "$(crew_outcome "$home" L1)"
assert_eq "commit abc123" "$(crew_outcome_note "$home" L1)"
crew_is_terminal "$home" L1; assert_rc 0 $?

it "takes the LATEST outcome when a crewmate reports more than once"
crew_meta_write "$home" L2 project=p mission=m feature=L2
crew_ledger_append "$home" L2 blocked "needed a key"
crew_ledger_append "$home" L2 progress "unblocked"
crew_ledger_append "$home" L2 "done" "finished after all"
crew_ledger_append "$home" L2 exited ""
assert_eq "done" "$(crew_outcome "$home" L2)"

it "reports no outcome for a crewmate that only ever went busy and idle"
crew_meta_write "$home" L3 project=p mission=m feature=L3
crew_ledger_append "$home" L3 busy ""
crew_ledger_append "$home" L3 idle ""
out="$(crew_outcome "$home" L3)"; rc=$?
assert_rc 1 "$rc"
assert_eq "" "$out"
crew_is_terminal "$home" L3; assert_rc 1 $?

it "still treats blocked as non-terminal when it is the latest outcome"
crew_meta_write "$home" L4 project=p mission=m feature=L4
crew_ledger_append "$home" L4 blocked "waiting"
crew_ledger_append "$home" L4 idle ""
assert_eq "blocked" "$(crew_outcome "$home" L4)"
crew_is_terminal "$home" L4; assert_rc 1 $?

finish
