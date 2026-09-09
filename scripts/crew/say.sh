#!/usr/bin/env bash
# say.sh - the one command a crewmate may use to speak to its supervisor.
#
# Usage: say.sh <ledger-path> <verb> [note...]
#
# The ledger lives OUTSIDE the crewmate's worktree, in the harness's state
# directory, so the crewmate cannot reach it with an ordinary write — and its
# tool allowlist deliberately contains no general-purpose shell. Without this,
# the brief instructs a crewmate to report progress it has no way to report,
# which is exactly what the first real smoke test found: the work was done
# correctly and the supervisor was told nothing.
#
# Granting this one narrow command is the whole solution. It appends a single
# well-formed line and can do nothing else.
#
# Verbs: progress · blocked · done · failed

set -uo pipefail
LEDGER="${1:?say.sh: ledger path required}"; shift
VERB="${1:?say.sh: verb required}"; shift
NOTE="$*"

case "$VERB" in
  progress|blocked|done|failed) ;;
  *) printf 'say.sh: unknown verb "%s" (progress|blocked|done|failed)\n' "$VERB" >&2; exit 2 ;;
esac

d="$(dirname "$LEDGER")"
[ -d "$d" ] || { printf 'say.sh: no such ledger directory: %s\n' "$d" >&2; exit 1; }
printf '%s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$VERB" "$NOTE" >> "$LEDGER" \
  || { printf 'say.sh: could not append to %s\n' "$LEDGER" >&2; exit 1; }
printf 'recorded: %s\n' "$VERB"
