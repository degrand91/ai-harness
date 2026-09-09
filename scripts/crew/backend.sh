#!/usr/bin/env bash
# backend.sh - selects the session-provider adapter and sources it.
#
# The backend is the VIEWER, not the transport. A crewmate is a headless
# `claude -p` process owned by scripts/crew/run.sh; the backend only gives that
# process a window a human can watch and interrupt. Steering goes through the
# inbox + SIGUSR1 path in send.sh, never through keystrokes into a pane.
#
# HARNESS_CREW_BACKEND=tmux (default) | fake
#   fake records every call to $CREW_FAKE_LOG and starts nothing, so the whole
#   crew suite runs in CI with no tmux installed.
#
# Adapter contract:
#   backend_open <task> <cwd> <logfile> <cmd...>   start cmd in a watchable window
#   backend_alive <task>                           0 = the window exists
#   backend_kill <task>                            best effort, never fails loudly
#   backend_capture <task> <lines>                 bounded tail of what is on screen

set -uo pipefail
_BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "${HARNESS_CREW_BACKEND:-tmux}" in
  fake) . "$_BACKEND_DIR/backend-fake.sh" ;;
  tmux) . "$_BACKEND_DIR/backend-tmux.sh" ;;
  *) printf 'crew: unknown backend "%s"\n' "${HARNESS_CREW_BACKEND}" >&2; return 2 2>/dev/null || exit 2 ;;
esac
