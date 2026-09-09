#!/usr/bin/env bash
# Tests for .claude/hooks/subagent-stop-record.sh — logs subagent completion and
# aggregates token usage into the mission's tokens block.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
HOOK=subagent-stop-record.sh
home="$(mktmphome)"
TOKENS='{"workers":{"input":0,"output":0},"scrutiny":{"input":0,"output":0},"user_testing":{"input":0,"output":0},"explorers":{"input":0,"output":0}}'
d="$(mkmission "$home" 2026-04-01-m "{\"state\":\"executing\",\"features\":[],\"tokens\":$TOKENS}")"
sf="$d/status.json"
tok() { jq -r ".tokens.$1.$2" "$sf"; }

it "logs the subagent type"
run_hook "$HOOK" '{"hook_event_name":"SubagentStop","agent_type":"worker"}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_contains "$(cat "$d/log.md")" "type=worker"

it "aggregates worker tokens from a nested usage block"
run_hook "$HOOK" '{"agent_type":"worker","usage":{"input_tokens":100,"output_tokens":20}}' "CLAUDE_PROJECT_DIR=$home"
assert_eq "100" "$(tok workers input)"
assert_eq "20"  "$(tok workers output)"

it "accumulates across several stops rather than overwriting"
run_hook "$HOOK" '{"agent_type":"worker","usage":{"input_tokens":50,"output_tokens":5}}' "CLAUDE_PROJECT_DIR=$home"
assert_eq "150" "$(tok workers input)"
assert_eq "25"  "$(tok workers output)"

it "accepts top-level token fields too"
run_hook "$HOOK" '{"agent_type":"scrutiny-validator","input_tokens":7,"output_tokens":3}' "CLAUDE_PROJECT_DIR=$home"
assert_eq "7" "$(tok scrutiny input)"

it "maps each agent type to its own role bucket"
run_hook "$HOOK" '{"agent_type":"user-testing-validator","usage":{"input_tokens":11,"output_tokens":1}}' "CLAUDE_PROJECT_DIR=$home"
run_hook "$HOOK" '{"agent_type":"explorer","usage":{"input_tokens":13,"output_tokens":2}}' "CLAUDE_PROJECT_DIR=$home"
assert_eq "11" "$(tok user_testing input)"
assert_eq "13" "$(tok explorers input)"

it "leaves status.json valid JSON after every update"
jq -e . "$sf" >/dev/null 2>&1; assert_rc 0 $?

it "ignores an unknown agent type without corrupting the tokens block"
before="$(cat "$sf")"
run_hook "$HOOK" '{"agent_type":"mystery","usage":{"input_tokens":99,"output_tokens":99}}' "CLAUDE_PROJECT_DIR=$home"
assert_eq "$(jq -S .tokens <<<"$before")" "$(jq -S .tokens "$sf")"

it "exits 0 when the mission has no tokens block at all"
home2="$(mktmphome)"
mkmission "$home2" 2026-04-02-m '{"state":"executing","features":[]}' >/dev/null
run_hook "$HOOK" '{"agent_type":"worker","usage":{"input_tokens":5,"output_tokens":5}}' "CLAUDE_PROJECT_DIR=$home2"
assert_rc 0 "$HOOK_RC"

it "exits 0 with no missions at all"
run_hook "$HOOK" '{"agent_type":"worker"}' "CLAUDE_PROJECT_DIR=$(mktmphome)"
assert_rc 0 "$HOOK_RC"

finish
