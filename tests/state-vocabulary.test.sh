#!/usr/bin/env bash
# The state vocabulary has ONE owner (scripts/lib/state-vocabulary.json) and TWO
# lookups: bash for hooks in hot paths, Python for batch readers. This asserts
# they agree on every entry — which is what makes two implementations safe.
#
# Without this, "one owner" is an aspiration and the two would drift exactly the
# way six independent status.json parsers drifted before the snapshot layer.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"
. "$HARNESS_ROOT/scripts/lib/status-read.sh"

V="$HARNESS_ROOT/scripts/lib/state-vocabulary.json"
py() { python3 -c "
import sys; sys.path.insert(0,'$HARNESS_ROOT/scripts/lib')
import harness; print(harness.normalize_state(*sys.argv[1:4]))" "$@"; }

it "the vocabulary file is valid and non-empty"
jq -e '.canonical | length > 0' "$V" >/dev/null 2>&1; assert_rc 0 $?
jq -e '.from_status | length > 0' "$V" >/dev/null 2>&1; assert_rc 0 $?

it "bash and python agree on every canonical state"
while IFS= read -r s; do
  [ -n "$s" ] || continue
  b="$(status_normalize "$s" "" "")"
  p="$(py "$s" "" "")"
  [ "$b" = "$p" ] || _fail "canonical '$s': bash=$b python=$p"
  [ "$b" = "$s" ] || _fail "canonical '$s' did not pass through: got $b"
done < <(jq -r '.canonical[]' "$V")

it "bash and python agree on every drifted .status value"
while IFS=$'\t' read -r k v; do
  [ -n "$k" ] || continue
  b="$(status_normalize "" "$k" "")"
  p="$(py "" "$k" "")"
  [ "$b" = "$p" ] || _fail ".status '$k': bash=$b python=$p"
  [ "$b" = "$v" ] || _fail ".status '$k': expected $v, bash gave $b"
done < <(jq -r '.from_status | to_entries[] | [.key, .value] | @tsv' "$V")

it "bash and python agree on every drifted .phase value"
while IFS=$'\t' read -r k v; do
  [ -n "$k" ] || continue
  b="$(status_normalize "" "" "$k")"
  p="$(py "" "" "$k")"
  [ "$b" = "$p" ] || _fail ".phase '$k': bash=$b python=$p"
  [ "$b" = "$v" ] || _fail ".phase '$k': expected $v, bash gave $b"
done < <(jq -r '.from_phase | to_entries[] | [.key, .value] | @tsv' "$V")

it "both refuse the same unknown values"
for junk in banana "" "in progress" CLOSED; do
  b="$(status_normalize "$junk" "" "")"; p="$(py "$junk" "" "")"
  [ "$b" = "$p" ] || _fail "junk '$junk': bash=$b python=$p"
  assert_eq "unknown" "$b"
done

it "both prefer .state over the drifted fields"
assert_eq "paused" "$(status_normalize paused in-progress feature-loop)"
assert_eq "paused" "$(py paused in-progress feature-loop)"

it "both treat the same states as terminal"
while IFS= read -r s; do
  [ -n "$s" ] || continue
  python3 -c "
import sys; sys.path.insert(0,'$HARNESS_ROOT/scripts/lib')
import harness; sys.exit(0 if not harness.is_active('$s') else 1)" \
    || _fail "python thinks terminal state '$s' is active"
done < <(jq -r '.terminal[]' "$V")

it "python treats unknown as not-active, matching the snapshot contract"
python3 -c "
import sys; sys.path.insert(0,'$HARNESS_ROOT/scripts/lib')
import harness; sys.exit(0 if not harness.is_active('unknown') else 1)"
assert_rc 0 $?

finish
