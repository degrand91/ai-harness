#!/usr/bin/env bash
# afk.sh - away mode: batch the routine, escalate only what needs the captain,
#          and shout if an escalation goes nowhere.
#
# Usage:
#   afk.sh start [<duration>]   e.g. 6h, 90m. Default 8h.
#   afk.sh status               is away mode on, and what has happened
#   afk.sh digest               print the digest without ending away mode
#   afk.sh return               end away mode and present the digest
#   afk.sh tick                 one supervision pass (the daemon loop calls this)
#   afk.sh daemon               run tick on a loop until the deadline
#   afk.sh ack <id>             acknowledge an escalation
#
# AWAY MODE OWNS THE WATCHER. While state/.afk exists the Stop-hook watcher
# stands down entirely, because two things deciding when to wake the session
# is two things disagreeing.
#
# THE WEDGE ALARM is the part worth having. It does not defend against nothing
# happening; it defends against SOMETHING HAPPENING THAT NEEDED YOU AND THE
# MESSAGE GOING NOWHERE. An escalation writes an ack file; if nothing
# acknowledges it within HARNESS_WEDGE_MINUTES the alarm climbs — notification,
# then Slack/email, then a repeating urgent alert — until acked or away mode ends.
#
# Routine events are digested, never delivered. Captain-relevant events are:
#   a blocking decision, a red feature, a crewmate that failed or vanished,
#   a mission that stalled.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
STATE="$HARNESS_ROOT/state"
MISSIONS="$HARNESS_ROOT/missions"
AFK="$STATE/.afk"
DIGEST="$STATE/afk-digest.md"
ESC="$STATE/afk-escalations"

# shellcheck source=lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh"
# shellcheck source=lib/crew.sh
. "$CODE_ROOT/scripts/lib/crew.sh"
# shellcheck source=lib/holds.sh
. "$CODE_ROOT/scripts/lib/holds.sh"

WEDGE_MIN="${HARNESS_WEDGE_MINUTES:-30}"
REPEAT_MIN="${HARNESS_WEDGE_REPEAT_MINUTES:-10}"
POLL="${HARNESS_AFK_POLL:-60}"

usage() { sed -n '2,14{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
now()   { date -u +%s; }
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ; }
notify() { "$CODE_ROOT/scripts/notify.sh" "$@" || true; }

parse_duration() {  # 6h | 90m | 3600 -> seconds
  local d="${1:-8h}"
  case "$d" in
    *h) printf '%s' $(( ${d%h} * 3600 )) ;;
    *m) printf '%s' $(( ${d%m} * 60 )) ;;
    *s) printf '%s' "${d%s}" ;;
    ''|*[!0-9]*) printf '28800' ;;
    *)  printf '%s' "$d" ;;
  esac
}

digest_line() { printf '%s  %s\n' "$(stamp)" "$1" >> "$DIGEST"; }

# An escalation is a durable record with an ack file, so "did anyone see this"
# is answerable after the fact rather than assumed.
escalate() {  # <id> <text>
  local id="$1" text="$2"
  mkdir -p "$ESC"
  [ -f "$ESC/$id.json" ] && return 0        # already raised; the alarm owns it now
  jq -n --arg id "$id" --arg t "$text" --arg at "$(stamp)" --argjson e "$(now)" \
    '{id:$id, text:$t, raised_at:$at, raised_epoch:$e, acked_at:null, last_alarm_epoch:$e}' \
    > "$ESC/$id.json" 2>/dev/null || return 0
  digest_line "ESCALATED $id: $text"
  notify "Harness" "$text"
}

# The wedge alarm: an escalation nobody acknowledged.
check_wedge() {
  [ -d "$ESC" ] || return 0
  local f id text raised last age since
  for f in "$ESC"/*.json; do
    [ -f "$f" ] || continue
    jq -e '.acked_at == null' "$f" >/dev/null 2>&1 || continue
    id="$(jq -r '.id' "$f" 2>/dev/null || true)"
    text="$(jq -r '.text' "$f" 2>/dev/null || true)"
    raised="$(jq -r '.raised_epoch' "$f" 2>/dev/null || echo 0)"
    last="$(jq -r '.last_alarm_epoch' "$f" 2>/dev/null || echo 0)"
    case "$raised$last" in *[!0-9]*) continue ;; esac
    age=$(( $(now) - raised ))
    since=$(( $(now) - last ))
    [ "$age" -ge $(( WEDGE_MIN * 60 )) ] || continue
    [ "$since" -ge $(( REPEAT_MIN * 60 )) ] || continue
    notify "Harness — UNACKNOWLEDGED" "$text (raised $(( age / 60 )) minutes ago, still unacknowledged)" --level urgent
    digest_line "WEDGE ALARM $id: unacknowledged for $(( age / 60 ))m"
    jq --argjson e "$(now)" '.last_alarm_epoch = $e' "$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f"
  done
}

tick() {
  mkdir -p "$STATE"
  # Blocking decisions.
  local md mid
  for md in "$MISSIONS"/*/; do
    [ -d "$md" ] || continue
    mid="$(basename "$md")"
    case "$mid" in .*) continue ;; esac
    if [ "$(holds_count_blocking "${md%/}" 2>/dev/null || echo 0)" -gt 0 ]; then
      escalate "hold-$mid" "$mid is blocked on a decision"
    fi
  done

  # Crewmate outcomes: failure and blockage escalate, success is digested.
  local t last
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    last="$(crew_ledger_last "$HARNESS_ROOT" "$t" 2>/dev/null || true)"
    case "$last" in
      failed)  escalate "crew-$t-failed"  "crewmate $t failed: $(crew_ledger_note "$HARNESS_ROOT" "$t")" ;;
      blocked) escalate "crew-$t-blocked" "crewmate $t is blocked: $(crew_ledger_note "$HARNESS_ROOT" "$t")" ;;
      done)
        if [ ! -f "$STATE/.afk-seen-$t" ]; then
          : > "$STATE/.afk-seen-$t"
          digest_line "crewmate $t finished: $(crew_ledger_note "$HARNESS_ROOT" "$t")"
        fi ;;
    esac
  done < <(crew_list "$HARNESS_ROOT" 2>/dev/null)

  check_wedge
}

