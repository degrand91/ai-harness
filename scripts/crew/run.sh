#!/usr/bin/env bash
# run.sh - owns one crewmate's process for its whole life.
#
# Usage: run.sh <harness-home> <task>
#   Everything else comes from state/<task>.meta, written by spawn.sh.
#
# ONE SCRIPT OWNS THE PROCESS, so steer, exit and resume are one loop rather
# than three scripts guessing at each other:
#
#   launch -> wait
#     exit 0, ledger ends done:            -> return 0
#     exit 0, ledger ends blocked:         -> leave the window open, return 3
#     SIGUSR1 (a steer arrived)            -> SIGINT the child, drain the inbox,
#                                             relaunch with --resume, continue
#     any other exit                       -> write failed:, return 1
#
# The interrupt-and-resume path is verified in docs/verification/crew-spike.md:
# SIGINT to a `-p` run, then `claude --resume <id> -p "<steer>"`, keeps the same
# session id and obeys the steer instead of continuing the interrupted work.
#
# THE PROMPT GOES ON STDIN, never as a positional argument: --allowed-tools and
# --disallowed-tools are variadic and silently swallow a trailing prompt (same
# doc). That failure reports "input must be provided through stdin", which names
# the symptom and not the cause.

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOME_DIR="${1:?run.sh: harness home required}"
TASK="${2:?run.sh: task id required}"

# shellcheck source=../lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"

STATE="$HOME_DIR/state"
INBOX="$STATE/$TASK.inbox"
STREAM="$STATE/$TASK.stream.jsonl"
USAGE="$STATE/$TASK.usage.json"
mkdir -p "$INBOX" "$STATE"

meta() { crew_meta_get "$HOME_DIR" "$TASK" "$1" 2>/dev/null; }

# Record our own pid so send.sh can signal us. This is the only process that may
# be signalled for this task; the claude child is ours to interrupt, not theirs.
crew_meta_set "$HOME_DIR" "$TASK" runner_pid "$$" 2>/dev/null || true
WORKTREE="$(meta worktree)"; BRIEF="$(meta brief)"; MODEL="$(meta model)"
# Tool patterns CONTAIN SPACES ("Bash(git add:*)"), so they are stored in the
# meta as a JSON array and read one per line. Space-splitting them turned
# "Bash(git add:*)" into two argv entries that matched nothing, and the first
# real crewmate could not commit, run its own test, or report progress.
ALLOW_ARR=(); DENY_ARR=()
while IFS= read -r _p; do [ -n "$_p" ] && ALLOW_ARR+=("$_p"); done < <(jq -r '(.allow_tools // []) | .[]' "$STATE/$TASK.meta" 2>/dev/null)
while IFS= read -r _p; do [ -n "$_p" ] && DENY_ARR+=("$_p"); done < <(jq -r '(.deny_tools // []) | .[]' "$STATE/$TASK.meta" 2>/dev/null)
[ -n "$WORKTREE" ] && [ -d "$WORKTREE" ] || { crew_ledger_append "$HOME_DIR" "$TASK" failed "worktree missing"; exit 1; }
[ -n "$BRIEF" ] && [ -f "$BRIEF" ] || { crew_ledger_append "$HOME_DIR" "$TASK" failed "brief missing"; exit 1; }

CHILD=""
STEER_PENDING=0
on_steer() { STEER_PENDING=1; [ -n "$CHILD" ] && kill -INT "$CHILD" 2>/dev/null || true; }
trap on_steer USR1
trap '[ -n "$CHILD" ] && kill -TERM "$CHILD" 2>/dev/null; exit 143' TERM INT

