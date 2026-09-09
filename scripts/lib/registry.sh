#!/usr/bin/env bash
# registry.sh - the single owner of the project registry (data/projects.md).
#
# The registry records the CAPTAIN'S STANDING POSTURE for a project. It does not
# answer "how does this task ship": that is decided per task at intake and
# passed explicitly to the crew scripts. Keeping the two separate is what lets a
# single task deviate with a logged reason instead of silently rewriting the
# operator's standing policy.
#
# Line format (anything else in the file is prose and is ignored):
#
#   - <name> [<mode>[ +yolo]] <path> [allow="<cmd>, <cmd>"] - <description> (added <date>)
#
#   - mobile-app [no-mistakes] ~/projects/mobile-app allow="bun *" - flagship (added 2026-05-21)
#   - forked-lib [direct-PR +yolo] /abs/path - mirroring (added 2026-06-02)
#
# Modes:
#   no-mistakes  full pipeline -> PR -> the no-mistakes gate -> merge authority
#   direct-PR    push + PR, no gate pipeline
#   local-only   local branch, guarded local merge, never a remote
# `+yolo` grants merge autonomy. It never changes what a crewmate may do.
#
# `allow=` is the project's build/test command set, appended to a crewmate's
# tool allowlist at spawn. Absent means the base allowlist only: a crewmate that
# needs more reports `blocked:` rather than being handed it silently.
#
# Usage (sourced):
#   registry_resolve <file> <name>   prints "<mode> <yolo> <path>"; 1 = unknown, 2 = malformed
#   registry_mode|yolo|path|allow <file> <name>
#   registry_list <file>             every registered name
#   registry_by_path <file> <path>   reverse lookup, for a mission's target_repo
#   registry_validate <file>         0 = every line parses
#
# EXIT CODES ARE THE CONTRACT.
#   0  resolved
#   1  not registered — the caller must ask, never assume a posture
#   2  registered but malformed — a loud refusal naming the project
#
# An unregistered project NEVER gets a default. Defaulting to the safest mode
# would silently ship work under a policy the operator never chose.

set -uo pipefail

_REGISTRY_MODES="no-mistakes direct-PR local-only"

# Print the raw registry line for <name>, or nothing. Exit 2 on a duplicate.
_registry_line() {
  local file="$1" name="$2" line found="" count=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "- "*) ;; *) continue ;; esac
    local rest="${line#- }"
    local candidate="${rest%% *}"
    [ "$candidate" = "$name" ] || continue
    found="$rest"; count=$((count + 1))
  done < "$file"
  if [ "$count" -gt 1 ]; then
    printf 'registry: project "%s" is registered twice in %s — remove one\n' "$name" "$file" >&2
    return 2
  fi
  [ -n "$found" ] || return 1
  printf '%s' "$found"
}

# Parse "<name> [<mode> +yolo] <path> [allow=...] - desc" into MODE/YOLO/PATH/ALLOW.
_registry_parse() {
  local rest="$1" name="$2"
  _RG_MODE=""; _RG_YOLO="off"; _RG_PATH=""; _RG_ALLOW=""

  case "$rest" in
    *"["*"]"*) ;;
    *) printf 'registry: "%s" has no [mode] — expected [no-mistakes|direct-PR|local-only]\n' "$name" >&2; return 2 ;;
  esac

  local bracket="${rest#*[}"; bracket="${bracket%%]*}"
  case "$bracket" in
    *" +yolo") _RG_YOLO="on"; _RG_MODE="${bracket% +yolo}" ;;
    *)         _RG_MODE="$bracket" ;;
  esac

  local m ok=0
  for m in $_REGISTRY_MODES; do [ "$_RG_MODE" = "$m" ] && ok=1; done
  if [ "$ok" -ne 1 ]; then
    printf 'registry: "%s" has unrecognised mode "%s" — expected one of: %s\n' \
      "$name" "$_RG_MODE" "$_REGISTRY_MODES" >&2
    return 2
  fi

  # Everything after "]" up to the " - " description separator.
  local tail="${rest#*]}"
  tail="${tail%% - *}"
  tail="${tail# }"

  if [ -z "$tail" ]; then
    printf 'registry: "%s" has no path — a registered project must name its primary checkout\n' "$name" >&2
    return 2
  fi

  case "$tail" in
    *allow=\"*)
      _RG_ALLOW="${tail#*allow=\"}"; _RG_ALLOW="${_RG_ALLOW%%\"*}"
      _RG_PATH="${tail%%allow=\"*}"
      ;;
    *) _RG_PATH="$tail" ;;
  esac
  _RG_PATH="${_RG_PATH%"${_RG_PATH##*[![:space:]]}"}"   # rstrip

  if [ -z "$_RG_PATH" ]; then
    printf 'registry: "%s" has no path before allow=\n' "$name" >&2
    return 2
  fi
  case "$_RG_PATH" in "~"*) _RG_PATH="$HOME${_RG_PATH#\~}" ;; esac
  return 0
}

_registry_load() {   # <file> <name> -> sets _RG_*; propagates 1/2
  local file="$1" name="$2" rest rc
  [ -f "$file" ] || return 1
  rest="$(_registry_line "$file" "$name")" || return $?
  _registry_parse "$rest" "$name"; rc=$?
  return $rc
}

registry_resolve() {
  local rc
  _registry_load "$1" "$2"; rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s %s %s\n' "$_RG_MODE" "$_RG_YOLO" "$_RG_PATH"
}

registry_mode()  { _registry_load "$1" "$2" || return $?; printf '%s\n' "$_RG_MODE"; }
registry_yolo()  { _registry_load "$1" "$2" || return $?; printf '%s\n' "$_RG_YOLO"; }
registry_path()  { _registry_load "$1" "$2" || return $?; printf '%s\n' "$_RG_PATH"; }
registry_allow() { _registry_load "$1" "$2" || return $?; printf '%s\n' "$_RG_ALLOW"; }

registry_list() {
  local file="$1" line
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "- "*) ;; *) continue ;; esac
    local rest="${line#- }"
    printf '%s\n' "${rest%% *}"
  done < "$file"
}

registry_by_path() {
  local file="$1" want="$2" name p
  case "$want" in "~"*) want="$HOME${want#\~}" ;; esac
  want="${want%/}"
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    p="$(registry_path "$file" "$name" 2>/dev/null)" || continue
    [ "${p%/}" = "$want" ] || continue
    printf '%s\n' "$name"
    return 0
  done < <(registry_list "$file")
  return 1
}

registry_validate() {
  local file="$1" name rc=0
  [ -f "$file" ] || { printf 'registry: %s does not exist\n' "$file" >&2; return 1; }
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    registry_resolve "$file" "$name" >/dev/null || rc=2
  done < <(registry_list "$file")
  return "$rc"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    resolve)  shift; registry_resolve  "$@" ;;
    mode)     shift; registry_mode     "$@" ;;
    yolo)     shift; registry_yolo     "$@" ;;
    path)     shift; registry_path     "$@" ;;
    allow)    shift; registry_allow    "$@" ;;
    list)     shift; registry_list     "$@" ;;
    by-path)  shift; registry_by_path  "$@" ;;
    validate) shift; registry_validate "$@" ;;
    -h|--help|"") sed -n '2,40{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    *) printf 'registry: unknown subcommand %s\n' "${1:-}" >&2; exit 2 ;;
  esac
fi
