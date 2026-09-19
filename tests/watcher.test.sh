#!/usr/bin/env bash
# Tests for scripts/watch.sh and .claude/hooks/stop-watch-rearm.sh.
#
# The watcher is the one component that can spend money unattended, so what it
# REFUSES to wake for matters more than what it wakes for.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

watch1() {  # single pass, no parking
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$1" HARNESS_WATCH_GRACE=0 \
    "$HARNESS_ROOT/scripts/watch.sh" --once >"$outf" 2>/dev/null || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

home="$(mktmphome)"
mkmission "$home" m1 '{"state":"executing","features":[{"id":"F001","slug":"a","state":"pending","color":null,"followups":[]}]}' >/dev/null

it "wakes to continue a loop with a pending feature and nothing in flight"
watch1 "$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "continue m1"

it "does NOT wake while a blocking decision is open — the captain owns it"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open m1 --question "Which way?" >/dev/null 2>&1
watch1 "$home"
assert_rc 0 "$HOOK_RC"
assert_eq "" "$HOOK_OUT"

it "wakes again once that decision is answered"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" answer m1 DH-001 "that way" >/dev/null 2>&1
watch1 "$home"
assert_rc 2 "$HOOK_RC"

it "does not wake for an advisory decision"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open m1 --question "Later?" --advisory >/dev/null 2>&1
watch1 "$home"
assert_rc 2 "$HOOK_RC"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" answer m1 DH-002 "sure" >/dev/null 2>&1

it "does NOT wake a paused mission — the captain asked to take over"
python3 -c "
import json,sys; p='$home/missions/m1/status.json'
d=json.load(open(p)); d['state']='paused'; json.dump(d,open(p,'w'))"
watch1 "$home"
assert_rc 0 "$HOOK_RC"
python3 -c "
import json,sys; p='$home/missions/m1/status.json'
d=json.load(open(p)); d['state']='executing'; json.dump(d,open(p,'w'))"

it "stands down entirely when the kill switch exists"
: > "$home/state/.watch-off"
watch1 "$home"
assert_rc 0 "$HOOK_RC"
rm -f "$home/state/.watch-off"

it "stands down in away mode — the AFK daemon owns the watcher"
# A real marker, as afk.sh start writes it. An empty file used to do here, but
# the watcher now reads the deadline out of it.
printf '{"entered_at":"2026-09-09T00:00:00Z","until_epoch":%s}\n' "$(( $(date -u +%s) + 3600 ))" > "$home/state/.afk"
watch1 "$home"
assert_rc 0 "$HOOK_RC"

it "and takes back over once away mode has expired"
# The daemon stops at its deadline but the marker survives until the operator
# returns. Standing down on the bare marker left nothing supervising at all.
printf '{"entered_at":"2026-09-09T00:00:00Z","until_epoch":%s}\n' "$(( $(date -u +%s) - 60 ))" > "$home/state/.afk"
watch1 "$home"
assert_rc 2 "$HOOK_RC"
rm -f "$home/state/.afk"

it "does not wake to continue while a crewmate is in flight on that mission"
crew_meta_write "$home" F001 project=p mission=m1 feature=F001 runner_pid=$$
crew_ledger_append "$home" F001 progress "working"
watch1 "$home"
assert_rc 0 "$HOOK_RC"

it "wakes immediately when a crewmate reports done"
crew_ledger_append "$home" F001 "done" "commit abc"
watch1 "$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "crew F001 done"

it "wakes when a crewmate reports blocked, even with a decision open elsewhere"
crew_ledger_append "$home" F001 blocked "needs a key"
watch1 "$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "blocked"

it "wakes when a live crewmate has been silent past the stall threshold"
crew_forget "$home" F001
crew_meta_write "$home" F002 project=p mission=m1 feature=F002 runner_pid=$$
crew_ledger_append "$home" F002 progress "quiet now"
age_file "$home/state/F002.ledger" --seconds 9999
watch1 "$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "stall F002"

it "a crew event outranks a stall, and a stall outranks a continuation"
crew_ledger_append "$home" F002 failed "gave up"
watch1 "$home"
assert_contains "$HOOK_OUT" "crew F002 failed"
crew_forget "$home" F002

# --- the rearm hook ----------------------------------------------------------
SID="watcher-session"
rearm() {
  local outf errf; outf="$(mktemp)"; errf="$(mktemp)"
  HOOK_RC=0
  printf '{"hook_event_name":"Stop","session_id":"%s"}' "$SID" | \
    env CLAUDE_PROJECT_DIR="$home" HARNESS_WATCH_GRACE=0 HARNESS_WATCH_ONCE=1 HARNESS_NOTIFY_DRYRUN=1 \
    "$HARNESS_ROOT/.claude/hooks/stop-watch-rearm.sh" >"$outf" 2>"$errf" || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; HOOK_ERR="$(cat "$errf")"; rm -f "$outf" "$errf"
  export HOOK_OUT HOOK_ERR HOOK_RC
}

it "the rearm hook stands down for a session that does not own the harness"
. "$HARNESS_ROOT/scripts/lib/session-lock.sh"
lock_take "$home/state/session.lock" "someone-else" "$$"
rearm
assert_rc 0 "$HOOK_RC"
assert_eq "" "$HOOK_ERR"

it "the owning session wakes, with the reason on stderr and nothing on stdout"
lock_release "$home/state/session.lock" "someone-else" >/dev/null
lock_take "$home/state/session.lock" "$SID" "$$"
rearm
assert_rc 2 "$HOOK_RC"
assert_eq "" "$HOOK_OUT"
assert_contains "$HOOK_ERR" "resume the feature loop"

it "counts continuation wakes toward a cap"
assert_eq "1" "$(cat "$home/state/watch-epoch")"
rearm; rearm
assert_eq "3" "$(cat "$home/state/watch-epoch")"

it "goes silent at the cap, after exactly one notification"
printf '10' > "$home/state/watch-epoch"
rearm
assert_rc 0 "$HOOK_RC"
assert_file_exists "$home/state/.watch-capped"
rearm
assert_rc 0 "$HOOK_RC"

it "a real crew event still wakes even at the continuation cap"
crew_meta_write "$home" F003 project=p mission=m1 feature=F003
crew_ledger_append "$home" F003 "done" "finished"
rearm
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "crewmate event"
crew_forget "$home" F003

it "the captain speaking resets the cap"
# UserPromptSubmit clears the epoch; that is what "attended again" means.
run_hook user-prompt-restore.sh '{"hook_event_name":"UserPromptSubmit","session_id":"x"}' "CLAUDE_PROJECT_DIR=$home"
assert_file_missing "$home/state/watch-epoch"
rm -f "$home/state/.watch-capped"
rearm
assert_rc 2 "$HOOK_RC"

it "stands down outside a harness checkout"
plain="$(mktemp -d)"; mkdir -p "$plain/missions"
printf '{"hook_event_name":"Stop","session_id":"x"}' | \
  env CLAUDE_PROJECT_DIR="$plain" HARNESS_WATCH_ONCE=1 \
  "$HARNESS_ROOT/.claude/hooks/stop-watch-rearm.sh" >/dev/null 2>&1
assert_rc 0 $?

it "does not arm merely because a directory contains a missions folder"
# The scope markers are checked on the DATA root. Checking the code root would
# always pass, since that is this repo.
bare="$(mktemp -d)"; mkdir -p "$bare/missions/m" "$bare/state"
printf '{"state":"executing","features":[{"id":"F1","state":"pending","color":null,"followups":[]}]}\n' \
  > "$bare/missions/m/status.json"
printf '{"hook_event_name":"Stop","session_id":"x"}' | \
  env CLAUDE_PROJECT_DIR="$bare" HARNESS_WATCH_ONCE=1 \
  "$HARNESS_ROOT/.claude/hooks/stop-watch-rearm.sh" >/dev/null 2>&1
assert_rc 0 $?
assert_file_missing "$bare/state/watch.lock"
rm -rf "$bare"
rm -rf "$plain"

it "does not continuation-wake for a mission abandoned months ago"
# The watcher auto-continuing a mission nobody has touched since May is the
# worst thing it could do. Same recency bound as the turn-end guard.
stale="$(mktmphome)"
d="$(mkmission "$stale" m-stale '{"state":"executing","features":[{"id":"F001","state":"pending","color":null,"followups":[]}]}')"
age_mission_by "$d" 9000000
watch1 "$stale"
assert_rc 0 "$HOOK_RC"

it "wakes for the same mission once it is touched again"
touch "$d/status.json"
watch1 "$stale"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "continue m-stale"

finish
