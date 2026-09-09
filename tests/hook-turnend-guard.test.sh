#!/usr/bin/env bash
# Tests for .claude/hooks/stop-turnend-guard.sh — the Stop guard.
# Exit 0 = allow the session to end. Exit 2 = block, reason on stderr.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

HOOK=stop-turnend-guard.sh
PAYLOAD='{"hook_event_name":"Stop"}'

# Relative mtimes come from fixtures.sh, which makes them explicit rather than
# leaving them to whatever order the filesystem happened to produce.
age_mission() { age_mission_by "$1" "$2"; }

home="$(mktmphome)"

it "allows a stop when there are no missions at all"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "allows a stop for a closed mission"
mkmission "$home" m-closed '{"state":"closed","features":[{"id":"F001","color":"red","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "blocks a stop on a red feature with no follow-up"
mkmission "$home" m-red '{"state":"executing","features":[{"id":"F002","color":"red","state":"closed","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "F002"
rm -rf "$home/missions/m-red"

it "allows a stop on a red feature that already has a follow-up"
mkmission "$home" m-red-fu '{"state":"executing","features":[{"id":"F002","color":"red","state":"closed","followups":["F002-followup-1"]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
rm -rf "$home/missions/m-red-fu"

# --- §0.1 regression --------------------------------------------------------
it "blocks a red feature in a DRIFTED-schema mission (§0.1 regression)"
# .status/.phase instead of .state — the shape of the real
# newest real mission in this repo. Before status-read.sh the
# guard read .state as "unknown", fell past the skip list, and reported clean.
mkmission "$home" m-drift '{"status":"in-progress","phase":"feature-loop","features":[{"id":"F009","color":"red","state":"closed","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "F009"
rm -rf "$home/missions/m-drift"

it "allows a stop for a drifted mission that is complete"
mkmission "$home" m-drift-done '{"status":"complete","features":[{"id":"F001","color":"red","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
rm -rf "$home/missions/m-drift-done"

# --- §0.4: the stuck check must be age-bounded ------------------------------
it "allows a stop while a feature is legitimately in progress (§0.4)"
# The header promised 'stuck for more than 1 hour'; the code had no age check,
# so this blocked on every normal turn during a feature.
d="$(mkmission "$home" m-fresh '{"state":"executing","current_feature":"F001","features":[{"id":"F001","state":"in_progress","color":null,"followups":[]}]}')"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "blocks a stop on a feature in progress with no activity for over an hour"
age_mission "$d" 7300
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "F001"
rm -rf "$home/missions/m-fresh"

# --- unknown state ----------------------------------------------------------
it "blocks a stop on a mission whose state cannot be classified"
mkdir -p "$home/missions/m-bad"
printf '{"state":"banana"}\n' > "$home/missions/m-bad/status.json"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "m-bad"
rm -rf "$home/missions/m-bad"

it "allows a stop when a corrupt status.json is the only oddity, but says so"
# A corrupt file is unknown → surfaced, not silently skipped.
mkdir -p "$home/missions/m-corrupt"
printf 'not json at all' > "$home/missions/m-corrupt/status.json"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "m-corrupt"
rm -rf "$home/missions/m-corrupt"

it "blocks a stop when a mission awaits approval with no decision filed"
# A question asked only in a chat turn is erased by a restart or a compaction.
mkmission "$home" m-approve '{"state":"awaiting_approval","features":[]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "m-approve"
assert_contains "$HOOK_ERR" "no decision is filed"

it "allows the stop once the decision is on disk"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open m-approve --question "Approve the plan?" >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "blocks again once that decision is answered but the state has not moved on"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" answer m-approve DH-001 "approved" >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
rm -rf "$home/missions/m-approve"

it "never writes to stdout (stdout is reserved for hook JSON)"
mkmission "$home" m-quiet '{"state":"executing","features":[]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_eq "" "$HOOK_OUT"

