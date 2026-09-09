#!/usr/bin/env bash
# memory-budget.sh - the single owner of how much context SessionStart may spend.
#
# Usage:
#   memory-budget.sh read              the effective budget, in estimated tokens
#   memory-budget.sh fit <max-tokens>  read stdin, emit at most that much
#
# WHY. SessionStart injects open decisions, crewmates needing attention,
# undrained notes and mission state. Each was bounded on its own by a hand-picked
# constant (3 missions, 5 log lines). Multiplied by a projects registry, every
# session starts heavy and nobody notices because no single piece is large.
#
# One accounted budget replaces the constants. `fit` truncates on a LINE
# boundary and says how much it dropped: silently losing the tail is how a
# session starts believing a half-told story.
#
# Estimation is deliberately crude — 4 characters per token. The point is a
# bound that exists, not a bound that is exact.
#
# Budget resolution, in order:
#   config/startup-memory-budget (an integer), else
#   HARNESS_MEMORY_BUDGET, else 7500.
#
# A malformed config file is an ERROR, not a silent fallback: an operator who
# wrote a budget deserves to know it was ignored.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
CONF="$HARNESS_ROOT/config/startup-memory-budget"

read_budget() {
  if [ -f "$CONF" ]; then
    local v; v="$(tr -d '[:space:]' < "$CONF" 2>/dev/null || true)"
    case "$v" in
      ''|*[!0-9]*) printf 'memory-budget: %s is not a positive integer\n' "$CONF" >&2; return 2 ;;
      *) printf '%s' "$v"; return 0 ;;
    esac
  fi
  local d="${HARNESS_MEMORY_BUDGET:-7500}"
  case "$d" in ''|*[!0-9]*) d=7500 ;; esac
  printf '%s' "$d"
}

case "${1:-}" in
  read) read_budget || exit 2; printf '\n' ;;
  fit)
    MAX="${2:-}"
    case "$MAX" in ''|*[!0-9]*) MAX="$(read_budget)" || exit 2 ;; esac
    LIMIT=$(( MAX * 4 ))   # ~4 chars per token
    total=0; dropped=0
    while IFS= read -r line || [ -n "$line" ]; do
      len=$(( ${#line} + 1 ))
      if [ "$dropped" -eq 0 ] && [ $(( total + len )) -le "$LIMIT" ]; then
        printf '%s\n' "$line"
        total=$(( total + len ))
      else
        dropped=$(( dropped + 1 ))
      fi
    done
    [ "$dropped" -gt 0 ] && printf '\n[%s more line(s) omitted to stay inside the startup memory budget of ~%s tokens — raise it in config/startup-memory-budget, or run /fleet for the full picture]\n' "$dropped" "$MAX"
    ;;
  -h|--help|"") sed -n '2,8{s/^# \{0,1\}//;s/^#$//;p;}' "$0" ;;
  *) printf 'memory-budget: unknown subcommand %s\n' "$1" >&2; exit 2 ;;
esac
