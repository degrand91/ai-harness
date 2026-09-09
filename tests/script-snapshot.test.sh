#!/usr/bin/env bash
# Tests for scripts/snapshot.sh — the single owner of reading fleet state.
#
# Six renderers used to parse status.json independently (38 jq call sites);
# schema drift went unnoticed in all of them. Everything now reads this one
# stable JSON contract, and the contract's shape is what these tests pin.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
# shellcheck disable=SC2120  # optional passthrough args; callers use none today
snap() {
  local outf; outf="$(mktemp)"
  HOOK_RC=0
  CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/snapshot.sh" "$@" >"$outf" 2>/dev/null || HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"; rm -f "$outf"
  export HOOK_OUT HOOK_RC
}
q() { printf '%s' "$HOOK_OUT" | jq -r "$1" 2>/dev/null; }

it "emits valid JSON with no missions at all"
snap
assert_rc 0 "$HOOK_RC"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?
assert_eq "0" "$(q '.missions | length')"

it "carries a schema version so consumers can detect a breaking change"
assert_eq "1" "$(q '.schema')"

it "reports a mission with its normalised state and features"
mkmission "$home" 2026-08-01-alpha '{"mission_id":"2026-08-01-alpha","title":"Alpha","state":"executing","current_feature":"F002","target_repo":"/p/alpha","features":[{"id":"F001","slug":"one","state":"closed","color":"green","followups":[]},{"id":"F002","slug":"two","state":"in_progress","color":null,"followups":[]}]}' >/dev/null
snap
assert_eq "1" "$(q '.missions | length')"
assert_eq "2026-08-01-alpha" "$(q '.missions[0].id')"
assert_eq "executing"        "$(q '.missions[0].state')"
assert_eq "Alpha"            "$(q '.missions[0].title')"
assert_eq "F002"             "$(q '.missions[0].current_feature')"
assert_eq "2"                "$(q '.missions[0].features | length')"
assert_eq "green"            "$(q '.missions[0].features[0].color')"

it "normalises a drifted-schema mission like every other consumer"
mkmission "$home" 2026-08-02-drift '{"status":"in-progress","phase":"feature-loop","features":[]}' >/dev/null
snap
assert_eq "executing" "$(q '.missions[] | select(.id=="2026-08-02-drift") | .state')"

it "marks an unclassifiable mission rather than dropping it"
mkdir -p "$home/missions/2026-08-03-bad"
printf 'not json\n' > "$home/missions/2026-08-03-bad/status.json"
snap
assert_eq "unknown" "$(q '.missions[] | select(.id=="2026-08-03-bad") | .state')"

it "flags whether a mission is active"
snap
assert_eq "true"  "$(q '.missions[] | select(.id=="2026-08-01-alpha") | .active')"
mkmission "$home" 2026-08-04-done '{"state":"closed","features":[]}' >/dev/null
snap
assert_eq "false" "$(q '.missions[] | select(.id=="2026-08-04-done") | .active')"

it "orders missions newest-activity first"
# Assert the CONTRACT (descending last_activity), not a particular fixture:
# fixtures written in the same second have no defined relative order, and
# pinning one is how a test passes by luck until it does not.
snap
ordered="$(printf '%s' "$HOOK_OUT" | jq -r '[.missions[].last_activity] | . as $a | ($a == ($a | sort | reverse))')"
assert_eq "true" "$ordered"

it "reports last activity as an epoch"
snap
last="$(q '.missions[0].last_activity')"
case "$last" in ''|*[!0-9]*) _fail "last_activity not numeric: [$last]" ;; esac
[ "$last" -gt "$(( $(date -u +%s) - 600 ))" ] || _fail "last_activity implausibly old"

