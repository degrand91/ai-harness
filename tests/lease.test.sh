#!/usr/bin/env bash
# Tests for scripts/lease.sh — named leases per resource.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
lease() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/lease.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

it "reports nothing leased to begin with"
lease list
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "no leases"

it "claims a free resource"
lease claim worktree-alpha --actor supervisor
assert_rc 0 "$HOOK_RC"
lease check worktree-alpha
assert_contains "$HOOK_OUT" "supervisor"
assert_contains "$HOOK_OUT" "live"

it "refuses a resource held by someone else"
lease claim worktree-alpha --actor validator
assert_rc 6 "$HOOK_RC"
assert_contains "$HOOK_OUT" "held by supervisor"

it "lets the holder re-claim its own lease"
lease claim worktree-alpha --actor supervisor
assert_rc 0 "$HOOK_RC"

it "keeps separate resources separate"
lease claim worktree-beta --actor validator
assert_rc 0 "$HOOK_RC"
lease list
assert_contains "$HOOK_OUT" "worktree-alpha"
assert_contains "$HOOK_OUT" "worktree-beta"

it "refuses to release a lease held by someone else"
lease release worktree-alpha --actor validator
assert_rc 6 "$HOOK_RC"
assert_contains "$HOOK_OUT" "refusing to release"

it "releases a lease the actor holds"
lease release worktree-alpha --actor supervisor
assert_rc 0 "$HOOK_RC"
lease check worktree-alpha
assert_rc 1 "$HOOK_RC"

it "reports an expired lease as stale and lets it be taken"
# A crashed process must not wedge a resource until a human notices.
lease claim short-lived --actor a --ttl 0
lease check short-lived
assert_contains "$HOOK_OUT" "stale"
lease claim short-lived --actor b
assert_rc 0 "$HOOK_RC"

it "treats a lease whose pid is dead as stale"
CLAUDE_PROJECT_DIR="$home" python3 -c "
import json,sys,os,time
p=os.path.join('$home','state','leases','ghost.lease')
json.dump({'resource':'ghost','actor':'gone','pid':999999,
           'expires_epoch':int(time.time())+9999,'claimed_at':'x'}, open(p,'w'))"
lease check ghost
assert_contains "$HOOK_OUT" "stale"
lease claim ghost --actor live-one
assert_rc 0 "$HOOK_RC"

it "sweep drops stale leases and keeps live ones"
lease claim keeper --actor me
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/lease.sh" claim goner --actor me --ttl 0 >/dev/null 2>&1
lease sweep
assert_rc 0 "$HOOK_RC"
lease check keeper
assert_contains "$HOOK_OUT" "live"
lease check goner
assert_rc 1 "$HOOK_RC"

it "refuses a resource name that could escape the lease directory"
lease claim "../evil" --actor me
assert_rc 2 "$HOOK_RC"
lease claim "a/b" --actor me
assert_rc 2 "$HOOK_RC"

it "reports no such lease rather than inventing one"
lease check never-claimed
assert_rc 1 "$HOOK_RC"
lease release never-claimed --actor me
assert_rc 1 "$HOOK_RC"

finish
