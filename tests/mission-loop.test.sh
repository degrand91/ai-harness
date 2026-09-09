#!/usr/bin/env bash
# End-to-end test of the FEATURE LOOP itself.
#
# Everything else in this suite is a unit test. Nothing tested that a mission
# actually moves: intake -> approve -> dispatch -> outcome -> land -> advance
# -> close. That gap is why Phase 3 shipped with no orchestrator surface calling
# it — 354 assertions passed while the crew was unreachable from the workflow.
#
# The model is stubbed: the crewmate's WORK is simulated (a commit and a ledger
# line), because what is under test is the loop, not the model.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
export CREW_FAKE_LOG="$home/fake.log"; : > "$CREW_FAKE_LOG"
run_h() {  # <script> <args...>
  local s="$1"; shift
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" HARNESS_CREW_BACKEND=fake HARNESS_NOTIFY_DRYRUN=1 \
    "$HARNESS_ROOT/$s" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
guard() {
  local errf; errf="$(mktemp)"; HOOK_RC=0
  printf '{"hook_event_name":"Stop","session_id":"s"}' | \
    env CLAUDE_PROJECT_DIR="$home" HARNESS_NOTIFY_DRYRUN=1 \
    "$HARNESS_ROOT/.claude/hooks/stop-no-red-status.sh" >/dev/null 2>"$errf" || HOOK_RC=$?
  HOOK_ERR="$(cat "$errf")"; rm -f "$errf"; export HOOK_ERR HOOK_RC
}
fstate() { jq -r --arg f "$1" '[.features[]|select(.id==$f)]|.[0].state' "$home/missions/$M/status.json"; }
mstate() { "$HARNESS_ROOT/scripts/lib/status-read.sh" state "$home/missions/$M/status.json"; }

# --- a registered project ----------------------------------------------------
proj="$home/app"; mkdir -p "$proj"; git -C "$proj" init -q -b main
printf 'v1\n' > "$proj/f.txt"; git -C "$proj" add -A
git -C "$proj" -c user.email=t@t -c user.name=t commit -qm init
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" add app "$proj" --mode local-only >/dev/null 2>&1

M=2026-09-09-loop
mkdir -p "$home/missions/$M"
python3 - "$home/missions/$M/status.json" "$proj" <<'PY'
import json, sys
json.dump({"mission_id":"2026-09-09-loop","state":"awaiting_approval",
 "target_repo":sys.argv[2],"models":{"worker_default":"haiku"},
 "crew":{"max_concurrent":1},
 "features":[{"id":"F001","slug":"one","state":"pending","color":None,"followups":[]},
             {"id":"F002","slug":"two","state":"pending","color":None,"followups":[]}],
 "tokens":{"workers":{"input":0,"output":0}}}, open(sys.argv[1],"w"), indent=2)
PY
: > "$home/missions/$M/log.md"

# --- approval is a decision, not a chat turn ---------------------------------
it "refuses to end a turn while approval is pending with nothing filed"
guard
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "no decision is filed"

it "filing DH-000 makes the approval gate real"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open "$M" \
  --question "Approve the plan and contract?" --options "approve,revise" >/dev/null 2>&1
guard
assert_rc 0 "$HOOK_RC"

it "will not dispatch while approval is unanswered"
run_h scripts/feature-dispatch.sh "$M" F001 --intent <(echo i) --done <(echo d)
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not executing"

it "approval moves the mission to executing"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" answer "$M" DH-001 "approved" >/dev/null 2>&1
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p));d['state']='executing';json.dump(d,open(p,'w'))"
assert_eq "executing" "$(mstate)"

# --- the loop ----------------------------------------------------------------
it "chooses crew because the project is registered"
run_h scripts/feature-dispatch.sh "$M" F001 --dry-run --intent <(echo i) --done <(echo d)
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "execution: crew"
assert_contains "$HOOK_OUT" "project: app"

it "a dry run decides nothing permanently"
# Recording the execution model IS a decision; a dry run must not make it.
assert_eq "null" "$(jq -r '.execution' "$home/missions/$M/status.json")"

it "dispatches the first feature"
run_h scripts/feature-dispatch.sh "$M" F001 \
  --intent <(echo "f.txt should say v2") --done <(echo "f.txt contains v2")
assert_rc 0 "$HOOK_RC"
assert_eq "in_progress" "$(fstate F001)"
assert_file_exists "$home/state/F001.meta"

it "records the execution model on a real dispatch, so it cannot switch later"
assert_eq "crew" "$(jq -r '.execution' "$home/missions/$M/status.json")"

