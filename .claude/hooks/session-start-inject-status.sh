#!/usr/bin/env bash
#
# SessionStart hook. If there's an active mission (state != closed/abandoned),
# inject its current status into the session context so the Orchestrator can
# resume cleanly without needing to run /mission-status first.
#
# Output: JSON on stdout with hookSpecificOutput.additionalContext.
# Exit 0.

set -euo pipefail

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-/Users/stefanodegrandis/projects/ai/harness}"
MISSIONS="${HARNESS_ROOT}/missions"

cat > /dev/null  # Discard stdin

[ ! -d "$MISSIONS" ] && { echo '{}'; exit 0; }

# Find most recently modified mission directory.
LATEST="$(ls -t "$MISSIONS" 2>/dev/null | grep -v '^\.gitkeep$' | head -n1 || true)"
[ -z "$LATEST" ] && { echo '{}'; exit 0; }

STATUS_FILE="$MISSIONS/$LATEST/status.json"
[ ! -f "$STATUS_FILE" ] && { echo '{}'; exit 0; }

STATE="$(jq -r '.state // "unknown"' "$STATUS_FILE" 2>/dev/null)"
case "$STATE" in
  closed|abandoned) echo '{}'; exit 0 ;;
esac

CURRENT="$(jq -r '.current_feature // "—"' "$STATUS_FILE" 2>/dev/null)"
N_FEATS="$(jq -r '.features | length' "$STATUS_FILE" 2>/dev/null)"

# Tail of log for recency cues.
LOG_TAIL=""
if [ -f "$MISSIONS/$LATEST/log.md" ]; then
  LOG_TAIL="$(tail -n 5 "$MISSIONS/$LATEST/log.md" 2>/dev/null || true)"
fi

CONTEXT="$(printf 'Active mission detected:\n  id: %s\n  state: %s\n  current_feature: %s\n  features in plan: %s\n\nRecent log:\n%s\n\nUse /mission-resume to continue, or /mission-status to inspect.' \
  "$LATEST" "$STATE" "$CURRENT" "$N_FEATS" "$LOG_TAIL")"

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}'

exit 0
