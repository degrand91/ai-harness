#!/usr/bin/env bash
#
# SessionStart hook. Injects a bounded summary of every ACTIVE mission so the
# Orchestrator resumes with the fleet in view instead of having to ask.
#
# This previously took `ls -t | head -n1` — one mission, the most recently
# touched — so with more than one mission in flight the others were invisible on
# resume. In this repo that hid three of four active missions. It now iterates
# all of them through scripts/lib/status-read.sh, newest first, and includes
# missions it cannot classify: a mission the tooling does not understand is
# exactly the one a human should be told about.
#
# Output: JSON on stdout (hookSpecificOutput.additionalContext). ALWAYS exit 0
# and ALWAYS valid JSON — a SessionStart hook that crashes or emits garbage
# degrades every turn that follows it.
#
# Bounds (Phase 5.2 replaces these constants with an accounted token budget):
#   HARNESS_SESSION_MAX_MISSIONS   default 3
#   HARNESS_SESSION_MAX_LOG_LINES  default 5

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
MISSIONS="${HARNESS_ROOT}/missions"
MAX_MISSIONS="${HARNESS_SESSION_MAX_MISSIONS:-3}"
MAX_LOG_LINES="${HARNESS_SESSION_MAX_LOG_LINES:-5}"

cat > /dev/null   # discard stdin

emit_empty() { printf '{}\n'; exit 0; }

# shellcheck source=../../scripts/lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh" 2>/dev/null || emit_empty
[ -d "$MISSIONS" ] || emit_empty

ACTIVE=()
while IFS= read -r m; do
  [ -n "$m" ] && ACTIVE+=("$m")
done < <(status_active_missions "$MISSIONS" 2>/dev/null)

[ "${#ACTIVE[@]}" -eq 0 ] && emit_empty

TOTAL="${#ACTIVE[@]}"
SHOWN=0
CONTEXT="Active missions: ${TOTAL}"
[ "$TOTAL" -gt "$MAX_MISSIONS" ] && CONTEXT="${CONTEXT} (showing newest ${MAX_MISSIONS})"
CONTEXT="${CONTEXT}"$'\n'

for id in "${ACTIVE[@]}"; do
  [ "$SHOWN" -ge "$MAX_MISSIONS" ] && break
  SHOWN=$((SHOWN + 1))
  dir="$MISSIONS/$id"
  sf="$dir/status.json"

  state="$(status_state "$sf" 2>/dev/null || true)"
  [ -z "$state" ] && state="unknown"

  if [ "$state" = "unknown" ]; then
    CONTEXT="${CONTEXT}"$'\n'"  id: ${id}"$'\n'"  state: unknown — status.json is malformed or uses an unrecognised vocabulary; repair it before relying on this mission"$'\n'
    continue
  fi

  current="$(jq -r '.current_feature // "—"' "$sf" 2>/dev/null || printf '—')"
  nfeat="$(jq -r '(.features // []) | length' "$sf" 2>/dev/null || printf '?')"
  title="$(status_title "$dir" 2>/dev/null || printf '%s' "$id")"

  CONTEXT="${CONTEXT}"$'\n'"  id: ${id}"
  [ "$title" != "$id" ] && CONTEXT="${CONTEXT}"$'\n'"  title: ${title}"
  CONTEXT="${CONTEXT}"$'\n'"  state: ${state}"$'\n'"  current_feature: ${current}"$'\n'"  features in plan: ${nfeat}"

  if [ -f "$dir/log.md" ]; then
    tail_lines="$(tail -n "$MAX_LOG_LINES" "$dir/log.md" 2>/dev/null || true)"
    if [ -n "$tail_lines" ]; then
      CONTEXT="${CONTEXT}"$'\n'"  recent log:"
      while IFS= read -r line; do
        CONTEXT="${CONTEXT}"$'\n'"    ${line}"
      done <<<"$tail_lines"
    fi
  fi
  CONTEXT="${CONTEXT}"$'\n'
done

CONTEXT="${CONTEXT}"$'\n'"Use /mission-status to inspect, /mission-resume to continue."

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}' 2>/dev/null || emit_empty

exit 0
