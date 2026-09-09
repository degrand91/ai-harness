#!/usr/bin/env bash
#
# mission-tui.sh — compact TUI of the active mission's state.
#
# Usage:
#   ./scripts/mission-tui.sh                   # most-recent non-closed mission
#   ./scripts/mission-tui.sh <mission-id>       # specific mission
#   ./scripts/mission-tui.sh --watch            # refresh every 2s (most-recent)
#   ./scripts/mission-tui.sh <mission-id> --watch

set -euo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Code comes from BASH_SOURCE, missions from CLAUDE_PROJECT_DIR (or the cwd when
# it looks like a harness home). Resolving both from the script's own location
# made this unusable against any home but its own checkout.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then HARNESS_ROOT="$CLAUDE_PROJECT_DIR"
elif [ -d "${PWD}/missions" ];  then HARNESS_ROOT="$PWD"
else                                 HARNESS_ROOT="$CODE_ROOT"; fi

# shellcheck source=lib/status-read.sh
. "${CODE_ROOT}/scripts/lib/status-read.sh"
MISSIONS_DIR="${HARNESS_ROOT}/missions"

# ── arg parsing ───────────────────────────────────────────────────────────────
WATCH=false
MISSION_ID=""
for arg in "$@"; do
  case "$arg" in
    --watch) WATCH=true ;;
    *)       MISSION_ID="$arg" ;;
  esac
done

# ── jq guard ──────────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not installed." >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Debian: apt install jq" >&2
  exit 1
fi

# ── ANSI helpers (only when stdout is a tty) ──────────────────────────────────
if [[ -t 1 ]]; then
  BOLD='\033[1m'; RESET='\033[0m'
  GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; CYAN='\033[36m'; DIM='\033[2m'
else
  BOLD=''; RESET=''; GREEN=''; YELLOW=''; RED=''; CYAN=''; DIM=''
fi

color_for() {
  local c="${1:-}"
  case "$c" in
    green)  printf '%s' "$GREEN"  ;;
    yellow) printf '%s' "$YELLOW" ;;
    red)    printf '%s' "$RED"    ;;
    *)      printf '%s' "$CYAN"   ;;
  esac
}

state_color() {
  local s="${1:-}"
  case "$s" in
    closed|done)       printf '%s' "$GREEN"  ;;
    in_progress)       printf '%s' "$YELLOW" ;;
    failed|abandoned)  printf '%s' "$RED"    ;;
    *)                 printf '%s' "$DIM"    ;;
  esac
}

