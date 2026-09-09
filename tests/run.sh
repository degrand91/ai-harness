#!/usr/bin/env bash
# run.sh - the single owner of running the harness test suite.
#
# Usage:
#   tests/run.sh                    run every tests/*.test.sh
#   tests/run.sh <file>...          run named test files
#   tests/run.sh --list             list discovered tests, run none
#   tests/run.sh --filter <substr>  run tests whose filename matches
#
# Dependency-free by design: bash, jq, and coreutils only. Each test file runs
# in its own process, so a crash or a stray `exit` in one cannot affect another.
# Exit 0 only when every file passed.

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export HARNESS_ROOT

usage() { sed -n '2,12{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; }

FILTER=""
LIST_ONLY=0
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list)    LIST_ONLY=1; shift ;;
    --filter)  FILTER="${2:?--filter needs a value}"; shift 2 ;;
    -*)        printf 'run.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    *)         FILES+=("$1"); shift ;;
  esac
done

if [ "${#FILES[@]}" -eq 0 ]; then
  while IFS= read -r f; do FILES+=("$f"); done < <(find "$TESTS_DIR" -maxdepth 1 -name '*.test.sh' | sort)
fi

if [ -n "$FILTER" ]; then
  KEPT=()
  for f in "${FILES[@]}"; do
    case "$(basename "$f")" in *"$FILTER"*) KEPT+=("$f") ;; esac
  done
  FILES=("${KEPT[@]:-}")
fi

if [ "${#FILES[@]}" -eq 0 ] || [ -z "${FILES[0]:-}" ]; then
  printf 'run.sh: no test files found\n' >&2
  exit 2
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  for f in "${FILES[@]}"; do basename "$f"; done
  exit 0
fi

# Missing jq is a hard stop: every hook uses it, so "tests pass" without it
# would be a lie rather than a skip.
command -v jq >/dev/null 2>&1 || { printf 'run.sh: jq is required\n' >&2; exit 2; }

PASSED=0; FAILED=0; FAILED_NAMES=()
START="$(date +%s)"

for f in "${FILES[@]}"; do
  name="$(basename "$f")"
  printf '  %s\n' "$name"
  if bash "$f"; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1)); FAILED_NAMES+=("$name")
  fi
done

ELAPSED=$(( $(date +%s) - START ))
printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf 'FAILED — %d passed, %d failed (%ds)\n' "$PASSED" "$FAILED" "$ELAPSED" >&2
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n" >&2; done
  exit 1
fi
printf 'ok — %d files passed (%ds)\n' "$PASSED" "$ELAPSED"
