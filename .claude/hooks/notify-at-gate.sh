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

# Defensive extraction — all fields are optional.
MSG="$(printf '%s' "$INPUT" | jq -r '.message // "Harness event"' 2>/dev/null || echo "Harness event")"
TITLE="$(printf '%s' "$INPUT" | jq -r '.title // "Harness"' 2>/dev/null || echo "Harness")"

# Sanitise for safe embedding in AppleScript string literals:
# escape backslashes first, then double-quotes.
SAFE_MSG="$(printf '%s' "$MSG"   | sed 's/\\/\\\\/g; s/"/\\"/g')"
SAFE_TITLE="$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')"

# ── Platform delivery ─────────────────────────────────────────────────────────
case "$(uname -s)" in
  Darwin)
    # macOS Notification Center via osascript.
    # Errors are suppressed — notification permission may be denied in CI.
    osascript -e "display notification \"${SAFE_MSG}\" with title \"${SAFE_TITLE}\"" 2>/dev/null || true
    ;;
  *)
    # Non-macOS: print to stderr so the operator can pipe or redirect.
    printf '[Harness notify] %s — %s\n' "$SAFE_TITLE" "$SAFE_MSG" >&2
    ;;
esac

# ── Optional: Slack webhook ───────────────────────────────────────────────────
if [ -n "${HARNESS_SLACK_WEBHOOK_URL:-}" ]; then
  (
    PAYLOAD="$(printf '{"text":"%s: %s"}' "$SAFE_TITLE" "$SAFE_MSG")"
    curl -sf -X POST -H 'Content-type: application/json' \
      --data "$PAYLOAD" "$HARNESS_SLACK_WEBHOOK_URL" > /dev/null
  ) 2>/dev/null || true
fi

# ── Optional: email via mail(1) ───────────────────────────────────────────────
if [ -n "${HARNESS_NOTIFY_EMAIL:-}" ]; then
  (
    printf '%s\n' "$MSG" | mail -s "$TITLE" "$HARNESS_NOTIFY_EMAIL"
  ) 2>/dev/null || true
fi

exit 0