it "rolls spend up per mission and for the fleet"
mkmission "$home" 2026-08-05-spend '{"state":"executing","features":[],"tokens":{"workers":{"input":100,"output":20},"scrutiny":{"input":50,"output":10}}}' >/dev/null
snap
assert_eq "150" "$(q '.missions[] | select(.id=="2026-08-05-spend") | .tokens.input')"
assert_eq "30"  "$(q '.missions[] | select(.id=="2026-08-05-spend") | .tokens.output')"
assert_eq "150" "$(q '.totals.tokens.input')"

it "includes registered projects and links missions to them by path"
mkdir -p "$home/repo-alpha" && git -C "$home/repo-alpha" init -q 2>/dev/null
CLAUDE_PROJECT_DIR="$home" "$HARNESS_ROOT/scripts/project.sh" add alpha "$home/repo-alpha" --mode no-mistakes >/dev/null 2>&1
python3 - "$home" <<'PY'
import json,sys,pathlib
p = pathlib.Path(sys.argv[1])/"missions"/"2026-08-01-alpha"/"status.json"
d = json.loads(p.read_text()); d["target_repo"] = str(pathlib.Path(sys.argv[1])/"repo-alpha")
p.write_text(json.dumps(d))
PY
snap
assert_eq "1"     "$(q '.projects | length')"
assert_eq "alpha" "$(q '.projects[0].name')"
assert_eq "no-mistakes" "$(q '.projects[0].mode')"
assert_eq "alpha" "$(q '.missions[] | select(.id=="2026-08-01-alpha") | .project')"

it "leaves project null for a mission whose repo is not registered"
assert_eq "null" "$(q '.missions[] | select(.id=="2026-08-02-drift") | .project')"

it "counts open decision holds (Phase 2 populates them; zero until then)"
snap
assert_eq "0" "$(q '.totals.open_holds')"

it "keeps the raw fields aligned when .state is empty"
# Regression guard for the delimiter trap: with @tsv, `read` collapses the empty
# .state field and slides .target_repo one slot left, so a drifted mission reads
# as unknown and loses its project link. Both are asserted elsewhere; this
# checks the specific shape that breaks.
mkmission "$home" 2026-08-06-empty '{"state":"","status":"in-progress","phase":"","target_repo":"/p/empty","features":[]}' >/dev/null
snap
assert_eq "executing" "$(q '.missions[] | select(.id=="2026-08-06-empty") | .state')"

it "spawns no subprocess per mission at all"
# The bash implementation batched jq to keep the count constant. The Python one
# reads the files directly, so the stronger property now holds: reading the
# fleet costs the same whether it has one mission or forty. Measured by
# shimming every external tool the old version reached for.
count_procs() {  # <harness-home>
  local shim log n; shim="$(mktemp -d)"; log="$shim/calls"; : > "$log"
  local tool
  for tool in jq stat git; do
    printf '#!/bin/sh\necho %s >> %s\nexec /usr/bin/env -i PATH=/usr/bin:/bin %s "$@"\n' \
      "$tool" "$log" "$tool" > "$shim/$tool"
    chmod +x "$shim/$tool"
  done
  CLAUDE_PROJECT_DIR="$1" PATH="$shim:$PATH" "$HARNESS_ROOT/scripts/snapshot.sh" >/dev/null 2>&1
  n="$(wc -l < "$log" | tr -d ' ')"
  rm -rf "$shim"
  printf '%s' "$n"
}
small="$(mktmphome)"
mkmission "$small" 2026-08-10-one '{"state":"executing","features":[]}' >/dev/null
big="$(mktmphome)"
for i in $(seq 10 49); do
  mkmission "$big" "2026-08-$i-bulk" '{"state":"executing","features":[]}' >/dev/null
done
n_small="$(count_procs "$small")"
n_big="$(count_procs "$big")"
assert_eq "$n_small" "$n_big"
[ "$n_small" -le 2 ] || _fail "a 1-mission fleet spawned $n_small subprocess(es)"

