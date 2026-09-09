#!/usr/bin/env bash
#
# PreCompact hook. Writes the facts a compaction must not erase to disk, so the
# next turn can be reminded of them.
#
# Context compaction is the second way a promised answer gets lost, after a
# restart. SessionStart already reconciles open decisions from disk; this covers
# the case where the session never restarts but its memory of the question is
# summarised away mid-flight.
#
# Writes state/precompact-<session>.md. .claude/hooks/user-prompt-restore.sh
# injects it once on the next prompt and deletes it.
#
# Always exit 0 and never write stdout: a hook that fails here must not also
# break the compaction.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
MISSIONS="${HARNESS_ROOT}/missions"
STATE="${HARNESS_ROOT}/state"

INPUT="$(cat 2>/dev/null || true)"
SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || SESSION_ID="unknown"

[ -d "$MISSIONS" ] || exit 0
mkdir -p "$STATE" 2>/dev/null || exit 0

# shellcheck source=../../scripts/lib/holds.sh
. "$CODE_ROOT/scripts/lib/holds.sh" 2>/dev/null || exit 0
# shellcheck source=../../scripts/lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh" 2>/dev/null || exit 0

OUT="$STATE/precompact-${SESSION_ID}.md"
TMP="$(mktemp "${OUT}.XXXXXX")" 2>/dev/null || exit 0

{
  printf '# Carried across a context compaction\n\n'
  printf 'Written at %s. This is state the summary may have dropped.\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  had_holds=0
  while IFS=$'\t' read -r m id blocking q; do
    [ -n "$m" ] || continue
    if [ "$had_holds" -eq 0 ]; then printf '## Open decisions (unanswered)\n\n'; had_holds=1; fi
    printf -- '- %s on %s [%s]: %s\n' "$id" "$m" "$blocking" "$q"
  done < <(holds_list_all "$MISSIONS" 2>/dev/null)
  [ "$had_holds" -eq 1 ] && printf '\n'

  had_missions=0
  while IFS= read -r mid; do
    [ -n "$mid" ] || continue
    if [ "$had_missions" -eq 0 ]; then printf '## Missions in flight\n\n'; had_missions=1; fi
    st="$(status_state "$MISSIONS/$mid/status.json" 2>/dev/null || echo unknown)"
    cf="$(jq -r '.current_feature // "-"' "$MISSIONS/$mid/status.json" 2>/dev/null || echo -)"
    printf -- '- %s: %s (current: %s)\n' "$mid" "$st" "$cf"
    if [ -f "$MISSIONS/$mid/log.md" ]; then
      tail -n 3 "$MISSIONS/$mid/log.md" 2>/dev/null | sed 's/^/    /'
    fi
  done < <(status_active_missions "$MISSIONS" 2>/dev/null | head -n 3)
} > "$TMP" 2>/dev/null

mv "$TMP" "$OUT" 2>/dev/null || rm -f "$TMP"
exit 0
