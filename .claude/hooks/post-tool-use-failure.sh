#!/usr/bin/env bash
# Ported from ECC (https://github.com/affaan-m/ECC)
# Original: hooks/post-tool-use-failure.sh
# Copyright (c) 2026 Affaan Mustafa — Licensed under MIT
# Note: ECC source was unreachable at port time; this is a minimal compatible implementation.
#
# PostToolUseFailure hook. Captures the failure event from stdin and logs a
# one-line entry to the active mission's log.md (if one exists). Exits 0
# unconditionally so the hook never blocks Claude Code's error-handling path.
#
# Input: JSON on stdin with .hook_event_name, .tool_name, and .error fields.

set -uo pipefail

INPUT="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")"
ERROR_MSG="$(printf '%s' "$INPUT" | jq -r '.error // ""' 2>/dev/null || echo "")"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown-time")"
SESSION="${CLAUDE_SESSION_ID:-unknown}"

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$HARNESS_ROOT" ]; then
  exit 0
fi

# Find most recent mission's log.md
LOG_FILE="$(ls -td "${HARNESS_ROOT}/missions"/*/log.md 2>/dev/null | head -n1 || echo "")"
if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
  exit 0
fi

# Truncate error to 200 chars to avoid polluting the log
SHORT_ERROR="$(printf '%s' "$ERROR_MSG" | head -c 200)"

printf '[%s] [session=%s] tool-failure tool=%s error=%s\n' \
  "$NOW" "$SESSION" "$TOOL_NAME" "$SHORT_ERROR" >> "$LOG_FILE"

exit 0
