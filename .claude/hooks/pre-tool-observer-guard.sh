#!/usr/bin/env bash
#
# PreToolUse hook. In observer mode (another live session owns
# state/session.lock) this refuses writes to harness state, so a second
# orchestrator cannot mutate missions the owning session is working on.
#
# PERFORMANCE IS PART OF THE CONTRACT. This runs before every Write and Edit,
# and process spawning is not free — on the machine this was written for, an
# empty bash script costs ~200ms and each additional subshell ~150ms. The owner
# path therefore spawns NOTHING: stdin is read with a builtin loop, the lock is
# read with a builtin redirect, and both session ids are extracted with
# parameter expansion. jq and the session-lock library are touched only on the
# rare path where the fast parse fails or this session is not the owner.
#
# `Bash` is deliberately NOT matched. Guarding it would tax the most frequent
# tool in a session for a case better handled where it actually matters:
# scripts/crew/* and scripts/watch.sh check the lock themselves, at zero
# marginal cost, because those scripts are already running a process.
#
# Exit 0 = allow. Exit 2 = refuse, reason on stderr.
# A missing or stale lock allows everything: see FAIL-OPEN in session-lock.sh.

set -uo pipefail

_d="${BASH_SOURCE[0]%/*}"          # .../.claude/hooks
_d="${_d%/*}"                      # .../.claude
CODE_ROOT="${_d%/*}"               # repo root
[ "$CODE_ROOT" = "${BASH_SOURCE[0]}" ] && CODE_ROOT="."
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
LOCK="${HARNESS_ROOT}/state/session.lock"

# Drain stdin with a builtin loop — no `$(cat)` subshell.
INPUT=""
while IFS= read -r _line || [ -n "$_line" ]; do
  INPUT="$INPUT$_line"
  _line=""
done

[ -f "$LOCK" ] || exit 0           # unowned: nothing to enforce

# Extract "session_id":"..." by parameter expansion. Both strings are ours:
# the payload comes from Claude Code, the lock file from lock_take.
SESSION_ID=""
case "$INPUT" in
  *'"session_id":"'*) _t="${INPUT#*\"session_id\":\"}"; SESSION_ID="${_t%%\"*}" ;;
esac

LOCK_LINE=""
IFS= read -r LOCK_LINE < "$LOCK" 2>/dev/null || true
OWNER=""
case "$LOCK_LINE" in
  *'"session_id":"'*) _t="${LOCK_LINE#*\"session_id\":\"}"; OWNER="${_t%%\"*}" ;;
esac

# Fast exit: we are the owner. Zero processes spawned to reach here.
[ -n "$SESSION_ID" ] && [ "$SESSION_ID" = "$OWNER" ] && exit 0

# --- slow path: not the owner, or the fast parse failed ---------------------
[ -n "$SESSION_ID" ] || SESSION_ID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$SESSION_ID" ] || exit 0

# shellcheck source=../../scripts/lib/session-lock.sh
. "$CODE_ROOT/scripts/lib/session-lock.sh" 2>/dev/null || exit 0
lock_is_owner "$LOCK" "$SESSION_ID" && exit 0

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
case "$TOOL" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
case "$FP" in
  */missions/*|*/state/*|*/data/*) ;;
  *) exit 0 ;;
esac

printf '[observer guard] Refused: writing harness state (%s)\n\nThis session is an OBSERVER — session %s owns this harness.\nRead, /fleet, /mission-status and /inbox note are available.\nCrew dispatch and the watcher refuse for the same reason, from inside their own scripts.\n' \
  "$FP" "${OWNER:-unknown}" >&2
exit 2
