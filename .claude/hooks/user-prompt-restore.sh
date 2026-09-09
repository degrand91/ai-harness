#!/usr/bin/env bash
#
# UserPromptSubmit hook. Two jobs, both cheap:
#
#   1. If a compaction just happened, re-inject what .claude/hooks/pre-compact-snapshot.sh
#      saved — open decisions and missions in flight — then delete the file so it
#      is injected exactly once.
#   2. Clear the watcher's auto-continuation epoch. A real message from the
#      captain means the loop is attended again, so Phase 4's continuation
#      budget resets. Writing the reset here rather than in the watcher keeps
#      "the captain spoke" in one place.
#
# Always exit 0. Emits JSON only when there is something to say.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
STATE="${HARNESS_ROOT}/state"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"

# (2) The captain spoke: the loop is attended.
rm -f "$STATE/watch-epoch" 2>/dev/null || true

# (1) Restore anything a compaction dropped.
[ -n "$SESSION_ID" ] || exit 0
CARRY="$STATE/precompact-${SESSION_ID}.md"
[ -f "$CARRY" ] || exit 0

BODY="$(cat "$CARRY" 2>/dev/null || true)"
rm -f "$CARRY" 2>/dev/null || true
[ -n "$BODY" ] || exit 0

jq -n --arg ctx "$BODY" '{
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: $ctx }
}' 2>/dev/null || true
exit 0
