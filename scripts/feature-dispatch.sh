#!/usr/bin/env bash
# feature-dispatch.sh - put one feature into execution.
#
# Usage:
#   feature-dispatch.sh <mission> <feature-id> [--intent <file|->] [--spec <file|->]
#                       [--done <file|->] [--model <name>] [--dry-run]
#
# THE MISSING LINK. Phase 3 built the whole crew lifecycle and nothing called
# it: no orchestrator surface mentioned spawn.sh, and mission-start still
# described in-process workers, so a crewmate had only ever been launched by
# hand. This is what the feature loop calls, and it is the single owner of
# "which execution model does this feature use, and what happens next".
#
# TWO EXECUTION MODELS, ONE DECISION POINT
#
#   crew      the feature runs as a headless process in its own worktree.
#             Requires the mission's target_repo to be a REGISTERED project:
#             registration is the operator's explicit act, and the crew needs
#             the delivery posture that comes with it.
#   subagent  the feature runs as an in-process Agent call. The fallback when
#             the project is not registered, and still the only path a model
#             can drive on its own — bash cannot spawn a subagent.
#
# Recorded at intake as `execution` in status.json, so a mission never changes
# model half way through. This script honours that field and never overrides it.
#
# For `crew` it does the whole job: brief, spawn, and mark the feature
# in_progress. For `subagent` it prints the spawn specification the orchestrator
# must hand to the Agent tool, because bash cannot do that part.
#
# Exit: 0 dispatched (or spec printed) · 2 refused

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"

# shellcheck source=lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh"
# shellcheck source=lib/registry.sh
. "$CODE_ROOT/scripts/lib/registry.sh"
# shellcheck source=lib/holds.sh
. "$CODE_ROOT/scripts/lib/holds.sh"
# shellcheck source=lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"

usage() { sed -n '2,8{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

MISSION="${1:-}"; FEATURE="${2:-}"; shift 2 2>/dev/null || true
[ -n "$MISSION" ] && [ -n "$FEATURE" ] || { usage; exit 2; }

INTENT=""; SPEC=""; DONE=""; MODEL=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --intent) INTENT="${2:?}"; shift 2 ;;
    --spec)   SPEC="${2:?}"; shift 2 ;;
    --done)   DONE="${2:?}"; shift 2 ;;
    --model)  MODEL="${2:?}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) die "feature-dispatch: unknown option $1" ;;
  esac
done

MDIR="$HARNESS_ROOT/missions/$MISSION"
SFILE="$MDIR/status.json"
[ -f "$SFILE" ] || die "feature-dispatch: no mission \"$MISSION\""

STATE="$(status_state "$SFILE" 2>/dev/null || true)"
case "$STATE" in
  executing|feature_loop) ;;
  "" |unknown) die "feature-dispatch: $MISSION has no readable state" ;;
  *) die "feature-dispatch: $MISSION is $STATE, not executing. Approve it, or /resume it." ;;
esac

# A mission blocked on the captain does not dispatch more work.
if [ "$(holds_count_blocking "$MDIR" 2>/dev/null || echo 0)" -gt 0 ]; then
  die "feature-dispatch: $MISSION has an unanswered blocking decision. Answer it first (/decide)."
fi

# The feature must exist and be pending.
FSTATE="$(jq -r --arg f "$FEATURE" '[.features[]? | select(.id == $f)] | .[0].state // ""' "$SFILE" 2>/dev/null || true)"
[ -n "$FSTATE" ] || die "feature-dispatch: $MISSION has no feature \"$FEATURE\""
case "$FSTATE" in
  pending) ;;
  in_progress) die "feature-dispatch: $FEATURE is already in progress" ;;
  *) die "feature-dispatch: $FEATURE is $FSTATE, not pending" ;;
esac

# --- which execution model? --------------------------------------------------
EXEC="$(jq -r '.execution // ""' "$SFILE" 2>/dev/null || true)"
TARGET="$(jq -r '.target_repo // ""' "$SFILE" 2>/dev/null || true)"
REGISTRY="$HARNESS_ROOT/data/projects.md"
PROJECT=""
[ -n "$TARGET" ] && PROJECT="$(registry_by_path "$REGISTRY" "$TARGET" 2>/dev/null || true)"

