#!/usr/bin/env bash
# Tests for the serial-execution pair:
#   pre-agent-spawn-serial.sh      claims the non-explorer slot (exit 2 = refuse)
#   subagent-stop-release-lock.sh  releases it
# protocols/serial-execution.md:3 — at most one non-explorer Worker at a time.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

SPAWN=pre-agent-spawn-serial.sh
RELEASE=subagent-stop-release-lock.sh
home="$(mktmphome)"
STATE="$home/.claude/hooks/agent-spawn-state.json"

spawn_pl()   { printf '{"tool_name":"Agent","tool_input":{"subagent_type":"%s"}}' "$1"; }
release_pl() { printf '{"hook_event_name":"SubagentStop","agent_type":"%s"}' "$1"; }
in_flight()  { jq -r '.in_flight_non_explorer' "$STATE" 2>/dev/null; }
explorers()  { jq -r '.explorer_count' "$STATE" 2>/dev/null; }

it "ignores tool calls that are not Agent spawns"
run_hook "$SPAWN" '{"tool_name":"Bash","tool_input":{"command":"ls"}}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "allows the first worker and marks the slot taken"
run_hook "$SPAWN" "$(spawn_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "true" "$(in_flight)"

it "refuses a second concurrent worker"
run_hook "$SPAWN" "$(spawn_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "concurrent"

it "refuses a validator while a worker is in flight"
run_hook "$SPAWN" "$(spawn_pl scrutiny-validator)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"

it "always allows explorers, and counts them"
run_hook "$SPAWN" "$(spawn_pl explorer)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
run_hook "$SPAWN" "$(spawn_pl explorer)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "2" "$(explorers)"
assert_eq "true" "$(in_flight)"

it "releasing an explorer decrements the count and keeps the worker slot held"
run_hook "$RELEASE" "$(release_pl explorer)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "1" "$(explorers)"
assert_eq "true" "$(in_flight)"

it "releasing the worker frees the slot for the next one"
run_hook "$RELEASE" "$(release_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "false" "$(in_flight)"
run_hook "$SPAWN" "$(spawn_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "explorer count never goes below zero"
run_hook "$RELEASE" "$(release_pl explorer)" "CLAUDE_PROJECT_DIR=$home"
run_hook "$RELEASE" "$(release_pl explorer)" "CLAUDE_PROJECT_DIR=$home"
run_hook "$RELEASE" "$(release_pl explorer)" "CLAUDE_PROJECT_DIR=$home"
assert_eq "0" "$(explorers)"

it "reclaims a stale lock left by a crashed worker"
# in_flight true with a timestamp older than the 600s staleness window.
printf '{"in_flight_non_explorer":true,"explorer_count":0,"updated_at":"2020-01-01T00:00:00Z"}\n' > "$STATE"
run_hook "$SPAWN" "$(spawn_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "true" "$(in_flight)"

it "does NOT reclaim a fresh lock"
printf '{"in_flight_non_explorer":true,"explorer_count":0,"updated_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STATE"
run_hook "$SPAWN" "$(spawn_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 2 "$HOOK_RC"

it "release exits 0 when no state file exists"
rm -f "$STATE"
run_hook "$RELEASE" "$(release_pl worker)" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "spawn survives malformed JSON without blocking the call"
run_hook "$SPAWN" 'not json' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

finish
