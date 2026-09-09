#!/usr/bin/env bash
# crew.sh - the single owner of crewmate state.
#
#   state/<task>.meta    what this crewmate is and where it lives (JSON)
#   state/<task>.ledger  append-only lines the crewmate and its hooks write
#
# THE LEDGER IS THE CONTRACT. It is append-only, and written by the crewmate's
# OWN process (via hooks injected into its worktree) rather than by the
# supervisor. A supervisor that died mid-flight therefore reconstructs the
# outcome from disk alone, with no need to interrogate a process that may
# already be gone.
#
# Verbs:
#   started:   the worktree and process exist
#   busy:      the crewmate accepted a prompt          (UserPromptSubmit hook)
#   idle:      a turn ended                            (Stop hook)
#   progress:  a self-reported milestone
#   blocked:   waiting on a human — NOT terminal
#   done:      finished successfully                   TERMINAL
#   failed:    finished unsuccessfully                 TERMINAL
#   exited:    the process ended                       (SessionEnd hook)
#
# `blocked` is deliberately NOT terminal: a blocked crewmate is waiting, not
# finished, and tearing its worktree down would throw away the work that got it
# there. Only `done` and `failed` end a task.
#
# Usage (sourced):
#   crew_meta_write <home> <task> k=v...     create or replace the meta record
#   crew_meta_set   <home> <task> <k> <v>    update one field
#   crew_meta_get   <home> <task> <k>        read one field (1 = no such task)
#   crew_list       <home>                   live task ids
#   crew_count      <home>                   how many live tasks
#   crew_ledger_append <home> <task> <verb> [note]
#   crew_ledger_last   <home> <task>         last COMPLETE line's verb
#   crew_ledger_note   <home> <task>         that line's note
#   crew_is_terminal   <home> <task>         0 = done|failed
#   crew_forget     <home> <task>            drop both files

set -uo pipefail

_crew_state() { printf '%s' "${1:?crew: home required}/state"; }

# A task id becomes a filename, so it may not contain a path separator or walk
# upwards. Refusing is the only safe response: a "sanitised" id would silently
# address a different task than the caller named.
_crew_ok_id() {
  case "${1:-}" in
    ''|*/*|.|..|*..*) return 2 ;;
    *) return 0 ;;
  esac
}

crew_meta_write() {
  local home="${1:?}" task="${2:?}"; shift 2
  _crew_ok_id "$task" || { printf 'crew: unsafe task id "%s"\n' "$task" >&2; return 2; }
  local dir; dir="$(_crew_state "$home")"; mkdir -p "$dir" || return 1
  local args=() kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    args+=(--arg "$k" "$v")
  done
  args+=(--arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg task "$task")
  local tmp; tmp="$(mktemp "${dir}/.${task}.XXXXXX")" || return 1
  jq -n "${args[@]}" '$ARGS.named' > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$dir/$task.meta" || { rm -f "$tmp"; return 1; }
}

crew_meta_set() {
  local home="${1:?}" task="${2:?}" k="${3:?}" v="${4:-}"
  _crew_ok_id "$task" || return 2
  local f; f="$(_crew_state "$home")/$task.meta"
  [ -f "$f" ] || return 1
  local tmp; tmp="$(mktemp "${f}.XXXXXX")" || return 1
  jq --arg k "$k" --arg v "$v" '.[$k] = $v' "$f" > "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}

crew_meta_get() {
  local home="${1:?}" task="${2:?}" k="${3:?}"
  _crew_ok_id "$task" || return 2
  local f; f="$(_crew_state "$home")/$task.meta"
  [ -f "$f" ] || return 1
  jq -r --arg k "$k" '.[$k] // ""' "$f" 2>/dev/null || return 1
}

crew_list() {
  local dir; dir="$(_crew_state "${1:?}")"
  [ -d "$dir" ] || return 0
  local f
  for f in "$dir"/*.meta; do
    [ -f "$f" ] || continue
    basename "$f" .meta
  done
}

crew_count() {
  local n=0 t
  while IFS= read -r t; do [ -n "$t" ] && n=$((n + 1)); done < <(crew_list "${1:?}")
  printf '%s' "$n"
}

crew_ledger_append() {
  local home="${1:?}" task="${2:?}" verb="${3:?}" note="${4:-}"
  _crew_ok_id "$task" || return 2
  local dir; dir="$(_crew_state "$home")"; mkdir -p "$dir" || return 1
  # One atomic append. A concurrent writer can interleave whole lines but never
  # tear one, which is what makes the last-complete-line read below sound.
  printf '%s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$verb" "$note" >> "$dir/$task.ledger"
}

# Last COMPLETE line only. A process killed mid-write leaves a partial final
# line with no newline; reading that as an outcome would invent a `done` that
# never happened.
_crew_last_line() {
  local f; f="$(_crew_state "${1:?}")/${2:?}.ledger"
  [ -f "$f" ] || return 1
  local line last=""
  while IFS= read -r line; do last="$line"; done < "$f"
  [ -n "$last" ] || return 1
  printf '%s' "$last"
}

crew_ledger_last() {
  local line; line="$(_crew_last_line "$1" "$2")" || return 0
  line="${line#* }"          # strip timestamp
  printf '%s' "${line%%:*}"
}

crew_ledger_note() {
  local line; line="$(_crew_last_line "$1" "$2")" || return 0
  line="${line#*: }"
  printf '%s' "$line"
}

crew_is_terminal() {
  case "$(crew_ledger_last "$1" "$2")" in
    done|failed) return 0 ;;
    *) return 1 ;;
  esac
}

crew_forget() {
  local home="${1:?}" task="${2:?}"
  _crew_ok_id "$task" || return 2
  local dir; dir="$(_crew_state "$home")"
  rm -f "$dir/$task.meta" "$dir/$task.ledger"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    list)     shift; crew_list "$@" ;;
    count)    shift; crew_count "$@"; printf '\n' ;;
    get)      shift; crew_meta_get "$@" ;;
    last)     shift; crew_ledger_last "$@"; printf '\n' ;;
    note)     shift; crew_ledger_note "$@"; printf '\n' ;;
    append)   shift; crew_ledger_append "$@" ;;
    terminal) shift; crew_is_terminal "$@" ;;
    -h|--help|"") sed -n '2,34{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    *) printf 'crew: unknown subcommand %s\n' "${1:-}" >&2; exit 2 ;;
  esac
fi
