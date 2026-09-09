#!/usr/bin/env bash
# teardown.sh - land a finished crewmate's work and clean up after it.
#
# Usage: teardown.sh <task> [--abandon]
#
# WRITE-AHEAD INTENT (fm-teardown.sh:9-17). The completion links — the PR URL,
# the branch, the worktree path — live only in the record this is about to
# delete. So the intended transition is written to state/<task>.close-pending
# FIRST. A process killed halfway leaves the next session enough to finish the
# job, and a failed transition keeps its pending record and is retried rather
# than silently dropped.
#
# Refuses while the runner is alive: tearing down a working crewmate destroys a
# worktree that is being written to.
#
# Delivery follows the mode recorded at spawn, never the registry (a task may
# have deviated, on purpose):
#   direct-PR    push the branch, open a PR
#   local-only   guarded fast-forward into the project's default branch
#   no-mistakes  DEGRADED: the gate tool is unverified here, so this pushes and
#                opens a PR and files a blocking decision instead of guessing at
#                an invocation. See docs/verification/crew-spike.md (e).
# `+yolo` is the only posture that merges unattended.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"
# shellcheck source=backend.sh
. "$CODE_ROOT/scripts/crew/backend.sh"

die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

TASK="${1:-}"; ABANDON=0
[ "${2:-}" = "--abandon" ] && ABANDON=1
[ -n "$TASK" ] || die "usage: teardown.sh <task> [--abandon]"
crew_meta_get "$HARNESS_ROOT" "$TASK" task >/dev/null 2>&1 || die "teardown.sh: no such task \"$TASK\"" 1

PID="$(crew_meta_get "$HARNESS_ROOT" "$TASK" runner_pid || true)"
case "$PID" in
  ''|*[!0-9]*) ;;
  *) kill -0 "$PID" 2>/dev/null && die "teardown.sh: $TASK is still running (runner $PID). Let it finish, or stop it first." ;;
esac

MODE="$(crew_meta_get "$HARNESS_ROOT" "$TASK" mode)"
YOLO="$(crew_meta_get "$HARNESS_ROOT" "$TASK" yolo)"
KIND="$(crew_meta_get "$HARNESS_ROOT" "$TASK" kind)"
WT="$(crew_meta_get "$HARNESS_ROOT" "$TASK" worktree)"
BRANCH="$(crew_meta_get "$HARNESS_ROOT" "$TASK" branch)"
PROJECT="$(crew_meta_get "$HARNESS_ROOT" "$TASK" project)"
MISSION="$(crew_meta_get "$HARNESS_ROOT" "$TASK" mission)"
MDIR_STATUS="$HARNESS_ROOT/missions/$MISSION/status.json"
PENDING="$HARNESS_ROOT/state/$TASK.close-pending"

LAST="$(crew_outcome "$HARNESS_ROOT" "$TASK" 2>/dev/null || true)"
if [ "$ABANDON" -eq 0 ] && [ "$LAST" != "done" ]; then
  die "teardown.sh: $TASK last reported \"${LAST:-nothing}\", not done. Use --abandon to discard it deliberately."
fi

PROJ_PATH=""
if [ -d "$WT" ]; then
  PROJ_PATH="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' || true)"
fi

# --- write-ahead intent ------------------------------------------------------
jq -n --arg task "$TASK" --arg mode "$MODE" --arg yolo "$YOLO" --arg wt "$WT" \
      --arg branch "$BRANCH" --arg project "$PROJECT" --arg mission "$MISSION" \
      --arg proj_path "$PROJ_PATH" --arg kind "$KIND" \
      --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson abandon "$([ "$ABANDON" -eq 1 ] && echo true || echo false)" \
  '{task:$task, mode:$mode, yolo:$yolo, worktree:$wt, branch:$branch,
    project:$project, mission:$mission, project_path:$proj_path, kind:$kind,
    abandon:$abandon, opened_at:$at, pr_url:null, landed:false}' > "$PENDING" \
  || die "teardown.sh: could not write the pending-close record; refusing to proceed" 1

backend_kill "$TASK" 2>/dev/null || true

PR_URL=""
land_direct_pr() {
  [ -d "$WT" ] || { printf 'teardown: worktree gone; nothing to push\n' >&2; return 1; }
  git -C "$WT" push -u origin "$BRANCH" >/dev/null 2>&1 || { printf 'teardown: git push failed\n' >&2; return 1; }
  command -v gh >/dev/null 2>&1 || { printf 'teardown: gh not installed; branch pushed, open the PR by hand\n' >&2; return 1; }
  PR_URL="$(gh pr create --head "$BRANCH" --fill --repo "$(git -C "$WT" remote get-url origin 2>/dev/null)" 2>/dev/null || true)"
  [ -n "$PR_URL" ] || PR_URL="$(gh pr view "$BRANCH" --json url -q .url 2>/dev/null || true)"
  [ -n "$PR_URL" ]
}

