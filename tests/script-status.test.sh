#!/usr/bin/env bash
# Tests for scripts/status.sh — the read-only mission view. Its output shape is
# consumed by .claude/skills/mission-status/SKILL.md, so the labels are contract.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
mkmission "$home" 2026-05-01-alpha '{"mission_id":"2026-05-01-alpha","state":"executing","started_at":"2026-05-01T00:00:00Z","current_feature":"F002","features":[{"id":"F001","slug":"one","state":"closed","color":"green","followups":[]},{"id":"F002","slug":"two","state":"in_progress","color":null,"followups":[]}]}' >/dev/null

it "renders a canonical mission with its features"
out="$( cd "$home" && "$HARNESS_ROOT/scripts/status.sh" 2026-05-01-alpha 2>&1 )"; rc=$?
assert_rc 0 "$rc"
assert_contains "$out" "2026-05-01-alpha"
assert_contains "$out" "State:"
assert_contains "$out" "executing"
assert_contains "$out" "F001"
assert_contains "$out" "F002"

it "reports a normalised state for a drifted-schema mission, never 'null'"
mkmission "$home" 2026-05-02-drift '{"mission_id":"2026-05-02-drift","status":"in-progress","phase":"feature-loop","features":[{"id":"F001","slug":"x","status":"complete"}]}' >/dev/null
out="$( cd "$home" && "$HARNESS_ROOT/scripts/status.sh" 2026-05-02-drift 2>&1 )"
assert_contains "$out" "executing"
assert_not_contains "$out" "State:          null"

it "says so plainly when a mission cannot be classified"
mkdir -p "$home/missions/2026-05-03-bad"
printf 'not json\n' > "$home/missions/2026-05-03-bad/status.json"
out="$( cd "$home" && "$HARNESS_ROOT/scripts/status.sh" 2026-05-03-bad 2>&1 )"
assert_contains "$out" "unknown"

it "errors clearly for a mission id that does not exist"
out="$( cd "$home" && "$HARNESS_ROOT/scripts/status.sh" no-such-mission 2>&1 )"; rc=$?
assert_rc 1 "$rc"
assert_contains "$out" "no mission"

it "defaults to the most recently touched mission when given no argument"
out="$( cd "$home" && "$HARNESS_ROOT/scripts/status.sh" 2>&1 )"; rc=$?
assert_rc 0 "$rc"

finish
