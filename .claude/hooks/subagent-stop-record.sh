#!/usr/bin/env bash
#
# SubagentStop hook. Records subagent timing + agent type to the most-recent
# mission's log.md. Helps the post-mortem aggregate cost & tokens by role.
#
# Input: JSON on stdin with hook_event_name=SubagentStop and (depending on
# Claude Code version) an agent_type field.

set -euo pipefail

INPUT="$(cat)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // .matcher // "subagent"' 2>/dev/null)"

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-/Users/stefanodegrandis/projects/ai/harness}"
MISSIONS="${HARNESS_ROOT}/missions"
[ ! -d "$MISSIONS" ] && exit 0

LATEST="$(ls -t "$MISSIONS" 2>/dev/null | grep -v '^\.gitkeep$' | head -n1 || true)"
[ -z "$LATEST" ] && exit 0

LOG="$MISSIONS/$LATEST/log.md"
[ ! -f "$LOG" ] && exit 0

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '[%s] subagent stopped — type=%s\n' "$NOW" "$AGENT_TYPE" >> "$LOG"

exit 0
