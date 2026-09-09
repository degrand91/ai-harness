#!/usr/bin/env bash
# Tests for scripts/lib/status-read.sh — the single owner of mission state.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/status-read.sh"

# --- pure mapping -----------------------------------------------------------
it "passes canonical .state through unchanged"
assert_eq "executing" "$(status_normalize executing "" "")"
assert_eq "awaiting_approval" "$(status_normalize awaiting_approval "" "")"
assert_eq "closed" "$(status_normalize closed "" "")"

it "maps the drifted .phase vocabulary"
assert_eq "executing" "$(status_normalize "" "in-progress" "feature-loop")"
assert_eq "executing" "$(status_normalize "" "" "feature-loop")"

it "maps the drifted .status vocabulary"
assert_eq "executing" "$(status_normalize "" "in-progress" "")"
assert_eq "closed"    "$(status_normalize "" "complete" "")"
assert_eq "abandoned" "$(status_normalize "" "cancelled" "")"
assert_eq "paused"    "$(status_normalize "" "on-hold" "")"

it "prefers .state over the drifted fields when both are present"
assert_eq "paused" "$(status_normalize paused "in-progress" "feature-loop")"

it "refuses an unrecognised state loudly (exit 3, not a silent pass)"
out="$(status_normalize "banana" "" "")"; rc=$?
assert_eq "unknown" "$out"
assert_rc 3 "$rc"

it "refuses when every field is empty"
out="$(status_normalize "" "" "")"; rc=$?
assert_eq "unknown" "$out"
assert_rc 3 "$rc"

# --- file reading -----------------------------------------------------------
home="$(mktmphome)"

it "reads a canonical mission from disk"
mkmission "$home" canon '{"state":"executing"}' >/dev/null
assert_eq "executing" "$(status_state "$home/missions/canon/status.json")"

it "reads a drifted mission from disk (the §0.1 regression)"
# This exact shape occurs in a real mission in this repo: no .state at all.
mkmission "$home" drift '{"status":"in-progress","phase":"feature-loop"}' >/dev/null
out="$(status_state "$home/missions/drift/status.json")"; rc=$?
assert_eq "executing" "$out"
assert_rc 0 "$rc"

it "does not let an empty leading field shift the others"
# Regression guard: tab-splitting via `read` swallowed the empty .state and
# slid .status into its slot, classifying every drifted mission as unknown.
mkmission "$home" shift1 '{"state":"","status":"in-progress","phase":""}' >/dev/null
assert_eq "executing" "$(status_state "$home/missions/shift1/status.json")"

it "treats a corrupt status.json as unknown, never as closed"
mkdir -p "$home/missions/corrupt"
printf '{ this is not json' > "$home/missions/corrupt/status.json"
out="$(status_state "$home/missions/corrupt/status.json")"; rc=$?
assert_eq "unknown" "$out"
assert_rc 3 "$rc"

it "treats a missing status.json as unknown"
out="$(status_state "$home/missions/nope/status.json")"; rc=$?
assert_eq "unknown" "$out"
assert_rc 3 "$rc"

# --- active classification --------------------------------------------------
it "classifies active, terminal, and unknown distinctly"
mkmission "$home" done1 '{"state":"closed"}' >/dev/null
mkmission "$home" gone1 '{"state":"abandoned"}' >/dev/null
status_is_active "$home/missions/canon/status.json"; assert_rc 0 $?
status_is_active "$home/missions/done1/status.json"; assert_rc 1 $?
status_is_active "$home/missions/gone1/status.json"; assert_rc 1 $?
status_is_active "$home/missions/corrupt/status.json"; assert_rc 2 $?

it "lists active AND unknown missions, excluding terminal ones"
listing="$(status_active_missions "$home/missions")"
assert_contains "$listing" "canon"
assert_contains "$listing" "drift"
assert_contains "$listing" "corrupt"
assert_not_contains "$listing" "done1"
assert_not_contains "$listing" "gone1"

it "returns nothing for a missing missions dir instead of erroring"
out="$(status_active_missions "$home/no-such-dir")"; rc=$?
assert_eq "" "$out"
assert_rc 0 "$rc"

# --- real repo --------------------------------------------------------------
it "classifies every real mission in this repo without an unknown"
unknowns=""
for f in "$HARNESS_ROOT"/missions/*/status.json; do
  [ -f "$f" ] || continue
  if ! status_state "$f" >/dev/null; then
    unknowns="$unknowns $(basename "$(dirname "$f")")"
  fi
done
assert_eq "" "$unknowns"

finish
