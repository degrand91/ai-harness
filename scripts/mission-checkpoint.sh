#!/usr/bin/env bash
#
# mission-checkpoint.sh — snapshot current mission progress into checkpoint.json.
#
# Usage:
#   ./scripts/mission-checkpoint.sh <mission-id>
#
# Writes missions/<id>/checkpoint.json and echoes the JSON to stdout.
# See protocols/checkpoint-protocol.md for the full schema and emit rules.

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISSIONS_DIR="${HARNESS_ROOT}/missions"

# ── arg validation ─────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <mission-id>" >&2
  exit 1
fi

MISSION_ID="$1"
MISSION_DIR="${MISSIONS_DIR}/${MISSION_ID}"

if [[ ! -d "$MISSION_DIR" ]]; then
  echo "error: mission directory not found: ${MISSION_DIR}" >&2
  exit 1
fi

# ── dependencies ───────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

STATUS_FILE="${MISSION_DIR}/status.json"

if [[ ! -f "$STATUS_FILE" ]]; then
  echo "error: status.json not found at ${STATUS_FILE}" >&2
  exit 1
fi

# ── read status.json ───────────────────────────────────────────────────────────
MISSION_STATE="$(jq -r '.state // "unknown"' "$STATUS_FILE")"
CURRENT_FEATURE_FROM_STATUS="$(jq -r '.current_feature // ""' "$STATUS_FILE")"

# ── compute completed_features (state == closed) ───────────────────────────────
COMPLETED_JSON="$(jq '[.features[]? | select(.state == "closed") | .id]' "$STATUS_FILE")"

# ── compute remaining_features (state == pending or in_progress) ───────────────
REMAINING_JSON="$(jq '[.features[]? | select(.state == "pending" or .state == "in_progress") | .id]' "$STATUS_FILE")"

# ── compute current_feature (in_progress takes precedence; fall back to status field) ─
CURRENT_FEATURE_IN_PROGRESS="$(jq -r '[.features[]? | select(.state == "in_progress") | .id][0] // ""' "$STATUS_FILE")"

if [[ -n "$CURRENT_FEATURE_IN_PROGRESS" ]]; then
  CURRENT_FEATURE="$CURRENT_FEATURE_IN_PROGRESS"
elif [[ -n "$CURRENT_FEATURE_FROM_STATUS" ]]; then
  CURRENT_FEATURE="$CURRENT_FEATURE_FROM_STATUS"
else
  CURRENT_FEATURE="null"
fi

# jq-safe value: quote string or emit JSON null
if [[ "$CURRENT_FEATURE" == "null" || -z "$CURRENT_FEATURE" ]]; then
  CURRENT_FEATURE_JSON="null"
else
  CURRENT_FEATURE_JSON="\"${CURRENT_FEATURE}\""
fi

# ── last commit SHA ────────────────────────────────────────────────────────────
LAST_COMMIT_SHA="$(git -C "${HARNESS_ROOT}" log -1 --pretty=%h 2>/dev/null || echo "unknown")"

# ── session id ────────────────────────────────────────────────────────────────
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

# ── ISO timestamp ──────────────────────────────────────────────────────────────
CHECKPOINT_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── post-mortem present ────────────────────────────────────────────────────────
POST_MORTEM_PRESENT="false"
if [[ -f "${MISSION_DIR}/post-mortem.md" ]]; then
  POST_MORTEM_PRESENT="true"
fi

# ── next_action ────────────────────────────────────────────────────────────────
# Determine next action based on mission state and remaining features.
FIRST_PENDING="$(jq -r '[.features[]? | select(.state == "pending") | .id][0] // ""' "$STATUS_FILE")"

case "$MISSION_STATE" in
  closed)
    NEXT_ACTION="mission already closed"
    ;;
  closing)
    if [[ "$POST_MORTEM_PRESENT" == "true" ]]; then
      NEXT_ACTION="run integration check"
    else
      NEXT_ACTION="run integration check or author post-mortem"
    fi
    ;;
  executing|feature_loop)
    if [[ -n "$CURRENT_FEATURE_IN_PROGRESS" ]]; then
      NEXT_ACTION="spawn worker for ${CURRENT_FEATURE_IN_PROGRESS}"
    elif [[ -n "$FIRST_PENDING" ]]; then
      NEXT_ACTION="spawn worker for ${FIRST_PENDING}"
    else
      NEXT_ACTION="all features done — transition to closing"
    fi
    ;;
  awaiting_approval)
    NEXT_ACTION="wait for user approval, then transition to executing"
    ;;
  paused)
    if [[ -n "$FIRST_PENDING" ]]; then
      NEXT_ACTION="resume — spawn worker for ${FIRST_PENDING}"
    else
      NEXT_ACTION="resume — all features done, transition to closing"
    fi
    ;;
  *)
    NEXT_ACTION="review status.json — state is '${MISSION_STATE}'"
    ;;
esac

# ── assemble and write checkpoint.json ────────────────────────────────────────
CHECKPOINT_JSON="$(jq -n \
  --arg mission_id       "$MISSION_ID" \
  --arg session_id       "$SESSION_ID" \
  --arg checkpoint_at    "$CHECKPOINT_AT" \
  --arg mission_state    "$MISSION_STATE" \
  --argjson completed    "$COMPLETED_JSON" \
  --argjson remaining    "$REMAINING_JSON" \
  --argjson current_f    "$CURRENT_FEATURE_JSON" \
  --arg last_commit_sha  "$LAST_COMMIT_SHA" \
  --argjson post_mortem  "$POST_MORTEM_PRESENT" \
  --arg next_action      "$NEXT_ACTION" \
  '{
    mission_id:         $mission_id,
    session_id:         $session_id,
    checkpoint_at:      $checkpoint_at,
    mission_state:      $mission_state,
    completed_features: $completed,
    remaining_features: $remaining,
    current_feature:    $current_f,
    last_commit_sha:    $last_commit_sha,
    post_mortem_present: $post_mortem,
    next_action:        $next_action
  }'
)"

CHECKPOINT_FILE="${MISSION_DIR}/checkpoint.json"
printf '%s\n' "$CHECKPOINT_JSON" > "$CHECKPOINT_FILE"

# echo to stdout so callers can capture or display
printf '%s\n' "$CHECKPOINT_JSON"
