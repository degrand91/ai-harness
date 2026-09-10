#!/usr/bin/env bash
# crew_outcome has TWO implementations — scripts/lib/crew.sh (bash, for hooks in
# hot paths) and scripts/lib/harness.py (for the snapshot, which must not spawn a
# subprocess per crewmate). This asserts they agree.
#
# The repo set this precedent for the state vocabulary: two lookups are safe
# only when something checks. The crew feature introduced a second lookup
# without the check, and its contract did not require one — a contract defect,
# filed as DH-002 and answered "add a parity test".
#
# What they encode is subtle enough to be worth pinning: the ledger's LAST line
# is NOT the outcome, because Stop and SessionEnd hooks append `idle:` and
# `exited:` after a crewmate reports.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
py_outcome() {  # <task>
  python3 -c "
import sys; sys.path.insert(0,'$HARNESS_ROOT/scripts/lib')
import harness, pathlib
o = harness.crew_outcome(pathlib.Path('$home/state/$1.ledger'))
print(o if o is not None else '')"
}
both_agree() {  # <task> <expected>
  local b p; b="$(crew_ledger_last_outcome_or_empty "$1")"; p="$(py_outcome "$1")"
  [ "$b" = "$p" ] || _fail "$1: bash=[$b] python=[$p] disagree"
  [ "$b" = "$2" ] || _fail "$1: expected [$2], both said [$b]"
}
crew_ledger_last_outcome_or_empty() { crew_outcome "$home" "$1" 2>/dev/null || true; }

it "agree that a crewmate with no ledger has no outcome"
crew_meta_write "$home" T0 project=p mission=m feature=T0
both_agree T0 ""

it "agree when only lifecycle lines exist"
crew_ledger_append "$home" T0 busy ""
crew_ledger_append "$home" T0 idle ""
both_agree T0 ""

it "agree on a plain done"
crew_meta_write "$home" T1 project=p mission=m feature=T1
crew_ledger_append "$home" T1 progress "working"
crew_ledger_append "$home" T1 "done" "commit abc"
both_agree T1 "done"

it "agree that lifecycle lines appended AFTER the outcome do not bury it"
# The whole reason both functions exist in this shape.
crew_ledger_append "$home" T1 idle ""
crew_ledger_append "$home" T1 exited ""
assert_eq "exited" "$(crew_ledger_last "$home" T1)"
both_agree T1 "done"

it "agree on failed"
crew_meta_write "$home" T2 project=p mission=m feature=T2
crew_ledger_append "$home" T2 "failed" "gave up"
crew_ledger_append "$home" T2 exited ""
both_agree T2 "failed"

it "agree on blocked, which is not terminal"
crew_meta_write "$home" T3 project=p mission=m feature=T3
crew_ledger_append "$home" T3 blocked "needs a key"
crew_ledger_append "$home" T3 idle ""
both_agree T3 "blocked"
crew_is_terminal "$home" T3; assert_rc 1 $?

it "agree on the LATEST outcome when a crewmate reports more than once"
crew_meta_write "$home" T4 project=p mission=m feature=T4
crew_ledger_append "$home" T4 blocked "waiting"
crew_ledger_append "$home" T4 progress "unblocked"
crew_ledger_append "$home" T4 "done" "finished after all"
both_agree T4 "done"

it "agree on a torn final line, which must not invent an outcome"
crew_meta_write "$home" T5 project=p mission=m feature=T5
crew_ledger_append "$home" T5 progress "still going"
printf '%s done: PR opened' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$home/state/T5.ledger"
b="$(crew_outcome "$home" T5 2>/dev/null || true)"
p="$(py_outcome T5)"
# They may differ on a torn line (bash reads complete lines only); what must
# hold is that NEITHER reports a terminal outcome from an unfinished write.
case "$b" in done|failed) _fail "bash invented an outcome from a torn line" ;; esac
case "$p" in done|failed) _fail "python invented an outcome from a torn line" ;; esac

it "agree on a note containing a colon"
crew_meta_write "$home" T6 project=p mission=m feature=T6
crew_ledger_append "$home" T6 "done" "fixed: the thing: properly"
both_agree T6 "done"
assert_eq "fixed: the thing: properly" "$(crew_outcome_note "$home" T6)"

it "agree across every verb the ledger defines"
for v in progress blocked "done" failed; do
  crew_meta_write "$home" "V-$v" project=p mission=m feature="V-$v"
  crew_ledger_append "$home" "V-$v" "$v" "note"
  b="$(crew_outcome "$home" "V-$v" 2>/dev/null || true)"; p="$(py_outcome "V-$v")"
  [ "$b" = "$p" ] || _fail "verb $v: bash=[$b] python=[$p]"
done

finish
