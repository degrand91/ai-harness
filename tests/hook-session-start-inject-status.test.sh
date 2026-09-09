#!/usr/bin/env bash
# Tests for .claude/hooks/session-start-inject-status.sh
# Must emit valid JSON on stdout and always exit 0 — a SessionStart hook that
# crashes or emits garbage degrades every session that follows it.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

HOOK=session-start-inject-status.sh
PAYLOAD='{"hook_event_name":"SessionStart","session_id":"test-session-1"}'

ctx() { printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

home="$(mktmphome)"

it "emits valid JSON and exits 0 with no missions"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

it "reports a single active mission"
mkmission "$home" 2026-01-01-alpha '{"state":"executing","current_feature":"F001","features":[{"id":"F001","slug":"a","state":"in_progress","color":null,"followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_contains "$(ctx)" "2026-01-01-alpha"
assert_contains "$(ctx)" "executing"

# --- §0.2 regression --------------------------------------------------------
it "reports EVERY active mission, not just the newest (§0.2 regression)"
mkmission "$home" 2026-01-02-bravo   '{"state":"executing","current_feature":"F001","features":[]}' >/dev/null
mkmission "$home" 2026-01-03-charlie '{"state":"planning","features":[]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
c="$(ctx)"
assert_contains "$c" "2026-01-01-alpha"
assert_contains "$c" "2026-01-02-bravo"
assert_contains "$c" "2026-01-03-charlie"

it "excludes closed and abandoned missions"
mkmission "$home" 2026-01-04-done '{"state":"closed","features":[]}'     >/dev/null
mkmission "$home" 2026-01-05-gone '{"state":"abandoned","features":[]}'  >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
c="$(ctx)"
assert_not_contains "$c" "2026-01-04-done"
assert_not_contains "$c" "2026-01-05-gone"

it "includes a drifted-schema mission as active (§0.1 regression)"
mkmission "$home" 2026-01-06-drift '{"status":"in-progress","phase":"feature-loop","features":[]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_contains "$(ctx)" "2026-01-06-drift"

it "surfaces a mission whose state cannot be classified rather than hiding it"
mkdir -p "$home/missions/2026-01-07-bad"
printf 'not json\n' > "$home/missions/2026-01-07-bad/status.json"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
c="$(ctx)"
assert_contains "$c" "2026-01-07-bad"
assert_contains "$c" "unknown"

it "caps the number of missions reported so a big fleet cannot flood context"
for n in 08 09 10 11 12; do
  mkmission "$home" "2026-01-$n-extra" '{"state":"executing","features":[]}' >/dev/null
done
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
count="$(ctx | grep -c '^  id: ' || true)"
[ "$count" -le 3 ] || _fail "expected at most 3 missions in context, got $count"

it "caps log lines per mission"
big="$home/missions/2026-01-01-alpha/log.md"
for i in $(seq 1 40); do echo "log line $i" >> "$big"; done
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
lines="$(ctx | grep -c 'log line' || true)"
[ "$lines" -le 5 ] || _fail "expected at most 5 log lines per mission, got $lines"

it "emits valid JSON even when a status.json is corrupt"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

it "still exits 0 when the missions directory does not exist"
empty="$(mktmphome)"; rm -rf "$empty/missions"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$empty"
assert_rc 0 "$HOOK_RC"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

# --- inbox integration ------------------------------------------------------
it "surfaces undrained inbox notes ahead of mission state"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/inbox.sh" note "look at the flaky test" >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
c="$(ctx)"
assert_contains "$c" "flaky test"
assert_contains "$c" "Undrained inbox notes"
# Notes come first: they are asks nothing has acted on yet.
[ "${c%%Active missions*}" != "$c" ] || _fail "expected mission summary after the notes"
notes_at="${c%%Undrained*}"
miss_at="${c%%Active missions*}"
[ "${#notes_at}" -lt "${#miss_at}" ] || _fail "inbox notes should precede mission state"

it "says nothing about the inbox once notes are acknowledged"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/inbox.sh" drain --ack N001 >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_not_contains "$(ctx)" "Undrained inbox notes"

it "still emits valid JSON with an unreadable note present"
printf 'not json\n' > "$home/data/inbox/N009.json"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?
assert_contains "$(ctx)" "unreadable"

# --- decision holds ---------------------------------------------------------
it "puts open decisions ahead of inbox notes and mission state"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open 2026-01-01-alpha --question "Merge PR 42?" >/dev/null 2>&1
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/inbox.sh" note "an idea" >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
c="$(ctx)"
assert_contains "$c" "Merge PR 42?"
assert_contains "$c" "OPEN DECISIONS"
before_holds="${c%%OPEN DECISIONS*}"
before_notes="${c%%Undrained*}"
before_miss="${c%%Active missions*}"
[ "${#before_holds}" -lt "${#before_notes}" ] || _fail "decisions should precede inbox notes"
[ "${#before_holds}" -lt "${#before_miss}" ]  || _fail "decisions should precede mission state"

it "stops mentioning a decision once it is answered"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" answer 2026-01-01-alpha DH-001 "yes, merge" >/dev/null 2>&1
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_not_contains "$(ctx)" "Merge PR 42?"

# --- crew ------------------------------------------------------------------
it "surfaces a blocked crewmate, and does not mention one that is working"
. "$HARNESS_ROOT/scripts/lib/crew.sh"
crew_meta_write "$home" C-BLOCK project=p mission=2026-01-01-alpha feature=C-BLOCK
crew_ledger_append "$home" C-BLOCK blocked "needs a credential"
crew_meta_write "$home" C-WORK project=p mission=2026-01-01-alpha feature=C-WORK runner_pid=$$
crew_ledger_append "$home" C-WORK progress "going fine"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
c="$(ctx)"
assert_contains "$c" "C-BLOCK"
assert_contains "$c" "needs a credential"
assert_not_contains "$c" "C-WORK"

it "flags a crewmate whose runner vanished without an outcome"
crew_meta_write "$home" C-GONE project=p mission=2026-01-01-alpha feature=C-GONE runner_pid=999999
crew_ledger_append "$home" C-GONE progress "was going fine"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_contains "$(ctx)" "SUSPICIOUS"

it "still emits valid JSON with crew state present"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

finish
