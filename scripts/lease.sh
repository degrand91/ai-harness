#!/usr/bin/env bash
# lease.sh - named leases, so two things wanting one resource is a refusal
#            rather than a race.
#
# Usage:
#   lease.sh claim <resource> [--actor <name>] [--ttl <seconds>] [--pid <pid>]
#   lease.sh release <resource> [--actor <name>]
#   lease.sh check <resource>      prints "<actor> <pid> <epoch> <live|stale>"
#   lease.sh sweep                 drop every stale lease
#   lease.sh list
#
# The serial-spawn lock answered exactly one question — "is a non-explorer
# subagent in flight" — with one boolean in one file. The moment two missions
# target one project, or a crewmate and a validator both want a worktree, that
# is not enough: the question becomes "who holds WHAT".
#
# A lease is stale when its ttl has passed, or when it names a pid that is no
# longer alive. Staleness is reclaimed silently, because the alternative is a
# crashed process wedging a resource until a human notices.
#
# --pid IS OPTIONAL AND DEFAULTS TO NONE. Recording this script's own pid would
# be worthless: a one-shot CLI is gone the instant it returns, so every lease
# would read as stale immediately. A caller that genuinely has a long-lived
# holder (scripts/crew/run.sh, say) passes --pid; everyone else relies on the
# ttl, which is the honest liveness signal for a lease taken from a shell.
#
# Exit: 0 held by you · 6 held by someone else · 1 no such lease (check/release)
#
# Tuning: HARNESS_LEASE_TTL (3600)

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
LEASES="$HARNESS_ROOT/state/leases"
TTL_DEFAULT="${HARNESS_LEASE_TTL:-3600}"

usage() { sed -n '2,10{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }
die() { printf '%s\n' "$1" >&2; exit "${2:-2}"; }

safe_name() {  # a resource name becomes a filename
  case "${1:-}" in
    ''|*/*|.|..|*..*) return 1 ;;
    *) return 0 ;;
  esac
}

lease_file() { printf '%s/%s.lease' "$LEASES" "$1"; }

is_live() {  # <file>
  [ -f "$1" ] || return 1
  local pid exp now
  pid="$(jq -r '.pid // 0' "$1" 2>/dev/null || echo 0)"
  exp="$(jq -r '.expires_epoch // 0' "$1" 2>/dev/null || echo 0)"
  now="$(date -u +%s)"
  case "$exp" in ''|*[!0-9]*) exp=0 ;; esac
  [ "$exp" -gt "$now" ] || return 1
  case "$pid" in
    ''|0|*[!0-9]*) return 0 ;;      # no usable pid: trust the ttl alone
    *) kill -0 "$pid" 2>/dev/null ;;
  esac
}

# Capture the subcommand BEFORE consuming anything: shifting first ate it, so
# `lease.sh list` reached the option loop as an unknown option.
CMD="${1:-}"
RES=""
ACTOR="$(id -un 2>/dev/null || echo unknown)"
TTL="$TTL_DEFAULT"
PID=0
[ $# -gt 0 ] && shift
case "$CMD" in
  claim|release|check) RES="${1:-}"; [ $# -gt 0 ] && shift ;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --actor) ACTOR="${2:?}"; shift 2 ;;
    --ttl)   TTL="${2:?}"; shift 2 ;;
    --pid)   PID="${2:?}"; shift 2 ;;
    *) die "lease.sh: unknown option $1" ;;
  esac
done

case "$CMD" in
  claim)
    safe_name "$RES" || die "lease.sh: unsafe resource name \"$RES\""
    mkdir -p "$LEASES" || die "lease.sh: cannot create $LEASES" 1
    f="$(lease_file "$RES")"
    if is_live "$f"; then
      holder="$(jq -r '.actor // "?"' "$f" 2>/dev/null || echo '?')"
      if [ "$holder" = "$ACTOR" ]; then
        : # our own lease; fall through and refresh it
      else
        printf 'lease.sh: "%s" is held by %s\n' "$RES" "$holder" >&2
        exit 6
      fi
    fi
    tmp="$(mktemp "${f}.XXXXXX")" || die "lease.sh: cannot write $f" 1
    case "$PID" in ''|*[!0-9]*) PID=0 ;; esac
    jq -n --arg r "$RES" --arg a "$ACTOR" --argjson p "$PID" \
          --argjson e "$(( $(date -u +%s) + TTL ))" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{resource:$r, actor:$a, pid:$p, expires_epoch:$e, claimed_at:$at}' > "$tmp" 2>/dev/null \
      || { rm -f "$tmp"; die "lease.sh: could not encode the lease" 1; }
    mv "$tmp" "$f" || { rm -f "$tmp"; die "lease.sh: could not place the lease" 1; }
    printf 'claimed %s for %s (ttl %ss)\n' "$RES" "$ACTOR" "$TTL"
    ;;
  release)
    safe_name "$RES" || die "lease.sh: unsafe resource name \"$RES\""
    f="$(lease_file "$RES")"
    [ -f "$f" ] || { printf 'lease.sh: "%s" is not leased\n' "$RES" >&2; exit 1; }
    holder="$(jq -r '.actor // "?"' "$f" 2>/dev/null || echo '?')"
    if [ "$holder" != "$ACTOR" ] && is_live "$f"; then
      printf 'lease.sh: refusing to release "%s" — it is held by %s, not %s\n' "$RES" "$holder" "$ACTOR" >&2
      exit 6
    fi
    rm -f "$f"; printf 'released %s\n' "$RES"
    ;;
  check)
    safe_name "$RES" || die "lease.sh: unsafe resource name \"$RES\""
    f="$(lease_file "$RES")"
    [ -f "$f" ] || exit 1
    state=stale; is_live "$f" && state=live
    printf '%s %s %s %s\n' \
      "$(jq -r '.actor // "?"' "$f" 2>/dev/null)" \
      "$(jq -r '.pid // 0' "$f" 2>/dev/null)" \
      "$(jq -r '.expires_epoch // 0' "$f" 2>/dev/null)" "$state"
    ;;
  sweep)
    n=0
    [ -d "$LEASES" ] || { printf 'swept 0\n'; exit 0; }
    for f in "$LEASES"/*.lease; do
      [ -f "$f" ] || continue
      is_live "$f" || { rm -f "$f"; n=$((n + 1)); }
    done
    printf 'swept %s\n' "$n"
    ;;
  list)
    [ -d "$LEASES" ] || { printf '(no leases)\n'; exit 0; }
    any=0
    for f in "$LEASES"/*.lease; do
      [ -f "$f" ] || continue
      any=1; state=stale; is_live "$f" && state=live
      printf '  %-28s %-12s %s\n' "$(basename "$f" .lease)" "$(jq -r '.actor // "?"' "$f" 2>/dev/null)" "$state"
    done
    [ "$any" -eq 1 ] || printf '(no leases)\n'
    ;;
  -h|--help|"") usage ;;
  *) die "lease.sh: unknown subcommand ${CMD}" ;;
esac
