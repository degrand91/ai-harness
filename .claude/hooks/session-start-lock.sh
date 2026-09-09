#!/usr/bin/env bash
#
# SessionStart hook. Claims this repo for one orchestrator session, or tells a
# second session that it is an observer.
#
# Two sessions open on the harness are two orchestrators: both dispatch, both
# write mission state, and both would arm a watcher. The first session to start
# owns state/session.lock; any other live session is told, in its own context,
# that it may look but not act. scripts/lib/session-lock.sh owns the contract;
# .claude/hooks/pre-tool-observer-guard.sh enforces it.
#
# Output: JSON on stdout. Always exit 0 — never block a session from starting.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
LOCK="${HARNESS_ROOT}/state/session.lock"

emit_empty() { printf '{}\n'; exit 0; }

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || emit_empty

# shellcheck source=../../scripts/lib/session-lock.sh
. "$CODE_ROOT/scripts/lib/session-lock.sh" 2>/dev/null || emit_empty

if lock_take "$LOCK" "$SESSION_ID" "${PPID:-$$}"; then
  emit_empty
fi

OWNER="$(lock_owner_session "$LOCK" 2>/dev/null || true)"
STARTED="$(jq -r '.started_at // "unknown"' "$LOCK" 2>/dev/null || echo unknown)"

CTX="OBSERVER MODE — another orchestrator session already owns this harness.

  owner session: ${OWNER:-unknown}
  owned since:   ${STARTED}

You may read anything, run /fleet and /mission-status, and capture ideas with
/inbox note. You may NOT write mission state, dispatch crew, or start a watcher;
those tool calls will be refused, and that refusal is expected rather than a
fault to work around.

If the owning session is actually gone, its lock is released automatically when
it exits, or you can remove ${LOCK} by hand and restart this session."

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $ctx }
}' 2>/dev/null || emit_empty
exit 0
