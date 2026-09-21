#!/usr/bin/env bash
#
# SubagentStop hook. For the harness roles (worker, validators, explorer, scout):
#   1. persists the subagent's final message to the current feature's folder —
#      worker → handoff.md, scrutiny* → scrutiny.md, user-testing → user-test.md —
#      stripped of any prose before the first `## Feature:` heading, so the
#      orchestrator no longer spends a turn copying verdicts to disk;
#   2. accumulates token usage into the active mission's status.json tokens block;
#   3. appends one line to the mission log.
#
# Any other agent_type (background Bash tasks, forks, the orchestrator itself)
# is ignored: those stops used to be logged too, and at one wake-up per 30 s
# they made up 75% of every mission log.
#
# The raw payload is always dumped to state/last-subagent-stop.json so the
# fields Claude Code actually sends can be inspected without guessing.
#
# Input: JSON on stdin with hook_event_name=SubagentStop, agent_type,
# last_assistant_message, agent_transcript_path (and, on builds that send it,
# usage.{input_tokens,output_tokens}).

# NOT `set -e`. §0.5 fixed this crash class in three hooks and missed this one:
# a payload jq cannot parse exited the hook non-zero instead of doing nothing.
# Recording a token count is best-effort; the subagent it observes has already
# finished, and there is nothing useful to fail about.
set -uo pipefail

INPUT="$(cat 2>/dev/null || true)"

HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-.}"
MISSIONS="${HARNESS_ROOT}/missions"

if [ -d "$HARNESS_ROOT/state" ]; then
  printf '%s' "$INPUT" > "$HARNESS_ROOT/state/last-subagent-stop.json" 2>/dev/null || true
fi

AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // .matcher // empty' 2>/dev/null || true)"

# ── Map agent_type → role bucket + persisted artifact ────────────────────────
TOKEN_ROLE=""; ARTIFACT=""
case "$AGENT_TYPE" in
  worker)                                       TOKEN_ROLE=workers;      ARTIFACT=handoff.md ;;
  scrutiny-validator|scrutiny-validator-external) TOKEN_ROLE=scrutiny;   ARTIFACT=scrutiny.md ;;
  user-testing-validator)                       TOKEN_ROLE=user_testing; ARTIFACT=user-test.md ;;
  explorer|scout)                               TOKEN_ROLE=explorers ;;
  *) exit 0 ;;
esac

[ ! -d "$MISSIONS" ] && exit 0

# shellcheck disable=SC2012  # mtime ordering; mission ids are date-slugs
LISTING="$(ls -t "$MISSIONS" 2>/dev/null || true)"
LATEST=""
while IFS= read -r _d; do
  case "$_d" in ''|.*) continue ;; esac
  LATEST="$_d"; break
done <<< "$LISTING"
[ -z "$LATEST" ] && exit 0

MISSION_DIR="$MISSIONS/$LATEST"
LOG="$MISSION_DIR/log.md"
STATUS_FILE="$MISSION_DIR/status.json"
[ ! -f "$LOG" ] && exit 0

# ── Persist the final message to the current feature's folder ────────────────
# The folder is found by id: each features/NNN-*/status.json carries `id`
# (F001, F001-followup-2, …); the name pattern is the fallback for folders
# scaffolded without one.
feature_dir_for() {
  local want="$1" d id num rest
  for d in "$MISSION_DIR"/features/*/; do
    [ -d "$d" ] || continue
    id=""
    [ -f "$d/status.json" ] && id="$(jq -r '.id // empty' "$d/status.json" 2>/dev/null || true)"
    if [ -z "$id" ]; then
      d="${d%/}"; num="${d##*/}"; rest="$num"
      num="${num%%-*}"
      case "$rest" in
        *-followup-*) rest="${rest#*-followup-}"; rest="${rest%%-*}"; id="F${num}-followup-${rest}" ;;
        *) id="F${num}" ;;
      esac
    fi
    if [ "$id" = "$want" ]; then printf '%s\n' "${d%/}"; return 0; fi
  done
  return 1
}

PERSIST_NOTE=""
if [ -n "$ARTIFACT" ] && [ -f "$STATUS_FILE" ]; then
  MESSAGE="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null || true)"
  CURRENT="$(jq -r '.current_feature // empty' "$STATUS_FILE" 2>/dev/null || true)"
  if [ -n "$MESSAGE" ] && [ -n "$CURRENT" ]; then
    # Defensive parse: keep from the first `## Feature:` heading onward.
    BODY="$(printf '%s\n' "$MESSAGE" | awk '/^## Feature:/{p=1} p')"
    FDIR="$(feature_dir_for "$CURRENT" 2>/dev/null || true)"
    if [ -n "$BODY" ] && [ -n "$FDIR" ]; then
      TARGET="$FDIR/$ARTIFACT"
      if [ -s "$TARGET" ]; then
        # A second run on the same feature (re-spawn, external + default
        # scrutiny) is appended, not overwritten: verdicts are evidence.
        printf '\n\n---\n<!-- appended by SubagentStop %s -->\n\n%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BODY" >> "$TARGET"
      else
        printf '%s\n' "$BODY" > "$TARGET"
      fi
      PERSIST_NOTE=" → ${TARGET#"$MISSION_DIR"/}"
    fi
  fi
