#!/usr/bin/env bash
# mission-diff.sh — plan-vs-log mission diff summary.
# Usage: ./scripts/mission-diff.sh <mission-id>

set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MISSIONS_DIR="${HARNESS_ROOT}/missions"

[[ $# -lt 1 ]] && { echo "Usage: $(basename "$0") <mission-id>" >&2; exit 1; }

MISSION_ID="$1"
MISSION_DIR="${MISSIONS_DIR}/${MISSION_ID}"

[[ -d "$MISSION_DIR" ]] || { echo "error: mission not found: $MISSION_DIR" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "error: jq required (brew install jq)" >&2; exit 1; }

SEP="──────────────────────────────────────────────────────────────"
COL_W=36

# ── parse plan.md: extract F-headings ────────────────────────────────────────
PLAN_FILE="${MISSION_DIR}/plan.md"
PLAN_IDS_LIST=""
PLAN_DATA=""   # lines: "FID\tslug"

if [[ -f "$PLAN_FILE" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^[#]+[[:space:]]+(F[0-9]+)[[:space:]]*[-—]+[[:space:]]*(.+)$ ]]; then
      fid="${BASH_REMATCH[1]}"
      fslug="${BASH_REMATCH[2]%"${BASH_REMATCH[2]##*[![:space:]]}"}"
      PLAN_IDS_LIST="${PLAN_IDS_LIST} ${fid}"
      PLAN_DATA="${PLAN_DATA}${fid}	${fslug}"$'\n'
    elif [[ "$line" =~ ^[#]+[[:space:]]+(F[0-9]+)[[:space:]]*$ ]]; then
      fid="${BASH_REMATCH[1]}"
      PLAN_IDS_LIST="${PLAN_IDS_LIST} ${fid}"
      PLAN_DATA="${PLAN_DATA}${fid}	<no description>"$'\n'
    fi
  done < "$PLAN_FILE"
fi
PLAN_IDS_LIST="${PLAN_IDS_LIST# }"

plan_slug_for()   { echo "$PLAN_DATA"   | awk -F'\t' -v id="$1" '$1==id{print $2;exit}'; }

# ── parse status.json ─────────────────────────────────────────────────────────
STATUS_FILE="${MISSION_DIR}/status.json"
MISSION_STATE="unknown"
CURRENT_FEATURE="-"
STATUS_DATA=""   # lines: "FID\tstate\tcolor"
STATUS_IDS_LIST=""

if [[ -f "$STATUS_FILE" ]]; then
  MISSION_STATE=$(jq -r '.state // "unknown"' "$STATUS_FILE")
  CURRENT_FEATURE=$(jq -r '.current_feature // "-"' "$STATUS_FILE")
  while IFS=$'\t' read -r fid fstate fcolor; do
    [[ -n "$fid" ]] || continue
    STATUS_DATA="${STATUS_DATA}${fid}	${fstate}	${fcolor}"$'\n'
    STATUS_IDS_LIST="${STATUS_IDS_LIST} ${fid}"
  done < <(jq -r '.features[]? | [.id//"", .state//"pending", .color//""] | @tsv' "$STATUS_FILE" 2>/dev/null || true)
fi
STATUS_IDS_LIST="${STATUS_IDS_LIST# }"

actual_state_for() { echo "$STATUS_DATA" | awk -F'\t' -v id="$1" '$1==id{print $2;exit}'; }
actual_color_for() { echo "$STATUS_DATA" | awk -F'\t' -v id="$1" '$1==id{print $3;exit}'; }

# ── parse log.md ──────────────────────────────────────────────────────────────
LOG_FILE="${MISSION_DIR}/log.md"
LOG_FOUND=false
LOG_STATS=""

if [[ -f "$LOG_FILE" && -s "$LOG_FILE" ]]; then
  LOG_FOUND=true
  n_total=$(grep -c '^\[' "$LOG_FILE" 2>/dev/null || true)
  n_worker=$(grep -c 'type=worker' "$LOG_FILE" 2>/dev/null || true)
  n_scrutiny=$(grep -c 'type=scrutiny-validator' "$LOG_FILE" 2>/dev/null || true)
  n_explorer=$(grep -c 'type=explorer' "$LOG_FILE" 2>/dev/null || true)
  n_usertest=$(grep -c 'type=user-testing-validator' "$LOG_FILE" 2>/dev/null || true)
  n_trans=$(grep -c 'state=' "$LOG_FILE" 2>/dev/null || true)
  n_amend=$(grep -ci 'contract.amend\|amendment\|contract updated' "$LOG_FILE" 2>/dev/null || true)
  LOG_STATS="  Total log lines        : ${n_total}
  Worker stops           : ${n_worker}
  Scrutiny-validator     : ${n_scrutiny}
  Explorer stops         : ${n_explorer}
  User-testing stops     : ${n_usertest}
  State transitions      : ${n_trans}
  Contract amendments    : ${n_amend}"
fi

# ── union of feature IDs (plan order first, then status extras, sorted) ───────
ALL_IDS_LIST="$PLAN_IDS_LIST"
for fid in $STATUS_IDS_LIST; do
  echo " $ALL_IDS_LIST " | grep -q " $fid " || ALL_IDS_LIST="${ALL_IDS_LIST} ${fid}"
done
ALL_IDS_LIST=$(echo "$ALL_IDS_LIST" | tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' ')

feature_verdict() {
  local fstate="$1" fcolor="$2"
  case "$fstate" in
    done|complete|completed|closed) [[ "$fcolor" == "red" ]] && echo "✗" || echo "✓" ;;
    failed|abandoned) echo "✗" ;;
    in_progress)      echo "~" ;;
    *)                echo "?" ;;
  esac
}

# ── output ────────────────────────────────────────────────────────────────────
echo "$SEP"
echo " Mission Diff: $MISSION_ID"
echo "$SEP"
echo " Mission state  : $MISSION_STATE"
echo " Current feature: $CURRENT_FEATURE"
echo

echo "PLANNED FEATURES (from plan.md)"
echo "$SEP"
if [[ -z "$PLAN_IDS_LIST" ]]; then
  echo " (no F-headings found in plan.md)"
else
  for fid in $PLAN_IDS_LIST; do
    echo "  $fid  $(plan_slug_for "$fid")"
  done
fi
echo

echo "LOG EVENTS SUMMARY (from log.md)"
echo "$SEP"
if [[ "$LOG_FOUND" == "false" ]]; then
  echo " (log.md absent or empty — known v0.5 gap)"
else
  echo "$LOG_STATS"
fi
echo

echo "FEATURE PLAN vs ACTUAL"
printf "%-6s  %-${COL_W}s  | %-30s  %s\n" "ID" "Planned (plan.md)" "Actual (status.json)" "Result"
printf "%-6s  %-${COL_W}s  | %-30s  %s\n" "------" "$(printf '%.0s-' $(seq 1 $COL_W))" "------------------------------" "------"

ALL_GREEN=true
if [[ -z "$ALL_IDS_LIST" ]]; then
  echo " (no features to compare)"
else
  for fid in $ALL_IDS_LIST; do
    pslug=$(plan_slug_for "$fid"); pslug="${pslug:-<not in plan>}"
    astate=$(actual_state_for "$fid"); astate="${astate:-<not in status.json>}"
    acolor=$(actual_color_for "$fid")
    result=$(feature_verdict "$astate" "${acolor:-}")
    [[ -n "${acolor:-}" ]] && adisplay="${astate}/${acolor}" || adisplay="$astate"
    [[ ${#pslug} -gt $COL_W ]] && pslug="${pslug:0:$((COL_W-1))}…"
    printf "%-6s  %-${COL_W}s  | %-30s  %s\n" "$fid" "$pslug" "$adisplay" "$result"
    [[ "$result" == "✓" ]] || ALL_GREEN=false
  done
fi
echo

echo "VERDICT"
echo "$SEP"
if [[ -z "$ALL_IDS_LIST" ]]; then
  echo " No features found — cannot determine verdict."
elif [[ "$ALL_GREEN" == "true" ]]; then
  echo " ALL PLANNED FEATURES LANDED GREEN  ✓"
else
  echo " NOT ALL PLANNED FEATURES GREEN — see feature table above."
fi
echo "$SEP"
