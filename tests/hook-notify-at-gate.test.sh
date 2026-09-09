#!/usr/bin/env bash
# Tests for .claude/hooks/notify-at-gate.sh. Delivery must NEVER fail a turn,
# so every path exits 0 — including malformed input.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
HOOK=notify-at-gate.sh
DRY=HARNESS_NOTIFY_DRYRUN=1

it "delivers a well-formed notification"
run_hook "$HOOK" '{"hook_event_name":"Notification","title":"Harness","message":"gate reached"}' "$DRY"
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_ERR" "gate reached"

it "falls back to defaults when fields are missing"
run_hook "$HOOK" '{"hook_event_name":"Notification"}' "$DRY"
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_ERR" "Harness"

it "survives malformed JSON without failing the turn"
run_hook "$HOOK" 'not json at all' "$DRY"
assert_rc 0 "$HOOK_RC"

it "survives empty stdin"
run_hook "$HOOK" '' "$DRY"
assert_rc 0 "$HOOK_RC"

it "escapes quotes and backslashes so they cannot break the delivery command"
run_hook "$HOOK" '{"message":"say \"hi\" \\ then stop","title":"T"}' "$DRY"
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_ERR" 'hi'

finish
