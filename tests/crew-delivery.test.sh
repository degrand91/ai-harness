#!/usr/bin/env bash
# Delivery: what teardown actually does with a finished crewmate's branch, per
# mode. crew-lifecycle covers the failure path (direct-PR with no remote);
# this covers the paths that succeed, which nothing exercised before -- the
# harness had shipped direct-PR and no-mistakes without ever landing one.
#
# `origin` is a real local bare repo, so `git push` is the real thing. Only `gh`
# is stubbed, because the alternative is opening pull requests from the suite.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
export CREW_FAKE_LOG="$home/fake.log"; : > "$CREW_FAKE_LOG"
GH_LOG="$home/gh.log"; : > "$GH_LOG"

# A stub `gh` that records its argv. PATH is prepended per-invocation so the
# "gh not installed" case can drop it without disturbing anything else.
stubdir="$home/stub"; mkdir -p "$stubdir"
cat > "$stubdir/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
[ -n "$GH_FAIL_CREATE" ] && [ "$1 $2" = "pr create" ] && exit 1
case "$1 $2" in
  "pr create") printf 'https://github.test/fake/pull/7\n' ;;
  "pr view")   printf 'https://github.test/fake/pull/existing\n' ;;
esac
GH
chmod +x "$stubdir/gh"
export GH_LOG

crew() {
  local s="$1"; shift
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  PATH="$stubdir:$PATH" CLAUDE_PROJECT_DIR="$home" HARNESS_CREW_BACKEND=fake \
    "$HARNESS_ROOT/scripts/crew/$s" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

mkmission "$home" m1 '{"state":"executing","features":[
  {"id":"D001","slug":"a","state":"in_progress"},{"id":"D002","slug":"b","state":"in_progress"},
  {"id":"D003","slug":"c","state":"in_progress"},{"id":"N001","slug":"d","state":"in_progress"},
  {"id":"L001","slug":"e","state":"in_progress"},{"id":"L002","slug":"f","state":"in_progress"},
  {"id":"N002","slug":"g","state":"in_progress"},{"id":"N003","slug":"h","state":"in_progress"}]}' >/dev/null

# A project with a real remote, so push is genuine.
remote="$home/origin.git"; git init -q --bare "$remote"
mkproj() {  # <name> <mode>
  local p="$home/$1"; mkdir -p "$p"; git -C "$p" init -q -b main
  printf 'x\n' > "$p/a.txt"; git -C "$p" add -A
  git -C "$p" -c user.email=t@t -c user.name=t commit -qm init
  git -C "$p" remote add origin "$remote" 2>/dev/null || true
  git -C "$p" push -q -u origin main 2>/dev/null || true
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" \
    add "$1" "$p" --mode "$2" >/dev/null 2>&1
}
# Land a crewmate: brief, spawn, make a commit in the worktree, report done.
work() {  # <task> <project> <mode>
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/crew/brief.sh" m1 "$1" \
    --intent <(echo "do it") --spec <(echo "simply") --done <(echo "tests pass") \
    --mode "$3" --yolo off >/dev/null 2>&1
  crew spawn.sh m1 "$1" --project "$2" --mode "$3" --yolo off
  local wt; wt="$(crew_meta_get "$home" "$1" worktree)"
  printf '%s\n' "$1" > "$wt/$1.txt"
  git -C "$wt" add -A
  git -C "$wt" -c user.email=c@c -c user.name=c commit -qm "feat: $1"
  crew_ledger_append "$home" "$1" "done" "ready"
}

# --- direct-PR ---------------------------------------------------------------
mkproj pr-proj direct-PR

it "direct-PR pushes the branch and opens a pull request"
work D001 pr-proj direct-PR
crew teardown.sh D001
assert_rc 0 "$HOOK_RC"
assert_contains "$(git -C "$remote" branch --list)" "hc/m1/d001"
assert_contains "$(cat "$GH_LOG")" "pr create --head hc/m1/d001 --fill"

it "and records the PR url somewhere that outlives the teardown"
# The pending record is deleted on success and stdout may scroll past an
# operator who is away, so the feature is the only durable home for it.
assert_file_missing "$home/state/D001.close-pending"
assert_eq "https://github.test/fake/pull/7" \
  "$(jq -r '.features[] | select(.id=="D001") | .pr_url' "$home/missions/m1/status.json")"

it "and the commit really reached the remote, not just the branch ref"
assert_contains "$(git -C "$remote" show --stat --oneline HEAD:D001.txt 2>&1 || \
                   git -C "$remote" ls-tree -r --name-only hc/m1/d001)" "D001.txt"

it "direct-PR keeps the branch, since the PR is still open against it"
assert_contains "$(git -C "$home/pr-proj" branch --list 'hc/*')" "d001"

it "and removes the worktree it no longer needs"
[ ! -d "$home/data/worktrees/pr-proj/D001" ] || _fail "worktree left behind"
assert_not_contains "$(git -C "$home/pr-proj" worktree list)" "D001"

it "falls back to the existing PR when one is already open for the branch"
# `gh pr create` fails on a branch that already has a PR; that is not a
# delivery failure, and re-running teardown must not report one.
work D002 pr-proj direct-PR
GH_FAIL_CREATE=1 crew teardown.sh D002
assert_rc 0 "$HOOK_RC"
assert_eq "https://github.test/fake/pull/existing" \
  "$(jq -r '.features[] | select(.id=="D002") | .pr_url' "$home/missions/m1/status.json")"

