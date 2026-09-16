#!/usr/bin/env bash
# The no-mistakes gate. `no-mistakes` is a per-project devDependency, so these
# drive a stub at the exact path the real one occupies
# (node_modules/.bin/no-mistakes) and speak the real report contract, taken
# from the published package's check-report-types.d.ts and verified against
# no-mistakes@0.61.2 -- see docs/verification/no-mistakes-gate.md.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/gate.sh"

home="$(mktmphome)"
mkroot() {  # <name> ; prints the root
  local r="$home/$1"; mkdir -p "$r/node_modules/.bin"; printf '%s' "$r"
}
# <root> <configPath-or-empty> <check-json>
stub() {
  local r="$1" cfg="$2" report="$3"
  cat > "$r/node_modules/.bin/no-mistakes" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "config resolve") printf '%s\n' '{"configPath":${cfg:-null}}' ;;
  "check "*|"check") printf '%s\n' '$report' ;;
esac
STUB
  chmod +x "$r/node_modules/.bin/no-mistakes"
}
CLEAN='{"react":[],"queues":[],"rules":[],"integration":[],"codebase":[],"advisories":[],"warnings":[]}'

it "reports no gate when the project has not installed the tool"
r="$(mkroot plain)"
gate_available "$r"; assert_rc 1 $?
gate_run "$r" >/dev/null 2>&1; assert_rc 2 $?

it "refuses to call an UNCONFIGURED project gated, even with the tool present"
# This is the whole point. `no-mistakes check` with no config reports empty
# findings and exits 0, so a gate wired straight to it can never fail --
# which would look exactly like verification that never happened.
r="$(mkroot unconfigured)"; stub "$r" "" "$CLEAN"
gate_available "$r"; assert_rc 1 $?
gate_run "$r" >/dev/null 2>&1; assert_rc 2 $?

it "passes a configured project with no findings"
r="$(mkroot clean)"; stub "$r" '".no-mistakes.json"' "$CLEAN"
gate_available "$r"; assert_rc 0 $?
gate_run "$r" >/dev/null 2>&1; assert_rc 0 $?

it "blocks on a finding in any blocking domain"
for d in react queues rules integration codebase; do
  r="$(mkroot "blk-$d")"
  stub "$r" '".no-mistakes.json"' \
    "$(printf '{"react":[],"queues":[],"rules":[],"integration":[],"codebase":[],"advisories":[],"warnings":[],"%s":[{"rule":"r1","file":"src/a.ts","line":3,"message":"nope"}]}' "$d")"
  gate_run "$r" >/dev/null 2>&1
  assert_rc 1 $? 
done

it "names the domain, file and line so the finding can be acted on"
r="$(mkroot named)"
stub "$r" '".no-mistakes.json"' \
  '{"react":[],"queues":[],"integration":[],"codebase":[],"advisories":[],"warnings":[],"rules":[{"rule":"no-cross-import","file":"src/a.ts","line":3,"message":"nope"}]}'
out="$(gate_run "$r" 2>&1)"
assert_contains "$out" "rules:"
assert_contains "$out" "no-cross-import"
assert_contains "$out" "src/a.ts:3"

it "does not block on advisories or warnings"
# They are the tool's non-blocking channel; treating them as failures would
# make the gate unusable and train the operator to override it.
r="$(mkroot advisory)"
stub "$r" '".no-mistakes.json"' \
  '{"react":[],"queues":[],"rules":[],"integration":[],"codebase":[],"advisories":[{"rule":"a","file":"f","line":1,"message":"m"}],"warnings":["heads up"]}'
out="$(gate_run "$r" 2>&1)"; assert_rc 0 $?
assert_contains "$out" "heads up"

it "treats an unreadable report as no gate, never as a pass"
r="$(mkroot garbage)"; stub "$r" '".no-mistakes.json"' 'not json at all'
gate_run "$r" >/dev/null 2>&1; assert_rc 2 $?

it "treats an empty report as no gate, never as a pass"
r="$(mkroot silent)"
cat > "$r/node_modules/.bin/no-mistakes" <<'STUB'
#!/usr/bin/env bash
[ "$1 $2" = "config resolve" ] && printf '{"configPath":".no-mistakes.json"}\n'
STUB
chmod +x "$r/node_modules/.bin/no-mistakes"
gate_run "$r" >/dev/null 2>&1; assert_rc 2 $?

it "never fetches the tool it gates with"
# A gate that downloads its own implementation at delivery time, over the
# network, is not a gate.
# Comments stripped: the file discusses npm install in prose, deliberately.
src="$(grep -v '^[[:space:]]*#' "$HARNESS_ROOT/scripts/lib/gate.sh")"
assert_not_contains "$src" "npx"
assert_not_contains "$src" "npm "

finish
