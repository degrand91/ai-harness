#!/usr/bin/env bash
# Tests for scripts/safe-push.sh - a push that can never hang the feature loop.
#
# 2026-10-02: one worker `git push` hung 146 minutes on a stalled HTTPS
# connection. These tests pin the three guarantees: a normal push works, a
# failing remote gives up after the stated attempts, and a hung git is killed
# by the wall clock instead of blocking forever.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

SP="$HARNESS_ROOT/scripts/safe-push.sh"
work="$(mktemp -d)"
git init -q --bare "$work/remote.git"
git init -q "$work/repo"
git -C "$work/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$work/repo" remote add origin "$work/remote.git"

run() {
  local outf; outf="$(mktemp)"
  RC=0
  SAFE_PUSH_BACKOFF=0 "$@" >"$outf" 2>&1 || RC=$?
  OUT="$(cat "$outf")"; rm -f "$outf"
}

it "pushes to a reachable remote"
run "$SP" "$work/repo" origin HEAD:refs/heads/main
assert_rc 0 "$RC"
assert_contains "$OUT" "pushed HEAD:refs/heads/main"
assert_eq "$(git -C "$work/repo" rev-parse HEAD)" "$(git -C "$work/remote.git" rev-parse main)"

it "gives up after the stated attempts on an unreachable remote"
run "$SP" "$work/repo" "$work/nowhere.git" HEAD:refs/heads/main --attempts 2
assert_rc 1 "$RC"
assert_contains "$OUT" "attempt 2/2 failed"
assert_contains "$OUT" "still local"

it "kills a hung git with the wall clock"
stub="$work/hang-git"
printf '#!/usr/bin/env bash\nsleep 30\n' >"$stub"; chmod +x "$stub"
start=$(date +%s)
SAFE_PUSH_GIT="$stub" run "$SP" "$work/repo" origin HEAD:refs/heads/main --attempts 1 --attempt-seconds 1
elapsed=$(( $(date +%s) - start ))
assert_rc 1 "$RC"
assert_eq "yes" "$([ "$elapsed" -lt 10 ] && echo yes || echo "no (${elapsed}s)")"

it "rejects a bad call with usage"
run "$SP" "$work/repo" origin
assert_rc 2 "$RC"
run "$SP" "$work/repo" origin HEAD --attempts x
assert_rc 2 "$RC"

rm -rf "$work"
finish