case "${1:-}" in
  start)
    mkdir -p "$STATE" "$ESC"
    SECS="$(parse_duration "${2:-8h}")"
    jq -n --arg at "$(stamp)" --argjson until "$(( $(now) + SECS ))" --argjson secs "$SECS" \
      '{entered_at:$at, until_epoch:$until, duration_seconds:$secs}' > "$AFK" \
      || { printf 'afk: could not enter away mode\n' >&2; exit 1; }
    : > "$DIGEST"
    digest_line "away mode started (until $(date -u -r "$(( $(now) + SECS ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$(( $(now) + SECS ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?'))"
    printf 'Away mode on for %s. The watcher stands down; escalations will find you.\n' "${2:-8h}"
    printf 'Start the daemon in another terminal:  ./scripts/afk.sh daemon &\n'
    ;;
  status)
    if [ ! -f "$AFK" ]; then printf 'Away mode is off.\n'; exit 0; fi
    printf 'Away mode on since %s.\n' "$(jq -r '.entered_at' "$AFK" 2>/dev/null || echo '?')"
    n=0; [ -d "$ESC" ] && for f in "$ESC"/*.json; do [ -f "$f" ] && jq -e '.acked_at == null' "$f" >/dev/null 2>&1 && n=$((n+1)); done
    printf 'Unacknowledged escalations: %s\n' "$n"
    ;;
  digest)
    [ -f "$DIGEST" ] && cat "$DIGEST" || printf '(nothing recorded)\n'
    ;;
  tick)   tick ;;
  daemon)
    [ -f "$AFK" ] || { printf 'afk: away mode is not on\n' >&2; exit 1; }
    UNTIL="$(jq -r '.until_epoch' "$AFK" 2>/dev/null || echo 0)"
    while [ -f "$AFK" ] && [ "$(now)" -lt "$UNTIL" ]; do
      tick
      sleep "$POLL"
    done
    [ -f "$AFK" ] && notify "Harness" "Away mode has expired. Run /afk return."
    ;;
  ack)
    ID="${2:-}"; [ -n "$ID" ] || { printf 'usage: afk.sh ack <id>\n' >&2; exit 2; }
    F="$ESC/$ID.json"
    [ -f "$F" ] || { printf 'afk: no escalation %s\n' "$ID" >&2; exit 1; }
    jq --arg at "$(stamp)" '.acked_at = $at' "$F" > "$F.tmp" 2>/dev/null && mv "$F.tmp" "$F"
    printf 'Acknowledged %s\n' "$ID"
    ;;
  return)
    if [ ! -f "$AFK" ]; then printf 'Away mode is off.\n'; exit 0; fi
    rm -f "$AFK"
    printf '=== away-mode digest ===\n'
    [ -f "$DIGEST" ] && cat "$DIGEST"
    printf '\n=== unacknowledged escalations ===\n'
    any=0
    if [ -d "$ESC" ]; then
      for f in "$ESC"/*.json; do
        [ -f "$f" ] || continue
        jq -e '.acked_at == null' "$f" >/dev/null 2>&1 || continue
        any=1; printf '  %s: %s\n' "$(jq -r '.id' "$f")" "$(jq -r '.text' "$f")"
      done
    fi
    [ "$any" -eq 1 ] || printf '  (none)\n'
    rm -f "$STATE"/.afk-seen-* 2>/dev/null || true
    printf '\nAway mode off. Present this, then run /decide if anything is blocking.\n'
    ;;
  -h|--help|"") usage ;;
  *) printf 'afk.sh: unknown subcommand %s\n' "$1" >&2; exit 2 ;;
esac
