#!/usr/bin/env bash
# snapshot.sh - the single owner of reading fleet state.
#
# Usage:
#   snapshot.sh            the fleet as one JSON document on stdout
#   snapshot.sh --pretty   the same, indented
#
# WHY THIS EXISTS. Six renderers each parsed status.json independently across 38
# jq call sites, so schema drift went unnoticed in all six at once. Everything
# now consumes this one document, and scripts/fleet.sh proves the pattern by
# parsing nothing itself.
#
# TWO JQ INVOCATIONS, WHATEVER THE FLEET SIZE. Every status.json is handed to
# `jq -n 'inputs'` in batch, with `input_filename` attributing each document to
# its mission; state normalisation stays in bash so scripts/lib/status-read.sh
# remains its single owner. Measured on 40 fixtures: batch 6 ms, per-mission
# 201 ms. mtimes are one batched `stat`. The Phase 4 watcher polls this every
# cycle, so the batch form is the contract, not an optimisation —
# tests/script-snapshot.test.sh counts the invocations.
#
# RESILIENCE. jq aborts the stream at the first malformed document rather than
# skipping it, so one corrupt status.json would silently drop every mission
# after it — and `ls -t` puts a just-broken mission first. Pass 1 retries,
# dropping the file jq names on stderr each time. Cost is one pass plus one per
# corrupt file: constant in fleet size, linear only in breakage. Corrupt
# missions still appear in the output, with state "unknown".
#
# Schema: {schema, generated_at, projects[], missions[], totals{}}
# `schema` is an integer; bump it on any breaking change to this shape.

set -uo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
MISSIONS="${HARNESS_ROOT}/missions"
REGISTRY="${HARNESS_ROOT}/data/projects.md"
SCHEMA=1

# shellcheck source=lib/status-read.sh
. "$CODE_ROOT/scripts/lib/status-read.sh"
# shellcheck source=lib/registry.sh
. "$CODE_ROOT/scripts/lib/registry.sh"

PRETTY=0
case "${1:-}" in
  --pretty) PRETTY=1 ;;
  -h|--help) sed -n '2,10{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
  "") ;;
  *) printf 'snapshot.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
esac

# --- gather mission files, newest activity first -----------------------------
FILES=(); IDS=(); ACTIVITY=(); ALLPATHS=()
if [ -d "$MISSIONS" ]; then
  # shellcheck disable=SC2012  # mtime ordering; mission ids are date-slugs
  LISTING="$(ls -t "$MISSIONS" 2>/dev/null || true)"
  while IFS= read -r id; do
    case "$id" in ''|.*) continue ;; esac
    [ -f "$MISSIONS/$id/status.json" ] || continue
    IDS+=("$id")
    FILES+=("$MISSIONS/$id/status.json")
    ACTIVITY+=(0)
    ALLPATHS+=("$MISSIONS/$id/status.json")
    [ -f "$MISSIONS/$id/log.md" ] && ALLPATHS+=("$MISSIONS/$id/log.md")
  done <<< "$LISTING"
fi

# One stat call for every file, rather than two per mission.
if [ "${#ALLPATHS[@]}" -gt 0 ]; then
  while read -r epoch path; do
    [ -n "${path:-}" ] || continue
    rel="${path#"$MISSIONS"/}"; mid="${rel%%/*}"
    k=0
    while [ "$k" -lt "${#IDS[@]}" ]; do
      if [ "${IDS[$k]}" = "$mid" ]; then
        [ "$epoch" -gt "${ACTIVITY[$k]}" ] 2>/dev/null && ACTIVITY[$k]="$epoch"
        break
      fi
      k=$((k + 1))
    done
  done < <(paths_mtime_epochs "${ALLPATHS[@]}")
fi

# --- registered projects (bash-only; no subprocess per project) --------------
PROJECTS_JSON="[]"
PROJ_NAMES=(); PROJ_PATHS=()
if [ -f "$REGISTRY" ]; then
  proj_entries=""
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! read -r pmode pyolo ppath < <(registry_resolve "$REGISTRY" "$name" 2>/dev/null); then
      continue
    fi
    PROJ_NAMES+=("$name"); PROJ_PATHS+=("${ppath%/}")
    [ -n "$proj_entries" ] && proj_entries="${proj_entries},"
    proj_entries="${proj_entries}{\"name\":\"${name}\",\"mode\":\"${pmode}\",\"yolo\":\"${pyolo}\",\"path\":\"${ppath}\"}"
  done < <(registry_list "$REGISTRY")
  PROJECTS_JSON="[${proj_entries}]"
fi

