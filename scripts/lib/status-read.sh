#!/usr/bin/env bash
# status-read.sh - the single owner of reading a mission's state.
#
# Every consumer (hooks, status.sh, snapshot.sh) reads mission state through
# this file and never reaches into status.json for `.state` itself. Mission
# files in the wild carry two vocabularies: the canonical `.state` documented in
# templates/status-schema.md, and a drifted `.status` + `.phase` shape. Reading
# one and ignoring the other is what let a Stop guard report "all clear" on the
# one mission most likely to be dirty.
#
# Usage (as a command, for tests and hooks):
#   scripts/lib/status-read.sh state  <status.json>   # print normalised state
#   scripts/lib/status-read.sh active <status.json>   # exit 0 if active
#   scripts/lib/status-read.sh title  <mission-dir>   # best-effort display name
#
# Usage (sourced):
#   . scripts/lib/status-read.sh
#   state="$(status_state "$f")" || handle_unknown
#
# CONTRACT. `status_state` prints exactly one canonical value and exits 0, or
# prints `unknown` and exits 3. Exit 3 is a LOUD refusal, never a silent pass:
# a caller that cannot classify a mission must say so rather than assume it is
# fine. `status_is_active` exits 2 on unknown for the same reason, so a caller
# using it in an `if` never silently drops the mission.
#
# Canonical states (templates/status-schema.md):
#   intake planning contract awaiting_approval executing feature_loop
#   closing closed abandoned paused

set -uo pipefail

# --- pure string mapping ----------------------------------------------------
# Takes raw `.state`, `.status`, `.phase`; prints canonical or "unknown".
# No file access, so it is trivially testable.
status_normalize() {
  local raw_state="${1:-}" raw_status="${2:-}" raw_phase="${3:-}"

  # `.state` is canonical when present and recognised.
  case "$raw_state" in
    intake|planning|contract|awaiting_approval|executing|feature_loop|closing|closed|abandoned|paused)
      printf '%s\n' "$raw_state"; return 0 ;;
  esac

  # Drifted vocabulary: `.status` carries the coarse state, `.phase` refines it.
  case "$raw_phase" in
    feature-loop|feature_loop) printf 'executing\n'; return 0 ;;
    planning)                  printf 'planning\n';  return 0 ;;
    intake)                    printf 'intake\n';    return 0 ;;
    contract)                  printf 'contract\n';  return 0 ;;
    closing)                   printf 'closing\n';   return 0 ;;
  esac

  case "$raw_status" in
    in-progress|in_progress|active|executing) printf 'executing\n';          return 0 ;;
    complete|completed|done|closed)           printf 'closed\n';             return 0 ;;
    abandoned|cancelled|canceled)             printf 'abandoned\n';          return 0 ;;
    paused|on-hold|on_hold)                   printf 'paused\n';             return 0 ;;
    awaiting-approval|awaiting_approval)      printf 'awaiting_approval\n';  return 0 ;;
  esac

  printf 'unknown\n'
  return 3
}

# --- file readers -----------------------------------------------------------
status_state() {
  local file="${1:?status_state: status.json path required}"
  if [ ! -f "$file" ]; then
    printf 'unknown\n'
    return 3
  fi
  # One jq call, three fields, one per line. NOT tab-separated: `read` treats a
  # tab as IFS whitespace and silently swallows a leading empty field, which
  # would shift `.status` into `.state`'s slot on exactly the drifted missions
  # this function exists to handle.
  local s t p
  {
    read -r s || s=""
    read -r t || t=""
    read -r p || p=""
  } < <(jq -r '(.state // ""), (.status // ""), (.phase // "")' "$file" 2>/dev/null || printf '\n\n\n')
  status_normalize "$s" "$t" "$p"
}

# Exit 0 = active (worth looking at), 1 = terminal, 2 = unknown.
status_is_active() {
  local file="${1:?status_is_active: status.json path required}"
  local state rc
  state="$(status_state "$file")"; rc=$?
  [ "$rc" -eq 3 ] && return 2
  case "$state" in
    closed|abandoned) return 1 ;;
    *)                return 0 ;;
  esac
}

# Portable mtime in epoch seconds.
#
# GNU first, and the result is VALIDATED as numeric before it is trusted. The
# obvious ordering (`stat -f %m || stat -c %Y`) is wrong: `-f` means
# `--file-system` to GNU stat, so on Linux the first branch SUCCEEDS with
# unrelated output and the fallback is never reached. Every mtime then reads as
# 0 and every file looks decades old — invisible on macOS, caught by CI on
# ubuntu-latest.
#
# Prints 0 when genuinely unreadable. Callers must treat 0 as UNKNOWN, never as
# "very old", or a stat failure turns into a false staleness report.
file_mtime_epoch() {
  local f="${1:?file_mtime_epoch: path required}" t
  t="$(stat -c %Y "$f" 2>/dev/null || true)"
  case "$t" in ''|*[!0-9]*) t="$(stat -f %m "$f" 2>/dev/null || true)" ;; esac
  case "$t" in ''|*[!0-9]*) t=0 ;; esac
  printf '%s' "$t"
}

# Newest mtime across the files a live mission touches; 0 when none is readable.
mission_last_activity() {
  local dir="${1:?mission_last_activity: mission dir required}" newest=0 f t
  for f in "$dir/status.json" "$dir/log.md"; do
    [ -f "$f" ] || continue
    t="$(file_mtime_epoch "$f")"
    [ "$t" -gt "$newest" ] 2>/dev/null && newest="$t"
  done
  printf '%s' "$newest"
}

# Best-effort human label for a mission directory.
status_title() {
  local dir="${1:?status_title: mission dir required}"
  local f="$dir/status.json" title=""
  [ -f "$f" ] && title="$(jq -r '.title // ""' "$f" 2>/dev/null || true)"
  printf '%s\n' "${title:-$(basename "$dir")}"
}

# List mission directories whose state is active or unknown, newest first.
# Unknown is INCLUDED by design: a mission we cannot classify is exactly the one
# a human should see.
status_active_missions() {
  local missions_dir="${1:?status_active_missions: missions dir required}"
  [ -d "$missions_dir" ] || return 0
  local d listing
  # ONE `ls -t` rather than a glob plus one stat(1) per mission: mtime ordering
  # is required, and on a host where each process costs ~150ms the per-file
  # variant is seconds slower on a 40-mission fleet. Mission ids are
  # date-slugs, so the filename caveats behind SC2012 do not apply.
  # shellcheck disable=SC2012
  listing="$(ls -t "$missions_dir" 2>/dev/null || true)"
  while IFS= read -r d; do
    case "$d" in ''|.*) continue ;; esac
    [ -d "$missions_dir/$d" ] || continue
    [ -f "$missions_dir/$d/status.json" ] || continue
    status_is_active "$missions_dir/$d/status.json"
    case $? in
      0|2) printf '%s\n' "$d" ;;
    esac
  done <<< "$listing"
}

# --- command surface --------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    state)    shift; status_state "$@" ;;
    active)   shift; status_is_active "$@" ;;
    title)    shift; status_title "$@" ;;
    mtime)    shift; file_mtime_epoch "$@" ;;
    activity) shift; mission_last_activity "$@" ;;
    list)     shift; status_active_missions "$@" ;;
    normalize) shift; status_normalize "$@" ;;
    -h|--help|"") sed -n '2,26{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    *) printf 'status-read: unknown subcommand %s\n' "${1:-}" >&2; exit 2 ;;
  esac
fi
