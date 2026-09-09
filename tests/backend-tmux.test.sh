#!/usr/bin/env bash
# Tests for scripts/crew/backend-tmux.sh, against REAL tmux.
#
# Skipped when tmux is absent, so CI stays green on a box without it — but the
# bug this pins could only ever be found here. `tmux new-window -t <session>`
# targets WINDOW <session>:0, not "the session's next free index", so the first
# spawn into a fresh session failed with "index 0 in use". The fake backend
# cannot reproduce it, and one earlier real run got past it by luck of indices.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

if ! command -v tmux >/dev/null 2>&1; then
  it "skipped: tmux is not installed"
  finish
fi

export HARNESS_TMUX_SESSION="harness-test-$$"
cleanup_tmux() { tmux kill-session -t "$HARNESS_TMUX_SESSION" 2>/dev/null || true; }
trap cleanup_tmux EXIT
cleanup_tmux

export HARNESS_CREW_BACKEND=tmux
# shellcheck source=../scripts/crew/backend.sh
. "$HARNESS_ROOT/scripts/crew/backend.sh"

it "the FIRST spawn into a fresh session succeeds"
# The regression. Everything below depends on this working.
backend_open t1 /tmp "/tmp/bt-$$-1.log" /bin/sleep 30
assert_rc 0 $?

it "the window exists and is reported alive"
backend_alive t1; assert_rc 0 $?

it "a second window opens alongside the first"
backend_open t2 /tmp "/tmp/bt-$$-2.log" /bin/sleep 30
assert_rc 0 $?
backend_alive t2; assert_rc 0 $?
backend_alive t1; assert_rc 0 $?

it "a task that was never opened is not alive"
backend_alive never-opened; assert_rc 1 $?

it "capture returns without error"
backend_capture t1 5 >/dev/null 2>&1; assert_rc 0 $?

it "kill removes one window and leaves the other"
backend_kill t1
backend_alive t1; assert_rc 1 $?
backend_alive t2; assert_rc 0 $?

it "killing an already-dead task is not an error"
backend_kill t1; assert_rc 0 $?
backend_kill never-opened; assert_rc 0 $?

it "targets the session's next free index, not window 0"
# The regression, pinned at the source: `-t <session>` means window <session>:0,
# so the first spawn into a fresh session failed with "index 0 in use". The
# trailing colon is what makes it mean "next free index".
code="$(grep -vE '^[[:space:]]*#' "$HARNESS_ROOT/scripts/crew/backend-tmux.sh")"
assert_contains "$code" '"${_TMUX_SESSION}:"'

it "does not swallow tmux's own error message"
# The original discarded stderr, so "index 0 in use" was invisible and the
# caller saw only a bare non-zero exit — which is how it survived a real run.
assert_contains "$code" "tmux could not open a window"
assert_not_contains "$code" 'new-window -d -t "$_TMUX_SESSION" -n "hc-$task" -c "$cwd" \'"''"

backend_kill t2
rm -f "/tmp/bt-$$-1.log" "/tmp/bt-$$-2.log" "/tmp/bt-$$-3.log"
finish
