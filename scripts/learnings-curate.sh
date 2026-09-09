#!/usr/bin/env bash
# learnings-curate.sh - keep the learnings corpus from growing without bound.
#
# Usage:
#   learnings-curate.sh            report tiers and the budget verdict
#   learnings-curate.sh --apply    archive what the report proposes
#
# learnings/ has taxonomy, frontmatter and a regenerating index. What it has no
# concept of is AGE: nothing ages out, nothing caps growth, and every entry is
# loaded into planning forever regardless of whether it has been relevant since
# the month it was written.
#
# TIERS
#   hot   named in one of the last HARNESS_LEARNINGS_RECENT (3) missions
#   warm  has a recurrence log with at least one entry — it keeps happening
#   cold  neither, and older than HARNESS_LEARNINGS_COLD_DAYS (60)
#
# ANTI-PATTERNS ARE NEVER AUTO-ARCHIVED. A trap you stopped hitting is exactly
# the one you are about to hit again; its absence from recent missions is
# evidence it is working, not evidence it is stale.
#
# ARCHIVING IS PROPOSED, NEVER PERFORMED, without --apply. Over budget, the
# report names the coldest entries and stops. Deleting somebody's hard-won note
# because a counter went over is how a corpus stops being trusted.
#
# Tuning: HARNESS_LEARNINGS_BUDGET (40) · HARNESS_LEARNINGS_COLD_DAYS (60)
#         HARNESS_LEARNINGS_RECENT (3)

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
LEARNINGS="$HARNESS_ROOT/learnings"
ARCHIVE="$LEARNINGS/archive"
MISSIONS="$HARNESS_ROOT/missions"

# shellcheck source=lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh"

BUDGET="${HARNESS_LEARNINGS_BUDGET:-40}"
COLD_DAYS="${HARNESS_LEARNINGS_COLD_DAYS:-60}"
RECENT="${HARNESS_LEARNINGS_RECENT:-3}"
APPLY=0
case "${1:-}" in
  --apply) APPLY=1 ;;
  -h|--help) sed -n '2,10{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
  "") ;;
  *) printf 'learnings-curate: unknown option %s\n' "$1" >&2; exit 2 ;;
esac

[ -d "$LEARNINGS" ] || { printf 'learnings-curate: no learnings/ directory\n' >&2; exit 1; }
mkdir -p "$ARCHIVE"

# The newest N mission directories, whatever their state.
RECENT_DIRS=()
if [ -d "$MISSIONS" ]; then
  # shellcheck disable=SC2012  # mtime ordering; mission ids are date-slugs
  while IFS= read -r m; do
    case "$m" in ''|.*) continue ;; esac
    [ -d "$MISSIONS/$m" ] || continue
    RECENT_DIRS+=("$MISSIONS/$m")
    [ "${#RECENT_DIRS[@]}" -ge "$RECENT" ] && break
  done <<< "$(ls -t "$MISSIONS" 2>/dev/null || true)"
fi

NOW="$(date -u +%s)"
HOT=0; WARM=0; COLD=0
COLD_LIST=()
REPORT=()

for kind in patterns anti-patterns proposals; do
  d="$LEARNINGS/$kind"
  [ -d "$d" ] || continue
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    slug="$(basename "$f" .md)"

    referenced=0
    if [ "${#RECENT_DIRS[@]}" -gt 0 ]; then
      grep -rqlF "$slug" "${RECENT_DIRS[@]}" 2>/dev/null && referenced=1
    fi

    recurs=0
    if awk '/^## Recurrence log/{f=1;next} f&&/^- /{print;exit}' "$f" 2>/dev/null | grep -q .; then
      recurs=1
    fi

    age_days=$(( ( NOW - $(file_mtime_epoch "$f") ) / 86400 ))

    if [ "$referenced" -eq 1 ]; then
      tier=hot; HOT=$((HOT + 1))
    elif [ "$recurs" -eq 1 ]; then
      tier=warm; WARM=$((WARM + 1))
    elif [ "$age_days" -gt "$COLD_DAYS" ]; then
      tier=cold; COLD=$((COLD + 1))
      # Anti-patterns are counted cold but never proposed for archival.
      [ "$kind" != "anti-patterns" ] && COLD_LIST+=("$f")
    else
      tier=warm; WARM=$((WARM + 1))
    fi

    REPORT+=("$(printf '%-6s %-14s %4sd  %s' "$tier" "$kind" "$age_days" "$slug")")
  done
done

TOTAL=$(( HOT + WARM + COLD ))

printf 'Learnings corpus: %s entries (hot %s, warm %s, cold %s)\n' "$TOTAL" "$HOT" "$WARM" "$COLD"
printf 'Budget: %s\n\n' "$BUDGET"
for line in "${REPORT[@]:-}"; do [ -n "$line" ] && printf '  %s\n' "$line"; done
printf '\n'

if [ "$TOTAL" -le "$BUDGET" ]; then
  printf 'Within budget. Nothing to archive.\n'
  [ "$COLD" -gt 0 ] && printf 'Note: %s cold entr(y|ies) exist but the corpus is small enough to keep them.\n' "$COLD"
  exit 0
fi

OVER=$(( TOTAL - BUDGET ))
printf 'OVER BUDGET by %s.\n\n' "$OVER"

if [ "${#COLD_LIST[@]}" -eq 0 ]; then
  printf 'Nothing is safe to archive automatically: every cold entry is an anti-pattern,\n'
  printf 'and a trap you stopped hitting is exactly the one you are about to hit again.\n'
  printf 'This needs a human decision — raise it with the captain rather than trimming.\n'
  exit 3
fi

printf 'Proposed for archival (coldest first, anti-patterns excluded):\n'
n=0
for f in "${COLD_LIST[@]}"; do
  [ "$n" -ge "$OVER" ] && break
  printf '  %s\n' "${f#"$LEARNINGS"/}"
  n=$((n + 1))
done
printf '\n'

if [ "$APPLY" -eq 0 ]; then
  printf 'Nothing has been moved. Re-run with --apply to archive these,\n'
  printf 'or leave them: the budget is a prompt to decide, not an instruction to delete.\n'
  exit 0
fi

n=0
for f in "${COLD_LIST[@]}"; do
  [ "$n" -ge "$OVER" ] && break
  rel="${f#"$LEARNINGS"/}"
  dest="$ARCHIVE/$(printf '%s' "$rel" | tr '/' '-')"
  mv "$f" "$dest" && printf 'archived %s\n' "$rel"
  n=$((n + 1))
done
printf '\nArchived %s entr(y|ies) to learnings/archive/. Nothing was deleted.\n' "$n"
printf 'Regenerate the index: ./scripts/learnings-index.sh\n'
