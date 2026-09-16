#!/usr/bin/env bash
# Single owner of "is away mode in force right now".
#
# The marker file alone is NOT the answer. The daemon stops at its deadline but
# the marker survives until the operator runs `afk.sh return` -- so a bare
# `[ -f .afk ]` test leaves the watcher stood down after the daemon has already
# stopped supervising. Between those two moments nothing watches the fleet at
# all, and the only signal was a single expiry notification that may have gone
# nowhere. That is the exact failure away mode exists to prevent.
#
# Found by running away mode to expiry rather than by reading it:
# docs/verification/away-mode-drill.md.
#
# Two callers used to test the marker directly (scripts/watch.sh and
# .claude/hooks/stop-watch-rearm.sh). Two lookups of one rule is how the state
# vocabulary drifted, so the rule lives here and they both ask.

afk_marker() { printf '%s/state/.afk' "${1:?}"; }

# The marker exists -- the operator turned away mode on and has not returned.
afk_on() { [ -f "$(afk_marker "${1:?}")" ]; }

afk_expired() {  # <harness_root>
  local f u
  f="$(afk_marker "${1:?}")"
  [ -f "$f" ] || return 1
  u="$(jq -r '.until_epoch // empty' "$f" 2>/dev/null || true)"
  # An unreadable marker counts as EXPIRED, so the watcher takes over. Of the
  # two ways to be wrong here, waking the operator needlessly is the one that
  # can be noticed; silence cannot.
  case "$u" in ''|*[!0-9]*) return 0 ;; esac
  [ "$(date -u +%s)" -ge "$u" ]
}

# Away mode is on AND still within its deadline. This is the one that decides
# whether the watcher stands down.
afk_in_force() { afk_on "${1:?}" && ! afk_expired "$1"; }
