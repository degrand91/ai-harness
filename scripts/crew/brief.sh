#!/usr/bin/env bash
# brief.sh - scaffold a crewmate brief.
#
# Usage:
#   brief.sh <mission> <task> --intent <file|-> --spec <file|-> --done <file|->
#            --mode <mode> --yolo <on|off> [--model <name>] [--scout]
#
# THE BRIEF IS THE WORKER PERSONA. `.claude/agents/worker.md` cannot load in a
# foreign cwd, so the persona ships as templates/crew-persona.md (passed with
# --append-system-prompt-file) and the task ships here.
#
# INTENT AND SPEC ARE SEPARATE, and that is the point (fm-brief.sh:5-10):
#   ## Captain's intent  the captain's own ask, plus the context needed to read
#                        it. Never build instructions.
#   ## Harness spec      how to build it. Never the captain's intent.
# Splitting them lets a crewmate push back on the HOW without discarding the
# WHY, and lets a SPEC-CLARIFICATION handoff mean something specific.
#
# The rendered brief records `mode=`, which scripts/crew/spawn.sh cross-checks
# against its own flag and REFUSES on mismatch: a crewmate's instructions and
# the recorded delivery contract cannot be allowed to drift apart.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"

usage() { sed -n '2,10{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

# `-` reads stdin; anything else must be READABLE, not necessarily a regular
# file — process substitution hands us /dev/fd/N, which `[ -f ]` rejects.
# `die` inside a command substitution only kills the subshell, so failures are
# returned and checked by the caller instead.
read_arg() {  # <file-or-dash>
  case "$1" in
    -) cat ;;
    *) [ -r "$1" ] || return 1; cat "$1" ;;
  esac
}
read_or_die() {  # <flag> <file-or-dash>
  local out
  out="$(read_arg "$2")" || die "brief.sh: $1: cannot read \"$2\""
  printf '%s' "$out"
}

MISSION="${1:-}"; TASK="${2:-}"; shift 2 2>/dev/null || true
[ -n "$MISSION" ] && [ -n "$TASK" ] || { usage; exit 2; }

INTENT=""; SPEC=""; DONE=""; MODE=""; YOLO="off"; MODEL=""; SCOUT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --intent) INTENT="$(read_or_die --intent "${2:?}")"; shift 2 ;;
    --spec)   SPEC="$(read_or_die --spec "${2:?}")"; shift 2 ;;
    --done)   DONE="$(read_or_die --done "${2:?}")"; shift 2 ;;
    --mode)   MODE="${2:?}"; shift 2 ;;
    --yolo)   YOLO="${2:?}"; shift 2 ;;
    --model)  MODEL="${2:?}"; shift 2 ;;
    --scout)  SCOUT=1; shift ;;
    *) die "brief.sh: unknown option $1" ;;
  esac
done

MDIR="${HARNESS_ROOT}/missions/${MISSION}"
[ -d "$MDIR" ] || die "brief.sh: no mission \"$MISSION\""

case "$MODE" in
  no-mistakes|direct-PR|local-only) ;;
  "") die "brief.sh: --mode is required" ;;
  *) die "brief.sh: unrecognised mode \"$MODE\"" ;;
esac
case "$YOLO" in on|off) ;; *) die "brief.sh: --yolo must be on or off" ;; esac

[ -n "$INTENT" ] || die "brief.sh: refusing a brief with no captain's intent — a crewmate that does not know WHY cannot push back on HOW"
[ "$SCOUT" -eq 1 ] || [ -n "$DONE" ] || die "brief.sh: refusing a ship brief with no definition of done"
[ -n "$SPEC" ] || SPEC="(none — follow the captain's intent and the definition of done)"
[ -n "$MODEL" ] || MODEL="$(jq -r '.models.worker_default // "sonnet"' "$MDIR/status.json" 2>/dev/null || echo sonnet)"
[ -n "$MODEL" ] && [ "$MODEL" != "null" ] || MODEL="sonnet"

OUT="$MDIR/briefs"; mkdir -p "$OUT" || die "brief.sh: cannot write to $OUT"
LEDGER="${HARNESS_ROOT}/state/${TASK}.ledger"
SAY_CMD="${CODE_ROOT}/scripts/crew/say.sh"
HANDOFF="$MDIR/briefs/${TASK}-handoff.md"

TPL="$CODE_ROOT/templates/crew-brief.md"
[ "$SCOUT" -eq 1 ] && [ -f "$CODE_ROOT/templates/crew-brief-scout.md" ] && TPL="$CODE_ROOT/templates/crew-brief-scout.md"
[ -f "$TPL" ] || die "brief.sh: template missing: $TPL"

python3 - "$TPL" "$OUT/${TASK}.md" <<PYEOF || die "brief.sh: could not render the brief"
import sys, pathlib
tpl = pathlib.Path(sys.argv[1]).read_text()
vals = {
    "{TASK_ID}": """${TASK}""",
    "{LEDGER_PATH}": """${LEDGER}""",
    "{SAY_CMD}": """${SAY_CMD}""",
    "{HANDOFF_PATH}": """${HANDOFF}""",
    "{WORKTREE}": "(set at spawn)",
    "{BRANCH}": "(set at spawn)",
    "{CAPTAINS_INTENT}": """${INTENT}""",
    "{HARNESS_SPEC}": """${SPEC}""",
    "{DEFINITION_OF_DONE}": """${DONE}""",
    "{MODE}": """${MODE}""",
    "{YOLO}": """${YOLO}""",
    "{MODEL}": """${MODEL}""",
}
for k, v in vals.items():
    tpl = tpl.replace(k, v)
pathlib.Path(sys.argv[2]).write_text(tpl)
PYEOF

# A leftover placeholder means a section was never filled; spawn refuses those,
# so catch it here where the error is actionable.
if grep -qE '\{[A-Z_]+\}' "$OUT/${TASK}.md"; then
  die "brief.sh: rendered brief still contains placeholders — $(grep -oE '\{[A-Z_]+\}' "$OUT/${TASK}.md" | sort -u | tr '\n' ' ')"
fi

printf '%s\n' "$OUT/${TASK}.md"