# --- jq pass 1 of 2: raw fields for every mission, one invocation ------------
# State normalisation stays in scripts/lib/status-read.sh (its single owner), so
# jq only extracts the three raw fields and bash decides. Duplicating the
# vocabulary map inside jq is exactly the drift this layer exists to prevent.
RAW=""
BAD_COUNT=0
if [ "${#FILES[@]}" -gt 0 ]; then
  # NOT @tsv. `read` treats a tab as IFS whitespace, so consecutive tabs collapse
  # and empty fields vanish - a mission with no `.state` would slide
  # `.target_repo` into `.status`'s slot. Unit Separator (U+001F) is not IFS
  # whitespace, so empty fields survive. This is the second time this trap has
  # bitten in this repo; see status_state in scripts/lib/status-read.sh.
  #
  # jq ABORTS the stream at the first malformed document rather than skipping
  # it, so every file after a corrupt one would silently vanish - and `ls -t`
  # puts a just-broken mission first, which is precisely when it happens. Each
  # failure names its file on stderr, so drop that file and retry. Cost is one
  # pass plus one per corrupt file: constant in fleet size, linear only in
  # breakage.
  attempt=("${FILES[@]}")
  while [ "${#attempt[@]}" -gt 0 ]; do
    _err="$(mktemp)"
    if RAW="$(jq -rn '
      inputs
      | [ input_filename, (.state? // ""), (.status? // ""), (.phase? // ""), (.target_repo? // "") ]
      | join("\u001f")
    ' "${attempt[@]}" 2>"$_err")"; then
      rm -f "$_err"; break
    fi
    _bad="$(sed -nE 's/^jq: error \(at (.*):[0-9]+\).*/\1/p' "$_err" | head -n1)"
    rm -f "$_err"
    [ -n "$_bad" ] || { RAW=""; break; }   # unattributable failure: give up cleanly
    BAD_COUNT=$((BAD_COUNT + 1))
    _keep=()
    for _f in "${attempt[@]}"; do [ "$_f" = "$_bad" ] || _keep+=("$_f"); done
    if [ "${#_keep[@]}" -eq 0 ]; then attempt=(); RAW=""; else attempt=("${_keep[@]}"); fi
  done
fi

# Pass 1 also answers "which files parse": a malformed document is absent from
# its output. Pass 2 is handed only those, so it never re-discovers the problem.
GOOD_FILES=()
if [ -n "$RAW" ]; then
  while IFS=$'\037' read -r rf _rest; do
    [ -n "${rf:-}" ] && GOOD_FILES+=("$rf")
  done <<< "$RAW"
fi

# --- sidecar: facts jq cannot see, joined to the docs by mission id ----------
SIDECAR=""
declare_i=0
while [ "$declare_i" -lt "${#IDS[@]}" ]; do
  id="${IDS[$declare_i]}"; act="${ACTIVITY[$declare_i]}"

  rs=""; rt=""; rp=""; rr=""
  if [ -n "$RAW" ]; then
    while IFS=$'\037' read -r rf a b c d; do
      [ "$rf" = "$MISSIONS/$id/status.json" ] || continue
      rs="$a"; rt="$b"; rp="$c"; rr="$d"; break
    done <<< "$RAW"
  fi

  if [ -n "$rs$rt$rp" ]; then
    state="$(status_normalize "$rs" "$rt" "$rp")" || state="unknown"
  else
    state="unknown"    # absent from RAW = the file did not parse
  fi
  case "$state" in closed|abandoned|unknown) active=false ;; *) active=true ;; esac

  project="null"
  if [ -n "$rr" ]; then
    case "$rr" in "~"*) rr="$HOME${rr#\~}" ;; esac
    rr="${rr%/}"
    j=0
    while [ "$j" -lt "${#PROJ_PATHS[@]}" ]; do
      if [ "${PROJ_PATHS[$j]}" = "$rr" ]; then project="\"${PROJ_NAMES[$j]}\""; break; fi
      j=$((j + 1))
    done
  fi

  holds=0
  if [ -d "$MISSIONS/$id/decisions" ]; then
    for hf in "$MISSIONS/$id/decisions"/*.json; do
      [ -f "$hf" ] || continue
      holds=$((holds + 1))
    done
  fi

  [ -n "$SIDECAR" ] && SIDECAR="${SIDECAR},"
  SIDECAR="${SIDECAR}{\"id\":\"${id}\",\"state\":\"${state}\",\"active\":${active},\"last_activity\":${act},\"project\":${project},\"open_holds\":${holds}}"
  declare_i=$((declare_i + 1))
done
SIDECAR="[${SIDECAR}]"

if [ "${#GOOD_FILES[@]}" -eq 0 ]; then
  DOCS="[]"
else
  # jq pass 2 of 2, over the documents pass 1 proved parseable.
  DOCS="$(jq -n '[inputs | {f: input_filename, doc: .}]' "${GOOD_FILES[@]}" 2>/dev/null || printf '[]')"
fi

JQ_ARGS=(-n --argjson side "$SIDECAR" --argjson docs "$DOCS" --argjson projects "$PROJECTS_JSON"
         --argjson schema "$SCHEMA" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mdir "$MISSIONS")
[ "$PRETTY" -eq 1 ] || JQ_ARGS+=(-c)

jq "${JQ_ARGS[@]}" '
  # Index parsed documents by mission id, derived from the file path.
  ($docs | map({ key: (.f | sub("^" + $mdir + "/"; "") | sub("/status\\.json$"; "")), value: .doc })
         | from_entries) as $byid
  | ($side | map(
      . as $s
      | ($byid[$s.id] // {}) as $d
      | {
          id:              $s.id,
          title:           ($d.title // $s.id),
          state:           $s.state,
          active:          $s.active,
          project:         $s.project,
          last_activity:   $s.last_activity,
          open_holds:      $s.open_holds,
          current_feature: ($d.current_feature // null),
          parsed:          ($byid | has($s.id)),
          features: ($d.features // [] | map({
            id:        (.id // null),
            slug:      (.slug // null),
            state:     (.state // .status // null),
            color:     (.color // null),
            followups: (.followups // [] | if type == "array" then length else . end)
          })),
          tokens: {
            input:  ([$d.tokens // {} | .[]? | .input  // 0] | add // 0),
            output: ([$d.tokens // {} | .[]? | .output // 0] | add // 0)
          }
        }
    )) as $missions
  | {
      schema: $schema,
      generated_at: $at,
      projects: $projects,
      missions: $missions,
      totals: {
        missions:        ($missions | length),
        active_missions: ($missions | map(select(.active)) | length),
        unparsed:        ($missions | map(select(.parsed | not)) | length),
        open_holds:      ($missions | map(.open_holds) | add // 0),
        tokens: {
          input:  ($missions | map(.tokens.input)  | add // 0),
          output: ($missions | map(.tokens.output) | add // 0)
        }
      }
    }
'
