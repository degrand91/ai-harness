#!/usr/bin/env bash
# Tests for scripts/crew/guard-pretool.sh — the crewmate sandbox's last layer.
#
# This is SECURITY-CRITICAL and was completely untested. It is the only one of
# the three sandbox layers that fires regardless of permission mode, so it is
# what still holds when the tool allowlist is misconfigured — and the allowlist
# has already been misconfigured once, in a way that shipped.
#
# A crewmate must never land its own work. The supervisor does that, under the
# delivery mode recorded at spawn.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

WT="/tmp/wt-fixture"
guard() {  # <command>
  local outf errf; outf="$(mktemp)"; errf="$(mktemp)"; HOOK_RC=0
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
    | "$HARNESS_ROOT/scripts/crew/guard-pretool.sh" "$WT" >"$outf" 2>"$errf" || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; HOOK_ERR="$(cat "$errf")"; rm -f "$outf" "$errf"
  export HOOK_OUT HOOK_ERR HOOK_RC
}
refused() { guard "$1"; [ "$HOOK_RC" -eq 2 ] || _fail "should have refused: $1 (got $HOOK_RC)"; }
allowed() { guard "$1"; [ "$HOOK_RC" -eq 0 ] || _fail "should have allowed: $1 (got $HOOK_RC)"; }

it "refuses every way a crewmate could land its own work"
refused "git push"
refused "git push origin main"
refused "git push --force origin HEAD"
refused "gh pr merge 12 --squash"
refused "gh pr create --fill"
refused "git merge main"

it "refuses destructive git that would discard the supervisor's view of the work"
refused "git reset --hard HEAD~1"
refused "git worktree remove ."
refused "git worktree add /tmp/x"

it "refuses an absolute rm -rf"
refused "rm -rf /"
refused "rm -rf /etc"

it "refuses leaving the worktree"
refused "cd / && ls"
refused "cd .. && cat secrets"
refused "cd ~ && ls"

it "catches a refused command chained behind an allowed one"
# A guard that only reads the first command is not a guard.
refused "git status && git push"
refused "echo hi; git push origin main"
refused "true || gh pr merge 1"

it "allows the work a crewmate is actually for"
allowed "git add -A"
allowed "git commit -m 'feat: a thing'"
allowed "git status --short"
allowed "git diff HEAD"
allowed "git log --oneline -5"

it "allows an ordinary build or test command"
allowed "bun test"
allowed "make test"
allowed "./run-tests.sh"

it "ignores tools that are not Bash"
outf="$(mktemp)"; rc=0
printf '{"tool_name":"Write","tool_input":{"file_path":"/x","content":"git push"}}' \
  | "$HARNESS_ROOT/scripts/crew/guard-pretool.sh" "$WT" >"$outf" 2>&1 || rc=$?
rm -f "$outf"
assert_rc 0 "$rc"

it "fails OPEN on malformed input rather than blocking all work"
# A guard that crashes into a refusal would strand a crewmate on a bad payload.
rc=0; printf 'not json' | "$HARNESS_ROOT/scripts/crew/guard-pretool.sh" "$WT" >/dev/null 2>&1 || rc=$?
assert_rc 0 "$rc"
rc=0; printf '' | "$HARNESS_ROOT/scripts/crew/guard-pretool.sh" "$WT" >/dev/null 2>&1 || rc=$?
assert_rc 0 "$rc"
rc=0; printf '{"tool_name":"Bash","tool_input":{}}' | "$HARNESS_ROOT/scripts/crew/guard-pretool.sh" "$WT" >/dev/null 2>&1 || rc=$?
assert_rc 0 "$rc"

it "explains itself to the crewmate rather than just refusing"
guard "git push origin main"
assert_contains "$HOOK_ERR" "does not land its own work"
assert_contains "$HOOK_ERR" "ledger"

it "writes nothing to stdout"
guard "git push"
assert_eq "" "$HOOK_OUT"

it "works with no worktree argument at all"
rc=0
printf '{"tool_name":"Bash","tool_input":{"command":"git push"}}' \
  | "$HARNESS_ROOT/scripts/crew/guard-pretool.sh" >/dev/null 2>&1 || rc=$?
assert_rc 2 "$rc"

finish
