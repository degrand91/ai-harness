#!/usr/bin/env bash
# project.sh - the command surface over the project registry.
#
# Usage:
#   project.sh list                       every registered project and its posture
#   project.sh resolve <name>             "<mode> <yolo> <path>"
#   project.sh mode|yolo|path|allow <name>
#   project.sh validate                   check every line parses
#   project.sh add <name> <path> --mode <mode> [--yolo] [--allow "<cmds>"] [--desc "<text>"]
#
# scripts/lib/registry.sh owns the file format and every parsing decision; this
# script owns argument handling, the refusals around `add`, and human output.
#
# Exit codes: 0 ok · 1 not registered · 2 refused (bad input or malformed registry)
#
# `add` REFUSES rather than repairs: an unknown mode, a path that is not a git
# checkout, or a name already present are all errors. Registering a project is
# a policy decision, and a policy silently corrected is a policy not chosen.

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
REGISTRY="${HARNESS_ROOT}/data/projects.md"

# shellcheck source=lib/registry.sh
. "$CODE_ROOT/scripts/lib/registry.sh"

usage() { sed -n '2,18{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }

die()   { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

# Translate the library's exit codes into one human sentence.
report_lookup_failure() {   # <rc> <name>
  case "$1" in
    1) printf 'project "%s" is not registered. Add it with:\n  ./scripts/project.sh add %s <path> --mode <no-mistakes|direct-PR|local-only>\n' "$2" "$2" >&2; exit 1 ;;
    *) exit 2 ;;   # the library already said what was wrong, on stderr
  esac
}

cmd_list() {
  local names name mode yolo path
  names="$(registry_list "$REGISTRY")"
  if [ -z "$names" ]; then
    printf 'No projects registered.\n\nAdd one with:\n  ./scripts/project.sh add <name> <path> --mode <no-mistakes|direct-PR|local-only>\n'
    return 0
  fi
  printf '%-24s %-14s %-6s %s\n' NAME MODE YOLO PATH
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! read -r mode yolo path < <(registry_resolve "$REGISTRY" "$name" 2>/dev/null); then
      printf '%-24s %-14s %-6s %s\n' "$name" "MALFORMED" "-" "(see ./scripts/project.sh validate)"
      continue
    fi
    printf '%-24s %-14s %-6s %s\n' "$name" "$mode" "$yolo" "$path"
  done <<< "$names"
}

cmd_add() {
  local name="${1:-}" path="${2:-}"; shift 2 2>/dev/null || true
  [ -n "$name" ] && [ -n "$path" ] || die "usage: project.sh add <name> <path> --mode <mode> [--yolo] [--allow \"<cmds>\"] [--desc \"<text>\"]"

  local mode="" yolo="" allow="" desc=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode)  mode="${2:-}"; shift 2 ;;
      --yolo)  yolo=" +yolo"; shift ;;
      --allow) allow="${2:-}"; shift 2 ;;
      --desc)  desc="${2:-}"; shift 2 ;;
      *) die "project.sh add: unknown option $1" ;;
    esac
  done

  [ -n "$mode" ] || die "project.sh add: --mode is required (no-mistakes | direct-PR | local-only)"
  case "$mode" in
    no-mistakes|direct-PR|local-only) ;;
    *) die "project.sh add: unrecognised mode \"$mode\" — expected no-mistakes, direct-PR or local-only" ;;
  esac

  case "$path" in "~"*) path="$HOME${path#\~}" ;; esac
  [ -d "$path" ] || die "project.sh add: $path does not exist"
  path="$(cd "$path" && pwd)"
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 \
    || die "project.sh add: $path is not a git checkout — the harness delivers work through git"

  mkdir -p "$(dirname "$REGISTRY")"
  if [ -f "$REGISTRY" ] && registry_list "$REGISTRY" | grep -qx "$name"; then
    die "project.sh add: \"$name\" is already registered — edit $REGISTRY to change its posture"
  fi
  if [ -f "$REGISTRY" ]; then
    local existing
    if existing="$(registry_by_path "$REGISTRY" "$path" 2>/dev/null)"; then
      die "project.sh add: $path is already registered as \"$existing\""
    fi
  fi

  if [ ! -f "$REGISTRY" ]; then
    cat > "$REGISTRY" <<'HEADER'
# Projects

The captain's standing delivery posture per project. One line each. Hand-editable.

    - <name> [<mode>[ +yolo]] <path> [allow="<cmd>, <cmd>"] - <description> (added <date>)

Modes: no-mistakes (pipeline -> PR -> gate) · direct-PR (push + PR) · local-only (no remote).
+yolo grants merge autonomy. allow= extends a crewmate's tool allowlist at spawn.

This records what was REGISTERED, never how a given task ships: that is decided
per task at intake. See protocols/project-registry.md.

HEADER
  fi

  [ -n "$desc" ] || desc="$name"
  local line="- ${name} [${mode}${yolo}] ${path}"
  [ -n "$allow" ] && line="${line} allow=\"${allow}\""
  line="${line} - ${desc} (added $(date -u +%Y-%m-%d))"
  printf '%s\n' "$line" >> "$REGISTRY"

  if ! registry_resolve "$REGISTRY" "$name" >/dev/null 2>&1; then
    die "project.sh add: wrote a line that does not parse — removed. Check for a \" - \" in the name or path."
  fi
  printf 'Registered %s [%s%s] %s\n' "$name" "$mode" "${yolo:+ +yolo}" "$path"
}

cmd_field() {   # <fn> <name>
  local fn="$1" name="${2:-}" out rc
  [ -n "$name" ] || die "usage: project.sh ${fn#registry_} <name>"
  out="$("$fn" "$REGISTRY" "$name")"; rc=$?
  [ "$rc" -eq 0 ] || report_lookup_failure "$rc" "$name"
  printf '%s\n' "$out"
}

case "${1:-}" in
  list)     cmd_list ;;
  add)      shift; cmd_add "$@" ;;
  resolve)  shift; cmd_field registry_resolve "${1:-}" ;;
  mode)     shift; cmd_field registry_mode    "${1:-}" ;;
  yolo)     shift; cmd_field registry_yolo    "${1:-}" ;;
  path)     shift; cmd_field registry_path    "${1:-}" ;;
  allow)    shift; cmd_field registry_allow   "${1:-}" ;;
  validate)
    if registry_validate "$REGISTRY"; then
      printf 'ok — %s project(s) registered, every line parses\n' "$(registry_list "$REGISTRY" | grep -c . || echo 0)"
    else
      exit 2
    fi
    ;;
  -h|--help|"") usage ;;
  *) die "project.sh: unknown subcommand ${1}" ;;
esac
