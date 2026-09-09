#!/usr/bin/env bash
# doctor.sh - the single owner of "is this harness home ready to run".
#
# Usage:
#   scripts/doctor.sh            check tools, create state roots, report
#   scripts/doctor.sh --check    report only; create nothing (CI mode)
#
# INSTALLS NOTHING and CHANGES NO PROJECT. It creates the four local state roots
# (data/ state/ config/ and missions/), reports on required and optional tools,
# and — once a project registry exists — prunes stale git worktree entries and
# names orphaned crew branches. Exit 1 only when a REQUIRED tool is missing.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"

CHECK_ONLY=0
case "${1:-}" in
  -h|--help) sed -n '2,12{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
  --check)   CHECK_ONLY=1 ;;
  "")        ;;
  *)         printf 'doctor.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
esac

MISSING_REQUIRED=0
ok()   { printf '  ok       %s\n' "$1"; }
warn() { printf '  MISSING  %s — %s\n' "$1" "$2"; }
bad()  { printf '  MISSING  %s — %s\n' "$1" "$2"; MISSING_REQUIRED=1; }

printf 'Required tools\n'
for t in git jq bash; do
  command -v "$t" >/dev/null 2>&1 && ok "$t ($($t --version 2>&1 | head -n1))" \
                                  || bad "$t" "the harness cannot run without it"
done

printf '\nOptional tools\n'
command -v gh >/dev/null 2>&1 \
  && { if gh auth status >/dev/null 2>&1; then ok "gh (authenticated)"; else warn "gh auth" "run: gh auth login"; fi } \
  || warn "gh" "needed for PR delivery modes — https://cli.github.com"
command -v tmux       >/dev/null 2>&1 && ok "tmux"       || warn "tmux"       "needed to watch crewmates (Phase 3)"
command -v shellcheck >/dev/null 2>&1 && ok "shellcheck" || warn "shellcheck" "brew install shellcheck"
command -v claude     >/dev/null 2>&1 && ok "claude ($(claude --version 2>&1 | head -n1))" \
                                      || warn "claude" "needed to launch crewmates (Phase 3)"
command -v no-mistakes >/dev/null 2>&1 && ok "no-mistakes" || warn "no-mistakes" "needed for [no-mistakes] delivery mode (Phase 3)"

printf '\nState roots\n'
for d in missions data state config; do
  p="$HARNESS_ROOT/$d"
  if [ -d "$p" ]; then
    ok "$d/"
  elif [ "$CHECK_ONLY" -eq 1 ]; then
    warn "$d/" "absent (run without --check to create)"
  else
    mkdir -p "$p" && printf '  created  %s/\n' "$d"
  fi
done

# Git hygiene across registered projects. The registry arrives in Phase 1.1; until
# then this section is a no-op rather than an error.
REGISTRY="$HARNESS_ROOT/data/projects.md"
if [ -f "$REGISTRY" ]; then
  printf '\nProject git hygiene\n'
  while IFS= read -r line; do
    case "$line" in -\ *) ;; *) continue ;; esac
    path="$(printf '%s' "$line" | sed -nE 's@.*\] +([^ ]+).*@\1@p')"
    [ -n "$path" ] || continue
    path="${path/#\~/$HOME}"
    [ -d "$path/.git" ] || { printf '  skip     %s (not a git checkout)\n' "$path"; continue; }
    [ "$CHECK_ONLY" -eq 0 ] && git -C "$path" worktree prune >/dev/null 2>&1
    orphans="$(git -C "$path" branch --list 'hc/*' --format='%(refname:short)' 2>/dev/null | while IFS= read -r b; do
      [ -n "$b" ] || continue
      task="${b##*/}"
      [ -f "$HARNESS_ROOT/state/$task.meta" ] || printf '%s ' "$b"
    done)"
    if [ -n "$orphans" ]; then
      printf '  orphans  %s: %s\n' "$(basename "$path")" "$orphans"
    else
      ok "$(basename "$path")"
    fi
  done < "$REGISTRY"
fi

printf '\n'
if [ "$MISSING_REQUIRED" -eq 1 ]; then
  printf 'NOT READY — install the required tools above.\n' >&2
  exit 1
fi
printf 'Ready.\n'
