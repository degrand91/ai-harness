#!/usr/bin/env bash
# session-lock.sh - the single owner of "which orchestrator session may act".
#
# Two Claude Code sessions opened on this repo are two orchestrators: both
# dispatch, both write mission state, and (from Phase 4) both arm a watcher.
# Nothing in Claude Code prevents it. This file makes one of them authoritative
# and the other an observer.
#
# IDENTITY IS session_id, NOT pid. Every hook payload carries `session_id`, so a
# hook can prove which session it belongs to without resolving a process
# ancestry. The recorded pid exists only to detect a lock left behind by a
# session that died without firing SessionEnd.
#
# Usage (sourced):
#   . scripts/lib/session-lock.sh
#   lock_take    <lockfile> <session_id> <pid>   0 = held by you, 1 = someone else
#   lock_release <lockfile> <session_id>         0 = released, 1 = not yours
#   lock_is_owner <lockfile> <session_id>        0 = you may act, 1 = observer
#   lock_owner_session <lockfile>                prints the owning session_id
#
# FAIL-OPEN IS DELIBERATE HERE. `lock_is_owner` returns 0 when no lock file
# exists. A missing lock means no managed session claimed the repo — a bare
# `bash` invocation, a test, a fresh checkout — and refusing every mutation in
# that case would break ordinary use to defend against a case that has not
# happened. The lock only ever *demotes* a second session, never gates a first.
#
# Staleness: a lock whose pid is dead, whose file is malformed, or which is
# older than HARNESS_LOCK_TTL (default 86400s) is stealable.

set -uo pipefail

lock_owner_session() {
  local f="${1:?lock_owner_session: lockfile required}"
  [ -f "$f" ] || return 1
  jq -r '.session_id // empty' "$f" 2>/dev/null || true
}

_lock_pid()     { jq -r '.pid // empty'        "${1}" 2>/dev/null || true; }
_lock_started() { jq -r '.started_at_epoch // 0' "${1}" 2>/dev/null || printf '0'; }

# 0 = the lock is live and should be respected; 1 = stale or absent.
_lock_is_live() {
  local f="$1"
  [ -f "$f" ] || return 1
  local sid pid started now ttl
  sid="$(lock_owner_session "$f")"
  [ -n "$sid" ] || return 1                       # malformed → stealable
  pid="$(_lock_pid "$f")"
  started="$(_lock_started "$f")"
  ttl="${HARNESS_LOCK_TTL:-86400}"
  now="$(date -u +%s)"
  case "$started" in ''|*[!0-9]*) started=0 ;; esac
  [ $(( now - started )) -gt "$ttl" ] && return 1  # too old → stealable
  # A pid we cannot signal is a session that is gone. An empty or non-numeric
  # pid is treated as live, because guessing "dead" would let a second session
  # steal a healthy lock.
  case "$pid" in
    ''|*[!0-9]*) return 0 ;;
    *) kill -0 "$pid" 2>/dev/null && return 0 || return 1 ;;
  esac
}

lock_take() {
  local f="${1:?lock_take: lockfile required}" sid="${2:?lock_take: session_id required}" pid="${3:-$$}"
  local dir; dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null || return 1

  if _lock_is_live "$f"; then
    [ "$(lock_owner_session "$f")" = "$sid" ] || return 1   # someone else holds it
  fi

  local tmp
  tmp="$(mktemp "${f}.tmp.XXXXXX")" || return 1
  jq -n --arg sid "$sid" --arg pid "$pid" --arg host "$(hostname 2>/dev/null || echo unknown)" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson epoch "$(date -u +%s)" \
    '{session_id:$sid, pid:($pid|tonumber? // 0), host:$host, started_at:$at, started_at_epoch:$epoch}' \
    > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
  return 0
}

lock_release() {
  local f="${1:?lock_release: lockfile required}" sid="${2:?lock_release: session_id required}"
  [ -f "$f" ] || return 0
  [ "$(lock_owner_session "$f")" = "$sid" ] || return 1
  rm -f "$f"
  return 0
}

lock_is_owner() {
  local f="${1:?lock_is_owner: lockfile required}" sid="${2:?lock_is_owner: session_id required}"
  [ -f "$f" ] || return 0            # unowned: see FAIL-OPEN above
  _lock_is_live "$f" || return 0     # stale: the next SessionStart will re-take it
  [ "$(lock_owner_session "$f")" = "$sid" ]
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    take)    shift; lock_take "$@" ;;
    release) shift; lock_release "$@" ;;
    owner)   shift; lock_owner_session "$@" ;;
    is-owner) shift; lock_is_owner "$@" ;;
    -h|--help|"") sed -n '2,28{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    *) printf 'session-lock: unknown subcommand %s\n' "${1:-}" >&2; exit 2 ;;
  esac
fi
