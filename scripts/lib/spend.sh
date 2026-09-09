#!/usr/bin/env bash
# spend.sh - the single owner of what the fleet has cost today.
#
# A mission's `cost_usd` accumulates over its whole life, which answers "what
# did this mission cost" but not "what have I spent today" — and a daily cap is
# the only one that stops a runaway before it becomes a bill.
#
# So spend is also recorded per day: state/spend/<YYYY-MM-DD>, one decimal
# number per line, appended by scripts/crew/teardown.sh as each crewmate's real
# reported cost lands.
#
# Usage (sourced):
#   spend_record <home> <usd>     append one crewmate's cost to today
#   spend_today  <home>           today's total, as a decimal string
#   spend_cap    <home>           the configured cap, or "" if none
#   spend_over_cap <home>         0 = over, 1 = under or uncapped
#
# NO CAP IS THE DEFAULT. A cap that appears without the operator choosing it
# would block work for a reason they never set.

set -uo pipefail

_spend_file() { printf '%s/state/spend/%s' "${1:?}" "$(date -u +%Y-%m-%d)"; }

spend_record() {
  local home="${1:?}" usd="${2:-0}"
  case "$usd" in ''|*[!0-9.]*) return 0 ;; esac
  local f; f="$(_spend_file "$home")"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 1
  printf '%s\n' "$usd" >> "$f"
}

spend_today() {
  local f; f="$(_spend_file "${1:?}")"
  [ -f "$f" ] || { printf '0'; return 0; }
  awk '{ s += $1 } END { printf "%.4f", s+0 }' "$f" 2>/dev/null || printf '0'
}

spend_cap() {
  local c="${1:?}/config/spend-cap-daily"
  [ -f "$c" ] || return 0
  local v; v="$(tr -d '[:space:]' < "$c" 2>/dev/null || true)"
  case "$v" in ''|*[!0-9.]*) return 0 ;; esac
  printf '%s' "$v"
}

# 0 = over the cap. Uncapped is never over.
spend_over_cap() {
  local home="${1:?}" cap today
  cap="$(spend_cap "$home")"
  [ -n "$cap" ] || return 1
  today="$(spend_today "$home")"
  awk -v a="$today" -v b="$cap" 'BEGIN { exit !(a+0 >= b+0) }'
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    today)  shift; spend_today "$@"; printf '\n' ;;
    cap)    shift; spend_cap "$@"; printf '\n' ;;
    record) shift; spend_record "$@" ;;
    over)   shift; spend_over_cap "$@" ;;
    -h|--help|"") sed -n '2,18{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    *) printf 'spend: unknown subcommand %s\n' "${1:-}" >&2; exit 2 ;;
  esac
fi
