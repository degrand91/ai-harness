#!/usr/bin/env bash
# End-to-end crew lifecycle against the fake backend: brief -> spawn -> steer ->
# peek -> reconcile -> teardown. No tmux, no model calls.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
export CREW_FAKE_LOG="$home/fake.log"; : > "$CREW_FAKE_LOG"
crew() {
  local s="$1"; shift
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" HARNESS_CREW_BACKEND=fake \
    "$HARNESS_ROOT/scripts/crew/$s" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
mkmission "$home" m1 '{"state":"executing","features":[]}' >/dev/null
proj="$home/proj"; mkdir -p "$proj"; git -C "$proj" init -q
printf 'x\n' > "$proj/a.txt"; git -C "$proj" add -A
git -C "$proj" -c user.email=t@t -c user.name=t commit -qm init
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" add alpha "$proj" --mode direct-PR --allow "make test" >/dev/null 2>&1
mkbrief() {  # <task> <mode>
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/crew/brief.sh" m1 "$1" \
    --intent <(echo "fix the thing") --spec <(echo "simply") --done <(echo "tests pass") \
    --mode "$2" --yolo off >/dev/null 2>&1
}

# --- brief -------------------------------------------------------------------
it "refuses a brief with no captain's intent"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/crew/brief.sh" m1 FX \
  --intent <(echo "") --spec <(echo "s") --done <(echo "d") --mode direct-PR --yolo off >/dev/null 2>&1
assert_rc 2 $?

it "renders a brief that separates intent from spec"
mkbrief F001 direct-PR
b="$(cat "$home/missions/m1/briefs/F001.md")"
assert_contains "$b" "## Captain's intent"
assert_contains "$b" "## Harness spec"
assert_contains "$b" "mode=direct-PR"

# --- spawn -------------------------------------------------------------------
it "refuses to spawn for an unregistered project"
crew spawn.sh m1 F001 --project ghost --mode direct-PR --yolo off
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not registered"

it "refuses when the brief's delivery contract disagrees with the flag"
crew spawn.sh m1 F001 --project alpha --mode local-only --yolo off
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "drift apart"

it "spawns a crewmate into its own worktree on its own branch"
crew spawn.sh m1 F001 --project alpha --mode direct-PR --yolo off
assert_rc 0 "$HOOK_RC"
assert_file_exists "$home/state/F001.meta"
[ -d "$home/data/worktrees/alpha/F001" ] || _fail "worktree not created"
assert_eq "hc/m1/f001" "$(crew_meta_get "$home" F001 branch)"

it "injects the crewmate-side hooks into the worktree, not the project"
s="$home/data/worktrees/alpha/F001/.claude/settings.local.json"
assert_file_exists "$s"
keys="$(jq -r '.hooks | keys | join(",")' "$s")"
assert_contains "$keys" "Stop"
assert_contains "$keys" "PreToolUse"
assert_file_missing "$proj/.claude/settings.local.json"

it "grants the project's registered commands and nothing more"
allow="$(crew_meta_get "$home" F001 allow_tools)"
assert_contains "$allow" "Bash(make test)"
assert_contains "$allow" "Bash(git commit:*)"
assert_not_contains "$allow" "Bash(git push"
assert_contains "$(crew_meta_get "$home" F001 deny_tools)" "WebFetch"

it "launches run.sh rather than claude directly"
assert_contains "$(cat "$CREW_FAKE_LOG")" "crew/run.sh"

it "never passes --dangerously-skip-permissions"
assert_not_contains "$(cat "$HARNESS_ROOT/scripts/crew/run.sh")" "dangerously-skip-permissions"

it "refuses to spawn the same task twice"
crew spawn.sh m1 F001 --project alpha --mode direct-PR --yolo off
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "already exists"
assert_contains "$HOOK_OUT" "in flight"

it "enforces the mission's concurrency limit, which ships at 1"
# protocols/serial-execution.md bans concurrent workers for correctness. Crew
# separates "own process" from "at the same time"; only the first is new.
mkbrief F900 direct-PR
crew spawn.sh m1 F900 --project alpha --mode direct-PR --yolo off
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "in flight and allows 1"

# --- steering ----------------------------------------------------------------
it "a steer is written to disk before any signal is sent"
crew send.sh F001 "use the retry helper"
assert_rc 0 "$HOOK_RC"
found="$(find "$home/state/F001.inbox" -name '*.md' | head -n1)"
[ -n "$found" ] || _fail "steer not written to the inbox"
assert_contains "$(cat "$found")" "retry helper"

it "refuses a steer to an unknown task rather than guessing"
crew send.sh F999 "hello"
assert_rc 1 "$HOOK_RC"
assert_contains "$HOOK_OUT" "refusing to guess"

it "refuses an empty steer"
crew send.sh F001 ""
assert_rc 2 "$HOOK_RC"

# --- peek --------------------------------------------------------------------
it "peek shows the ledger before the window"
crew peek.sh F001 5
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "ledger"
assert_contains "$HOOK_OUT" "started:"

# --- reconcile ---------------------------------------------------------------
it "reconcile reports a crewmate with no runner as suspicious, not failed"
crew reconcile.sh
assert_rc 3 "$HOOK_RC"
assert_contains "$HOOK_OUT" "SUSPICIOUS"
assert_not_contains "$(cat "$home/state/F001.ledger")" "failed:"

it "reconcile trusts a terminal ledger line over process state"
crew_ledger_append "$home" F001 "done" "commit abc123"
crew reconcile.sh
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "done"
assert_not_contains "$HOOK_OUT" "SUSPICIOUS"

it "reconcile treats blocked as waiting, not finished"
mkbrief F002 direct-PR
crew spawn.sh m1 F002 --project alpha --mode direct-PR --yolo off
crew_ledger_append "$home" F002 blocked "needs a credential"
crew reconcile.sh
assert_contains "$HOOK_OUT" "blocked"
assert_contains "$HOOK_OUT" "attach"

# --- teardown ----------------------------------------------------------------
it "refuses to tear down a crewmate that never reported done"
crew teardown.sh F002
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not done"

it "abandoning is explicit, and cleans up the worktree and branch"
crew teardown.sh F002 --abandon
assert_rc 0 "$HOOK_RC"
assert_file_missing "$home/state/F002.meta"
[ ! -d "$home/data/worktrees/alpha/F002" ] || _fail "worktree not removed"
assert_not_contains "$(git -C "$proj" branch --list 'hc/*')" "f002"

it "leaves no stale worktree registration in the project"
assert_not_contains "$(git -C "$proj" worktree list)" "F002"

it "writes a pending-close record before doing anything destructive"
# The completion links live only in the record teardown is about to delete.
assert_contains "$(cat "$HARNESS_ROOT/scripts/crew/teardown.sh")" "close-pending"

it "tearing down a done crewmate with no remote fails loudly and keeps the worktree"
crew teardown.sh F001
assert_rc 1 "$HOOK_RC"
assert_contains "$HOOK_OUT" "delivery failed"
assert_file_exists "$home/state/F001.close-pending"
[ -d "$home/data/worktrees/alpha/F001" ] || _fail "worktree removed despite failed delivery"

finish
