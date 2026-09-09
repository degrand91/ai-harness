#!/usr/bin/env bash
#
# status.sh — human-readable view of a mission's current state.
#
# Usage:
#   ./scripts/status.sh                 # most recently modified mission
#   ./scripts/status.sh <mission-id>    # specific mission

set -euo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Missions are read from the invoking directory when it looks like a harness
# home, so the suite can point this at a fixture; otherwise from the checkout.
if [ -d "${PWD}/missions" ]; then HARNESS_ROOT="$PWD"; else HARNESS_ROOT="$CODE_ROOT"; fi
MISSIONS_DIR="${HARNESS_ROOT}/missions"

# shellcheck source=lib/status-read.sh
. "${CODE_ROOT}/scripts/lib/status-read.sh"

case "${1:-}" in
  -h|--help) sed -n '3,8{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
esac

MISSION_ID="${1:-}"
if [[ -z "$MISSION_ID" ]]; then
  # pick most-recent
  MISSION_ID="$(ls -t "$MISSIONS_DIR" 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$MISSION_ID" || ! -d "${MISSIONS_DIR}/${MISSION_ID}" ]]; then
  echo "error: no mission found (looked in ${MISSIONS_DIR})" >&2
  exit 1
fi

MISSION_DIR="${MISSIONS_DIR}/${MISSION_ID}"

echo "=========================================="
echo " Mission: ${MISSION_ID}"
echo "=========================================="
echo

STATE="$(status_state "${MISSION_DIR}/status.json" || true)"

if command -v jq >/dev/null 2>&1; then
  printf 'State:          %s\n' "$STATE"
  [ "$STATE" = "unknown" ] && printf '                (status.json is malformed or uses an unrecognised vocabulary)\n'
  jq -r '
    "Started:        \(.started_at // "—")",
    "Approved:       \(.approved_at // "—")",
    "Closed:         \(.closed_at // "—")",
    "Current:        \(.current_feature // "—")",
    "",
    "Features:",
    (.features[]? | "  \(.id) \(.slug)  \(.state)  color=\(.color // "—")  followups=\(.followups)")
  ' "${MISSION_DIR}/status.json" 2>/dev/null || echo "(status.json could not be parsed — showing raw file below)"
  jq -e . "${MISSION_DIR}/status.json" >/dev/null 2>&1 || sed -n '1,20p' "${MISSION_DIR}/status.json"
else
  echo "(jq not installed — raw status.json:)"
  cat "${MISSION_DIR}/status.json"
fi

echo
echo "=========================================="
echo " Last 10 log entries"
echo "=========================================="
tail -n 10 "${MISSION_DIR}/log.md" 2>/dev/null || echo "(no log)"

echo
echo "Mission folder: ${MISSION_DIR}"
