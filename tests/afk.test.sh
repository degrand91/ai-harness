#!/usr/bin/env bash
# Tests for scripts/afk.sh — away mode and the wedge alarm.
#
# The wedge alarm does not defend against nothing happening. It defends against
# something happening that needed the captain, and the message going nowhere.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
afk() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" HARNESS_NOTIFY_DRYRUN=1 \
    "$HARNESS_ROOT/scripts/afk.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
mkmission "$home" m1 '{"state":"executing","features":[]}' >/dev/null

it "reports away mode off before it is started"
afk status
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "off"

it "starting away mode creates the marker the watcher stands down on"
afk start 2h
assert_rc 0 "$HOOK_RC"
assert_file_exists "$home/state/.afk"
assert_eq "7200" "$(jq -r '.duration_seconds' "$home/state/.afk")"

it "the watcher stands down entirely while away mode is on"
out="$(CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/watch.sh" --once 2>/dev/null)"; rc=$?
assert_rc 0 "$rc"
assert_eq "" "$out"

it "a finished crewmate is digested, not delivered"
crew_meta_write "$home" T1 project=p mission=m1 feature=F001
crew_ledger_append "$home" T1 "done" "shipped it"
afk tick
assert_rc 0 "$HOOK_RC"
afk digest
assert_contains "$HOOK_OUT" "T1 finished"
[ -f "$home/state/afk-escalations/crew-T1-done.json" ] && _fail "a routine success must not escalate"

it "a failed crewmate escalates"
crew_meta_write "$home" T2 project=p mission=m1 feature=F002
crew_ledger_append "$home" T2 failed "exit 1"
afk tick
assert_file_exists "$home/state/afk-escalations/crew-T2-failed.json"
assert_eq "null" "$(jq -r '.acked_at' "$home/state/afk-escalations/crew-T2-failed.json")"

it "a blocking decision escalates"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open m1 --question "Which way?" >/dev/null 2>&1
afk tick
assert_file_exists "$home/state/afk-escalations/hold-m1.json"

it "an advisory decision does not escalate"
mkmission "$home" m2 '{"state":"executing","features":[]}' >/dev/null
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open m2 --question "Later?" --advisory >/dev/null 2>&1
afk tick
assert_file_missing "$home/state/afk-escalations/hold-m2.json"

it "the same event escalates once, not on every tick"
before="$(jq -r '.raised_at' "$home/state/afk-escalations/crew-T2-failed.json")"
afk tick; afk tick
assert_eq "$before" "$(jq -r '.raised_at' "$home/state/afk-escalations/crew-T2-failed.json")"

# --- the wedge alarm ---------------------------------------------------------
it "does not alarm before the wedge threshold"
out="$(CLAUDE_PROJECT_DIR="$home" HARNESS_NOTIFY_DRYRUN=1 HARNESS_WEDGE_MINUTES=60 \
  "$HARNESS_ROOT/scripts/afk.sh" tick 2>&1)"
assert_not_contains "$out" "UNACKNOWLEDGED"

it "alarms once an escalation has gone unacknowledged past the threshold"
out="$(CLAUDE_PROJECT_DIR="$home" HARNESS_NOTIFY_DRYRUN=1 HARNESS_WEDGE_MINUTES=0 HARNESS_WEDGE_REPEAT_MINUTES=0 \
  "$HARNESS_ROOT/scripts/afk.sh" tick 2>&1)"
assert_contains "$out" "UNACKNOWLEDGED"
assert_contains "$out" "urgent"

it "acknowledging stops the alarm"
afk ack crew-T2-failed
assert_rc 0 "$HOOK_RC"
assert_contains "$(jq -r '.acked_at' "$home/state/afk-escalations/crew-T2-failed.json")" "20"
out="$(CLAUDE_PROJECT_DIR="$home" HARNESS_NOTIFY_DRYRUN=1 HARNESS_WEDGE_MINUTES=0 HARNESS_WEDGE_REPEAT_MINUTES=0 \
  "$HARNESS_ROOT/scripts/afk.sh" tick 2>&1)"
assert_not_contains "$out" "crewmate T2 failed (raised"

it "refuses to acknowledge an escalation that does not exist"
afk ack no-such-thing
assert_rc 1 "$HOOK_RC"

it "return presents the digest and the unacknowledged escalations"
afk return
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "digest"
# The digest is a full history, so it still mentions the acknowledged item.
# What matters is which escalations are listed as STILL unacknowledged.
unacked="${HOOK_OUT#*unacknowledged escalations}"
assert_contains "$unacked" "hold-m1"
assert_not_contains "$unacked" "crew-T2-failed"

it "return ends away mode, so the watcher takes over again"
assert_file_missing "$home/state/.afk"
# And it immediately has something to say: a crewmate failed while we were away.
out="$(CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/watch.sh" --once 2>/dev/null)"; rc=$?
assert_rc 2 "$rc"
assert_contains "$out" "crew T1"

it "an expired away mode hands the watcher back, rather than leaving nobody"
# Found by running away mode to expiry: the daemon stops at its deadline but
# the marker survives until the operator runs `return`. Standing the watcher
# down on the bare marker left NOTHING supervising the fleet in between --
# the exact failure away mode exists to prevent.
# See docs/verification/away-mode-drill.md.
. "$HARNESS_ROOT/scripts/lib/afk-state.sh"
exp="$(mktmphome)"
printf '{"entered_at":"2026-09-09T00:00:00Z","until_epoch":%s}\n' "$(( $(date -u +%s) - 60 ))" > "$exp/state/.afk"
afk_on "$exp";       assert_rc 0 $?
afk_expired "$exp";  assert_rc 0 $?
afk_in_force "$exp"; assert_rc 1 $?

it "and away mode still in force keeps standing the watcher down"
liv="$(mktmphome)"
printf '{"entered_at":"2026-09-09T00:00:00Z","until_epoch":%s}\n' "$(( $(date -u +%s) + 3600 ))" > "$liv/state/.afk"
afk_in_force "$liv"; assert_rc 0 $?

it "an unreadable marker counts as expired, so something is always supervising"
# Of the two ways to be wrong, waking the operator needlessly can be noticed.
# Silence cannot.
bad="$(mktmphome)"; printf 'not json\n' > "$bad/state/.afk"
afk_in_force "$bad"; assert_rc 1 $?

it "status says EXPIRED rather than reporting away mode as simply on"
out="$(CLAUDE_PROJECT_DIR="$exp" "$HARNESS_ROOT/scripts/afk.sh" status 2>&1)"
assert_contains "$out" "EXPIRED"
assert_contains "$out" "watcher has taken over"

it "the watcher stands down only while away mode is in force"
assert_contains "$(cat "$HARNESS_ROOT/scripts/watch.sh")" 'afk_in_force "$HARNESS_ROOT"'
assert_contains "$(cat "$HARNESS_ROOT/.claude/hooks/stop-watch-rearm.sh")" 'afk_in_force "$HARNESS_ROOT"'

it "the daemon refuses to run when away mode is off"
afk daemon
assert_rc 1 "$HOOK_RC"

finish
