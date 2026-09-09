#!/usr/bin/env bash
#
# SessionEnd hook. Releases state/session.lock if THIS session owns it, so the
# next session starts as owner instead of as an observer.
#
# An observer's SessionEnd is a no-op: it never touches the owner's lock.
# Always exit 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
LOCK="${HARNESS_ROOT}/state/session.lock"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || exit 0

# shellcheck source=../../scripts/lib/session-lock.sh
. "$CODE_ROOT/scripts/lib/session-lock.sh" 2>/dev/null || exit 0

lock_release "$LOCK" "$SESSION_ID" >/dev/null 2>&1 || true
exit 0