land_local_only() {
  [ -n "$PROJ_PATH" ] && [ -d "$PROJ_PATH" ] || { printf 'teardown: cannot locate the primary checkout\n' >&2; return 1; }
  local default; default="$(git -C "$PROJ_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  # Fast-forward ONLY. A merge that needs a commit means the default branch moved
  # under the crewmate, and resolving that is the captain's call.
  git -C "$PROJ_PATH" merge --ff-only "$BRANCH" >/dev/null 2>&1 \
    || { printf 'teardown: %s cannot fast-forward onto %s — it moved under the crewmate\n' "$BRANCH" "$default" >&2; return 1; }
}

LANDED=0
if [ "$ABANDON" -eq 1 ]; then
  printf 'Abandoning %s (no delivery).\n' "$TASK"; LANDED=1
elif [ "$KIND" = "scout" ]; then
  printf 'Scout %s: report kept, branch discarded.\n' "$TASK"; LANDED=1
else
  case "$MODE" in
    direct-PR)   land_direct_pr && LANDED=1 ;;
    local-only)  land_local_only && LANDED=1 ;;
    no-mistakes)
      if land_direct_pr; then
        LANDED=1
        "$CODE_ROOT/scripts/hold.sh" open "$MISSION" \
          --question "$TASK is registered no-mistakes, but the gate tool is not verified on this machine. Run the gate by hand on ${PR_URL:-the PR}, or approve merging without it?" \
          --options "run the gate by hand,merge without the gate" \
          --recommend "run the gate by hand — the registered posture asked for it" >/dev/null 2>&1 || true
        printf 'no-mistakes degraded to direct-PR; a decision has been filed (see docs/verification/crew-spike.md).\n' >&2
      fi ;;
  esac
fi

if [ "$LANDED" -eq 0 ]; then
  printf 'teardown.sh: delivery failed for %s. The pending record is kept at %s and will be retried; the worktree is left in place.\n' "$TASK" "$PENDING" >&2
  exit 1
fi

[ -n "$PR_URL" ] && jq --arg u "$PR_URL" '.pr_url = $u' "$PENDING" > "$PENDING.tmp" 2>/dev/null && mv "$PENDING.tmp" "$PENDING"

# --- clean up ----------------------------------------------------------------
if [ -n "$PROJ_PATH" ] && [ -d "$PROJ_PATH" ]; then
  git -C "$PROJ_PATH" worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"
  git -C "$PROJ_PATH" worktree prune >/dev/null 2>&1 || true
  if [ "$MODE" = "local-only" ] || [ "$ABANDON" -eq 1 ] || [ "$KIND" = "scout" ]; then
    git -C "$PROJ_PATH" branch -D "$BRANCH" >/dev/null 2>&1 || true
  fi
else
  rm -rf "$WT" 2>/dev/null || true
fi

# --- fold the crewmate's usage into the mission -----------------------------
# SubagentStop never fires for a crewmate, so nothing else accounts for its
# spend. run.sh writes state/<task>.usage.json from the stream-json result
# event; without this the mission's token block stayed at zero and /fleet
# reported a fleet that had cost nothing.
USAGE="$HARNESS_ROOT/state/$TASK.usage.json"
SFILE="$MDIR_STATUS"
if [ -f "$USAGE" ] && [ -f "$SFILE" ]; then
  if UP="$(jq -s --arg role workers '
        .[0] as $st | .[1] as $u
        | ($st.tokens // {}) as $tk
        | $st
        | .tokens = ($tk
            | .[$role] = {
                input:  (((.[$role].input  // 0)) + ($u.input  // 0)),
                output: (((.[$role].output // 0)) + ($u.output // 0))
              }
          )
        | .cost_usd = (((.cost_usd // 0)) + ($u.cost_usd // 0))
      ' "$SFILE" "$USAGE" 2>/dev/null)" && [ -n "$UP" ]; then
    printf '%s\n' "$UP" > "$SFILE"
  fi
fi

crew_forget "$HARNESS_ROOT" "$TASK"
rm -f "$HARNESS_ROOT/state/$TASK.stream.jsonl" "$HARNESS_ROOT/state/$TASK.stderr" \
      "$HARNESS_ROOT/state/$TASK.window.log" "$USAGE" 2>/dev/null || true
rm -rf "$HARNESS_ROOT/state/$TASK.inbox" 2>/dev/null || true
rm -f "$PENDING"

printf 'Tore down %s%s\n' "$TASK" "${PR_URL:+ — $PR_URL}"
