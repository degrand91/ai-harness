#!/usr/bin/env bash
# safe-push.sh - push without ever hanging on a stalled connection.
#
# Usage:
#   scripts/safe-push.sh <repo-dir> <remote> <refspec> [--attempts N] [--attempt-seconds S]
#
# A plain `git push` over HTTPS has no stall timeout: on a flaky link (a local
# proxy, a VPN) it can wait forever. Observed 2026-10-02: one worker push hung
# 146 minutes and the others took 3 to 7 minutes each. This wrapper:
#   - aborts a transfer that stays under 1 KB/s for 20 s (git's own
#     http.lowSpeedLimit / http.lowSpeedTime),
#   - bounds every attempt by a hard wall clock (default 120 s),
#   - never waits for a credential prompt (GIT_TERMINAL_PROMPT=0),
#   - retries (default 3 attempts, 5 s apart).
#
# Workers do not push: the orchestrator calls this once per feature.
# Exit: 0 pushed · 1 every attempt failed · 2 usage
# Test hook: SAFE_PUSH_GIT overrides the git binary; SAFE_PUSH_BACKOFF the pause.

set -uo pipefail

usage() { sed -n '2,18{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }

[ $# -ge 1 ] && { [ "$1" = "-h" ] || [ "$1" = "--help" ]; } && { usage; exit 0; }
[ $# -ge 3 ] || { usage >&2; exit 2; }

REPO="$1"; REMOTE="$2"; REFSPEC="$3"; shift 3
ATTEMPTS=3
ATTEMPT_SECONDS=120
while [ $# -gt 0 ]; do
  case "$1" in
    --attempts)        ATTEMPTS="${2:?--attempts needs a value}"; shift 2 ;;
    --attempt-seconds) ATTEMPT_SECONDS="${2:?--attempt-seconds needs a value}"; shift 2 ;;
    *) echo "safe-push: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$ATTEMPTS$ATTEMPT_SECONDS" in *[!0-9]*) echo "safe-push: numbers only" >&2; exit 2 ;; esac
[ -d "$REPO" ] || { echo "safe-push: no such directory: $REPO" >&2; exit 2; }

GIT_BIN="${SAFE_PUSH_GIT:-git}"
BACKOFF="${SAFE_PUSH_BACKOFF:-5}"
export GIT_TERMINAL_PROMPT=0

# perl's alarm is the portable wall clock (macOS ships no `timeout`).
run_bounded() {
  perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$ATTEMPT_SECONDS" "$@"
}

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
  start=$(date +%s)
  if run_bounded "$GIT_BIN" -C "$REPO" \
      -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
      push "$REMOTE" "$REFSPEC"; then
    echo "safe-push: pushed $REFSPEC to $REMOTE in $(( $(date +%s) - start ))s (attempt $attempt)"
    exit 0
  fi
  rc=$?
  echo "safe-push: attempt $attempt/$ATTEMPTS failed after $(( $(date +%s) - start ))s (rc $rc)" >&2
  attempt=$(( attempt + 1 ))
  [ "$attempt" -le "$ATTEMPTS" ] && sleep "$BACKOFF"
done
echo "safe-push: giving up; the commit is still local in $REPO" >&2
exit 1
