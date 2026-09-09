#!/usr/bin/env bash
# Tests for scripts/project.sh — the command surface over the project registry.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
proj() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"
  export HOOK_OUT HOOK_RC
}

# A real git checkout to register.
repo="$home/repo-one"; mkdir -p "$repo"; git -C "$repo" init -q 2>/dev/null
plain="$home/not-a-repo"; mkdir -p "$plain"

it "lists nothing, successfully, before anything is registered"
proj list
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "No projects registered"

it "registers a project"
proj add repo-one "$repo" --mode no-mistakes --desc "the first one"
assert_rc 0 "$HOOK_RC"
proj mode repo-one
assert_rc 0 "$HOOK_RC"
assert_eq "no-mistakes" "$HOOK_OUT"

it "resolves posture and path together"
proj resolve repo-one
assert_contains "$HOOK_OUT" "no-mistakes off $repo"

it "shows the project in the listing with its mode"
proj list
assert_contains "$HOOK_OUT" "repo-one"
assert_contains "$HOOK_OUT" "no-mistakes"

it "refuses to register the same name twice"
proj add repo-one "$repo" --mode local-only
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "already registered"

it "refuses a path that is not a git checkout"
proj add plain-dir "$plain" --mode local-only
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "git"

it "refuses a path that does not exist"
proj add ghost "$home/nowhere" --mode local-only
assert_rc 2 "$HOOK_RC"

it "refuses an unrecognised mode"
proj add repo-two "$repo" --mode wishful
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "mode"

it "records +yolo and an allow list"
repo2="$home/repo-two"; mkdir -p "$repo2"; git -C "$repo2" init -q 2>/dev/null
proj add repo-two "$repo2" --mode direct-PR --yolo --allow "cargo *, make test" --desc "second"
assert_rc 0 "$HOOK_RC"
proj resolve repo-two
assert_contains "$HOOK_OUT" "direct-PR on"
proj allow repo-two
assert_eq "cargo *, make test" "$HOOK_OUT"

it "refuses an unregistered project instead of defaulting"
proj mode never-added
assert_rc 1 "$HOOK_RC"
assert_contains "$HOOK_OUT" "not registered"

it "validates the whole registry"
proj validate
assert_rc 0 "$HOOK_RC"

it "reports a malformed registry loudly"
printf -- '- broken [nonsense] /x - y (added 2026-01-01)\n' >> "$home/data/projects.md"
proj validate
assert_rc 2 "$HOOK_RC"

it "writes a registry a human can read and edit by hand"
content="$(cat "$home/data/projects.md")"
assert_contains "$content" "# Projects"
assert_contains "$content" "- repo-one [no-mistakes]"

finish
