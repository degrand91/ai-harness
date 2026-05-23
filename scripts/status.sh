#!/usr/bin/env bash
#
# status.sh — human-readable view of a mission's current state.
#
# Usage:
#   ./scripts/status.sh                 # most recently modified mission
#   ./scripts/status.sh <mission-id>    # specific mission

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISSIONS_DIR="${HARNESS_ROOT}/missions"

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

if command -v jq >/dev/null 2>&1; then
  jq -r '
    "State:          \(.state)",
    "Started:        \(.started_at)",
    "Approved:       \(.approved_at // "—")",
    "Closed:         \(.closed_at // "—")",
    "Current:        \(.current_feature // "—")",
    "",
    "Features:",
    (.features[]? | "  \(.id) \(.slug)  \(.state)  color=\(.color // "—")  followups=\(.followups)")
  ' "${MISSION_DIR}/status.json"
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
