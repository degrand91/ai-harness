#!/usr/bin/env bash
# Tests for scripts/lib/registry.sh — the single owner of the project registry.
#
# The registry records the CAPTAIN'S STANDING POSTURE for a project. It never
# answers "how does this task ship" — that is decided per task at intake and
# passed explicitly. Keeping those separate is what lets a task deviate with a
# logged reason instead of silently rewriting the registry.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/registry.sh"

home="$(mktmphome)"
REG="$home/data/projects.md"

cat > "$REG" <<'REGISTRY'
# Projects

Registered delivery postures. One line per project.

- mobile-app [no-mistakes] ~/projects/mobile-app allow="bun *, npx expo *" - the flagship app (added 2026-05-21)
- forked-lib [direct-PR +yolo] /abs/path/forked-lib allow="cargo *" - fork mirroring (added 2026-06-02)
- harness [local-only] ~/projects/harness - this repo (added 2026-09-09)
REGISTRY

# --- reading a registered project -------------------------------------------
it "resolves mode, yolo and path for a project"
assert_eq "no-mistakes off $HOME/projects/mobile-app" "$(registry_resolve "$REG" mobile-app)"

it "reads the +yolo flag and an absolute path"
assert_eq "direct-PR on /abs/path/forked-lib" "$(registry_resolve "$REG" forked-lib)"

it "handles a project with no allow= field"
assert_eq "local-only off $HOME/projects/harness" "$(registry_resolve "$REG" harness)"

it "expands ~ to the home directory"
assert_contains "$(registry_resolve "$REG" mobile-app)" "$HOME/projects/mobile-app"

it "returns each field individually"
assert_eq "no-mistakes"                 "$(registry_mode  "$REG" mobile-app)"
assert_eq "off"                         "$(registry_yolo  "$REG" mobile-app)"
assert_eq "$HOME/projects/mobile-app"   "$(registry_path  "$REG" mobile-app)"
assert_eq "bun *, npx expo *"           "$(registry_allow "$REG" mobile-app)"
assert_eq ""                            "$(registry_allow "$REG" harness)"

it "lists every registered project name"
listing="$(registry_list "$REG")"
assert_contains "$listing" "mobile-app"
assert_contains "$listing" "forked-lib"
assert_contains "$listing" "harness"

it "finds a project by its path, for matching a mission's target_repo"
assert_eq "forked-lib" "$(registry_by_path "$REG" /abs/path/forked-lib)"
assert_eq "mobile-app" "$(registry_by_path "$REG" "$HOME/projects/mobile-app")"

# --- refusals: an unregistered project is never given a default -------------
it "refuses an unregistered project rather than assuming a posture"
out="$(registry_resolve "$REG" no-such-project)"; rc=$?
assert_rc 1 "$rc"
assert_eq "" "$out"

it "refuses when the registry file does not exist"
out="$(registry_resolve "$home/data/nope.md" mobile-app)"; rc=$?
assert_rc 1 "$rc"

it "reports no match for an unknown path instead of guessing"
out="$(registry_by_path "$REG" /somewhere/else)"; rc=$?
assert_rc 1 "$rc"
assert_eq "" "$out"

# --- malformed entries fail loudly ------------------------------------------
it "refuses a line with an unrecognised mode"
bad="$home/data/bad-mode.md"
printf -- '- proj [wishful-thinking] /p - x (added 2026-01-01)\n' > "$bad"
out="$(registry_resolve "$bad" proj 2>/dev/null)"; rc=$?
assert_rc 2 "$rc"

it "refuses a line with no path"
bad2="$home/data/bad-path.md"
printf -- '- proj [no-mistakes] - x (added 2026-01-01)\n' > "$bad2"
out="$(registry_resolve "$bad2" proj 2>/dev/null)"; rc=$?
assert_rc 2 "$rc"

it "names the offending project when a line is malformed"
err="$(registry_resolve "$bad" proj 2>&1 >/dev/null)"
assert_contains "$err" "proj"

# --- registry hygiene -------------------------------------------------------
it "ignores prose, headings and blank lines"
assert_eq "3" "$(registry_list "$REG" | grep -c .)"

it "ignores a duplicate registration but reports it"
dup="$home/data/dup.md"
cat > "$dup" <<'DUP'
- proj [no-mistakes] /a - first (added 2026-01-01)
- proj [local-only] /b - second (added 2026-02-01)
DUP
out="$(registry_resolve "$dup" proj 2>/dev/null)"; rc=$?
assert_rc 2 "$rc"
err="$(registry_resolve "$dup" proj 2>&1 >/dev/null)"
assert_contains "$err" "twice"

it "treats an empty registry as no projects, not as an error"
empty="$home/data/empty.md"; : > "$empty"
assert_eq "" "$(registry_list "$empty")"
registry_list "$empty" >/dev/null; assert_rc 0 $?

# --- validation surface -----------------------------------------------------
it "validates a whole registry in one pass"
registry_validate "$REG" >/dev/null 2>&1; assert_rc 0 $?
registry_validate "$bad" >/dev/null 2>&1; assert_rc 2 $?

finish
