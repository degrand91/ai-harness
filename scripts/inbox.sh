#!/usr/bin/env bash
# inbox.sh - the captain's out-of-band capture surface.
#
# Usage:
#   inbox.sh note <text>...     queue an idea durably; `-` reads stdin
#   inbox.sh list               pending notes, newest last
#   inbox.sh drain [--ack <id>...]   present pending notes; acknowledge by id
#   inbox.sh status             one line, from durable records only
#   inbox.sh ask <question>...  a one-shot side question, answered and forgotten
#
# FOUR THINGS THAT LOOK LIKE ONE AND ARE NOT (fm-inbox.sh:1-27):
#
#   note    Survives a crash. Written before anything else happens, so an idea
#           captured while the orchestrator is mid-turn is never lost. This is
#           the only subcommand that will wake the orchestrator (Phase 4 wires
#           the wake; the record format is fixed now so it need not change).
#   list    Read-only view of what is pending.
#   drain   Present, then acknowledge explicitly. Acknowledging archives rather
#           than deletes, so a note is never destroyed by a fat finger.
#   status  Answers "what is waiting" from durable records ONLY. No network, no
#           wake, no writes — safe to poll in a loop.
#   ask     A side question. It never touches the inbox, the backlog, or the
#           wake queue, and leaves no record. A side question must not become
#           fleet work; that is the entire reason it is a separate verb.
#
# Notes live in data/inbox/NNNN.json; acknowledged ones move to
# data/inbox/archive/. One file per note, so two concurrent captures cannot
# corrupt each other's record.

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
INBOX="${HARNESS_ROOT}/data/inbox"
ARCHIVE="${INBOX}/archive"

usage() { sed -n '2,10{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

next_id() {
  local n=1 f
  mkdir -p "$INBOX" "$ARCHIVE"
  while :; do
    f="$(printf 'N%03d' "$n")"
    if [ ! -f "$INBOX/$f.json" ] && [ ! -f "$ARCHIVE/$f.json" ]; then
      printf '%s' "$f"; return 0
    fi
    n=$((n + 1))
  done
}

# Print "<id>\t<first line of body>" for every pending note, oldest first.
each_note() {
  [ -d "$INBOX" ] || return 0
  local f id body
  for f in "$INBOX"/*.json; do
    [ -f "$f" ] || continue
    id="$(basename "$f" .json)"
    if body="$(jq -r '.body // ""' "$f" 2>/dev/null)" && [ -n "$body" ]; then
      printf '%s\t%s\n' "$id" "$(printf '%s' "$body" | head -n1)"
    else
      printf '%s\t%s\n' "$id" "(unreadable note file — inspect $f)"
    fi
  done
}

cmd_note() {
  local body
  if [ "${1:-}" = "-" ]; then
    body="$(cat)"
  else
    body="$*"
  fi
  # Trim surrounding whitespace; a blank note is a mistake, not a record.
  body="${body#"${body%%[![:space:]]*}"}"
  body="${body%"${body##*[![:space:]]}"}"
  [ -n "$body" ] || die "inbox: refusing to file an empty note"

  mkdir -p "$INBOX" "$ARCHIVE"
  local id; id="$(next_id)"
  local tmp; tmp="$(mktemp "${INBOX}/.${id}.XXXXXX")" || die "inbox: cannot write to $INBOX"
  jq -n --arg id "$id" --arg body "$body" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg host "$(hostname 2>/dev/null || echo unknown)" \
     '{id:$id, body:$body, created_at:$at, host:$host, acked_at:null}' > "$tmp" \
     || { rm -f "$tmp"; die "inbox: could not encode the note"; }
  mv "$tmp" "$INBOX/$id.json" || { rm -f "$tmp"; die "inbox: could not file the note"; }
  printf 'Filed %s. It will be presented at the next drain.\n' "$id"
}

cmd_list() {
  local out; out="$(each_note)"
  if [ -z "$out" ]; then printf 'Inbox is empty.\n'; return 0; fi
  printf 'Pending notes:\n'
  printf '%s\n' "$out" | while IFS=$'\t' read -r id line; do
    printf '  %s  %s\n' "$id" "$line"
  done
}

cmd_status() {
  local n; n="$(each_note | grep -c . || true)"
  [ -n "$n" ] || n=0
  if [ "$n" -eq 0 ]; then printf 'Inbox: empty.\n'; else printf 'Inbox: %s note(s) pending.\n' "$n"; fi
}

cmd_drain() {
  if [ "${1:-}" != "--ack" ]; then
    local out; out="$(each_note)"
    if [ -z "$out" ]; then printf 'Nothing to drain.\n'; return 0; fi
    printf 'Pending notes (acknowledge with: inbox.sh drain --ack <id>...):\n\n'
    printf '%s\n' "$out" | while IFS=$'\t' read -r id _; do
      printf '  %s\n' "$id"
      jq -r '.body' "$INBOX/$id.json" 2>/dev/null | sed 's/^/      /'
      printf '\n'
    done
    return 0
  fi
  shift
  [ "$#" -gt 0 ] || die "inbox: --ack needs at least one note id"
  mkdir -p "$ARCHIVE"
  local id rc=0
  for id in "$@"; do
    if [ ! -f "$INBOX/$id.json" ]; then
      printf 'inbox: no pending note %s\n' "$id" >&2; rc=2; continue
    fi
    local tmp; tmp="$(mktemp "${ARCHIVE}/.${id}.XXXXXX")"
    if jq --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.acked_at = $at' "$INBOX/$id.json" > "$tmp" 2>/dev/null; then
      mv "$tmp" "$ARCHIVE/$id.json" && rm -f "$INBOX/$id.json" && printf 'Acknowledged %s\n' "$id"
    else
      # An unreadable note is still archived rather than stranded or destroyed.
      rm -f "$tmp"
      mv "$INBOX/$id.json" "$ARCHIVE/$id.json" && printf 'Archived unreadable %s\n' "$id"
    fi
  done
  return "$rc"
}

cmd_ask() {
  local dry=0 args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry=1; shift ;;
      *) args+=("$1"); shift ;;
    esac
  done
  local q="${args[*]:-}"
  q="${q#"${q%%[![:space:]]*}"}"
  [ -n "$q" ] || die "inbox: ask needs a question"

  if [ "$dry" -eq 1 ]; then
    printf 'would ask (no state touched): %s\n' "$q"
    return 0
  fi
  command -v claude >/dev/null 2>&1 || die "inbox: claude is not installed; ask needs it" 2
  # No tools, cheapest model, no project context: a side question is cheap by
  # construction and cannot reach fleet state even by accident.
  claude -p --model haiku --disallowed-tools "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch,Agent" "$q"
}

case "${1:-}" in
  note)   shift; cmd_note "$@" ;;
  list)   shift; cmd_list ;;
  drain)  shift; cmd_drain "$@" ;;
  status) shift; cmd_status ;;
  ask)    shift; cmd_ask "$@" ;;
  -h|--help|"") usage ;;
  *) die "inbox.sh: unknown subcommand ${1}" ;;
esac
