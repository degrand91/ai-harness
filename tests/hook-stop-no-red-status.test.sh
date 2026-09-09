#!/usr/bin/env bash
# Tests for .claude/hooks/stop-no-red-status.sh — the Stop guard.
# Exit 0 = allow the session to end. Exit 2 = block, reason on stderr.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

HOOK=stop-no-red-status.sh
PAYLOAD='{"hook_event_name":"Stop"}'

# Age a mission's status.json so the stuck-feature age check can be exercised.
age_mission() {  # <mission-dir> <seconds-ago>
  local dir="$1" secs="$2" stamp
  if date -u -d "@0" >/dev/null 2>&1; then
    stamp="$(date -u -d "@$(( $(date +%s) - secs ))" +%Y%m%d%H%M.%S)"   # GNU
  else
    stamp="$(date -u -r "$(( $(date +%s) - secs ))" +%Y%m%d%H%M.%S)"     # BSD
  fi
  touch -t "$stamp" "$dir/status.json" "$dir/log.md"
}

home="$(mktmphome)"

it "allows a stop when there are no missions at all"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "allows a stop for a closed mission"
mkmission "$home" m-closed '{"state":"closed","features":[{"id":"F001","color":"red","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "blocks a stop on a red feature with no follow-up"
mkmission "$home" m-red '{"state":"executing","features":[{"id":"F002","color":"red","state":"closed","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "F002"
rm -rf "$home/missions/m-red"

it "allows a stop on a red feature that already has a follow-up"
mkmission "$home" m-red-fu '{"state":"executing","features":[{"id":"F002","color":"red","state":"closed","followups":["F002-followup-1"]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
rm -rf "$home/missions/m-red-fu"

# --- §0.1 regression --------------------------------------------------------
it "blocks a red feature in a DRIFTED-schema mission (§0.1 regression)"
# .status/.phase instead of .state — the shape of the real
# newest real mission in this repo. Before status-read.sh the
# guard read .state as "unknown", fell past the skip list, and reported clean.
mkmission "$home" m-drift '{"status":"in-progress","phase":"feature-loop","features":[{"id":"F009","color":"red","state":"closed","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "F009"
rm -rf "$home/missions/m-drift"

it "allows a stop for a drifted mission that is complete"
mkmission "$home" m-drift-done '{"status":"complete","features":[{"id":"F001","color":"red","followups":[]}]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
rm -rf "$home/missions/m-drift-done"

# --- §0.4: the stuck check must be age-bounded ------------------------------
it "allows a stop while a feature is legitimately in progress (§0.4)"
# The header promised 'stuck for more than 1 hour'; the code had no age check,
# so this blocked on every normal turn during a feature.
d="$(mkmission "$home" m-fresh '{"state":"executing","current_feature":"F001","features":[{"id":"F001","state":"in_progress","color":null,"followups":[]}]}')"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "blocks a stop on a feature in progress with no activity for over an hour"
age_mission "$d" 7300
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "F001"
rm -rf "$home/missions/m-fresh"

# --- unknown state ----------------------------------------------------------
it "blocks a stop on a mission whose state cannot be classified"
mkdir -p "$home/missions/m-bad"
printf '{"state":"banana"}\n' > "$home/missions/m-bad/status.json"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "m-bad"
rm -rf "$home/missions/m-bad"

it "allows a stop when a corrupt status.json is the only oddity, but says so"
# A corrupt file is unknown → surfaced, not silently skipped.
mkdir -p "$home/missions/m-corrupt"
printf 'not json at all' > "$home/missions/m-corrupt/status.json"
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "m-corrupt"
rm -rf "$home/missions/m-corrupt"

it "never writes to stdout (stdout is reserved for hook JSON)"
mkmission "$home" m-quiet '{"state":"executing","features":[]}' >/dev/null
run_hook "$HOOK" "$PAYLOAD" "CLAUDE_PROJECT_DIR=$home"
assert_eq "" "$HOOK_OUT"

finish
