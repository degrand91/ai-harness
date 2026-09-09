#!/usr/bin/env bash
# Tests for scripts/memory-budget.sh and its use by SessionStart.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
mb() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/memory-budget.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

it "falls back to a documented default"
mb read
assert_rc 0 "$HOOK_RC"
assert_eq "7500" "$HOOK_OUT"

it "reads a configured budget"
printf '2000\n' > "$home/config/startup-memory-budget"
mb read
assert_eq "2000" "$HOOK_OUT"

it "treats a malformed budget as an error, not a silent fallback"
# An operator who wrote a budget deserves to know it was ignored.
printf 'lots\n' > "$home/config/startup-memory-budget"
mb read
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not a positive integer"
rm -f "$home/config/startup-memory-budget"

it "passes short input through untouched"
out="$(printf 'one\ntwo\n' | CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/memory-budget.sh" fit 1000)"
assert_eq "one
two" "$out"

it "truncates on a line boundary and says how much it dropped"
out="$(printf 'aaaa\nbbbb\ncccc\ndddd\neeee\n' | CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/memory-budget.sh" fit 2)"
assert_contains "$out" "aaaa"
assert_contains "$out" "omitted to stay inside the startup memory budget"
assert_not_contains "$out" "eeee"

it "never emits a partial line"
# Losing the tail silently is how a session starts believing a half-told story.
printf '%s' "$out" | while IFS= read -r l; do
  case "$l" in ''|\[*) continue ;; esac
  [ "${#l}" -eq 4 ] || _fail "partial line emitted: [$l]"
done

it "SessionStart output stays inside a small configured budget"
printf '200\n' > "$home/config/startup-memory-budget"
for i in $(seq 1 6); do
  mkmission "$home" "2026-01-0$i-m" '{"state":"executing","current_feature":"F001","features":[]}' >/dev/null
  for j in $(seq 1 40); do echo "a long log line number $j with plenty of text in it" >> "$home/missions/2026-01-0$i-m/log.md"; done
done
run_hook session-start-inject-status.sh '{"hook_event_name":"SessionStart","session_id":"s"}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"
ctx="$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.additionalContext // ""')"
[ "${#ctx}" -le 1200 ] || _fail "context was ${#ctx} chars, over the ~200-token budget"
assert_contains "$ctx" "omitted"

it "still emits valid JSON after truncation"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

finish
