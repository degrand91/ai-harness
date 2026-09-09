#!/usr/bin/env bash
# backend-tmux.sh - the tmux session-provider adapter.
#
# One window per crewmate, named hc-<task>, in the tmux session named by
# HARNESS_TMUX_SESSION (default "harness"). The window runs scripts/crew/run.sh,
# so Ctrl-C in the window reaches the process owner and the window outlives the
# process — the last screen stays readable after a crewmate exits.

set -uo pipefail
_TMUX_SESSION="${HARNESS_TMUX_SESSION:-harness}"
_win() { printf '%s:hc-%s' "$_TMUX_SESSION" "$1"; }

_tmux_ensure_session() {
  tmux has-session -t "$_TMUX_SESSION" 2>/dev/null && return 0
  tmux new-session -d -s "$_TMUX_SESSION" -n harness 2>/dev/null
}

backend_open() {
  local task="$1" cwd="$2" log="$3"; shift 3
  command -v tmux >/dev/null 2>&1 || { printf 'crew: tmux is not installed\n' >&2; return 1; }
  _tmux_ensure_session || { printf 'crew: could not create tmux session %s\n' "$_TMUX_SESSION" >&2; return 1; }
  # `remain-on-exit` keeps the last screen after the process ends, which is the
  # difference between diagnosing a failed crewmate and guessing about it.
  tmux new-window -d -t "$_TMUX_SESSION" -n "hc-$task" -c "$cwd" \
    "$* 2>&1 | tee -a $(printf '%q' "$log")" 2>/dev/null || return 1
  tmux set-window-option -t "$(_win "$task")" remain-on-exit on >/dev/null 2>&1 || true
}
backend_alive()   { tmux list-windows -t "$_TMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -qx "hc-$1"; }
backend_kill()    { tmux kill-window -t "$(_win "$1")" 2>/dev/null || true; }
backend_capture() { tmux capture-pane -p -t "$(_win "$1")" 2>/dev/null | tail -n "${2:-40}"; }
