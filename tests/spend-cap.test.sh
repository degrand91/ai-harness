#!/usr/bin/env bash
# Tests for the daily spend cap (plan §1.2) and scout report landing (§3.7).
#
# A mission's cost_usd accumulates over its whole life, which answers "what did
# this mission cost" but not "what have I spent today" — and only a DAILY cap
# stops a runaway before it becomes a bill.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/spend.sh"
. "$HARNESS_ROOT/scripts/lib/crew.sh"

home="$(mktmphome)"
export CREW_FAKE_LOG="$home/fake.log"; : > "$CREW_FAKE_LOG"
crew() {
  local s="$1"; shift
  local outf; outf="$(mktemp)"; HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" HARNESS_CREW_BACKEND=fake \
    "$HARNESS_ROOT/scripts/crew/$s" "$@" >"$outf" 2>&1 || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"; export HOOK_OUT HOOK_RC
}

it "reports zero spend and no cap on a fresh home"
assert_eq "0" "$(spend_today "$home")"
assert_eq "" "$(spend_cap "$home")"

it "an uncapped home is never over the cap"
spend_over_cap "$home"; assert_rc 1 $?

it "records and totals a day's spend"
spend_record "$home" 0.07
spend_record "$home" 0.05
assert_eq "0.1200" "$(spend_today "$home")"

it "ignores a malformed cost rather than corrupting the total"
spend_record "$home" "lots"
assert_eq "0.1200" "$(spend_today "$home")"

it "a malformed cap is treated as no cap, not as zero"
# Zero would block every spawn for a value the operator never chose.
printf 'plenty\n' > "$home/config/spend-cap-daily"
assert_eq "" "$(spend_cap "$home")"
spend_over_cap "$home"; assert_rc 1 $?

it "is under a cap it has not reached"
printf '1.00\n' > "$home/config/spend-cap-daily"
spend_over_cap "$home"; assert_rc 1 $?

it "is over a cap it has reached"
printf '0.10\n' > "$home/config/spend-cap-daily"
spend_over_cap "$home"; assert_rc 0 $?

# --- the cap actually stops a spawn -----------------------------------------
proj="$home/p"; mkdir -p "$proj"; git -C "$proj" init -q -b main
printf 'x\n' > "$proj/a"; git -C "$proj" add -A
git -C "$proj" -c user.email=t@t -c user.name=t commit -qm init
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" add p "$proj" --mode local-only >/dev/null 2>&1
M=2026-09-09-cap
mkmission "$home" "$M" '{"state":"executing","features":[{"id":"F001","slug":"a","state":"pending","color":null,"followups":[]}]}' >/dev/null
mk() { CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/crew/brief.sh" "$M" "$1" \
  --intent <(echo i) --done <(echo d) --mode local-only --yolo off --model haiku >/dev/null 2>&1; }

it "refuses to spawn once the cap is reached"
mk F001
crew spawn.sh "$M" F001 --project p --mode local-only --yolo off
assert_rc 2 "$HOOK_RC"
assert_contains "$HOOK_OUT" "daily cap"

it "files a decision rather than only failing"
# An operator who set a cap wants to be asked, not to find work quietly stopped.
assert_eq "1" "$(ls "$home/missions/$M/decisions"/*.json 2>/dev/null | wc -l | tr -d ' ')"
assert_contains "$(cat "$home/missions/$M/decisions"/DH-001.json)" "daily cap"

it "spawns again once the cap is raised"
printf '100.00\n' > "$home/config/spend-cap-daily"
crew spawn.sh "$M" F001 --project p --mode local-only --yolo off
assert_rc 0 "$HOOK_RC"

it "teardown records the crewmate's real cost against today"
before="$(spend_today "$home")"
printf '{"input":10,"output":20,"cost_usd":0.25}\n' > "$home/state/F001.usage.json"
crew_ledger_append "$home" F001 "done" "fixture"
crew teardown.sh F001 >/dev/null 2>&1
awk -v a="$(spend_today "$home")" -v b="$before" 'BEGIN{exit !(a-b > 0.24 && a-b < 0.26)}' \
  || _fail "expected today's spend to rise by 0.25, got $before -> $(spend_today "$home")"

# --- §3.7: a scout's report is the only thing that survives it ---------------
it "scout teardown keeps the report and discards the branch"
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p));d['features'].append({'id':'S001','slug':'scout','state':'pending','color':None,'followups':[]});json.dump(d,open(p,'w'))"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/crew/brief.sh" "$M" S001 \
  --intent <(echo "find out why") --done <(echo "a report") \
  --mode local-only --yolo off --model haiku --scout >/dev/null 2>&1
crew spawn.sh "$M" S001 --project p --mode local-only --yolo off --scout
assert_rc 0 "$HOOK_RC"
printf '# Findings\n\nIt was DNS.\n' > "$home/missions/$M/briefs/S001-handoff.md"
crew_ledger_append "$home" S001 "done" "report written"
crew teardown.sh S001
assert_rc 0 "$HOOK_RC"
assert_file_exists "$home/missions/$M/reports/S001.md"
assert_contains "$(cat "$home/missions/$M/reports/S001.md")" "It was DNS"
assert_not_contains "$(git -C "$proj" branch --list 'hc/*')" "s001"

it "says so plainly when a scout wrote no report"
python3 -c "
import json;p='$home/missions/$M/status.json'
d=json.load(open(p));d['features'].append({'id':'S002','slug':'q','state':'pending','color':None,'followups':[]});json.dump(d,open(p,'w'))"
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/crew/brief.sh" "$M" S002 \
  --intent <(echo q) --done <(echo r) --mode local-only --yolo off --model haiku --scout >/dev/null 2>&1
crew spawn.sh "$M" S002 --project p --mode local-only --yolo off --scout >/dev/null 2>&1
crew_ledger_append "$home" S002 "done" "nothing written"
crew teardown.sh S002
assert_contains "$HOOK_OUT" "wrote no report"

finish