if [ -z "$EXEC" ]; then
  # Not recorded at intake (a mission written before `execution` existed).
  # Resolve once, record it, and never re-decide: a mission that changes
  # execution model half way through is a mission nobody can reason about.
  if [ -n "$PROJECT" ]; then EXEC=crew; else EXEC=subagent; fi
  if [ "$DRY" -eq 0 ]; then
    tmp="$(mktemp)"; jq --arg e "$EXEC" '.execution = $e' "$SFILE" > "$tmp" 2>/dev/null && mv "$tmp" "$SFILE" || rm -f "$tmp"
  fi
fi

case "$EXEC" in
  crew)
    [ -n "$PROJECT" ] || die "feature-dispatch: $MISSION is execution=crew but its target_repo is not a registered project.
Register it (./scripts/project.sh add <name> $TARGET --mode <mode>), or set execution=\"subagent\"."
    ;;
  subagent) ;;
  *) die "feature-dispatch: unrecognised execution model \"$EXEC\" (crew|subagent)" ;;
esac

# --- subagent: bash cannot spawn one, so hand back the specification ---------
if [ "$EXEC" = "subagent" ]; then
  WMODEL="$MODEL"
  [ -n "$WMODEL" ] || WMODEL="$(jq -r '.models.worker_default // "sonnet"' "$SFILE" 2>/dev/null || echo sonnet)"
  cat <<SPEC
execution: subagent

Spawn the worker yourself with the Agent tool — bash cannot:

  subagent_type: "worker"
  model:         "$WMODEL"
  description:   "Worker — $FEATURE"

Give it the feature spec at missions/$MISSION/features/*/spec.md and the
contract slice. Then set the feature to in_progress in status.json.

(This mission is not using crew because $([ -n "$TARGET" ] && echo "$TARGET is not a registered project" || echo "it has no target_repo").
 Register the project to run features as crewmates instead.)
SPEC
  exit 0
fi

# --- crew: do the whole job --------------------------------------------------
read -r RMODE _RYOLO _RPATH < <(registry_resolve "$REGISTRY" "$PROJECT") \
  || die "feature-dispatch: could not resolve project \"$PROJECT\""

# The task's delivery is decided here, at intake, and passed explicitly. The
# registry is the standing posture, not this task's answer.
MODE="$RMODE"
YOLO="$(jq -r '.delivery.yolo // "off"' "$SFILE" 2>/dev/null || echo off)"
case "$YOLO" in on|off) ;; *) YOLO=off ;; esac
[ -n "$MODEL" ] || MODEL="$(jq -r '.models.worker_default // "sonnet"' "$SFILE" 2>/dev/null || echo sonnet)"

if [ "$DRY" -eq 1 ]; then
  printf 'execution: crew\nproject: %s\nmode: %s\nyolo: %s\nmodel: %s\nfeature: %s\n' \
    "$PROJECT" "$MODE" "$YOLO" "$MODEL" "$FEATURE"
  exit 0
fi

[ -n "$INTENT" ] || die "feature-dispatch: --intent is required for a crew dispatch.
A crewmate that does not know WHY cannot push back on HOW."
[ -n "$DONE" ] || die "feature-dispatch: --done is required — the definition of done is the brief's contract slice."

BRIEF_ARGS=("$MISSION" "$FEATURE" --intent "$INTENT" --done "$DONE" --mode "$MODE" --yolo "$YOLO" --model "$MODEL")
[ -n "$SPEC" ] && BRIEF_ARGS+=(--spec "$SPEC")
"$CODE_ROOT/scripts/crew/brief.sh" "${BRIEF_ARGS[@]}" >/dev/null \
  || die "feature-dispatch: could not render the brief"

"$CODE_ROOT/scripts/crew/spawn.sh" "$MISSION" "$FEATURE" \
  --project "$PROJECT" --mode "$MODE" --yolo "$YOLO" --model "$MODEL" \
  || die "feature-dispatch: spawn refused; the brief is written and nothing was launched" 2

# Only now is the feature in progress: recording it before the spawn succeeded
# would leave a feature that looks dispatched with nothing running.
tmp="$(mktemp)"
if jq --arg f "$FEATURE" '(.features[] | select(.id == $f) | .state) = "in_progress" | .current_feature = $f' \
     "$SFILE" > "$tmp" 2>/dev/null; then mv "$tmp" "$SFILE"; else rm -f "$tmp"; fi
printf '[%s] dispatched %s as crew on %s (%s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FEATURE" "$PROJECT" "$MODE" >> "$MDIR/log.md"

printf 'Dispatched %s as a crewmate on %s [%s].\nWatch it: ./scripts/crew/peek.sh %s\n' \
  "$FEATURE" "$PROJECT" "$MODE" "$FEATURE"
