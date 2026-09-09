#!/usr/bin/env bash
# pr-poll.sh - report the state of a pull request, once.
#
# Usage:
#   pr-poll.sh <pr-url-or-branch> [--repo <owner/name>]
#
# Prints one line: "<state> <checks> <url>" where state is
# open|merged|closed|unknown and checks is pass|fail|pending|none.
#
# THIS DOES NOT LOOP. The Phase 4 watcher already sleeps on fleet state; a
# second polling loop inside it would be two schedulers disagreeing about how
# often to ask. One call, one answer, exit.
#
# Exit: 0 = answered · 1 = could not answer (no gh, no auth, no such PR)

set -uo pipefail
usage() { sed -n '2,10{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }

TARGET="${1:-}"; REPO=""
[ "${2:-}" = "--repo" ] && REPO="${3:-}"
case "$TARGET" in -h|--help|"") usage; exit 0 ;; esac

command -v gh >/dev/null 2>&1 || { printf 'unknown none %s\n' "$TARGET"; exit 1; }
gh auth status >/dev/null 2>&1 || { printf 'unknown none %s\n' "$TARGET"; exit 1; }

ARGS=(pr view "$TARGET" --json "state,url,statusCheckRollup")
[ -n "$REPO" ] && ARGS+=(--repo "$REPO")
JSON="$(gh "${ARGS[@]}" 2>/dev/null || true)"
[ -n "$JSON" ] || { printf 'unknown none %s\n' "$TARGET"; exit 1; }

printf '%s' "$JSON" | jq -r '
  ( .statusCheckRollup // [] ) as $c
  | ( if ($c | length) == 0 then "none"
      elif ($c | map(select(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .conclusion == "CANCELLED")) | length) > 0 then "fail"
      elif ($c | map(select(.status != "COMPLETED")) | length) > 0 then "pending"
      else "pass" end ) as $checks
  | "\(.state | ascii_downcase) \($checks) \(.url)"
'