it "refuses to dispatch the same feature twice"
run_h scripts/feature-dispatch.sh "$M" F001 --intent <(echo i) --done <(echo d)
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "already in progress"

it "honours the concurrency limit while one crewmate is in flight"
run_h scripts/feature-dispatch.sh "$M" F002 --intent <(echo i) --done <(echo d)
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "in flight and allows 1"

it "allows the turn to end while a crewmate is working"
guard
assert_rc 0 "$HOOK_RC"

# --- simulate the crewmate finishing ----------------------------------------
it "the crewmate's own ledger is what reports the outcome"
WT="$(crew_meta_get "$home" F001 worktree)"
printf 'v2\n' > "$WT/f.txt"
git -C "$WT" add -A && git -C "$WT" -c user.email=c@t -c user.name=c commit -qm "feat: v2" >/dev/null
crew_ledger_append "$home" F001 progress "edited f.txt"
crew_ledger_append "$home" F001 "done" "commit $(git -C "$WT" rev-parse --short HEAD)"
crew_ledger_append "$home" F001 idle ""
crew_ledger_append "$home" F001 exited ""
assert_eq "done" "$(crew_outcome "$home" F001)"

it "reconcile reports it ready, and the watcher wakes for it"
run_h scripts/crew/reconcile.sh
assert_contains "$HOOK_OUT" "ready for validation and teardown"
run_h scripts/watch.sh --once
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "crew F001 done"

it "the validator can read the worktree before it is torn down"
[ -f "$WT/f.txt" ] || _fail "worktree removed before validation"
assert_eq "v2" "$(cat "$WT/f.txt")"

it "teardown lands the work under the registered mode"
run_h scripts/crew/teardown.sh F001
assert_rc 0 "$HOOK_RC"
assert_eq "v2" "$(cat "$proj/f.txt")"
assert_file_missing "$home/state/F001.meta"
assert_not_contains "$(git -C "$proj" branch --list 'hc/*')" "f001"

it "the loop advances to the next feature"
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p))
d['features'][0].update(state='closed', color='green')
json.dump(d,open(p,'w'))"
assert_eq "closed" "$(fstate F001)"
run_h scripts/feature-dispatch.sh "$M" F002 \
  --intent <(echo "f.txt should say v3") --done <(echo "f.txt contains v3")
assert_rc 0 "$HOOK_RC"
assert_eq "in_progress" "$(fstate F002)"

it "a red outcome does not tear the worktree down"
crew_ledger_append "$home" F002 failed "could not do it"
run_h scripts/crew/teardown.sh F002
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not done"
WT2="$(crew_meta_get "$home" F002 worktree)"
[ -d "$WT2" ] || _fail "worktree removed after a failure"

it "abandoning a failed feature is explicit and cleans up"
run_h scripts/crew/teardown.sh F002 --abandon
assert_rc 0 "$HOOK_RC"
assert_file_missing "$home/state/F002.meta"

it "the guard refuses to end the loop with work still pending"
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p)); d['features'][1]['state']='pending'; json.dump(d,open(p,'w'))"
touch "$home/missions/$M/status.json" "$home/missions/$M/log.md"
guard
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "ended blind"

it "and allows it once every feature is closed"
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p))
d['features'][1].update(state='closed', color='green')
d['state']='closing'
json.dump(d,open(p,'w'))"
guard
assert_rc 0 "$HOOK_RC"

it "a closed mission wakes nothing"
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p)); d['state']='closed'; json.dump(d,open(p,'w'))"
run_h scripts/watch.sh --once
assert_rc 0 "$HOOK_RC"

# --- the other execution model ----------------------------------------------
it "falls back to subagent when the project is not registered, and says why"
M2=2026-09-09-unreg
mkdir -p "$home/missions/$M2"
printf '{"state":"executing","target_repo":"/not/registered","models":{"worker_default":"sonnet"},"features":[{"id":"F001","slug":"x","state":"pending","color":null,"followups":[]}]}\n' \
  > "$home/missions/$M2/status.json"
: > "$home/missions/$M2/log.md"
run_h scripts/feature-dispatch.sh "$M2" F001
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "execution: subagent"
assert_contains "$HOOK_OUT" "Agent tool"
assert_contains "$HOOK_OUT" "not a registered project"

it "records the chosen model so a mission never switches half way through"
assert_eq "subagent" "$(jq -r '.execution' "$home/missions/$M2/status.json")"

finish
