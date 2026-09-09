#!/usr/bin/env bash
# spawn.sh - put a crewmate to work on one brief, in its own worktree.
#
# Usage:
#   spawn.sh <mission> <task> --project <name> --mode <mode> --yolo <on|off>
#            [--model <name>] [--scout]
#
# Order of operations, each step refusing loudly rather than continuing:
#   1. resolve the project and its registered posture
#   2. cross-check the brief's recorded delivery contract against --mode
#   3. create the worktree
#   4. inject the crewmate-side hooks and guard
#   5. resolve the tool allowlist
#   6. record meta, then open a window running scripts/crew/run.sh
#
# TWO SOURCES OF TRUTH MUST AGREE (fm-spawn.sh:10-14). The brief records
# `mode=`; this refuses a mismatch with its own flag. A crewmate's instructions
# and the recorded delivery contract cannot be allowed to drift apart, because
# the brief is what the crewmate obeys and the flag is what the supervisor
# later ships by.
#
# THE SANDBOX IS THREE LAYERS, none of them --dangerously-skip-permissions:
#   the worktree (a crewmate cannot reach the primary checkout),
#   the `-p` allowlist (anything else is absent from its tool list entirely),
#   and the injected PreToolUse guard (fires regardless of permission mode).
# See docs/verification/crew-spike.md (b).

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"

# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"
# shellcheck source=../lib/registry.sh
. "$CODE_ROOT/scripts/lib/registry.sh"
# shellcheck source=backend.sh
. "$CODE_ROOT/scripts/crew/backend.sh"

usage() { sed -n '2,8{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

MISSION="${1:-}"; TASK="${2:-}"; shift 2 2>/dev/null || true
[ -n "$MISSION" ] && [ -n "$TASK" ] || { usage; exit 2; }

PROJECT=""; MODE=""; YOLO=""; MODEL=""; SCOUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="${2:?}"; shift 2 ;;
    --mode)    MODE="${2:?}"; shift 2 ;;
    --yolo)    YOLO="${2:?}"; shift 2 ;;
    --model)   MODEL="${2:?}"; shift 2 ;;
    --scout)   SCOUT=1; shift ;;
    *) die "spawn.sh: unknown option $1" ;;
  esac
done

[ -n "$PROJECT" ] || die "spawn.sh: --project is required"
[ -n "$MODE" ] || die "spawn.sh: --mode is required — a task's delivery is decided at intake, never looked up here"
[ -n "$YOLO" ] || die "spawn.sh: --yolo is required (on|off)"
case "$MODE" in no-mistakes|direct-PR|local-only) ;; *) die "spawn.sh: unrecognised mode \"$MODE\"" ;; esac
case "$YOLO" in on|off) ;; *) die "spawn.sh: --yolo must be on or off" ;; esac

MDIR="$HARNESS_ROOT/missions/$MISSION"
[ -d "$MDIR" ] || die "spawn.sh: no mission \"$MISSION\""
BRIEF="$MDIR/briefs/$TASK.md"
[ -f "$BRIEF" ] || die "spawn.sh: no brief at $BRIEF — run scripts/crew/brief.sh first"

# --- 0. today's spend ---------------------------------------------------------
# A cap is the only thing that stops a runaway before it becomes a bill. It
# REFUSES and FILES A DECISION rather than merely failing: an operator who set a
# cap wants to be asked, not to find work quietly stopped.
# shellcheck source=../lib/spend.sh
. "$CODE_ROOT/scripts/lib/spend.sh"
if spend_over_cap "$HARNESS_ROOT"; then
  _cap="$(spend_cap "$HARNESS_ROOT")"; _today="$(spend_today "$HARNESS_ROOT")"
  "$CODE_ROOT/scripts/hold.sh" open "$MISSION" \
    --question "Today's crew spend is \$$_today, at or over the \$$_cap daily cap. Raise it, or stop for today?" \
    --options "raise the cap,stop for today" \
    --recommend "stop unless this task is time-critical — the cap was set for a reason" >/dev/null 2>&1 || true
  die "spawn.sh: today's spend (\$$_today) has reached the daily cap (\$$_cap). A decision has been filed; answer it with /decide, or raise config/spend-cap-daily."
fi

# --- 0a. is this task already in flight? ------------------------------------
# Checked before the concurrency limit, because "you already spawned this exact
# task" tells the caller far more than "you are at the limit".
if crew_meta_get "$HARNESS_ROOT" "$TASK" task >/dev/null 2>&1; then
  if crew_is_terminal "$HARNESS_ROOT" "$TASK"; then
    die "spawn.sh: $TASK already exists and has finished ($(crew_ledger_last "$HARNESS_ROOT" "$TASK")). Tear it down before respawning."
  fi
  die "spawn.sh: $TASK already exists and is in flight. Steer it (./scripts/crew/send.sh $TASK \"...\") or tear it down."
