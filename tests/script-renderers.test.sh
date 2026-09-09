#!/usr/bin/env bash
# Tests for the per-mission renderers: mission-tui, mission-diff,
# mission-checkpoint, mission-html-report.
#
# These render detail the fleet snapshot deliberately does not carry (per-feature
# files, plan-vs-actual diffs), so they read mission files directly by design.
# What they must NOT do is decide mission state themselves — that is
# scripts/lib/status-read.sh's job. Reading `.state` directly is how a
# drifted-schema mission gets reported as "unknown" or "null" in four more
# places, which is exactly the §0.1 defect duplicated.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
run_in_home() {  # <script> <args...>
  local s="$1"; shift
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  ( cd "$home" && CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/$s" "$@" ) >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

CANON='{"mission_id":"m-canon","state":"executing","current_feature":"F001","features":[{"id":"F001","slug":"one","state":"in_progress","color":null,"followups":[]},{"id":"F002","slug":"two","state":"pending","color":null,"followups":[]}]}'
# The shape of the real drifted mission: no .state at all.
DRIFT='{"mission_id":"m-drift","status":"in-progress","phase":"feature-loop","current_feature":"F001","features":[{"id":"F001","slug":"one","state":"in_progress","color":null,"followups":[]}]}'

mkmission "$home" m-canon "$CANON" >/dev/null
mkmission "$home" m-drift "$DRIFT" >/dev/null
printf '# Plan\n\n- F001 one\n- F002 two\n' > "$home/missions/m-canon/plan.md"
printf '# Plan\n\n- F001 one\n' > "$home/missions/m-drift/plan.md"

# --- mission-tui -------------------------------------------------------------
it "mission-tui reports a canonical state"
run_in_home mission-tui.sh m-canon
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "executing"

it "mission-tui normalises a drifted mission instead of showing unknown"
run_in_home mission-tui.sh m-drift
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "executing"
assert_not_contains "$HOOK_OUT" "unknown"

it "mission-tui picks a drifted mission as the active one"
# The picker orders by status.json mtime. Both fixtures are written in the same
# instant, so without an explicit touch the order is undefined — this passed on
# macOS and failed on Linux purely by luck of the filesystem.
touch "$home/missions/m-drift/status.json"
run_in_home mission-tui.sh
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "m-drift"

# --- mission-diff ------------------------------------------------------------
it "mission-diff reports a canonical state"
run_in_home mission-diff.sh m-canon
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "executing"

it "mission-diff normalises a drifted mission"
run_in_home mission-diff.sh m-drift
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "executing"

# --- mission-checkpoint ------------------------------------------------------
it "mission-checkpoint records a canonical state"
run_in_home mission-checkpoint.sh m-canon
assert_rc 0 "$HOOK_RC"
assert_eq "executing" "$(printf '%s' "$HOOK_OUT" | jq -r '.mission_state' 2>/dev/null)"

it "mission-checkpoint records a drifted mission's normalised state"
run_in_home mission-checkpoint.sh m-drift
assert_rc 0 "$HOOK_RC"
assert_eq "executing" "$(printf '%s' "$HOOK_OUT" | jq -r '.mission_state' 2>/dev/null)"

it "mission-checkpoint writes valid JSON to the mission folder"
assert_file_exists "$home/missions/m-drift/checkpoint.json"
jq -e . "$home/missions/m-drift/checkpoint.json" >/dev/null 2>&1; assert_rc 0 $?

# --- mission-html-report -----------------------------------------------------
it "mission-html-report renders a canonical state"
run_in_home mission-html-report.sh m-canon
assert_rc 0 "$HOOK_RC"

it "mission-html-report normalises a drifted mission"
run_in_home mission-html-report.sh m-drift
assert_rc 0 "$HOOK_RC"
report="$(find "$home/missions/m-drift" -name '*.html' 2>/dev/null | head -n1)"
[ -n "$report" ] || report="$HOOK_OUT"
if [ -f "$report" ]; then body="$(cat "$report")"; else body="$HOOK_OUT"; fi
assert_contains "$body" "executing"

# --- the shared guarantee ----------------------------------------------------
it "no renderer decides mission state on its own"
# Every one of these must resolve state through the single owner. A direct
# `.state` read is the §0.1 defect, duplicated.
for s in mission-tui mission-diff mission-checkpoint mission-html-report; do
  code="$(grep -vE '^[[:space:]]*#' "$HARNESS_ROOT/scripts/$s.sh")"
  case "$code" in
    *"status_state"*) ;;
    *) _fail "$s.sh does not call status_state" ;;
  esac
  # Only the mission's TOP-LEVEL state is status-read's to own. `.features[].state`
  # is an ordinary field and is read directly on purpose, so a line that reaches
  # through `.features` is fine; one that reads `.state` off the mission file
  # itself is the §0.1 defect returning.
  while IFS= read -r line; do
    case "$line" in
      *".features"*) continue ;;
      *".state"*)
        case "$line" in
          *STATUS_FILE*|*'"$sj"'*) _fail "$s.sh reads top-level .state directly: $line" ;;
        esac ;;
    esac
  done <<< "$code"
done

it "an unreadable mission is reported as unknown, not as a crash"
mkdir -p "$home/missions/m-bad"
printf 'not json\n' > "$home/missions/m-bad/status.json"
run_in_home mission-tui.sh m-bad
assert_contains "$HOOK_OUT" "unknown"

finish
