#!/usr/bin/env bash
#
# Stop hook. Refuses to let the session end while a mission is in a state a
# human would not want left unattended:
#
#   - a red feature with no follow-up opened for it
#   - a feature stuck `in_progress` with no outcome colour and no file activity
#     for over an hour (likely an abandoned worker)
#   - a mission whose state cannot be classified at all
#
# The third case is the point of the rewrite. This guard previously read
# `.state` directly and treated anything unrecognised as "unknown", which was
# not in its skip list, so it fell through to a red-feature filter that a
# drifted-schema mission could not match. It reported "all clear" on exactly the
# missions it could not understand. State now comes from scripts/lib/status-read.sh,
# the single owner of that decision, and an unclassifiable mission BLOCKS.
#
# The stuck-feature check is age-bounded. The original header promised "more
# than 1 hour" but no age test existed, so the guard fired on every ordinary
# turn taken while a feature was in progress.
#
# Exit codes:
#   0  — allow stop
#   2  — block stop, reason on stderr (Claude shows it to the model)
#
# stdout is never written: it is reserved for hook JSON.
#
# Tuning: HARNESS_STUCK_SECONDS (default 3600).

set -uo pipefail

# CODE location vs DATA location. The library ships beside this hook in the same
# checkout, so it is resolved from BASH_SOURCE. CLAUDE_PROJECT_DIR says where the
# *missions* are, which under test is a throwaway directory with no scripts/ at
# all — sourcing the library from there would silently disable the guard.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
MISSIONS="${HARNESS_ROOT}/missions"
STUCK_SECONDS="${HARNESS_STUCK_SECONDS:-3600}"

cat > /dev/null   # drain stdin; we decide from state, not from the payload

# shellcheck source=../../scripts/lib/status-read.sh
if ! . "$CODE_ROOT/scripts/lib/status-read.sh" 2>/dev/null; then
  echo "[Stop hook] scripts/lib/status-read.sh is missing or unreadable — cannot verify mission state. Repair the checkout." >&2
  exit 2
fi

[ -d "$MISSIONS" ] || exit 0

# Portable mtime in epoch seconds; prints 0 when unavailable so a missing file
# can never look "recently active".
mtime_epoch() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || printf '0'
}

# Newest mtime across the files a live mission touches.
last_activity() {
  local dir="$1" newest=0 f t
  for f in "$dir/status.json" "$dir/log.md"; do
    [ -f "$f" ] || continue
    t="$(mtime_epoch "$f")"
    [ "$t" -gt "$newest" ] 2>/dev/null && newest="$t"
  done
  printf '%s' "$newest"
}

PROBLEMS=()
NOW="$(date -u +%s)"

shopt -s nullglob
for mission_dir in "$MISSIONS"/*/; do
  [ -d "$mission_dir" ] || continue
  id="$(basename "$mission_dir")"
  case "$id" in .*) continue ;; esac
  status_file="$mission_dir/status.json"
  [ -f "$status_file" ] || continue

  state="$(status_state "$status_file")"
  if [ "$state" = "unknown" ]; then
    PROBLEMS+=("Mission ${id}: state cannot be classified — status.json is malformed or uses an unrecognised vocabulary. Fix it or set an explicit state.")
    continue
  fi

  case "$state" in
    closed|abandoned|paused|awaiting_approval|intake) continue ;;
  esac

  reds="$(jq -r '
    .features // [] |
    map(select(.color == "red")) |
    map(select(.followups | length == 0 or any(.; . | test("^F.*-followup-")) == false)) |
    map(.id) | join(",")
  ' "$status_file" 2>/dev/null || true)"
  [ -n "$reds" ] && PROBLEMS+=("Mission ${id}: red features without follow-ups: ${reds}")

  if [ "$state" = "executing" ] || [ "$state" = "feature_loop" ]; then
    stuck="$(jq -r '
      .features // [] |
      map(select(.state == "in_progress" and .color == null)) |
      map(.id) | join(",")
    ' "$status_file" 2>/dev/null || true)"
    if [ -n "$stuck" ]; then
      last="$(last_activity "$mission_dir")"
      age=$(( NOW - last ))
      if [ "$age" -gt "$STUCK_SECONDS" ]; then
        PROBLEMS+=("Mission ${id}: feature(s) ${stuck} in progress with no outcome and no activity for $(( age / 60 )) minutes")
      fi
    fi
  fi
done

[ "${#PROBLEMS[@]}" -eq 0 ] && exit 0

{
  echo "[Stop hook] Refusing to end — unresolved mission issues:"
  for p in "${PROBLEMS[@]}"; do echo "  - $p"; done
  echo
  echo "Red features: open a follow-up, or abandon/pause the mission."
  echo "Stuck features: close the feature, or set the mission to abandoned/paused."
  echo "Unclassifiable state: repair status.json (see templates/status-schema.md)."
} >&2
exit 2