it "fails loudly when gh is missing, having pushed the branch"
# The push is done and must not be silently reported as a full delivery: the
# operator has to open the PR by hand.
work D003 pr-proj direct-PR
outf="$(mktemp)"; HOOK_RC=0
CLAUDE_PROJECT_DIR="$home" HARNESS_CREW_BACKEND=fake PATH="/usr/bin:/bin" \
  "$HARNESS_ROOT/scripts/crew/teardown.sh" D003 >"$outf" 2>&1 || HOOK_RC=$?
HOOK_OUT="$(cat "$outf")"; rm -f "$outf"
assert_rc 1 "$HOOK_RC"
assert_contains "$HOOK_OUT" "gh not installed"
assert_contains "$(git -C "$remote" branch --list)" "hc/m1/d003"

it "and keeps the worktree so the delivery can be retried"
[ -d "$home/data/worktrees/pr-proj/D003" ] || _fail "worktree removed after a failed delivery"
assert_file_exists "$home/state/D003.close-pending"

it "and retrying once gh is back completes the delivery"
crew teardown.sh D003
assert_rc 0 "$HOOK_RC"
assert_file_missing "$home/state/D003.meta"

it "warns rather than losing the url when the mission has no such feature"
work D004 pr-proj direct-PR
crew teardown.sh D004
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not in m1 features[]"
assert_contains "$HOOK_OUT" "https://github.test/fake/pull/7"

# --- no-mistakes -------------------------------------------------------------
mkproj nm-proj no-mistakes

it "no-mistakes lands like direct-PR but says it degraded"
work N001 nm-proj no-mistakes
crew teardown.sh N001
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "degraded to direct-PR"
assert_contains "$(git -C "$remote" branch --list)" "hc/m1/n001"

it "and files a decision rather than quietly skipping its own gate"
# The registered posture asked for a gate that did not run. Degrading silently
# would make no-mistakes indistinguishable from direct-PR.
q="$(cat "$home/missions/m1/decisions/"*.json 2>/dev/null)"
assert_contains "$q" "N001"
assert_contains "$q" "gate"

# A project that really has a gate. The stub sits where the real per-project
# devDependency does; gate.test.sh pins it against the published contract.
nm_stub() {  # <project-root> <check-json>
  mkdir -p "$1/node_modules/.bin"
  cat > "$1/node_modules/.bin/no-mistakes" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "config resolve") printf '%s\n' '{"configPath":".no-mistakes.json"}' ;;
  *) printf '%s\n' '$2' ;;
esac
STUB
  chmod +x "$1/node_modules/.bin/no-mistakes"
}
CLEAN_REPORT='{"react":[],"queues":[],"rules":[],"integration":[],"codebase":[],"advisories":[],"warnings":[]}'
DIRTY_REPORT='{"react":[],"queues":[],"integration":[],"codebase":[],"advisories":[],"warnings":[],"rules":[{"rule":"no-cross-import","file":"src/a.ts","line":3,"message":"nope"}]}'

it "a passing gate delivers, and says the gate actually ran"
work N002 nm-proj no-mistakes
nm_stub "$(crew_meta_get "$home" N002 worktree)" "$CLEAN_REPORT"
crew teardown.sh N002
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "gate passed"
assert_not_contains "$HOOK_OUT" "degraded"
assert_contains "$(git -C "$remote" branch --list)" "hc/m1/n002"

it "a failing gate blocks delivery instead of opening a PR"
work N003 nm-proj no-mistakes
nm_stub "$(crew_meta_get "$home" N003 worktree)" "$DIRTY_REPORT"
crew teardown.sh N003
assert_rc 1 "$HOOK_RC"
assert_contains "$HOOK_OUT" "no-cross-import"
assert_not_contains "$(git -C "$remote" branch --list)" "hc/m1/n003"

it "and keeps the branch and worktree so the crewmate can fix it"
[ -d "$home/data/worktrees/nm-proj/N003" ] || _fail "worktree removed after a blocked gate"
assert_file_exists "$home/state/N003.close-pending"

it "and files a decision, since a blocked delivery needs a human call"
assert_contains "$(cat "$home/missions/m1/decisions/"*.json)" "failed its no-mistakes gate"

# --- local-only --------------------------------------------------------------
mkproj lo-proj local-only

it "local-only fast-forwards into the primary checkout"
work L001 lo-proj local-only
crew teardown.sh L001
assert_rc 0 "$HOOK_RC"
assert_file_exists "$home/lo-proj/L001.txt"

it "and deletes the branch, which has served its purpose"
assert_not_contains "$(git -C "$home/lo-proj" branch --list 'hc/*')" "l001"

it "and pushes nothing"
assert_not_contains "$(git -C "$remote" branch --list)" "hc/m1/l001"

it "refuses to land when the default branch moved under the crewmate"
# Fast-forward only: resolving a real merge is the captain's call, and doing it
# unattended is how a crewmate's work gets silently reverted.
work L002 lo-proj local-only
printf 'captain was here\n' >> "$home/lo-proj/a.txt"
git -C "$home/lo-proj" -c user.email=t@t -c user.name=t commit -qam "captain's own commit"
crew teardown.sh L002
assert_rc 1 "$HOOK_RC"
assert_contains "$HOOK_OUT" "cannot fast-forward"

it "and keeps everything in place for the captain to resolve"
[ -d "$home/data/worktrees/lo-proj/L002" ] || _fail "worktree removed despite failed delivery"
assert_file_exists "$home/state/L002.close-pending"
assert_contains "$(git -C "$home/lo-proj" branch --list 'hc/*')" "l002"

finish