it "a corrupt mission costs nothing extra"
# The bash version retried a jq pass per corrupt file. Reading files directly
# means a parse failure is just a None, with no recovery pass to pay for.
mkdir -p "$big/missions/2026-08-99-corrupt"
printf 'not json\n' > "$big/missions/2026-08-99-corrupt/status.json"
mkdir -p "$big/missions/2026-08-98-corrupt"
printf '{ also not json\n' > "$big/missions/2026-08-98-corrupt/status.json"
assert_eq "$n_big" "$(count_procs "$big")"

it "still reports every healthy mission when some are corrupt"
snap_big() {
  HOOK_OUT="$(CLAUDE_PROJECT_DIR="$big" "$HARNESS_ROOT/scripts/snapshot.sh" 2>/dev/null)"
  export HOOK_OUT
}
snap_big
assert_eq "40" "$(printf '%s' "$HOOK_OUT" | jq -r '[.missions[] | select(.state=="executing")] | length')"
assert_eq "2"  "$(printf '%s' "$HOOK_OUT" | jq -r '.totals.unparsed')"

it "renders 40 missions well inside the watcher's budget"
for i in $(seq 10 49); do
  mkmission "$home" "2026-09-$i-bulk" '{"state":"executing","features":[{"id":"F001","slug":"x","state":"closed","color":"green","followups":[]}],"tokens":{"workers":{"input":10,"output":1}}}' >/dev/null
done
start="$(date +%s)"
snap
elapsed=$(( $(date +%s) - start ))
assert_rc 0 "$HOOK_RC"
[ "$(q '.missions | length')" -ge 40 ] || _fail "expected >= 40 missions"
[ "$elapsed" -le 2 ] || _fail "snapshot took ${elapsed}s on 40+ missions (budget: well under 2s)"

it "still emits valid JSON with a corrupt mission in a large fleet"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1; assert_rc 0 $?

it "reports a live crewmate, reading its outcome from the ledger not its last line"
# pid 1 always exists; kill -0 on it either succeeds or raises EPERM, and
# EPERM still means alive — same contract crew.sh's `kill -0` relies on.
printf '{"task":"F900","mission":"2026-08-01-alpha","project":"alpha","runner_pid":"1"}' > "$home/state/F900.meta"
printf '%s\n%s\n%s\n' \
  '2026-08-01T00:00:00Z started: ' \
  '2026-08-01T00:01:00Z done: shipped it' \
  '2026-08-01T00:01:01Z idle: ' > "$home/state/F900.ledger"
snap
assert_eq "1"                "$(q '.crew | length')"
assert_eq "F900"             "$(q '.crew[0].task')"
assert_eq "2026-08-01-alpha" "$(q '.crew[0].mission')"
assert_eq "alpha"            "$(q '.crew[0].project')"
assert_eq "done"             "$(q '.crew[0].outcome')"
assert_eq "true"             "$(q '.crew[0].alive')"
assert_eq "1"                "$(q '.totals.crew.total')"
assert_eq "1"                "$(q '.totals.crew.live')"

it "reports null outcome for a crewmate that never reached a terminal line, and a dead runner as not alive"
printf '{"task":"F901","mission":"2026-08-01-alpha","project":"alpha","runner_pid":"999999"}' > "$home/state/F901.meta"
printf '2026-08-01T00:00:00Z progress: still going\n' > "$home/state/F901.ledger"
snap
assert_eq "2"    "$(q '.crew | length')"
assert_eq "null" "$(q '.crew[] | select(.task=="F901") | .outcome')"
assert_eq "false" "$(q '.crew[] | select(.task=="F901") | .alive')"
assert_eq "2"    "$(q '.totals.crew.total')"
assert_eq "1"    "$(q '.totals.crew.live')"

it "spawns no subprocess per crewmate either"
rm -f "$small/state"/*.meta "$small/state"/*.ledger 2>/dev/null
printf '{"task":"F800","mission":"m","project":"p","runner_pid":"1"}' > "$small/state/F800.meta"
printf '2026-08-01T00:00:00Z done: x\n' > "$small/state/F800.ledger"
n_small_crew="$(count_procs "$small")"
assert_eq "$n_small" "$n_small_crew"

finish
