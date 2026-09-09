#!/usr/bin/env bash
# Tests for the single-orchestrator session lock (§0.3):
#   scripts/lib/session-lock.sh      the contract
#   session-start-lock.sh            take it, or announce observer mode
#   pre-tool-observer-guard.sh       refuse mutations from a second session
#   session-end-release-lock.sh      release only what you own
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/session-lock.sh"

payload() { printf '{"hook_event_name":"%s","session_id":"%s"}' "$1" "$2"; }
tool_payload() { # <session_id> <tool> <json-tool-input>
  printf '{"hook_event_name":"PreToolUse","session_id":"%s","tool_name":"%s","tool_input":%s}' "$1" "$2" "$3"
}
ctx() { printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

home="$(mktmphome)"
LOCK="$home/state/session.lock"

# --- library ----------------------------------------------------------------
it "reports no owner when no lock file exists"
lock_is_owner "$LOCK" "s1"; assert_rc 0 $?      # unowned = anyone may act

it "takes an unheld lock"
lock_take "$LOCK" "s1" "$$"; assert_rc 0 $?
assert_file_exists "$LOCK"
assert_eq "s1" "$(lock_owner_session "$LOCK")"

it "recognises the owner and rejects a stranger"
lock_is_owner "$LOCK" "s1"; assert_rc 0 $?
lock_is_owner "$LOCK" "s2"; assert_rc 1 $?

it "refuses to hand a live lock to a second session"
lock_take "$LOCK" "s2" "$$"; assert_rc 1 $?
assert_eq "s1" "$(lock_owner_session "$LOCK")"

it "lets the owner re-take its own lock (idempotent restart)"
lock_take "$LOCK" "s1" "$$"; assert_rc 0 $?

it "does not release a lock it does not own"
lock_release "$LOCK" "s2"; assert_rc 1 $?
assert_file_exists "$LOCK"

it "releases a lock it owns"
lock_release "$LOCK" "s1"; assert_rc 0 $?
assert_file_missing "$LOCK"

it "steals a lock whose recorded pid is dead"
lock_take "$LOCK" "dead-session" 999999
lock_take "$LOCK" "s3" "$$"; assert_rc 0 $?
assert_eq "s3" "$(lock_owner_session "$LOCK")"
lock_release "$LOCK" "s3" >/dev/null

it "treats a malformed lock file as stealable rather than wedging forever"
printf 'garbage' > "$LOCK"
lock_take "$LOCK" "s4" "$$"; assert_rc 0 $?
lock_release "$LOCK" "s4" >/dev/null

# --- SessionStart -----------------------------------------------------------
it "the first session takes the lock and is not told it is an observer"
run_hook session-start-lock.sh "$(payload SessionStart first)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "first" "$(lock_owner_session "$LOCK")"
assert_not_contains "$(ctx)" "OBSERVER MODE"

it "a second concurrent session is put into observer mode"
run_hook session-start-lock.sh "$(payload SessionStart second)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_contains "$(ctx)" "OBSERVER MODE"
assert_contains "$(ctx)" "first"
assert_eq "first" "$(lock_owner_session "$LOCK")"

it "emits valid JSON in both cases"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

# --- PreToolUse guard -------------------------------------------------------
it "the lock owner may write to missions/"
run_hook pre-tool-observer-guard.sh "$(tool_payload first Write "{\"file_path\":\"$home/missions/m/spec.md\"}")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "an observer may NOT write to missions/"
run_hook pre-tool-observer-guard.sh "$(tool_payload second Write "{\"file_path\":\"$home/missions/m/spec.md\"}")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "observer"

it "does not tax Bash — crew and watcher enforce the lock in their own scripts"
# Guarding Bash here would cost a process on the most frequent tool in a
# session. scripts/crew/* and scripts/watch.sh check the lock themselves.
run_hook pre-tool-observer-guard.sh "$(tool_payload second Bash '{"command":"./scripts/crew/spawn.sh F001"}')" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "an observer MAY read"
run_hook pre-tool-observer-guard.sh "$(tool_payload second Read "{\"file_path\":\"$home/missions/m/spec.md\"}")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "writes outside missions/ are not the guard's business"
run_hook pre-tool-observer-guard.sh "$(tool_payload second Write '{"file_path":"/tmp/scratch.txt"}')" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "allows everything when no lock is held at all"
rm -f "$LOCK"
run_hook pre-tool-observer-guard.sh "$(tool_payload whoever Write "{\"file_path\":\"$home/missions/m/spec.md\"}")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

# --- SessionEnd -------------------------------------------------------------
it "SessionEnd from an observer leaves the owner's lock alone"
lock_take "$LOCK" "first" "$$"
run_hook session-end-release-lock.sh "$(payload SessionEnd second)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "first" "$(lock_owner_session "$LOCK")"

it "SessionEnd from the owner releases the lock"
run_hook session-end-release-lock.sh "$(payload SessionEnd first)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_file_missing "$LOCK"

it "a session that starts after the owner exits takes the lock cleanly"
run_hook session-start-lock.sh "$(payload SessionStart third)" "CLAUDE_PROJECT_DIR=$home"
assert_eq "third" "$(lock_owner_session "$LOCK")"
assert_not_contains "$(ctx)" "OBSERVER MODE"

finish
