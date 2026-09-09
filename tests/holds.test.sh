#!/usr/bin/env bash
# Tests for scripts/lib/holds.sh and scripts/hold.sh — durable decision holds.
#
# A blocking question to the captain is a FILE, not a conversational turn. A
# question asked in prose is lost to a restart or a context compaction; a
# question on disk is reconciled at every session start. This is the mechanism
# the captain already hand-rolled as `open_questions` and `user_actions` in one
# mission's status.json.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/holds.sh"

home="$(mktmphome)"
hold() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/hold.sh" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}
mkmission "$home" m-one '{"state":"executing","features":[]}' >/dev/null
mkmission "$home" m-two '{"state":"executing","features":[]}' >/dev/null
DEC="$home/missions/m-one/decisions"

it "reports no open holds before anything is filed"
hold list
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "No open decisions"

it "opens a blocking hold and gives it an id"
hold open m-one --question "Ship as A or B?" --options "A,B" --recommend "A — smaller diff"
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "DH-001"
assert_file_exists "$DEC/DH-001.json"

it "records the question, options and recommendation"
body="$(cat "$DEC/DH-001.json")"
assert_contains "$body" "Ship as A or B?"
assert_contains "$body" "smaller diff"
assert_eq "true" "$(jq -r '.blocking' "$DEC/DH-001.json")"
assert_eq "m-one" "$(jq -r '.mission_id' "$DEC/DH-001.json")"
assert_eq "null"  "$(jq -r '.answer' "$DEC/DH-001.json")"

it "lists an open hold with its mission"
hold list
assert_contains "$HOOK_OUT" "DH-001"
assert_contains "$HOOK_OUT" "m-one"
assert_contains "$HOOK_OUT" "Ship as A or B?"

it "numbers holds per mission, so ids do not collide across missions"
hold open m-two --question "Second mission question"
assert_contains "$HOOK_OUT" "DH-001"
assert_file_exists "$home/missions/m-two/decisions/DH-001.json"

it "opens a second hold in the same mission with the next id"
hold open m-one --question "Another one"
assert_contains "$HOOK_OUT" "DH-002"

it "refuses a hold with no question"
hold open m-one --question ""
assert_rc 2 "$HOOK_RC"

it "refuses a hold for a mission that does not exist"
hold open no-such-mission --question "hello"
assert_rc 2 "$HOOK_RC"

it "supports an advisory (non-blocking) hold"
hold open m-one --question "Worth doing later?" --advisory
assert_rc 0 "$HOOK_RC"
assert_eq "false" "$(jq -r '.blocking' "$DEC/DH-003.json")"

it "counts only BLOCKING holds as things that stop work"
assert_eq "2" "$(holds_count_blocking "$home/missions/m-one")"
assert_eq "3" "$(holds_count_open "$home/missions/m-one")"

it "answering moves the hold out of the open set"
hold answer m-one DH-001 "A"
assert_rc 0 "$HOOK_RC"
assert_file_missing "$DEC/DH-001.json"
assert_file_exists "$DEC/answered/DH-001.json"
assert_eq "A" "$(jq -r '.answer' "$DEC/answered/DH-001.json")"
assert_contains "$(jq -r '.answered_at' "$DEC/answered/DH-001.json")" "20"

it "an answered hold no longer appears as open"
hold list
assert_not_contains "$HOOK_OUT" "Ship as A or B?"

it "an answered hold can still be shown by id"
hold show m-one DH-001
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "A"

it "refuses to answer a hold that is not open"
hold answer m-one DH-001 "again"
assert_rc 2 "$HOOK_RC"
hold answer m-one DH-999 "nope"
assert_rc 2 "$HOOK_RC"

it "refuses an empty answer rather than recording silence as a decision"
hold answer m-one DH-002 ""
assert_rc 2 "$HOOK_RC"

it "counting open holds is a file count, so the snapshot stays cheap"
# Answered holds move to a subdirectory rather than being rewritten in place,
# so snapshot.sh counts open decisions without parsing any of them.
assert_eq "2" "$(holds_count_open "$home/missions/m-one")"
assert_eq "0" "$(holds_count_open "$home/missions/nonexistent")"

it "survives a corrupt hold file without hiding the others"
printf 'not json\n' > "$DEC/DH-009.json"
hold list
assert_rc 0 "$HOOK_RC"
assert_contains "$HOOK_OUT" "Another one"
assert_contains "$HOOK_OUT" "unreadable"

finish