# --- §4.0: the blind-stop rule ----------------------------------------------
. "$HARNESS_ROOT/scripts/lib/crew.sh"
blind_home="$(mktmphome)"
mkmission "$blind_home" m-loop '{"state":"executing","features":[{"id":"F001","slug":"a","state":"closed","color":"green","followups":[]},{"id":"F002","slug":"b","state":"pending","color":null,"followups":[]}]}' >/dev/null

it "refuses a stop that ends the loop with a pending feature and nothing in flight"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "ended blind"
assert_contains "$HOOK_ERR" "m-loop"

it "allows the stop while a crewmate is in flight on that mission"
crew_meta_write "$blind_home" T1 project=p mission=m-loop feature=F002 runner_pid=$$
crew_ledger_append "$blind_home" T1 progress "working"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 0 "$HOOK_RC"

it "refuses again once that crewmate reaches a terminal line"
crew_ledger_append "$blind_home" T1 "done" "finished"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 2 "$HOOK_RC"
crew_forget "$blind_home" T1

it "allows the stop when the captain is the one being waited on"
CLAUDE_PROJECT_DIR="$blind_home" "$HARNESS_ROOT/scripts/hold.sh" open m-loop --question "Which way?" >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 0 "$HOOK_RC"
CLAUDE_PROJECT_DIR="$blind_home" "$HARNESS_ROOT/scripts/hold.sh" answer m-loop DH-001 "this way" >/dev/null 2>&1

it "allows the stop on a paused mission — the captain asked to take over"
python3 -c "
import json; p='$blind_home/missions/m-loop/status.json'
d=json.load(open(p)); d['state']='paused'; json.dump(d,open(p,'w'))"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 0 "$HOOK_RC"
python3 -c "
import json; p='$blind_home/missions/m-loop/status.json'
d=json.load(open(p)); d['state']='executing'; json.dump(d,open(p,'w'))"

it "fails open after a bounded number of refusals rather than wedging the session"
# A guard that can refuse forever is worse than a loop that ran one feature too
# many, so it gives up and says so.
rm -f "$blind_home/state/blind-stop-count"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1" "HARNESS_BLIND_STOP_LIMIT=2"
assert_rc 2 "$HOOK_RC"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1" "HARNESS_BLIND_STOP_LIMIT=2"
assert_rc 2 "$HOOK_RC"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1" "HARNESS_BLIND_STOP_LIMIT=2"
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_ERR" "failed open"

it "giving up resets the counter, so the guard works again next turn"
assert_file_missing "$blind_home/state/blind-stop-count"

it "the counter resets once the loop is no longer blind"
python3 -c "
import json; p='$blind_home/missions/m-loop/status.json'
d=json.load(open(p))
d['features'][1]['state']='closed'; d['features'][1]['color']='green'
json.dump(d,open(p,'w'))"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$blind_home" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 0 "$HOOK_RC"
assert_file_missing "$blind_home/state/blind-stop-count"

# --- staleness: a rail that fires forever is a rail people turn off ---------
it "does not refuse a stop for a mission abandoned months ago"
# Without this bound, one stale mission left `executing` refuses every stop in
# every future session. Found by pointing the new guard at this repo, where two
# real missions had been untouched for 105 days.
stale="$(mktmphome)"
d="$(mkmission "$stale" m-stale '{"state":"executing","features":[{"id":"F001","slug":"a","state":"pending","color":null,"followups":[]}]}')"
age_mission "$d" 9000000
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$stale" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 0 "$HOOK_RC"

it "still refuses for the same mission when it is recently active"
touch "$d/status.json" "$d/log.md"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$stale" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "ended blind"

it "does not refuse for a stale mission awaiting approval"
stale2="$(mktmphome)"
d2="$(mkmission "$stale2" m-old-approve '{"state":"awaiting_approval","features":[]}')"
age_mission "$d2" 9000000
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$stale2" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 0 "$HOOK_RC"

it "still refuses for a fresh mission awaiting approval with nothing filed"
touch "$d2/status.json" "$d2/log.md"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$stale2" "HARNESS_NOTIFY_DRYRUN=1"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "no decision is filed"

finish
