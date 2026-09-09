#!/usr/bin/env bash
# Tests for .claude/hooks/post-write-mission-state.sh — appends a one-line
# audit entry to the mission log when a mission file is written.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
HOOK=post-write-mission-state.sh
home="$(mktmphome)"
d="$(mkmission "$home" 2026-02-01-m)"
pl() { printf '{"hook_event_name":"PostToolUse","tool_input":{"file_path":"%s"}}' "$1"; }

it "logs a write inside a mission folder"
run_hook "$HOOK" "$(pl "$d/features/001-x/spec.md")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_contains "$(cat "$d/log.md")" "state mutation"

it "ignores writes outside any mission folder"
before="$(cat "$d/log.md")"
run_hook "$HOOK" "$(pl "$home/learnings/patterns/x.md")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
assert_eq "$before" "$(cat "$d/log.md")"

it "does not log edits to the mission log itself (no recursion)"
before="$(cat "$d/log.md")"
run_hook "$HOOK" "$(pl "$d/log.md")" "CLAUDE_PROJECT_DIR=$home"
assert_eq "$before" "$(cat "$d/log.md")"

it "exits 0 when the payload carries no file path"
run_hook "$HOOK" '{"hook_event_name":"PostToolUse","tool_input":{}}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "exits 0 for a mission that has no log.md yet"
mkdir -p "$home/missions/2026-02-02-nolog"
run_hook "$HOOK" "$(pl "$home/missions/2026-02-02-nolog/spec.md")" "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

it "survives malformed JSON"
run_hook "$HOOK" 'garbage' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

finish
