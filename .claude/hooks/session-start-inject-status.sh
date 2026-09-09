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

# Undrained inbox notes sit above mission state but below open decisions, because they are
# things the captain asked for that nothing has acted on yet.
INBOX_DIR="${HARNESS_ROOT}/data/inbox"
if [ -d "$INBOX_DIR" ]; then
  NOTES=""
  for nf in "$INBOX_DIR"/*.json; do
    [ -f "$nf" ] || continue
    nid="$(basename "$nf" .json)"
    nbody="$(jq -r '.body // ""' "$nf" 2>/dev/null | head -n1 || true)"
    [ -n "$nbody" ] || nbody="(unreadable note — inspect $nf)"
    NOTES="${NOTES}"$'\n'"  ${nid}  ${nbody}"
  done
  if [ -n "$NOTES" ]; then
    CONTEXT="Undrained inbox notes (captured while you were busy; present them, then \`./scripts/inbox.sh drain --ack <id>\`):${NOTES}"$'\n\n'"${CONTEXT}"
  fi
fi

# Crewmates that need attention: blocked, finished, or vanished. A crewmate
# still working is deliberately NOT reported — nothing is required of the
# session, and naming it invites an interruption to "check on it".
CREW_TEXT=""
if . "$CODE_ROOT/scripts/lib/crew.sh" 2>/dev/null; then
  while IFS= read -r ctask; do
    [ -n "$ctask" ] || continue
    clast="$(crew_ledger_last "$HARNESS_ROOT" "$ctask" 2>/dev/null || true)"
    case "$clast" in
      blocked|done|failed)
        CREW_TEXT="${CREW_TEXT}"$'\n'"  ${ctask}: ${clast} — $(crew_ledger_note "$HARNESS_ROOT" "$ctask" 2>/dev/null || true)" ;;
      *)
        cpid="$(crew_meta_get "$HARNESS_ROOT" "$ctask" runner_pid 2>/dev/null || true)"
        case "$cpid" in
          ''|*[!0-9]*) CREW_TEXT="${CREW_TEXT}"$'\n'"  ${ctask}: no runner recorded — reconcile before trusting it" ;;
          *) kill -0 "$cpid" 2>/dev/null || CREW_TEXT="${CREW_TEXT}"$'\n'"  ${ctask}: runner gone with no outcome — SUSPICIOUS, peek before tearing down" ;;
        esac ;;
    esac
  done < <(crew_list "$HARNESS_ROOT" 2>/dev/null)
fi
if [ -n "$CREW_TEXT" ]; then
  CONTEXT="CREWMATES NEEDING ATTENTION (./scripts/crew/reconcile.sh for the full picture):${CREW_TEXT}"$'\n\n'"${CONTEXT}"
fi

# OPEN DECISIONS COME FIRST, ahead of everything. Each block below PREPENDS
# to CONTEXT, so this one runs LAST to end up on top. They are questions the captain
# has already been asked and has not answered; presenting work before them is how
# a session ends up doing something the captain was about to redirect.
HOLDS_TEXT=""
if [ -d "$MISSIONS" ] && . "$CODE_ROOT/scripts/lib/holds.sh" 2>/dev/null; then
  while IFS=$'\t' read -r hm hid hblock hq; do
    [ -n "$hm" ] || continue
    HOLDS_TEXT="${HOLDS_TEXT}"$'\n'"  ${hid} on ${hm} [${hblock}]"$'\n'"      ${hq}"
  done < <(holds_list_all "$MISSIONS" 2>/dev/null)
fi
if [ -n "$HOLDS_TEXT" ]; then
  CONTEXT="OPEN DECISIONS awaiting the captain — present these before starting or resuming work.${HOLDS_TEXT}"$'\n\n'"Answer with: ./scripts/hold.sh answer <mission> <id> \"<answer>\", or use /decide."$'\n\n'"${CONTEXT}"
fi

CONTEXT="${CONTEXT}"$'\n'"Use /fleet for everything in flight, /mission-status to inspect, /mission-resume to continue."

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $ctx
  }
}' 2>/dev/null || emit_empty

exit 0
