#!/usr/bin/env bash
# Tests for scripts/inbox.sh — the out-of-band capture surface.
#
# Four subcommands that it would be natural to merge into one, and must not be
# (fm-inbox.sh:1-27). `note` is durable and will wake the orchestrator once;
# `status` reads durable records only and is safe to poll; `ask` answers a side
# question and must never become fleet work; `drain` presents and acknowledges.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
inbox() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/inbox.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
# `grep -c .` prints 0 AND exits 1 when there are no matches, so a trailing
# `|| echo 0` emits it twice. Count with wc instead.
note_count() { find "$home/data/inbox" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

it "reports an empty inbox without erroring"
inbox list
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "empty"

it "captures a note durably"
inbox note "check the flaky login test"
assert_rc 0 "$HOOK_RC"
assert_eq "1" "$(note_count)"
inbox list
assert_contains "$HOOK_OUT" "flaky login test"

it "gives each note an id that is shown to the user"
inbox note "second idea"
inbox list
assert_contains "$HOOK_OUT" "N002"
assert_eq "2" "$(note_count)"

it "accepts a note on stdin so long text needs no quoting"
printf 'a much longer thought\nacross two lines\n' | \
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/inbox.sh" note - >/dev/null 2>&1
assert_eq "3" "$(note_count)"
inbox list
assert_contains "$HOOK_OUT" "much longer thought"

it "refuses an empty note rather than filing a blank record"
inbox note ""
assert_rc 2 "$HOOK_RC"
assert_eq "3" "$(note_count)"

it "drain shows pending notes without acknowledging them"
inbox drain
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "flaky login test"
assert_eq "3" "$(note_count)"

it "acknowledging a note archives it"
inbox drain --ack N001
assert_rc 0 "$HOOK_RC"
assert_eq "2" "$(note_count)"
assert_file_exists "$home/data/inbox/archive/N001.json"
inbox list
assert_not_contains "$HOOK_OUT" "flaky login test"

it "refuses to acknowledge a note that does not exist"
inbox drain --ack N999
assert_rc 2 "$HOOK_RC"

it "acknowledges several notes at once"
inbox drain --ack N002 N003
assert_rc 0 "$HOOK_RC"
assert_eq "0" "$(note_count)"

it "status answers from durable records and writes nothing"
inbox note "a fresh one"
before="$(ls -l "$home/data/inbox" | wc -l)"
inbox status
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "1 note"
assert_eq "$before" "$(ls -l "$home/data/inbox" | wc -l)"

it "status is safe to run repeatedly"
inbox status; first="$HOOK_OUT"
inbox status
assert_eq "$first" "$HOOK_OUT"

it "ask never touches the inbox"
before="$(note_count)"
inbox ask "what is 2 + 2" --dry-run
assert_rc 0 "$HOOK_RC"
assert_eq "$before" "$(note_count)"
assert_contains "$HOOK_OUT" "would ask"

it "ask refuses an empty question"
inbox ask "" --dry-run
assert_rc 2 "$HOOK_RC"

it "records who captured a note and when"
body="$(cat "$home/data/inbox/N004.json")"
assert_contains "$body" "created_at"
assert_contains "$body" "a fresh one"

it "survives a corrupt note file without losing the others"
printf 'not json\n' > "$home/data/inbox/N999.json"
inbox list
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "a fresh one"
assert_contains "$HOOK_OUT" "unreadable"

finish