# ── mission selection ─────────────────────────────────────────────────────────
resolve_mission() {
  if [[ -n "$MISSION_ID" ]]; then
    echo "$MISSION_ID"
    return
  fi

  # Sort by mtime of status.json; prefer non-closed/abandoned
  local best="" best_open=""
  while IFS= read -r dir; do
    local sj="${dir}/status.json"
    [[ -f "$sj" ]] || continue
    local st
    st=$(status_state "$sj" 2>/dev/null || true)
    if [[ "$st" != "closed" && "$st" != "abandoned" ]]; then
      best_open="$(basename "$dir")"
      break  # ls -t gives newest first
    fi
    [[ -z "$best" ]] && best="$(basename "$dir")"
  done < <(ls -td "${MISSIONS_DIR}"/*/status.json 2>/dev/null | sed 's|/status\.json$||')

  if [[ -n "$best_open" ]]; then
    echo "$best_open"
  elif [[ -n "$best" ]]; then
    echo "$best"
  fi
}

# ── render ────────────────────────────────────────────────────────────────────
render() {
  local mid
  mid="$(resolve_mission)"

  if [[ -z "$mid" || ! -d "${MISSIONS_DIR}/${mid}" ]]; then
    echo "error: no mission found in ${MISSIONS_DIR}" >&2
    return 1
  fi

  local mdir="${MISSIONS_DIR}/${mid}"
  local sj="${mdir}/status.json"

  if [[ ! -f "$sj" ]]; then
    echo "error: status.json not found at ${sj}" >&2
    return 1
  fi

  # Parse top-level fields
  local state current_feature chain_target
  state=$(status_state "$sj" 2>/dev/null || true); [ -n "$state" ] || state="unknown"

  # A mission whose state cannot be read has nothing else worth reading either.
  # Say so plainly rather than letting jq's parse errors reach the operator.
  if [[ "$state" == "unknown" ]]; then
    printf '%b%s%b\n' "$BOLD" "──────────────────────────────────────────────" "$RESET"
    printf ' %bMission:%b  %s\n' "$BOLD" "$RESET" "$mid"
    printf ' %bState:%b    unknown — status.json is malformed or uses an unrecognised vocabulary\n' "$BOLD" "$RESET"
    printf ' %bFile:%b     %s\n' "$BOLD" "$RESET" "$sj"
    printf '%b%s%b\n' "$BOLD" "──────────────────────────────────────────────" "$RESET"
    return 0
  fi

  current_feature=$(jq -r '.current_feature // "—"' "$sj" 2>/dev/null || echo "—")
  chain_target=$(jq -r '.chain_target // ""' "$sj" 2>/dev/null || true)

  local sep="──────────────────────────────────────────────"

  # Header
  printf '%b%s%b\n' "$BOLD" "$sep" "$RESET"
  printf ' %bMission:%b  %s\n' "$BOLD" "$RESET" "$mid"
  printf ' %bState:%b    %b%s%b\n' "$BOLD" "$RESET" "$(state_color "$state")" "$state" "$RESET"
  [[ -n "$chain_target" ]] && printf ' %bTarget:%b   %s\n' "$BOLD" "$RESET" "$chain_target"
  printf ' %bCurrent:%b  %s\n' "$BOLD" "$RESET" "$current_feature"
  printf '%b%s%b\n' "$BOLD" "$sep" "$RESET"

  # Features table
  printf '\n%bFeatures%b\n' "$BOLD" "$RESET"
  printf '  %-6s  %-36s  %-12s  %s\n' "ID" "Slug" "State" "Color"
  printf '  %-6s  %-36s  %-12s  %s\n' "------" "------------------------------------" "------------" "-----"

  local nfeatures
  nfeatures=$(jq '.features | length' "$sj")
  local i
  for (( i=0; i<nfeatures; i++ )); do
    local fid fslug fstate fcolor
    fid=$(jq -r ".features[$i].id // \"\"" "$sj")
    fslug=$(jq -r ".features[$i].slug // \"\"" "$sj")
    fstate=$(jq -r ".features[$i].state // \"pending\"" "$sj")
    fcolor=$(jq -r ".features[$i].color // \"—\"" "$sj")
    printf '  %b%-6s%b  %-36s  %b%-12s%b  %b%s%b\n' \
      "$(state_color "$fstate")" "$fid" "$RESET" \
      "$fslug" \
      "$(state_color "$fstate")" "$fstate" "$RESET" \
      "$(color_for "$fcolor")" "$fcolor" "$RESET"
  done

  # Last 8 lines of log.md
  local logfile="${mdir}/log.md"
  printf '\n%b%s%b\n' "$BOLD" "$sep" "$RESET"
  printf '%bLast log entries%b\n' "$BOLD" "$RESET"
  if [[ -f "$logfile" ]]; then
    tail -n 8 "$logfile"
  else
    printf '%b(no log.md)%b\n' "$DIM" "$RESET"
  fi

  # Last feature scrutiny verdict
  local last_scrutiny=""
  for (( i=nfeatures-1; i>=0; i-- )); do
    local fslug_raw fnum
    fnum=$(printf '%03d' "$((i+1))")
    fslug_raw=$(jq -r ".features[$i].slug // \"\"" "$sj")
    local sf="${mdir}/features/${fnum}-${fslug_raw}/scrutiny.md"
    if [[ -f "$sf" ]]; then
      last_scrutiny="$sf"
      break
    fi
  done

  printf '\n%b%s%b\n' "$BOLD" "$sep" "$RESET"
  printf '%bScrutiny%b\n' "$BOLD" "$RESET"
  if [[ -n "$last_scrutiny" ]]; then
    printf '%b%s%b\n' "$DIM" "$last_scrutiny" "$RESET"
    # Extract verdict line if present
    grep -iE 'verdict|result|outcome|pass|fail' "$last_scrutiny" 2>/dev/null | head -3 || true
  else
    printf '%b(no scrutiny available)%b\n' "$DIM" "$RESET"
  fi

  printf '%b%s%b\n' "$BOLD" "$sep" "$RESET"
}

# ── main ──────────────────────────────────────────────────────────────────────
if [[ "$WATCH" == "true" ]]; then
  while true; do
    clear
    render
    sleep 2
  done
else
  render
fi
