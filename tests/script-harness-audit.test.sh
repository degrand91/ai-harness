#!/usr/bin/env bash
# Tests for the mission-state checks in scripts/harness-audit.sh. These read
# through scripts/lib/status-read.sh; reading `.state` directly here reported a
# legible drifted mission as invalid — the §0.1 defect in a second consumer.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

# Invoked directly rather than via run_script, so the fixture root is honoured.
audit() {
  local outf; outf="$(mktemp)"
  HARNESS_AUDIT_ROOT="$1" "$HARNESS_ROOT/scripts/harness-audit.sh" >"$outf" 2>&1 || true
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"
  export HOOK_OUT
}

home="$(mktmphome)"
cp -R "$HARNESS_ROOT/.claude/agents" "$home/.claude/" 2>/dev/null || true
cp -R "$HARNESS_ROOT/.claude/skills" "$home/.claude/" 2>/dev/null || true
cp "$HARNESS_ROOT/.claude/settings.json" "$home/.claude/" 2>/dev/null || true

it "accepts a canonical mission state"
mkmission "$home" 2026-07-01-canon '{"state":"executing","features":[]}' >/dev/null
audit "$home"
assert_contains "$HOOK_OUT" "[PASS] All mission state fields are valid enum values"

it "accepts a DRIFTED-schema mission instead of calling it invalid (§0.1)"
mkmission "$home" 2026-07-02-drift '{"status":"in-progress","phase":"feature-loop","features":[]}' >/dev/null
audit "$home"
assert_contains "$HOOK_OUT" "[PASS] All mission state fields are valid enum values"

it "rejects a genuinely unclassifiable mission"
mkdir -p "$home/missions/2026-07-03-bad"
printf '{"state":"banana"}\n' > "$home/missions/2026-07-03-bad/status.json"
audit "$home"
assert_contains "$HOOK_OUT" "[FAIL] All mission state fields are valid enum values"
assert_contains "$HOOK_OUT" "2026-07-03-bad"
rm -rf "$home/missions/2026-07-03-bad"

it "skips red features in a terminal mission"
mkmission "$home" 2026-07-04-closed '{"state":"closed","features":[{"id":"F001","slug":"x","color":"red"}]}' >/dev/null
audit "$home"
assert_contains "$HOOK_OUT" "[PASS] No red mission features in active missions"

it "reports red features in a drifted mission that is still active"
mkmission "$home" 2026-07-05-drift-red '{"status":"in-progress","features":[{"id":"F001","slug":"boom","color":"red"}]}' >/dev/null
audit "$home"
assert_contains "$HOOK_OUT" "boom"

finish
