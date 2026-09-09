#!/usr/bin/env bash
# fixtures.sh - the single owner of test scaffolding: temp harness homes,
# mission fixtures, hook invocation, and assertions.
#
# Sourced by every tests/*.test.sh. No external dependencies (no bats, no
# shunit2) - the suite must run on a bare macOS or Ubuntu box with git, jq and
# bash, because that is all the harness itself requires.
#
# Contract for a test file:
#   . "$(dirname "${BASH_SOURCE[0]}")/lib/fixtures.sh"
#   it "does the thing"; assert_eq expected "$actual"
#   finish            # last line; sets the exit status
#
# Every temp home is removed on exit, including on failure.

set -uo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)}"
export HARNESS_ROOT

_TESTS_RUN=0
_TESTS_FAILED=0
_CURRENT_IT="(no it() called yet)"
_TMP_HOMES=()

# --- lifecycle --------------------------------------------------------------
_cleanup() {
  local h
  for h in "${_TMP_HOMES[@]:-}"; do
    [ -n "$h" ] && [ -d "$h" ] && rm -rf "$h"
  done
}
trap _cleanup EXIT INT TERM

it() {
  _CURRENT_IT="$1"
  _TESTS_RUN=$((_TESTS_RUN + 1))
}

_fail() {
  _TESTS_FAILED=$((_TESTS_FAILED + 1))
  printf '    FAIL: %s\n' "$_CURRENT_IT" >&2
  local line
  while IFS= read -r line; do printf '          %s\n' "$line" >&2; done <<<"$1"
}

finish() {
  if [ "$_TESTS_FAILED" -gt 0 ]; then
    printf '    %d/%d failed\n' "$_TESTS_FAILED" "$_TESTS_RUN" >&2
    exit 1
  fi
  printf '    %d passed\n' "$_TESTS_RUN"
  exit 0
}

# --- assertions -------------------------------------------------------------
assert_eq() {
  local expected="$1" actual="$2"
  [ "$expected" = "$actual" ] && return 0
  _fail "expected: [$expected]
actual:   [$actual]"
}

assert_contains() {
  local haystack="$1" needle="$2"
  case "$haystack" in *"$needle"*) return 0 ;; esac
  _fail "expected to contain: [$needle]
actual:              [$haystack]"
}

assert_not_contains() {
  local haystack="$1" needle="$2"
  case "$haystack" in *"$needle"*) ;; *) return 0 ;; esac
  _fail "expected NOT to contain: [$needle]
actual:                  [$haystack]"
}

assert_rc() {
  local expected="$1" actual="$2"
  [ "$expected" = "$actual" ] && return 0
  _fail "expected exit code $expected, got $actual
stdout: [${HOOK_OUT:-}]
stderr: [${HOOK_ERR:-}]"
}

assert_file_exists() {
  [ -f "$1" ] && return 0
  _fail "expected file to exist: $1"
}

assert_file_missing() {
  [ ! -f "$1" ] && return 0
  _fail "expected file NOT to exist: $1"
}

# --- temp harness home ------------------------------------------------------
# A throwaway CLAUDE_PROJECT_DIR with the four state roots and the marker files
# that identify a genuine harness checkout.
mktmphome() {
  local home
  home="$(mktemp -d "${TMPDIR:-/tmp}/harness-test.XXXXXX")"
  mkdir -p "$home/missions" "$home/.claude/hooks" "$home/.claude/agents" \
           "$home/data" "$home/state" "$home/config" "$home/learnings"
  : > "$home/.claude/agents/orchestrator.md"
  _TMP_HOMES+=("$home")
  printf '%s\n' "$home"
}

# mkmission <home> <id> [json]
# Default json is a minimal canonical executing mission.
mkmission() {
  local home="$1" id="$2" json="${3:-}"
  mkdir -p "$home/missions/$id"
  if [ -z "$json" ]; then
    json='{"mission_id":"'"$id"'","state":"executing","current_feature":"F001","features":[{"id":"F001","slug":"a","state":"in_progress","color":null,"followups":[]}]}'
  fi
  printf '%s\n' "$json" > "$home/missions/$id/status.json"
  : > "$home/missions/$id/log.md"
  printf '%s\n' "$home/missions/$id"
}

# --- hook invocation --------------------------------------------------------
# run_hook <hook-name> <stdin-json> [env assignments...]
# Sets HOOK_OUT, HOOK_ERR, HOOK_RC. Never aborts the test file on nonzero.
run_hook() {
  local hook="$1" payload="$2"; shift 2
  local outf errf
  outf="$(mktemp)"; errf="$(mktemp)"
  HOOK_RC=0
  printf '%s' "$payload" | env "$@" "$HARNESS_ROOT/.claude/hooks/$hook" >"$outf" 2>"$errf" || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; HOOK_ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
  export HOOK_OUT HOOK_ERR HOOK_RC
}

# run_script <relative-path> <args...> - same capture shape, for scripts/.
run_script() {
  local script="$1"; shift
  local outf errf
  outf="$(mktemp)"; errf="$(mktemp)"
  HOOK_RC=0
  "$HARNESS_ROOT/$script" "$@" >"$outf" 2>"$errf" || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; HOOK_ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
  export HOOK_OUT HOOK_ERR HOOK_RC
}
