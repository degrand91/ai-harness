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

it "survives malformed input rather than exiting non-zero"
# §0.5 fixed this class in three hooks and missed this one. A hook that crashes
# on a payload it cannot read is a hook that reports a failure that did not
# happen.
run_hook "$HOOK" 'garbage' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "survives empty stdin"
run_hook "$HOOK" '' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "survives a payload with no recognisable fields"
run_hook "$HOOK" '{"nope":1}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "leaves the tokens block untouched when it cannot read the payload"
before="$(jq -S .tokens "$sf")"
run_hook "$HOOK" 'garbage' "CLAUDE_PROJECT_DIR=$home"
assert_eq "$before" "$(jq -S .tokens "$sf")"

# --- persistence: the verdict lands on disk without an orchestrator turn -----
phome="$(mktmphome)"
pd="$(mkmission "$phome" 2026-04-03-m '{"state":"executing","current_feature":"F002-followup-1","features":[],"tokens":'"$TOKENS"'}')"
mkdir -p "$pd/features/002-replay-import-ui" "$pd/features/002-followup-1-lazy-chunk"
printf '{"id":"F002"}\n' > "$pd/features/002-replay-import-ui/status.json"
printf '{"id":"F002-followup-1"}\n' > "$pd/features/002-followup-1-lazy-chunk/status.json"
msg_pl() { jq -cn --arg t "$1" --arg m "$2" '{hook_event_name:"SubagentStop",agent_type:$t,last_assistant_message:$m}'; }

it "writes a scrutiny verdict to the current feature's scrutiny.md, preamble stripped"
run_hook "$HOOK" "$(msg_pl scrutiny-validator $'Perfect, all pass.\n\n## Feature: lazy-chunk — Scrutiny Verdict: green\n\n### Assertions\n| C-1 | x | pass |')" "CLAUDE_PROJECT_DIR=$phome"
assert_rc 0 "$HOOK_RC"
f="$pd/features/002-followup-1-lazy-chunk/scrutiny.md"
assert_file_exists "$f"
assert_eq "## Feature: lazy-chunk — Scrutiny Verdict: green" "$(head -n1 "$f")"
assert_file_missing "$pd/features/002-replay-import-ui/scrutiny.md"
assert_contains "$(tail -n1 "$pd/log.md")" "scrutiny.md"

it "routes worker → handoff.md and user-testing → user-test.md"
run_hook "$HOOK" "$(msg_pl worker $'## Feature: lazy-chunk\n### What was implemented\n- x')" "CLAUDE_PROJECT_DIR=$phome"
run_hook "$HOOK" "$(msg_pl user-testing-validator $'## Feature: lazy-chunk — User-Testing Verdict: red')" "CLAUDE_PROJECT_DIR=$phome"
assert_file_exists "$pd/features/002-followup-1-lazy-chunk/handoff.md"
assert_file_exists "$pd/features/002-followup-1-lazy-chunk/user-test.md"

it "appends a second verdict on the same feature instead of overwriting"
run_hook "$HOOK" "$(msg_pl scrutiny-validator $'## Feature: lazy-chunk — Scrutiny Verdict: red')" "CLAUDE_PROJECT_DIR=$phome"
assert_contains "$(cat "$f")" "Verdict: green"
assert_contains "$(cat "$f")" "Verdict: red"
assert_contains "$(cat "$f")" "appended by SubagentStop"

it "writes nothing when the message has no ## Feature: heading"
before="$(cat "$pd"/features/002-followup-1-lazy-chunk/*.md)"
run_hook "$HOOK" "$(msg_pl scrutiny-validator 'I could not run anything.')" "CLAUDE_PROJECT_DIR=$phome"
assert_rc 0 "$HOOK_RC"
assert_eq "$before" "$(cat "$pd"/features/002-followup-1-lazy-chunk/*.md)"

it "finds the feature folder by name when it has no status.json"
rm "$pd/features/002-followup-1-lazy-chunk/status.json"
run_hook "$HOOK" "$(msg_pl worker $'## Feature: again')" "CLAUDE_PROJECT_DIR=$phome"
assert_contains "$(cat "$pd/features/002-followup-1-lazy-chunk/handoff.md")" "## Feature: again"

it "does not log stops of non-harness agents (the 30-second poll noise)"
n_before="$(wc -l < "$pd/log.md")"
run_hook "$HOOK" '{"hook_event_name":"SubagentStop","agent_type":"orchestrator","usage":{"input_tokens":5,"output_tokens":5}}' "CLAUDE_PROJECT_DIR=$phome"
run_hook "$HOOK" '{"hook_event_name":"SubagentStop","agent_type":"subagent"}' "CLAUDE_PROJECT_DIR=$phome"
assert_rc 0 "$HOOK_RC"
assert_eq "$n_before" "$(wc -l < "$pd/log.md")"

it "dumps the raw payload for inspection"
assert_file_exists "$phome/state/last-subagent-stop.json"

# --- tokens from the transcript: the payload carries none on 2.1.278 ---------
thome="$(mktmphome)"
td="$(mkmission "$thome" 2026-04-04-m '{"state":"executing","features":[],"tokens":'"$TOKENS"'}')"
tr="$thome/agent-x.jsonl"
{
  printf '{"type":"user","message":{"content":"task"}}\n'
  printf '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":27632,"cache_read_input_tokens":0,"output_tokens":1}}}\n'
  printf '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"cache_creation_input_tokens":27632,"cache_read_input_tokens":0,"output_tokens":188}}}\n'
  printf '{"type":"attachment","attachment":{"type":"date"}}\n'
  printf '{"type":"assistant","message":{"id":"m2","usage":{"input_tokens":8,"cache_creation_input_tokens":1506,"cache_read_input_tokens":27632,"output_tokens":130}}}\n'
} > "$tr"

it "sums usage from agent_transcript_path when the payload has no usage, deduping streamed partials by message id"
run_hook "$HOOK" "$(jq -cn --arg t "$tr" '{agent_type:"worker",agent_transcript_path:$t}')" "CLAUDE_PROJECT_DIR=$thome"
assert_rc 0 "$HOOK_RC"
assert_eq "29156" "$(jq -r .tokens.workers.input "$td/status.json")"
assert_eq "318"   "$(jq -r .tokens.workers.output "$td/status.json")"
assert_eq "27632" "$(jq -r .tokens.workers.cache_read "$td/status.json")"
assert_contains "$(tail -n1 "$td/log.md")" "+27632cached"

it "prefers payload usage over the transcript when both exist"
run_hook "$HOOK" "$(jq -cn --arg t "$tr" '{agent_type:"worker",agent_transcript_path:$t,usage:{input_tokens:1,output_tokens:1}}')" "CLAUDE_PROJECT_DIR=$thome"
assert_eq "29157" "$(jq -r .tokens.workers.input "$td/status.json")"

it "ignores an unreadable transcript path"
run_hook "$HOOK" '{"agent_type":"worker","agent_transcript_path":"/nonexistent/x.jsonl"}' "CLAUDE_PROJECT_DIR=$thome"
assert_rc 0 "$HOOK_RC"
assert_eq "29157" "$(jq -r .tokens.workers.input "$td/status.json")"

finish