fi

# --- 0b. the concurrency limit -----------------------------------------------
# protocols/serial-execution.md bans CONCURRENT workers for correctness, and
# that rule survives the crew rewrite untouched. Crew separates "its own
# process" from "at the same time"; only the first is new. The limit ships at 1
# and raising it is a deliberate, separate decision.
MAXC="$(jq -r '.crew.max_concurrent // 1' "$MDIR/status.json" 2>/dev/null || echo 1)"
case "$MAXC" in ''|*[!0-9]*) MAXC=1 ;; esac
LIVE=0
while IFS= read -r _t; do
  [ -n "$_t" ] || continue
  [ "$(crew_meta_get "$HARNESS_ROOT" "$_t" mission 2>/dev/null)" = "$MISSION" ] || continue
  crew_is_terminal "$HARNESS_ROOT" "$_t" && continue
  LIVE=$((LIVE + 1))
done < <(crew_list "$HARNESS_ROOT")
if [ "$LIVE" -ge "$MAXC" ]; then
  die "spawn.sh: $MISSION already has $LIVE crewmate(s) in flight and allows $MAXC. Finish or tear one down; raising the limit is a deliberate change to status.json crew.max_concurrent, and protocols/serial-execution.md explains why it is 1."
fi

# --- 1. the project ----------------------------------------------------------
REGISTRY="$HARNESS_ROOT/data/projects.md"
# REG_YOLO is read to consume the field; the task's yolo comes from --yolo,
# never from the registry — see the deviation note below.
PROJ_PATH=""; REG_MODE=""; REG_YOLO=""
# shellcheck disable=SC2034  # REG_YOLO consumes a field we deliberately ignore
if ! read -r REG_MODE REG_YOLO PROJ_PATH < <(registry_resolve "$REGISTRY" "$PROJECT" 2>/dev/null); then
  die "spawn.sh: project \"$PROJECT\" is not registered — ./scripts/project.sh add $PROJECT <path> --mode <mode>" 2
fi
[ -d "$PROJ_PATH/.git" ] || git -C "$PROJ_PATH" rev-parse --git-dir >/dev/null 2>&1 \
  || die "spawn.sh: $PROJ_PATH is not a git checkout"

# A task may deviate from the registered posture, but never silently.
if [ "$MODE" != "$REG_MODE" ]; then
  printf 'spawn.sh: NOTE — %s is registered [%s] but this task ships %s. Deviation is allowed; record why in the mission log.\n' \
    "$PROJECT" "$REG_MODE" "$MODE" >&2
fi

# --- 2. two sources of truth must agree -------------------------------------
BRIEF_MODE="$(grep -oE 'mode=[a-zA-Z-]+' "$BRIEF" 2>/dev/null | head -n1 | cut -d= -f2 || true)"
if [ -z "$BRIEF_MODE" ]; then
  die "spawn.sh: the brief records no delivery contract — regenerate it with scripts/crew/brief.sh"
fi
[ "$BRIEF_MODE" = "$MODE" ] || die "spawn.sh: brief says mode=$BRIEF_MODE but spawn was told --mode $MODE. Refusing: the crewmate's instructions and the recorded delivery must not drift apart."
if grep -qE '\{[A-Z_]+\}' "$BRIEF"; then
  die "spawn.sh: the brief still contains placeholders: $(grep -oE '\{[A-Z_]+\}' "$BRIEF" | sort -u | tr '\n' ' ')"
fi

# --- 3. the worktree ---------------------------------------------------------
SLUG="$(printf '%s' "$TASK" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
BRANCH="hc/${MISSION}/${SLUG}"
WORKTREE="$HARNESS_ROOT/data/worktrees/$PROJECT/$TASK"
[ -e "$WORKTREE" ] && die "spawn.sh: $WORKTREE already exists — tear the previous task down first"
mkdir -p "$(dirname "$WORKTREE")" || die "spawn.sh: cannot create $(dirname "$WORKTREE")"