fi

# ── Extract token usage ────────────────────────────────────────────────────────
INPUT_TOKENS="$(printf '%s' "$INPUT" | jq -r '
  ( .usage.input_tokens  // .input_tokens  // 0 ) |
  if type == "number" then . else 0 end
' 2>/dev/null || echo 0)"
OUTPUT_TOKENS="$(printf '%s' "$INPUT" | jq -r '
  ( .usage.output_tokens // .output_tokens // 0 ) |
  if type == "number" then . else 0 end
' 2>/dev/null || echo 0)"
INPUT_TOKENS="${INPUT_TOKENS%%.*}";   INPUT_TOKENS="${INPUT_TOKENS:-0}"
OUTPUT_TOKENS="${OUTPUT_TOKENS%%.*}"; OUTPUT_TOKENS="${OUTPUT_TOKENS:-0}"
CACHE_READ=0

# Claude Code 2.1.278 sends no `usage` in this payload (verified 2026-09-21 —
# every mission's tokens block read 0 for months because of it). It does send
# `agent_transcript_path`: the subagent's own JSONL, where every assistant line
# carries `message.usage`. Streaming writes several lines per API message
# (same `message.id`, partial output counts), so take the fullest line per id.
# `input` = uncached input + cache writes (both billed at ≥ the input rate);
# cache reads are kept apart because they cost a tenth.
if [ "$INPUT_TOKENS" -eq 0 ] 2>/dev/null && [ "$OUTPUT_TOKENS" -eq 0 ] 2>/dev/null; then
  TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r '.agent_transcript_path // empty' 2>/dev/null || true)"
  if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
    SUMS="$(jq -s '
      [ .[] | select(.type == "assistant" and (.message.usage? // null) != null) ]
      | group_by(.message.id // .uuid)
      | map(max_by(.message.usage.output_tokens // 0) | .message.usage)
      | { input:      (map((.input_tokens // 0) + (.cache_creation_input_tokens // 0)) | add // 0),
          cache_read: (map(.cache_read_input_tokens // 0) | add // 0),
          output:     (map(.output_tokens // 0) | add // 0) }
      | "\(.input) \(.output) \(.cache_read)"' "$TRANSCRIPT" 2>/dev/null || true)"
    SUMS="$(printf '%s' "$SUMS" | tr -d '"')"
    if [ -n "$SUMS" ]; then
      read -r INPUT_TOKENS OUTPUT_TOKENS CACHE_READ <<< "$SUMS"
      case "$INPUT_TOKENS"  in ''|*[!0-9]*) INPUT_TOKENS=0 ;; esac
      case "$OUTPUT_TOKENS" in ''|*[!0-9]*) OUTPUT_TOKENS=0 ;; esac
      case "$CACHE_READ"    in ''|*[!0-9]*) CACHE_READ=0 ;; esac
    fi
  fi
fi

# ── Aggregate tokens into status.json (graceful degradation) ─────────────────
TOKEN_NOTE=""
if [ "$INPUT_TOKENS" -gt 0 ] 2>/dev/null || [ "$OUTPUT_TOKENS" -gt 0 ] 2>/dev/null; then
  if [ -f "$STATUS_FILE" ] && jq -e '.tokens' "$STATUS_FILE" >/dev/null 2>&1; then
    UPDATED="$(jq \
      --arg role "$TOKEN_ROLE" \
      --argjson inp "$INPUT_TOKENS" \
      --argjson out "$OUTPUT_TOKENS" \
      --argjson cr  "$CACHE_READ" \
      '.tokens[$role].input  += $inp
       | .tokens[$role].output += $out
       | .tokens[$role].cache_read = ((.tokens[$role].cache_read // 0) + $cr)' \
      "$STATUS_FILE" 2>/dev/null || true)"
    if [ -n "$UPDATED" ]; then
      printf '%s' "$UPDATED" > "$STATUS_FILE"
      TOKEN_NOTE=" tokens=+${INPUT_TOKENS}in/+${OUTPUT_TOKENS}out/+${CACHE_READ}cached→${TOKEN_ROLE}"
    fi
  fi
fi

# ── Log entry ─────────────────────────────────────────────────────────────────
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '[%s] subagent stopped — type=%s%s%s\n' "$NOW" "$AGENT_TYPE" "$TOKEN_NOTE" "$PERSIST_NOTE" >> "$LOG"

exit 0
