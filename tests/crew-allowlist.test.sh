#!/usr/bin/env bash
# Tests for scripts/crew/allowlist.py.
#
# This file's two lessons both come from a shipped failure: patterns contain
# spaces so they must travel as a LIST, and Claude Code's syntax uses a COLON.
# Getting either wrong left the first real crewmate unable to commit, run its
# own test, or report progress — while every unit test passed.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

AL="$HARNESS_ROOT/scripts/crew/allowlist.py"
al() { HOOK_OUT="$("$AL" "$@")"; export HOOK_OUT; }
has() { printf '%s' "$HOOK_OUT" | jq -e --arg p "$1" 'index($p) != null' >/dev/null 2>&1; }

it "emits a JSON array, not a string"
al --say /x/say.sh
printf '%s' "$HOOK_OUT" | jq -e 'type == "array"' >/dev/null 2>&1; assert_rc 0 $?

it "grants the commands a crewmate needs to do and record its work"
for p in "Read" "Edit" "Write" "Bash(git add:*)" "Bash(git commit:*)"; do
  has "$p" || _fail "missing $p"
done

it "always grants the one command it may use to speak to its supervisor"
# Its ledger is outside the worktree; without this the brief asks for progress
# reports the sandbox forbids.
has "Bash(/x/say.sh:*)" || _fail "say.sh not granted"

it "never grants a way to land its own work"
for p in "Bash(git push:*)" "Bash(gh:*)" "Bash(git merge:*)"; do
  has "$p" && _fail "must not grant $p"
done

it "normalises however a human wrote the registry entry"
# 'bun *' / 'bun' / 'bun:*' all mean the same thing to a human.
al --say /x/s.sh --project-allow "bun *"
has "Bash(bun:*)" || _fail "'bun *' did not normalise"
al --say /x/s.sh --project-allow "bun"
has "Bash(bun:*)" || _fail "'bun' did not normalise"
al --say /x/s.sh --project-allow "bun:*"
has "Bash(bun:*)" || _fail "'bun:*' did not normalise"

it "uses a colon, never a space — the syntax that silently matched nothing"
al --say /x/s.sh --project-allow "make test"
has "Bash(make test:*)" || _fail "multi-word command lost"
has "Bash(make test)"   && _fail "emitted the space form that matches nothing"

it "keeps a multi-word pattern as ONE array entry"
# The bug: joining on spaces and re-splitting made each pattern argv fragments.
al --say /x/s.sh --project-allow "npx expo start"
n="$(printf '%s' "$HOOK_OUT" | jq -r '[.[] | select(startswith("Bash(npx"))] | length')"
assert_eq "1" "$n"

it "handles several registry commands"
al --say /x/s.sh --project-allow "bun *, make test, cargo build"
for p in "Bash(bun:*)" "Bash(make test:*)" "Bash(cargo build:*)"; do
  has "$p" || _fail "missing $p"
done

it "ignores empty entries and stray whitespace"
al --say /x/s.sh --project-allow " , bun * ,, "
has "Bash(bun:*)" || _fail "lost the real entry"
printf '%s' "$HOOK_OUT" | jq -e 'all(.[]; . != "Bash(:*)")' >/dev/null 2>&1; assert_rc 0 $?

it "a scout may read anything and write only its report"
al --say /x/s.sh --scout
has "Read" || _fail "scout cannot read"
has "Write" || _fail "scout cannot write its report"
has "Bash(git commit:*)" && _fail "a scout must not commit"
has "Bash(/x/s.sh:*)" || _fail "a scout must still be able to report"

it "requires a say path rather than silently producing a mute crewmate"
rc=0; "$AL" --project-allow "bun *" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || _fail "should refuse without --say"

finish
