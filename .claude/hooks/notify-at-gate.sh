#!/usr/bin/env bash
#
# Notification hook — fires on Claude Code Notification events.
#
# This hook receives a JSON payload on stdin describing a notification event.
# It attempts to surface the notification to the operator via the best available
# method for the current platform.
#
# CONFIGURATION:
#   No configuration required for basic macOS notifications.
#   Optional environment variables extend behaviour:
#
#   HARNESS_SLACK_WEBHOOK_URL
#     If set, POSTs the notification as a Slack incoming-webhook message.
#     Requires: curl
#     Example:
#       export HARNESS_SLACK_WEBHOOK_URL=https://hooks.slack.com/services/T.../B.../xxx
#
#   HARNESS_NOTIFY_EMAIL
#     If set, sends a one-line email via the local `mail` command.
#     Requires: mail(1) configured with a working MTA.
#     Example:
#       export HARNESS_NOTIFY_EMAIL=ops@example.com
#
# PLATFORM SUPPORT (shipped):
#   macOS  — osascript display notification (Notification Center)
#   Other  — printf to stderr (operator pipes to their own system)
#
# EXTENSIBILITY:
#   Add new delivery methods after the platform block. Each method should
#   be wrapped in a subshell or || true so failures never cause exit != 0.
#
# Exit code:
#   Always 0. Notification failure must NEVER block Claude Code.
#
# Input: JSON on stdin — schema is treated as optional/unstable.
#   Known fields (as of 2026-05):
#     hook_event_name  string  — "Notification"
#     message          string  — human-readable notification text
#     title            string  — optional short title
#     session_id       string  — Claude session identifier

set -euo pipefail

# ── Read stdin ────────────────────────────────────────────────────────────────
INPUT="$(cat)"

# Defensive extraction — all fields are optional. Escaping is NOT done here:
# scripts/notify.sh owns it, and doing it twice would render literal backslashes.
MSG="$(printf '%s' "$INPUT" | jq -r '.message // empty' 2>/dev/null || true)"
TITLE="$(printf '%s' "$INPUT" | jq -r '.title // empty' 2>/dev/null || true)"
[ -n "$MSG" ] || MSG="Harness event"
[ -n "$TITLE" ] || TITLE="Harness"

# All delivery goes through scripts/notify.sh, the single owner, so this hook
# and the away-mode daemon cannot drift apart. Delivery must never fail a turn.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
"$CODE_ROOT/scripts/notify.sh" "$TITLE" "$MSG" || true
exit 0
