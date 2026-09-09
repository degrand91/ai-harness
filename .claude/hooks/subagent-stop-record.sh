#!/usr/bin/env bash
#
# SubagentStop hook. Records subagent timing + agent type to the most-recent
# mission's log.md. Also extracts token usage from the SubagentStop payload
# and aggregates it into the active mission's status.json tokens block.
#
# Input: JSON on stdin with hook_event_name=SubagentStop and (depending on
# Claude Code version) an agent_type field plus optional usage/token fields.

# NOT `set -e`. §0.5 fixed this crash class in three hooks and missed this one:
# a payload jq cannot parse exited the hook non-zero instead of doing nothing.
# Recording a token count is best-effort; the subagent it observes has already
# finished, and there is nothing useful to fail about.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"
AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // .matcher // "subagent"' 2>/dev/null || echo subagent)"
[ -n "$AGENT_TYPE" ] || AGENT_TYPE=subagent

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-.}"
MISSIONS="${HARNESS_ROOT}/missions"
[ ! -d "$MISSIONS" ] && exit 0

# shellcheck disable=SC2012  # mtime ordering; mission ids are date-slugs
LISTING="$(ls -t "$MISSIONS" 2>/dev/null || true)"
LATEST=""
while IFS= read -r _d; do
  case "$_d" in ''|.*) continue ;; esac
  LATEST="$_d"; break
done <<< "$LISTING"
[ -z "$LATEST" ] && exit 0

LOG="$MISSIONS/$LATEST/log.md"
[ ! -f "$LOG" ] && exit 0

# ── Extract token usage ────────────────────────────────────────────────────────
# The SubagentStop payload may carry usage under several shapes:
#   { "usage": { "input_tokens": N, "output_tokens": N } }
#   { "input_tokens": N, "output_tokens": N }
#   { "total_tokens": N }
# We try each path with a fallback to 0.
INPUT_TOKENS="$(printf '%s' "$INPUT" | jq -r '
  ( .usage.input_tokens  // .input_tokens  // 0 ) |
  if type == "number" then . else 0 end
' 2>/dev/null || echo 0)"

OUTPUT_TOKENS="$(printf '%s' "$INPUT" | jq -r '
  ( .usage.output_tokens // .output_tokens // 0 ) |
  if type == "number" then . else 0 end
' 2>/dev/null || echo 0)"

# Coerce to integers (strip any fractional part that jq might emit)
INPUT_TOKENS="${INPUT_TOKENS%%.*}"
OUTPUT_TOKENS="${OUTPUT_TOKENS%%.*}"
INPUT_TOKENS="${INPUT_TOKENS:-0}"
OUTPUT_TOKENS="${OUTPUT_TOKENS:-0}"

# ── Map agent_type → tokens role key ─────────────────────────────────────────
TOKEN_ROLE=""
case "$AGENT_TYPE" in
  worker)
    TOKEN_ROLE="workers"
    ;;
  scrutiny-validator|scrutiny-validator-external)
    TOKEN_ROLE="scrutiny"
    ;;
  user-testing-validator)
    TOKEN_ROLE="user_testing"
    ;;
  explorer|scout)
    TOKEN_ROLE="explorers"
    ;;
  *)
    TOKEN_ROLE=""
    ;;
esac

# ── Aggregate tokens into status.json (graceful degradation) ─────────────────
TOKEN_NOTE=""
if [ -n "$TOKEN_ROLE" ] && { [ "$INPUT_TOKENS" -gt 0 ] 2>/dev/null || [ "$OUTPUT_TOKENS" -gt 0 ] 2>/dev/null; }; then
  STATUS_FILE="$MISSIONS/$LATEST/status.json"
  if [ -f "$STATUS_FILE" ] && jq -e '.tokens' "$STATUS_FILE" >/dev/null 2>&1; then
    UPDATED="$(jq \
      --arg role "$TOKEN_ROLE" \
      --argjson inp "$INPUT_TOKENS" \
      --argjson out "$OUTPUT_TOKENS" \
      '.tokens[$role].input  += $inp | .tokens[$role].output += $out' \
      "$STATUS_FILE" 2>/dev/null || true)"
    if [ -n "$UPDATED" ]; then
      printf '%s' "$UPDATED" > "$STATUS_FILE"
      TOKEN_NOTE=" tokens=+${INPUT_TOKENS}in/+${OUTPUT_TOKENS}out→${TOKEN_ROLE}"
    fi
  fi
fi

# ── Log entry (existing behaviour + optional token delta) ─────────────────────
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '[%s] subagent stopped — type=%s%s\n' "$NOW" "$AGENT_TYPE" "$TOKEN_NOTE" >> "$LOG"

exit 0
