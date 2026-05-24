#!/usr/bin/env bash
#
# Stop hook. Refuses to let the session end if any mission has a red feature
# (`color: "red"`) that isn't followed by a closed follow-up, OR if an
# in-flight mission has state="executing" with current_feature stuck
# `in_progress` for more than 1 hour (likely abandoned).
#
# Exit codes:
#   0  — allow stop (no red status)
#   2  — block stop, print reason to stderr (Claude will see the reason)
#
# Input: JSON on stdin (unused).

set -euo pipefail

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-/Users/stefanodegrandis/projects/ai/harness}"
MISSIONS="${HARNESS_ROOT}/missions"

[ ! -d "$MISSIONS" ] && exit 0

# Discard stdin (we don't need the prompt context).
cat > /dev/null

PROBLEMS=()

shopt -s nullglob
for mission_dir in "$MISSIONS"/*/; do
  [ -d "$mission_dir" ] || continue
  id="$(basename "$mission_dir")"
  [ "$id" = ".gitkeep" ] && continue
  status_file="$mission_dir/status.json"
  [ ! -f "$status_file" ] && continue

  state="$(jq -r '.state // "unknown"' "$status_file" 2>/dev/null)"
  case "$state" in
    closed|abandoned|paused|awaiting_approval|intake) continue ;;
  esac

  # Look for red features without a closed follow-up.
  reds="$(jq -r '
    .features // [] |
    map(select(.color == "red")) |
    map(select(.followups | length == 0 or any(.; . | test("^F.*-followup-")) == false)) |
    map(.id) |
    join(",")
  ' "$status_file" 2>/dev/null)"

  if [ -n "$reds" ]; then
    PROBLEMS+=("Mission ${id}: red features without follow-ups: ${reds}")
  fi

  # Detect stuck in-progress features: executing missions with a feature that
  # has state="in_progress" and color=null indicate the worker never completed
  # (or the orchestrator forgot to update state after the feature closed).
  # We only check missions still in "executing" state — abandoned/paused/closed
  # are already filtered out by the case statement above.
  if [ "$state" = "executing" ]; then
    stuck="$(jq -r '
      .features // [] |
      map(select(.state == "in_progress" and .color == null)) |
      map(.id) |
      join(",")
    ' "$status_file" 2>/dev/null)"

    if [ -n "$stuck" ]; then
      PROBLEMS+=("Mission ${id}: stuck in-progress feature(s) with no outcome color: ${stuck}")
    fi
  fi
done

if [ ${#PROBLEMS[@]} -gt 0 ]; then
  {
    echo "[Stop hook] Refusing to end — unresolved mission issues detected:"
    for p in "${PROBLEMS[@]}"; do
      echo "  - $p"
    done
    echo
    echo "For red features: open a follow-up feature, or explicitly abandon/pause the mission."
    echo "For stuck in-progress features: close the feature properly, or set mission state to abandoned/paused."
  } >&2
  exit 2
fi

exit 0
