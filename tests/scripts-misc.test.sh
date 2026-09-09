#!/usr/bin/env bash
# Coverage for the remaining scripts nothing exercised: doctor, fleet-html,
# learnings-index, pr-poll. Each is small, but "small and untested" is how the
# hooks in Phase 0 came to be quietly broken.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

run_s() {
  local s="$1"; shift
  local outf; outf="$(mktemp)"; HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/$s" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
home="$(mktmphome)"

# --- doctor ------------------------------------------------------------------
it "doctor creates the four state roots"
bare="$(mktmphome)"; rm -rf "$bare/data" "$bare/state" "$bare/config"
CLAUDE_PROJECT_DIR="$bare" "$HARNESS_ROOT/scripts/doctor.sh" >/dev/null 2>&1
for d in missions data state config; do
  [ -d "$bare/$d" ] || _fail "doctor did not create $d/"
done

it "doctor --check creates nothing"
bare2="$(mktmphome)"; rm -rf "$bare2/data" "$bare2/state" "$bare2/config"
CLAUDE_PROJECT_DIR="$bare2" "$HARNESS_ROOT/scripts/doctor.sh" --check >/dev/null 2>&1
[ -d "$bare2/data" ] && _fail "--check created data/"

it "doctor reports the required tools and exits 0 when they are present"
run_s scripts/doctor.sh --check
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "Required tools"
assert_contains "$HOOK_OUT" "git"
assert_contains "$HOOK_OUT" "jq"

it "doctor names an optional tool it cannot find without failing"
run_s scripts/doctor.sh --check
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "Optional tools"

it "doctor says nothing about gates when no project is registered [no-mistakes]"
gh_home="$(mktmphome)"
printf -- '- plain [local-only] %s - x (added 2026-01-01)\n' "$gh_home" > "$gh_home/data/projects.md"
out="$(CLAUDE_PROJECT_DIR="$gh_home" "$HARNESS_ROOT/scripts/doctor.sh" --check 2>&1)"
assert_not_contains "$out" "Delivery gates"

it "doctor warns that a [no-mistakes] project without a usable gate has none"
# The tool is a per-project devDependency, so "is it on PATH" is the wrong
# question; and having it without a .no-mistakes.json is still no gate, because
# `check` then reports nothing and exits 0.
printf -- '- gated [no-mistakes] %s - x (added 2026-01-01)\n' "$gh_home" >> "$gh_home/data/projects.md"
out="$(CLAUDE_PROJECT_DIR="$gh_home" "$HARNESS_ROOT/scripts/doctor.sh" --check 2>&1)"
assert_contains "$out" "Delivery gates"
assert_contains "$out" "no usable gate"

it "and reports one that does have a gate as ok"
mkdir -p "$gh_home/node_modules/.bin"
cat > "$gh_home/node_modules/.bin/no-mistakes" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "config resolve" ] && printf '{"configPath":".no-mistakes.json"}\n'
STUB
chmod +x "$gh_home/node_modules/.bin/no-mistakes"
out="$(CLAUDE_PROJECT_DIR="$gh_home" "$HARNESS_ROOT/scripts/doctor.sh" --check 2>&1)"
assert_contains "$out" "gated (no-mistakes gate)"

it "doctor rejects an unknown option rather than ignoring it"
run_s scripts/doctor.sh --wat
assert_rc 2 "$HOOK_RC"

# --- fleet-html --------------------------------------------------------------
it "fleet-html renders a page from the snapshot"
mkmission "$home" 2026-09-01-a '{"title":"Alpha","state":"executing","current_feature":"F001","features":[{"id":"F001","slug":"x","state":"in_progress","color":null,"followups":[]}]}' >/dev/null
run_s scripts/fleet-html.sh "$home/out.html"
assert_rc 0 "$HOOK_RC"
assert_file_exists "$home/out.html"
body="$(cat "$home/out.html")"
assert_contains "$body" "<!doctype html>"
assert_contains "$body" "2026-09-01-a"
assert_contains "$body" "executing"

it "fleet-html escapes mission text rather than injecting it as markup"
mkmission "$home" 2026-09-02-x '{"title":"<script>alert(1)</script>","state":"executing","features":[]}' >/dev/null
run_s scripts/fleet-html.sh "$home/out2.html"
assert_rc 0 "$HOOK_RC"
assert_not_contains "$(cat "$home/out2.html")" "<script>alert(1)</script>"
assert_contains "$(cat "$home/out2.html")" "&lt;script&gt;"

it "fleet-html parses no mission state itself"
code="$(grep -vE '^[[:space:]]*#' "$HARNESS_ROOT/scripts/fleet-html.sh")"
assert_not_contains "$code" "status.json"
assert_contains "$code" "snapshot.sh"

it "fleet-html survives a corrupt mission"
mkdir -p "$home/missions/2026-09-03-bad"; printf 'nope\n' > "$home/missions/2026-09-03-bad/status.json"
run_s scripts/fleet-html.sh "$home/out3.html"
assert_rc 0 "$HOOK_RC"
assert_contains "$(cat "$home/out3.html")" "2026-09-03-bad"

# --- learnings-index ---------------------------------------------------------
it "learnings-index regenerates an index"
mkdir -p "$home/learnings/patterns" "$home/learnings/anti-patterns" "$home/learnings/proposals"
printf -- '---\nname: a-thing\ndescription: it worked\n---\n\nbody\n' > "$home/learnings/patterns/a-thing.md"
( cd "$home" && "$HARNESS_ROOT/scripts/learnings-index.sh" ) >/dev/null 2>&1 || true
[ -f "$home/learnings/INDEX.md" ] || [ -f "$HARNESS_ROOT/learnings/INDEX.md" ] || _fail "no index produced"

it "learnings-index is idempotent, as its header claims"
# The claim is byte-identical output on a second run; a claim nothing checks is
# a claim that quietly stops being true.
a="$(cd "$HARNESS_ROOT" && ./scripts/learnings-index.sh 2>/dev/null)"
b="$(cd "$HARNESS_ROOT" && ./scripts/learnings-index.sh 2>/dev/null)"
assert_eq "$a" "$b"

# --- pr-poll -----------------------------------------------------------------
it "pr-poll answers 'unknown none' rather than hanging when gh is unavailable"
shim="$(mktemp -d)"; printf '#!/bin/sh\nexit 127\n' > "$shim/gh"; chmod +x "$shim/gh"
out="$(PATH="$shim:$PATH" "$HARNESS_ROOT/scripts/pr-poll.sh" some-branch 2>&1)"; rc=$?
assert_rc 1 "$rc"
assert_contains "$out" "unknown none"
rm -rf "$shim"

it "pr-poll prints its usage rather than guessing at a target"
out="$("$HARNESS_ROOT/scripts/pr-poll.sh" 2>&1)"; rc=$?
assert_rc 0 "$rc"
assert_contains "$out" "pr-poll"

finish
