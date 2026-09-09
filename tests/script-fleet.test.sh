#!/usr/bin/env bash
# Tests for scripts/fleet.sh — the human view over the snapshot contract.
# Its defining property: it parses no mission state itself.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
fleet() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/fleet.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

it "says so plainly when there is nothing to show"
fleet
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "No missions"

it "lists an active mission with its state and current feature"
mkmission "$home" 2026-08-01-alpha '{"title":"Alpha work","state":"executing","current_feature":"F002","features":[{"id":"F001","slug":"one","state":"closed","color":"green","followups":[]},{"id":"F002","slug":"two","state":"in_progress","color":null,"followups":[]}]}' >/dev/null
fleet
assert_contains "$HOOK_OUT" "2026-08-01-alpha"
assert_contains "$HOOK_OUT" "executing"
assert_contains "$HOOK_OUT" "F002"

it "hides closed missions by default and shows them with --all"
mkmission "$home" 2026-08-02-done '{"state":"closed","features":[]}' >/dev/null
fleet
assert_not_contains "$HOOK_OUT" "2026-08-02-done"
fleet --all
assert_contains "$HOOK_OUT" "2026-08-02-done"

it "shows registered projects and their delivery posture"
mkdir -p "$home/repo-a" && git -C "$home/repo-a" init -q 2>/dev/null
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" add alpha "$home/repo-a" --mode no-mistakes >/dev/null 2>&1
fleet
assert_contains "$HOOK_OUT" "alpha"
assert_contains "$HOOK_OUT" "no-mistakes"

it "warns loudly about a mission it could not parse"
mkdir -p "$home/missions/2026-08-03-bad"
printf 'not json\n' > "$home/missions/2026-08-03-bad/status.json"
fleet
assert_contains "$HOOK_OUT" "2026-08-03-bad"
assert_contains "$HOOK_OUT" "unknown"

it "reports fleet spend"
mkmission "$home" 2026-08-04-spend '{"state":"executing","features":[],"tokens":{"workers":{"input":1200,"output":300}}}' >/dev/null
fleet
assert_contains "$HOOK_OUT" "1200"

it "passes the raw snapshot through with --json"
fleet --json
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?
assert_eq "1" "$(printf '%s' "$HOOK_OUT" | jq -r '.schema')"

it "parses no mission state of its own"
# The contract from fm-fleet-view.sh:3-5. Every fact must come from
# snapshot.sh; a renderer that reads status.json is a renderer that can drift.
# Comments are stripped first — the header is allowed to explain the rule it
# is obeying.
code="$(grep -vE '^[[:space:]]*#' "$HARNESS_ROOT/scripts/fleet.sh")"
assert_not_contains "$code" "status.json"
assert_not_contains "$code" "status-read.sh"
assert_not_contains "$code" "missions/"
assert_contains     "$code" "snapshot.sh"

finish
