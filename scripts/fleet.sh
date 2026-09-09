#!/usr/bin/env bash
# fleet.sh - the human view of everything in flight.
#
# Usage:
#   fleet.sh          active missions, by project
#   fleet.sh --all    include closed and abandoned missions
#   fleet.sh --json   the underlying snapshot, unmodified
#
# THIS SCRIPT PARSES NO MISSION STATE. Every fact comes from scripts/snapshot.sh,
# the single owner of reading fleet state. That is the whole point: six renderers
# each parsing status.json independently is how schema drift went unnoticed in
# all six at once. A renderer that reads a mission file is a renderer that can
# drift, so this one is not allowed to — tests/script-fleet.test.sh asserts that
# the source mentions neither status.json nor status-read.sh.

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SHOW_ALL=0
case "${1:-}" in
  --all)  SHOW_ALL=1 ;;
  --json) exec "$CODE_ROOT/scripts/snapshot.sh" --pretty ;;
  -h|--help) sed -n '2,8{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
  "") ;;
  *) printf 'fleet.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
esac

SNAP="$("$CODE_ROOT/scripts/snapshot.sh")" || { printf 'fleet.sh: snapshot failed\n' >&2; exit 1; }

printf '%s' "$SNAP" | jq -r --argjson all "$SHOW_ALL" '
  # Truncate to n-1 then pad, so a long id can never run into the next column.
  def pad($n): (.[0:$n-1] + (" " * $n))[0:$n];

  ( .projects ) as $projects
  # An unreadable mission is never hidden. It is not "active" — we cannot know
  # that — but it is precisely the mission a human needs to be told about, so it
  # is always shown regardless of the filter.
  | ( if $all == 1 then .missions
      else [.missions[] | select(.active or .state == "unknown")] end ) as $shown
  | (
      if ($projects | length) > 0 then
        "PROJECTS",
        ( $projects[] | "  " + (.name | pad(22)) + (.mode | pad(14))
                      + (if .yolo == "on" then "+yolo  " else "       " end) + .path ),
        ""
      else empty end
    ),
    (
      if ($shown | length) == 0 then
        (if $all == 1 then "No missions." else "No missions in flight." end)
      else
        "MISSIONS" + (if $all == 1 then " (all)" else "" end),
        ( $shown[]
          | "  " + (.id | pad(38))
            + (.state | pad(12))
            + ((.project // "-") | pad(14))
            + (if .current_feature then .current_feature else "-" end)
            + (if .open_holds > 0 then "  [\(.open_holds) open decision(s)]" else "" end)
            + (if .state == "unknown" then "  <- unreadable mission file" else "" end)
        ),
        (
          $shown[]
          | select(.features | length > 0)
          | select(.state != "unknown")
          | "    " + .id + ": "
            + ([ .features[]
                 | .id + "/" + (.color // .state // "?") ] | join("  "))
        )
      end
    ),
    "",
    "TOTALS",
    "  missions: \(.totals.missions)   active: \(.totals.active_missions)   open decisions: \(.totals.open_holds)"
      + (if .totals.unparsed > 0 then "   unreadable: \(.totals.unparsed)" else "" end),
    "  tokens:   \(.totals.tokens.input) in / \(.totals.tokens.output) out",
    "",
    "  snapshot: \(.generated_at)"
'
