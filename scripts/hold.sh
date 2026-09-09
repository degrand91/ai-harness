#!/usr/bin/env bash
# hold.sh - open, list, answer and inspect decision holds.
#
# Usage:
#   hold.sh list                              every open decision, all missions
#   hold.sh open <mission> --question "<q>" [--options "a,b"] [--recommend "<r>"]
#                                           [--advisory] [--context <path>]
#   hold.sh answer <mission> <id> "<answer>"
#   hold.sh show <mission> <id>
#
# scripts/lib/holds.sh owns the layout and the id scheme; this owns arguments,
# refusals and human output.
#
# Exit codes: 0 ok · 1 nothing found · 2 refused
#
# THE RULE THIS ENFORCES: a blocking question is not asked until it is filed.
# An answer given in chat and never recorded is an answer that a restart or a
# context compaction erases, and the captain is then asked the same question
# twice — which is how they stop trusting the queue.

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
MISSIONS="${HARNESS_ROOT}/missions"

# shellcheck source=lib/holds.sh
. "$CODE_ROOT/scripts/lib/holds.sh"

usage() { sed -n '2,12{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

cmd_list() {
  local any=0 mission id blocking question
  while IFS=$'\t' read -r mission id blocking question; do
    [ -n "$mission" ] || continue
    if [ "$any" -eq 0 ]; then printf 'Open decisions:\n\n'; any=1; fi
    printf '  %s  %s  [%s]\n      %s\n\n' "$id" "$mission" "$blocking" "$question"
  done < <(holds_list_all "$MISSIONS")
  [ "$any" -eq 1 ] || printf 'No open decisions.\n'
}

cmd_open() {
  local mission="${1:-}"; shift 2>/dev/null || true
  [ -n "$mission" ] || die "usage: hold.sh open <mission> --question \"<q>\" [--options a,b] [--recommend r] [--advisory]"
  local mdir="$MISSIONS/$mission"
  [ -d "$mdir" ] || die "hold.sh: no mission \"$mission\" in $MISSIONS"

  local question="" options="" recommend="" context="" blocking=true
  while [ $# -gt 0 ]; do
    case "$1" in
      --question)  question="${2:-}"; shift 2 ;;
      --options)   options="${2:-}"; shift 2 ;;
      --recommend) recommend="${2:-}"; shift 2 ;;
      --context)   context="${2:-}"; shift 2 ;;
      --advisory)  blocking=false; shift ;;
      *) die "hold.sh open: unknown option $1" ;;
    esac
  done
  question="${question#"${question%%[![:space:]]*}"}"
  [ -n "$question" ] || die "hold.sh: refusing to file a decision with no question"

  local dir; dir="$(holds_dir "$mdir")"
  mkdir -p "$dir" "$(holds_answered_dir "$mdir")" || die "hold.sh: cannot write to $dir"
  local id; id="$(holds_next_id "$mdir")"

  local opts_json="[]"
  if [ -n "$options" ]; then
    opts_json="$(printf '%s' "$options" | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; ""))' 2>/dev/null || printf '[]')"
  fi

  local tmp; tmp="$(mktemp "${dir}/.${id}.XXXXXX")"
  jq -n --arg id "$id" --arg m "$mission" --arg q "$question" --arg r "$recommend" \
        --arg c "$context" --argjson o "$opts_json" --argjson b "$blocking" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id:$id, mission_id:$m, opened_at:$at, blocking:$b, question:$q,
      options:$o, recommendation:$r, context_path:$c,
      answered_at:null, answer:null}' > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; die "hold.sh: could not encode the decision"; }
  mv "$tmp" "$dir/$id.json" || { rm -f "$tmp"; die "hold.sh: could not file the decision"; }

  printf 'Filed %s on %s (%s).\n' "$id" "$mission" \
    "$([ "$blocking" = true ] && echo blocking || echo advisory)"
  printf 'It will be presented at every session start until answered.\n'
}

cmd_answer() {
  local mission="${1:-}" id="${2:-}" answer="${3:-}"
  [ -n "$mission" ] && [ -n "$id" ] || die "usage: hold.sh answer <mission> <id> \"<answer>\""
  local mdir="$MISSIONS/$mission"
  local dir; dir="$(holds_dir "$mdir")"
  local adir; adir="$(holds_answered_dir "$mdir")"
  [ -f "$dir/$id.json" ] || die "hold.sh: $id is not an open decision on $mission"

  answer="${answer#"${answer%%[![:space:]]*}"}"
  [ -n "$answer" ] || die "hold.sh: refusing to record an empty answer — silence is not a decision"

  mkdir -p "$adir"
  local tmp; tmp="$(mktemp "${adir}/.${id}.XXXXXX")"
  if jq --arg a "$answer" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.answer = $a | .answered_at = $at' "$dir/$id.json" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$adir/$id.json" && rm -f "$dir/$id.json"
  else
    rm -f "$tmp"
    die "hold.sh: $id is unreadable; inspect $dir/$id.json by hand rather than answering it blind"
  fi
  printf 'Answered %s on %s.\n' "$id" "$mission"
}

cmd_show() {
  local mission="${1:-}" id="${2:-}"
  [ -n "$mission" ] && [ -n "$id" ] || die "usage: hold.sh show <mission> <id>"
  local mdir="$MISSIONS/$mission" f
  for f in "$(holds_dir "$mdir")/$id.json" "$(holds_answered_dir "$mdir")/$id.json"; do
    [ -f "$f" ] || continue
    jq . "$f" 2>/dev/null || cat "$f"
    return 0
  done
  printf 'hold.sh: no decision %s on %s\n' "$id" "$mission" >&2
  exit 1
}

case "${1:-}" in
  list)   shift; cmd_list ;;
  open)   shift; cmd_open "$@" ;;
  answer) shift; cmd_answer "$@" ;;
  show)   shift; cmd_show "$@" ;;
  -h|--help|"") usage ;;
  *) die "hold.sh: unknown subcommand ${1}" ;;
esac