drain_inbox() {
  local f out=""
  for f in "$INBOX"/*.md; do
    [ -f "$f" ] || continue
    out="${out}$(cat "$f")"$'\n'
    rm -f "$f"
  done
  printf '%s' "$out"
}

# Pull session_id and the result event out of the stream we just tee'd.
absorb_stream() {
  [ -f "$STREAM" ] || return 0
  local sid
  sid="$(python3 - "$STREAM" <<'PY' 2>/dev/null || true
import json, sys
sid = None
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except Exception: continue
    if o.get("session_id"): sid = o["session_id"]
print(sid or "")
PY
)"
  [ -n "$sid" ] && crew_meta_set "$HOME_DIR" "$TASK" session_id "$sid"
  python3 - "$STREAM" "$USAGE" <<'PY' 2>/dev/null || true
import json, sys
res = None
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line: continue
    try: o = json.loads(line)
    except Exception: continue
    if o.get("type") == "result": res = o
if res:
    u = res.get("usage") or {}
    json.dump({
        "input": u.get("input_tokens", 0),
        "output": u.get("output_tokens", 0),
        "cache_read": u.get("cache_read_input_tokens", 0),
        "cost_usd": res.get("total_cost_usd", 0),
        "num_turns": res.get("num_turns", 0),
        "is_error": res.get("is_error", False),
    }, open(sys.argv[2], "w"))
PY
}

launch() {  # <prompt>
  local prompt="$1" sid; sid="$(meta session_id)"
  local cmd=(claude -p --output-format stream-json --verbose)
  [ -n "$MODEL" ] && cmd+=(--model "$MODEL")
  [ -n "$sid" ] && cmd+=(--resume "$sid")
  cmd+=(--append-system-prompt-file "$CODE_ROOT/templates/crew-persona.md")
  # Variadic flags go LAST, and the prompt goes on stdin.
  [ "${#ALLOW_ARR[@]}" -gt 0 ] && cmd+=(--allowed-tools "${ALLOW_ARR[@]}")
  [ "${#DENY_ARR[@]}" -gt 0 ]  && cmd+=(--disallowed-tools "${DENY_ARR[@]}")

  # The stream goes through render.sh: raw JSON to $STREAM for parsing, a
  # readable line to stdout so the backend window shows the crewmate working.
  # Without this the window the operator is meant to watch was empty.
  printf '%s' "$prompt" \
    | ( cd "$WORKTREE" && "${cmd[@]}" ) 2>>"$STATE/$TASK.stderr" \
    | "$CODE_ROOT/scripts/crew/render.py" "$STREAM" &
  CHILD=$!
  wait "$CHILD"; local rc=$?
  CHILD=""
  return "$rc"
}

PROMPT="Read the brief at $BRIEF and begin. Follow its Protocol section exactly."
ATTEMPTS=0
MAX_STEERS="${HARNESS_CREW_MAX_STEERS:-20}"

while :; do
  launch "$PROMPT"; RC=$?
  absorb_stream

  if [ "$STEER_PENDING" -eq 1 ]; then
    STEER_PENDING=0
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "$ATTEMPTS" -gt "$MAX_STEERS" ]; then
      crew_ledger_append "$HOME_DIR" "$TASK" failed "steer limit ($MAX_STEERS) reached"
      exit 1
    fi
    STEERS="$(drain_inbox)"
    [ -n "$STEERS" ] || STEERS="(interrupted with no message; continue)"
    crew_ledger_append "$HOME_DIR" "$TASK" progress "steered"
    PROMPT="The captain sent a steer:"$'\n\n'"$STEERS"$'\n\n'"Take it into account and continue."
    continue
  fi

  # The OUTCOME, not the last line: Stop and SessionEnd hooks append after it.
  LAST="$(crew_outcome "$HOME_DIR" "$TASK" 2>/dev/null || true)"
  case "$LAST" in
    done)    exit 0 ;;
    blocked) printf '\ncrewmate %s is blocked: %s\nattach with: ./scripts/crew/attach.sh %s\n' \
               "$TASK" "$(crew_outcome_note "$HOME_DIR" "$TASK")" "$TASK"; exit 3 ;;
    failed)  exit 1 ;;
  esac

  # The process ended without claiming an outcome. That is a failure, and the
  # supervisor must be told rather than left waiting on a ledger that never moves.
  if [ "$RC" -ne 0 ]; then
    crew_ledger_append "$HOME_DIR" "$TASK" failed "process exited $RC without a terminal ledger line"
  else
    crew_ledger_append "$HOME_DIR" "$TASK" failed "process ended without writing done: or failed:"
  fi
  exit 1
done
