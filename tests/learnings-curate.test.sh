#!/usr/bin/env bash
# Tests for scripts/learnings-curate.sh — the lifecycle learnings/ never had.
#
# The corpus had taxonomy, frontmatter and an index, but no concept of AGE:
# nothing aged out, nothing capped growth, and everything loaded into planning
# forever. The refusals matter more than the tiering.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
mkdir -p "$home/learnings/patterns" "$home/learnings/anti-patterns" "$home/learnings/proposals"

# shellcheck disable=SC2120  # optional passthrough args
cur() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/learnings-curate.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
old_entry() {  # <kind> <slug> [extra-body]
  local f="$home/learnings/$1/$2.md"
  printf '# %s\n\n%s\n' "$2" "${3:-body}" > "$f"
  if date -u -d "@0" >/dev/null 2>&1; then ts="$(date -u -d "@$(( $(date +%s) - 200*86400 ))" +%Y%m%d%H%M.%S)"
  else ts="$(date -u -r "$(( $(date +%s) - 200*86400 ))" +%Y%m%d%H%M.%S)"; fi
  touch -t "$ts" "$f"
}
fresh_entry() { printf '# %s\n\nbody\n' "$2" > "$home/learnings/$1/$2.md"; }

it "reports an empty corpus without erroring"
cur
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "0 entries"

it "a recently written entry is warm, not cold"
fresh_entry patterns new-thing
cur
assert_contains "$HOOK_OUT" "warm   patterns"

it "an old, unreferenced entry is cold"
old_entry patterns ancient-thing
cur
assert_contains "$HOOK_OUT" "cold   patterns"

it "an entry named in a recent mission is hot, however old the file is"
mkmission "$home" 2026-09-01-recent '{"state":"executing","features":[]}' >/dev/null
printf 'we applied ancient-thing here\n' > "$home/missions/2026-09-01-recent/log.md"
cur
assert_contains "$HOOK_OUT" "hot    patterns"

it "an old entry with a recurrence log is warm — it keeps happening"
old_entry patterns keeps-happening '## Recurrence log

- **2026-01-01** — saw it again.'
cur
assert_contains "$HOOK_OUT" "warm   patterns"

it "stays quiet while the corpus is within budget"
cur
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "Within budget"

it "proposes archival when over budget, and moves nothing"
for i in 1 2 3 4 5; do old_entry patterns "filler-$i"; done
before="$(find "$home/learnings/patterns" -name '*.md' | wc -l | tr -d ' ')"
CLAUDE_PROJECT_DIR="$home" HARNESS_LEARNINGS_BUDGET=3 "$HARNESS_ROOT/scripts/learnings-curate.sh" > /tmp/c1.out 2>&1
assert_contains "$(cat /tmp/c1.out)" "OVER BUDGET"
assert_contains "$(cat /tmp/c1.out)" "Proposed for archival"
assert_contains "$(cat /tmp/c1.out)" "Nothing has been moved"
assert_eq "$before" "$(find "$home/learnings/patterns" -name '*.md' | wc -l | tr -d ' ')"

it "never proposes an anti-pattern, however cold"
old_entry anti-patterns old-trap
CLAUDE_PROJECT_DIR="$home" HARNESS_LEARNINGS_BUDGET=3 "$HARNESS_ROOT/scripts/learnings-curate.sh" > /tmp/c2.out 2>&1
assert_not_contains "$(sed -n '/Proposed for archival/,$p' /tmp/c2.out)" "old-trap"

it "--apply archives rather than deletes, and only the proposed count"
CLAUDE_PROJECT_DIR="$home" HARNESS_LEARNINGS_BUDGET=3 "$HARNESS_ROOT/scripts/learnings-curate.sh" --apply > /tmp/c3.out 2>&1
assert_contains "$(cat /tmp/c3.out)" "Nothing was deleted"
[ "$(find "$home/learnings/archive" -name '*.md' | wc -l | tr -d ' ')" -gt 0 ] || _fail "nothing was archived"
assert_file_exists "$home/learnings/anti-patterns/old-trap.md"

it "refuses to trim when every cold entry is an anti-pattern"
home2="$(mktmphome)"
mkdir -p "$home2/learnings/anti-patterns" "$home2/learnings/patterns" "$home2/learnings/proposals"
for i in 1 2 3 4; do
  f="$home2/learnings/anti-patterns/trap-$i.md"; printf '# trap\n' > "$f"
  if date -u -d "@0" >/dev/null 2>&1; then ts="$(date -u -d "@$(( $(date +%s) - 200*86400 ))" +%Y%m%d%H%M.%S)"
  else ts="$(date -u -r "$(( $(date +%s) - 200*86400 ))" +%Y%m%d%H%M.%S)"; fi
  touch -t "$ts" "$f"
done
CLAUDE_PROJECT_DIR="$home2" HARNESS_LEARNINGS_BUDGET=1 "$HARNESS_ROOT/scripts/learnings-curate.sh" > /tmp/c4.out 2>&1; rc=$?
assert_rc 3 "$rc"
assert_contains "$(cat /tmp/c4.out)" "needs a human decision"

finish
