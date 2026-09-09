#!/usr/bin/env bash
# backend-fake.sh - records what the tmux adapter would have done.
#
# Exists so the crew suite runs in CI with no tmux, and so a test can assert the
# exact launch command without starting a model. Never starts a process.
# $CREW_FAKE_LOG receives one line per call.

set -uo pipefail
_fake_log() { printf '%s\n' "$*" >> "${CREW_FAKE_LOG:-/dev/null}"; }

backend_open() {
  local task="$1" cwd="$2" log="$3"; shift 3
  _fake_log "open task=$task cwd=$cwd log=$log cmd=$*"
  : > "${CREW_FAKE_LOG:-/dev/null}.alive.$task" 2>/dev/null || true
}
backend_alive()   { [ -f "${CREW_FAKE_LOG:-/dev/null}.alive.$1" ]; }
backend_kill()    { _fake_log "kill task=$1"; rm -f "${CREW_FAKE_LOG:-/dev/null}.alive.$1" 2>/dev/null || true; }
backend_capture() { _fake_log "capture task=$1 lines=${2:-40}"; printf '(fake backend: no pane for %s)\n' "$1"; }
