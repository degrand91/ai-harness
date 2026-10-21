#!/usr/bin/env bash
# setup.sh is the one-command bootstrap. It must: report readiness without ever
# mutating the system in the default/--check mode, cover core + capabilities +
# per-skill readiness, refuse an unknown flag, and answer --help. Installing is
# not exercised here — it needs a package manager and network, and the whole
# point of --check is that it is safe to run anywhere, including the suite.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
export CLAUDE_PROJECT_DIR="$home"

it "setup.sh --check exits 0 when the required tools are present"
# The temp home already has the four state roots, and git/jq/bash are what the
# suite itself runs on, so core is ready by construction.
run_script scripts/setup.sh --check
assert_rc 0 "$HOOK_RC"

it "the report covers core, capability tools, and per-skill readiness"
assert_contains "$HOOK_OUT" "Core harness"
assert_contains "$HOOK_OUT" "Capability tools"
assert_contains "$HOOK_OUT" "Skill readiness"

it "no argument behaves like --check"
run_script scripts/setup.sh
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "Skill readiness"

it "--check mutates nothing — it emits no install action"
run_script scripts/setup.sh --check
# `doing()` prints a '  install  ' line; it must never fire outside --install.
assert_not_contains "$HOOK_OUT" "  install  "

it "an unknown flag is refused with exit 2, not treated as work"
run_script scripts/setup.sh --bogus
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_ERR" "unknown option"

it "--help names the script and exits 0"
run_script scripts/setup.sh --help
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "setup.sh"

it "--help does not leak script body past the comment header"
assert_not_contains "$HOOK_OUT" "set -uo pipefail"

finish
