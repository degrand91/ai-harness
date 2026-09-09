#!/usr/bin/env bash
#
# THE TURN-END GUARD. Refuses to let the session end while a mission is in a
# state a human would not want left unattended:
#
# Renamed from stop-no-red-status.sh: it long ago stopped being only a red-status
# check, and a name that describes a third of what a file does is a name that
# makes readers miss the rest.
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
# It is ALSO the primary continuity mechanism (§4.0). Once crewmates are real
# processes, nearly every wake is an event. The remaining case — the
# orchestrator ended its turn with an obvious agent-owned next step and nothing
# in flight — is an orchestrator MISTAKE, and the right response is to refuse
# that stop, not to resume it on a timer. The asyncRewake watcher's
# continuation wake is only the backstop for when this guard fails open.
#
# LOOP SAFETY: three consecutive blind-stop blocks and this fails open with one
# notification. A guard that can refuse forever is a wedged session, and a
# wedged session is worse than a loop that ran one feature too many.
#
# Tuning: HARNESS_STUCK_SECONDS (3600) · HARNESS_BLIND_STOP_LIMIT (3)
#         HARNESS_LOOP_ACTIVE_SECONDS (86400).

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
# shellcheck source=../../scripts/lib/holds.sh
. "$CODE_ROOT/scripts/lib/holds.sh" 2>/dev/null || true
if ! . "$CODE_ROOT/scripts/lib/status-read.sh" 2>/dev/null; then
  echo "[Stop hook] scripts/lib/status-read.sh is missing or unreadable — cannot verify mission state. Repair the checkout." >&2
  exit 2
fi

[ -d "$MISSIONS" ] || exit 0

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

  # `awaiting_approval` means a question was put to the captain. If no decision
  # is filed for it, the question exists only in a chat turn — and a restart or
  # a compaction erases it. Refuse the stop rather than let it evaporate.
  if [ "$state" = "awaiting_approval" ]; then
    # Recency-bounded, like the blind-stop rule below. A mission left awaiting
    # approval months ago is a housekeeping problem, not a reason to refuse
    # every stop in every future session — and a rail that fires forever on
    # something nobody is working on is a rail people turn off.
    ml="$(mission_last_activity "$mission_dir" 2>/dev/null || echo 0)"
    case "$ml" in ''|*[!0-9]*) ml=0 ;; esac
    if [ "$ml" -gt 0 ] && [ $(( NOW - ml )) -ge "${HARNESS_LOOP_ACTIVE_SECONDS:-86400}" ]; then
      continue
    fi
    if [ "$(holds_count_open "$mission_dir")" -eq 0 ] 2>/dev/null; then
      PROBLEMS+=("Mission ${id}: state is awaiting_approval but no decision is filed. File it (./scripts/hold.sh open ${id} --question \"...\") so it survives a restart, or change the mission state.")
    fi
    continue
  fi

  case "$state" in
    closed|abandoned|paused|intake) continue ;;
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
      last="$(mission_last_activity "$mission_dir")"
      # An unreadable mtime (0) means "unknown", never "ancient". Reporting a
      # mission as stale because stat failed would block every stop on a host
      # whose stat we cannot read.
      if [ "$last" -gt 0 ] 2>/dev/null; then
        age=$(( NOW - last ))
      else
        age=0
      fi
      if [ "$age" -gt "$STUCK_SECONDS" ]; then
        PROBLEMS+=("Mission ${id}: feature(s) ${stuck} in progress with no outcome and no activity for $(( age / 60 )) minutes")
      fi
    fi
  fi
done

# --- §4.0: did this turn end blind? -----------------------------------------
# A mission executing, with a pending feature, nothing in flight, and nobody
# waiting on the captain, means the loop stopped for no reason.
BLIND=""
BLIND_COUNTER="$HARNESS_ROOT/state/blind-stop-count"
if [ "${#PROBLEMS[@]}" -eq 0 ] && [ -d "$HARNESS_ROOT/state" ]; then
  # shellcheck source=../../scripts/lib/crew.sh
  if . "$CODE_ROOT/scripts/lib/crew.sh" 2>/dev/null; then
    for mission_dir in "$MISSIONS"/*/; do
      [ -d "$mission_dir" ] || continue
      id="$(basename "$mission_dir")"
      case "$id" in .*) continue ;; esac
      [ -f "$mission_dir/status.json" ] || continue
      [ "$(status_state "$mission_dir/status.json" 2>/dev/null)" = "executing" ] || continue
      [ "$(holds_count_blocking "${mission_dir%/}" 2>/dev/null || echo 0)" -eq 0 ] || continue

      # A mission nobody has touched in days is not "the loop stopped for no
      # reason" — it is an abandoned mission. Without this bound, a stale
      # mission left `executing` months ago refuses every stop in every future
      # session, which is precisely how a safety rail becomes something people
      # switch off.
      last="$(mission_last_activity "${mission_dir%/}" 2>/dev/null || echo 0)"
      case "$last" in ''|*[!0-9]*) last=0 ;; esac
      [ "$last" -gt 0 ] || continue
      [ $(( NOW - last )) -lt "${HARNESS_LOOP_ACTIVE_SECONDS:-86400}" ] || continue

      pending="$(jq -r '[.features[]? | select(.state == "pending")] | length' "$mission_dir/status.json" 2>/dev/null || echo 0)"
      case "$pending" in ''|*[!0-9]*) pending=0 ;; esac
      [ "$pending" -gt 0 ] || continue

      live=0
      while IFS= read -r _t; do
        [ -n "$_t" ] || continue
        [ "$(crew_meta_get "$HARNESS_ROOT" "$_t" mission 2>/dev/null)" = "$id" ] || continue
        crew_is_terminal "$HARNESS_ROOT" "$_t" || live=1
      done < <(crew_list "$HARNESS_ROOT" 2>/dev/null)
      [ "$live" -eq 1 ] && continue

      BLIND="$id ($pending feature(s) pending)"
      break
    done
  fi
fi

if [ -n "$BLIND" ]; then
  LIMIT="${HARNESS_BLIND_STOP_LIMIT:-3}"
  N=0; [ -f "$BLIND_COUNTER" ] && N="$(cat "$BLIND_COUNTER" 2>/dev/null || echo 0)"
  case "$N" in ''|*[!0-9]*) N=0 ;; esac
  if [ "$N" -ge "$LIMIT" ]; then
    # Fail open. A guard that refuses forever is a wedged session.
    # notify's stderr is NOT suppressed: this path exits 0, so Claude never
    # delivers stderr to the model, and swallowing it would leave giving up
    # completely invisible.
    "$CODE_ROOT/scripts/notify.sh" "Harness" "Turn-end guard failed open after $LIMIT blind stops on $BLIND" || true
    rm -f "$BLIND_COUNTER" 2>/dev/null || true
    exit 0
  fi
  printf '%s' "$((N + 1))" > "$BLIND_COUNTER" 2>/dev/null || true
  {
    echo "[Stop hook] This turn ended blind."
    echo
    echo "  $BLIND is executing, nothing is in flight, and nothing is waiting on the captain."
    echo
    echo "Do one of these before stopping:"
    echo "  - dispatch the next feature (./scripts/crew/spawn.sh, or the in-process worker)"
    echo "  - file the decision you actually need (./scripts/hold.sh open $BLIND --question \"...\")"
    echo "  - set the mission to paused, if the captain asked you to stop (/pause)"
  } >&2
  exit 2
fi
rm -f "$BLIND_COUNTER" 2>/dev/null || true

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
