#!/usr/bin/env bash
# Tests for .claude/hooks/post-tool-use-failure.sh — records tool failures to
# the active mission log. Must never interfere with error handling: always 0.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
HOOK=post-tool-use-failure.sh
home="$(mktmphome)"
d="$(mkmission "$home" 2026-03-01-m)"

it "logs a tool failure"
run_hook "$HOOK" '{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","error":"boom"}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
log="$(cat "$d/log.md")"
assert_contains "$log" "tool-failure"
assert_contains "$log" "Bash"
assert_contains "$log" "boom"

it "truncates a very long error so it cannot flood the log"
long="$(printf 'x%.0s' $(seq 1 900))"
run_hook "$HOOK" "$(jq -nc --arg e "$long" '{tool_name:"Bash",error:$e}')" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
last="$(tail -n1 "$d/log.md")"
[ "${#last}" -lt 400 ] || _fail "log line not truncated: ${#last} chars"

it "exits 0 with no mission present"
empty="$(mktmphome)"
run_hook "$HOOK" '{"tool_name":"Bash","error":"boom"}' "CLAUDE_PROJECT_DIR=$empty"
assert_rc 0 "$HOOK_RC"

it "exits 0 when CLAUDE_PROJECT_DIR is unset"
run_hook "$HOOK" '{"tool_name":"Bash","error":"boom"}' "CLAUDE_PROJECT_DIR="
assert_rc 0 "$HOOK_RC"

it "survives malformed JSON"
run_hook "$HOOK" 'not json' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

finish
