#!/usr/bin/env bash
# Tests for the compaction-survival pair:
#   pre-compact-snapshot.sh   writes what a summary must not erase
#   user-prompt-restore.sh    injects it once, then deletes it
#
# Compaction is the second way a promised answer is lost, after a restart.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

SID="sess-abc"
pl() { printf '{"hook_event_name":"%s","session_id":"%s"}' "$1" "$SID"; }
ctx() { printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

home="$(mktmphome)"
mkmission "$home" m-live '{"state":"executing","current_feature":"F002","features":[]}' >/dev/null
printf 'log line one\nlog line two\n' > "$home/missions/m-live/log.md"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" open m-live --question "Merge PR 42?" >/dev/null 2>&1
CARRY="$home/state/precompact-${SID}.md"

it "PreCompact records open decisions"
run_hook pre-compact-snapshot.sh "$(pl PreCompact)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_file_exists "$CARRY"
body="$(cat "$CARRY")"
assert_contains "$body" "Merge PR 42?"
assert_contains "$body" "DH-001"

it "PreCompact records missions in flight and recent log lines"
assert_contains "$(cat "$CARRY")" "m-live"
assert_contains "$(cat "$CARRY")" "executing"
assert_contains "$(cat "$CARRY")" "log line two"

it "PreCompact writes nothing to stdout"
assert_eq "" "$HOOK_OUT"

it "the next prompt re-injects what was carried"
run_hook user-prompt-restore.sh "$(pl UserPromptSubmit)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
c="$(ctx)"
assert_contains "$c" "Merge PR 42?"
assert_contains "$c" "compaction"

it "the carry file is consumed exactly once"
assert_file_missing "$CARRY"
run_hook user-prompt-restore.sh "$(pl UserPromptSubmit)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "" "$HOOK_OUT"

it "a prompt from another session does not consume this session's carry"
run_hook pre-compact-snapshot.sh "$(pl PreCompact)" "CLAUDE_PROJECT_DIR=$home"
assert_file_exists "$CARRY"
run_hook user-prompt-restore.sh '{"hook_event_name":"UserPromptSubmit","session_id":"other"}' "CLAUDE_PROJECT_DIR=$home"
assert_file_exists "$CARRY"

it "any real prompt clears the watcher continuation epoch"
# The captain speaking means the loop is attended again (Phase 4 reads this).
mkdir -p "$home/state"; printf '7\n' > "$home/state/watch-epoch"
run_hook user-prompt-restore.sh "$(pl UserPromptSubmit)" "CLAUDE_PROJECT_DIR=$home"
assert_file_missing "$home/state/watch-epoch"

it "both hooks survive a payload with no session id"
run_hook pre-compact-snapshot.sh '{"hook_event_name":"PreCompact"}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
run_hook user-prompt-restore.sh '{}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "both hooks survive malformed JSON"
run_hook pre-compact-snapshot.sh 'garbage' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
run_hook user-prompt-restore.sh 'garbage' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "emits valid JSON when it emits anything at all"
run_hook pre-compact-snapshot.sh "$(pl PreCompact)" "CLAUDE_PROJECT_DIR=$home"
run_hook user-prompt-restore.sh "$(pl UserPromptSubmit)" "CLAUDE_PROJECT_DIR=$home"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

finish