DEFAULT_BRANCH="$(git -C "$PROJ_PATH" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
[ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="$(git -C "$PROJ_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
git -C "$PROJ_PATH" worktree add -q -b "$BRANCH" "$WORKTREE" "$DEFAULT_BRANCH" 2>/dev/null \
  || git -C "$PROJ_PATH" worktree add -q -b "$BRANCH" "$WORKTREE" 2>/dev/null \
  || die "spawn.sh: could not create a worktree at $WORKTREE off $DEFAULT_BRANCH"

# --- 4. crewmate-side hooks --------------------------------------------------
# How the harness reaches a process running in someone else's repo without
# touching that repo: the settings live in the WORKTREE, which is disposable.
mkdir -p "$WORKTREE/.claude"
CREWLIB="$CODE_ROOT/scripts/lib/crew.sh"
GUARD="$CODE_ROOT/scripts/crew/guard-pretool.sh"
python3 - "$WORKTREE/.claude/settings.local.json" "$CREWLIB" "$HARNESS_ROOT" "$TASK" "$GUARD" "$WORKTREE" <<'PY'
import json, sys
out, crewlib, home, task, guard, wt = sys.argv[1:7]
def hook(verb):
    return {"hooks": [{"type": "command",
                       "command": f'{crewlib!r} append {home!r} {task!r} {verb} 2>/dev/null || true'.replace("'", '"')}]}
json.dump({
    "hooks": {
        "UserPromptSubmit": [hook("busy")],
        "Stop":             [hook("idle")],
        "SessionEnd":       [hook("exited")],
        "PreToolUse":       [{"matcher": "Bash",
                              "hooks": [{"type": "command",
                                         "command": f'"{guard}" "{wt}"'}]}],
    }
}, open(out, "w"), indent=2)
PY

# --- 5. the tool allowlist ---------------------------------------------------
# Claude Code's pattern syntax is Bash(<prefix>:*) — a COLON, not a space. A
# registry entry is written the way a human says it ("bun *"), so it is
# normalised here rather than making the operator learn the syntax.
#
# Built as a JSON array because patterns contain spaces: joining on spaces and
# splitting later broke every multi-word pattern, so the first real crewmate
# could not commit or run its own test.
PROJ_ALLOW_RAW="$(registry_allow "$REGISTRY" "$PROJECT" 2>/dev/null || true)"
SAY="$CODE_ROOT/scripts/crew/say.sh"
LEDGER_PATH="$HARNESS_ROOT/state/$TASK.ledger"

# An array, not an interpolated string: building argv by string concatenation
# is the exact class of bug this file already shipped once.
ALLOW_ARGS=(--say "$SAY" --project-allow "$PROJ_ALLOW_RAW")
[ "$SCOUT" -eq 1 ] && ALLOW_ARGS+=(--scout)
ALLOW_JSON="$("$CODE_ROOT/scripts/crew/allowlist.py" "${ALLOW_ARGS[@]}")" \
  || die "spawn.sh: could not build the tool allowlist"
DENY_JSON='["WebFetch","WebSearch","Agent","NotebookEdit"]'

# --- 6. record, then launch --------------------------------------------------
[ -n "$MODEL" ] || MODEL="$(grep -oE 'model=[A-Za-z0-9._-]+' "$BRIEF" | head -n1 | cut -d= -f2 || true)"
[ -n "$MODEL" ] || MODEL="sonnet"

crew_meta_write "$HARNESS_ROOT" "$TASK" \
  project="$PROJECT" mission="$MISSION" feature="$TASK" \
  worktree="$WORKTREE" branch="$BRANCH" brief="$BRIEF" \
  mode="$MODE" yolo="$YOLO" model="$MODEL" \
  say_cmd="$SAY" ledger="$LEDGER_PATH" \
  kind="$([ "$SCOUT" -eq 1 ] && echo scout || echo ship)" \
  || die "spawn.sh: could not record state/$TASK.meta"

crew_meta_set_json "$HARNESS_ROOT" "$TASK" allow_tools "$ALLOW_JSON" \
  || die "spawn.sh: could not record the tool allowlist"
crew_meta_set_json "$HARNESS_ROOT" "$TASK" deny_tools "$DENY_JSON" \
  || die "spawn.sh: could not record the denied tools"

crew_ledger_append "$HARNESS_ROOT" "$TASK" started "worktree $WORKTREE on $BRANCH"

LOG="$HARNESS_ROOT/state/$TASK.window.log"
if ! backend_open "$TASK" "$WORKTREE" "$LOG" "$CODE_ROOT/scripts/crew/run.sh" "$HARNESS_ROOT" "$TASK"; then
  crew_ledger_append "$HARNESS_ROOT" "$TASK" failed "could not open a session window"
  die "spawn.sh: could not open a window for $TASK (backend: ${HARNESS_CREW_BACKEND:-tmux})" 1
fi

printf 'Spawned %s on %s [%s yolo=%s model=%s]\n  worktree: %s\n  branch:   %s\n' \
  "$TASK" "$PROJECT" "$MODE" "$YOLO" "$MODEL" "$WORKTREE" "$BRANCH"
