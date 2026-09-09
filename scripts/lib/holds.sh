#!/usr/bin/env bash
# holds.sh - the single owner of decision holds.
#
# A blocking question to the captain is a FILE, not a conversational turn. A
# question asked in prose is lost to a restart or a context compaction; a
# question on disk is reconciled at every session start and cannot be forgotten.
# The captain already hand-rolled this as `open_questions` and `user_actions`
# inside one mission's status.json — this makes it a schema the tooling reads.
#
# Layout:
#   missions/<id>/decisions/DH-001.json           OPEN
#   missions/<id>/decisions/answered/DH-001.json  ANSWERED
#
# ANSWERING MOVES THE FILE. That is deliberate: counting open decisions is then
# a file count, so scripts/snapshot.sh reports them without parsing anything and
# keeps its constant-jq-invocation contract. It also means an answer is never
# lost by an in-place rewrite going wrong.
#
# Usage (sourced):
#   holds_dir <mission-dir>            the open-holds directory
#   holds_count_open <mission-dir>     how many decisions are waiting
#   holds_count_blocking <mission-dir> how many of those stop work
#   holds_next_id <mission-dir>        DH-NNN, per mission
#   holds_list_open <mission-dir>      "<id>\t<blocking>\t<question>" per line
#
# Ids are per mission, so two missions both having a DH-001 is normal and
# correct: a hold is only ever addressed together with its mission.

set -uo pipefail

holds_dir()          { printf '%s' "${1:?holds_dir: mission dir required}/decisions"; }
holds_answered_dir() { printf '%s' "${1:?holds_answered_dir: mission dir required}/decisions/answered"; }

holds_count_open() {
  local d; d="$(holds_dir "${1:?}")"
  [ -d "$d" ] || { printf '0'; return 0; }
  local n=0 f
  for f in "$d"/*.json; do [ -f "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

holds_count_blocking() {
  local d; d="$(holds_dir "${1:?}")"
  [ -d "$d" ] || { printf '0'; return 0; }
  local n=0 f
  for f in "$d"/*.json; do
    [ -f "$f" ] || continue
    # An unreadable hold counts as blocking: we cannot prove it is safe to pass.
    if ! jq -e '.blocking == false' "$f" >/dev/null 2>&1; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

holds_next_id() {
  local d; d="$(holds_dir "${1:?}")"
  local a; a="$(holds_answered_dir "${1}")"
  local n=1 id
  while :; do
    id="$(printf 'DH-%03d' "$n")"
    if [ ! -f "$d/$id.json" ] && [ ! -f "$a/$id.json" ]; then
      printf '%s' "$id"; return 0
    fi
    n=$((n + 1))
  done
}

# "<id><TAB><blocking><TAB><question>" per open hold, oldest id first.
holds_list_open() {
  local d; d="$(holds_dir "${1:?}")"
  [ -d "$d" ] || return 0
  local f id q b
  for f in "$d"/*.json; do
    [ -f "$f" ] || continue
    id="$(basename "$f" .json)"
    if q="$(jq -r '.question // ""' "$f" 2>/dev/null)" && [ -n "$q" ]; then
      b="$(jq -r 'if .blocking == false then "advisory" else "blocking" end' "$f" 2>/dev/null || printf 'blocking')"
      printf '%s\t%s\t%s\n' "$id" "$b" "$q"
    else
      printf '%s\t%s\t%s\n' "$id" "blocking" "(unreadable hold file — inspect $f)"
    fi
  done
}

# Every open hold across every mission: "<mission><TAB><id><TAB><blocking><TAB><question>"
holds_list_all() {
  local missions="${1:?holds_list_all: missions dir required}"
  [ -d "$missions" ] || return 0
  local md mid line
  for md in "$missions"/*/; do
    [ -d "$md" ] || continue
    mid="$(basename "$md")"
    case "$mid" in .*) continue ;; esac
    while IFS= read -r line; do
      [ -n "$line" ] && printf '%s\t%s\n' "$mid" "$line"
    done < <(holds_list_open "${md%/}")
  done
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    count-open)     shift; holds_count_open "$@"; printf '\n' ;;
    count-blocking) shift; holds_count_blocking "$@"; printf '\n' ;;
    next-id)        shift; holds_next_id "$@"; printf '\n' ;;
    list-open)      shift; holds_list_open "$@" ;;
    list-all)       shift; holds_list_all "$@" ;;
    -h|--help|"")   sed -n '2,26{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    *) printf 'holds: unknown subcommand %s\n' "${1:-}" >&2; exit 2 ;;
  esac
fi
