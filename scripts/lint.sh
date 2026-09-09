#!/usr/bin/env bash
# lint.sh - the single owner of static analysis for this repo's shell.
#
# Usage:
#   scripts/lint.sh              lint every tracked shell script
#   scripts/lint.sh <file>...    lint named files
#   scripts/lint.sh --strict     treat a missing shellcheck as an error
#
# Installs nothing. Without shellcheck it prints how to get it and exits 0, so a
# local run never hard-fails on a tool the harness does not require. CI passes
# --strict, so the check cannot silently evaporate there.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CODE_ROOT" || exit 1

STRICT=0; FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) sed -n '2,12{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
    --strict)  STRICT=1; shift ;;
    *)         FILES+=("$1"); shift ;;
  esac
done

if ! command -v shellcheck >/dev/null 2>&1; then
  printf 'shellcheck not installed — skipping.\n  macOS:  brew install shellcheck\n  Ubuntu: sudo apt-get install -y shellcheck\n' >&2
  [ "$STRICT" -eq 1 ] && exit 1
  exit 0
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(
    find scripts tests .claude/hooks -name '*.sh' -type f 2>/dev/null | sort
  )
fi
[ "${#FILES[@]}" -eq 0 ] && { printf 'lint.sh: no shell files found\n' >&2; exit 0; }

# SC1091: sourced libraries are resolved at runtime, not by shellcheck's static
#         path following.
# SC2317: functions in a sourced library look unreachable to shellcheck.
shellcheck --shell=bash --severity=warning --exclude=SC1091,SC2317 "${FILES[@]}"
rc=$?
[ "$rc" -eq 0 ] && printf 'ok — %d shell files clean\n' "${#FILES[@]}"
exit "$rc"
