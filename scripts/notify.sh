#!/usr/bin/env bash
# notify.sh - the single owner of getting a message to the operator.
#
# Usage: notify.sh <title> <message> [--level normal|urgent]
#
# Extracted from .claude/hooks/notify-at-gate.sh so the hook and the away-mode
# daemon share one implementation and cannot drift apart. Delivery failure is
# never fatal: a notification that cannot be sent must not break the thing that
# was trying to send it.
#
# Channels, tried in order and all best-effort:
#   macOS Notification Center (osascript)
#   HARNESS_SLACK_WEBHOOK_URL
#   HARNESS_NOTIFY_EMAIL (via mail(1))
#   stderr, always
#
# HARNESS_NOTIFY_DRYRUN=1 prints what would be sent and sends nothing.

set -uo pipefail
case "${1:-}" in
  -h|--help) sed -n '2,20{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
esac

TITLE="${1:-Harness}"; MSG="${2:-}"; LEVEL="normal"
[ "${3:-}" = "--level" ] && LEVEL="${4:-normal}"
[ -n "$MSG" ] || { printf 'usage: notify.sh <title> <message> [--level normal|urgent]\n' >&2; exit 2; }

SAFE_MSG="$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')"
SAFE_TITLE="$(printf '%s' "$TITLE" | sed 's/\\/\\\\/g; s/"/\\"/g')"

if [ -n "${HARNESS_NOTIFY_DRYRUN:-}" ]; then
  printf '[dry-run:%s] %s — %s\n' "$LEVEL" "$SAFE_TITLE" "$SAFE_MSG" >&2
  exit 0
fi

case "$(uname -s)" in
  Darwin)
    if [ "$LEVEL" = "urgent" ]; then
      osascript -e "display notification \"${SAFE_MSG}\" with title \"${SAFE_TITLE}\" sound name \"Basso\"" 2>/dev/null || true
    else
      osascript -e "display notification \"${SAFE_MSG}\" with title \"${SAFE_TITLE}\"" 2>/dev/null || true
    fi ;;
esac

if [ -n "${HARNESS_SLACK_WEBHOOK_URL:-}" ]; then
  ( curl -sf -X POST -H 'Content-type: application/json' \
      --data "$(printf '{"text":"%s: %s"}' "$SAFE_TITLE" "$SAFE_MSG")" \
      "$HARNESS_SLACK_WEBHOOK_URL" >/dev/null ) 2>/dev/null || true
fi

if [ -n "${HARNESS_NOTIFY_EMAIL:-}" ]; then
  ( printf '%s\n' "$MSG" | mail -s "$TITLE" "$HARNESS_NOTIFY_EMAIL" ) 2>/dev/null || true
fi

[ "$LEVEL" = "urgent" ] && printf '\a' >&2
printf '[harness] %s — %s\n' "$TITLE" "$MSG" >&2
exit 0
