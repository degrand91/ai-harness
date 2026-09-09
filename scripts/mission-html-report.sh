#!/usr/bin/env bash
#
# NOTE: this renders ONE mission in detail. For the fleet, use
# scripts/fleet-html.sh, which reads the snapshot contract instead of parsing
# mission files. The two are not redundant — this one shows per-feature files
# and full markdown bodies that the fleet snapshot deliberately does not carry —
# but if you only want "what is happening", reach for fleet-html.sh.
set -euo pipefail

CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Code comes from BASH_SOURCE, missions from CLAUDE_PROJECT_DIR (or the cwd when
# it looks like a harness home). Resolving both from the script's own location
# made this unusable against any home but its own checkout.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then HARNESS_ROOT="$CLAUDE_PROJECT_DIR"
elif [ -d "${PWD}/missions" ];  then HARNESS_ROOT="$PWD"
else                                 HARNESS_ROOT="$CODE_ROOT"; fi

# shellcheck source=lib/status-read.sh
. "${CODE_ROOT}/scripts/lib/status-read.sh"
REPO_ROOT="$HARNESS_ROOT"

usage() {
  echo "Usage: $(basename "$0") <mission-id> [--open]" >&2
  exit 1
}

MISSION_ID=""
OPEN_AFTER=false
for arg in "$@"; do
  case "$arg" in
    --open) OPEN_AFTER=true ;;
    -*) usage ;;
    *) MISSION_ID="$arg" ;;
  esac
done

[ -z "$MISSION_ID" ] && usage

MISSION_DIR="$REPO_ROOT/missions/$MISSION_ID"
[ -d "$MISSION_DIR" ] || { echo "Error: mission directory not found: $MISSION_DIR" >&2; exit 1; }

OUT="$MISSION_DIR/report.html"

# ── helpers ──────────────────────────────────────────────────────────────────

read_file() {
  local f="$1"
  [ -f "$f" ] && cat "$f" || echo "(not found)"
}

escape_html() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

jq_field() {
  local file="$1" field="$2" fallback="${3:--}"
  [ -f "$file" ] && jq -r "${field} // \"${fallback}\"" "$file" 2>/dev/null || echo "$fallback"
}

# ── gather data ───────────────────────────────────────────────────────────────

STATUS_FILE="$MISSION_DIR/status.json"

MISSION_STATE=$(status_state "$STATUS_FILE" 2>/dev/null || true)
[ -n "$MISSION_STATE" ] || MISSION_STATE="unknown"
CURRENT_FEATURE=$(jq_field "$STATUS_FILE" '.current_feature' '-')
CHAIN_TARGET=$(jq_field "$STATUS_FILE" '.chain_target' '-')

MISSION_MD=$(read_file "$MISSION_DIR/mission.md" | escape_html)
PLAN_MD=$(read_file "$MISSION_DIR/plan.md" | escape_html)
CONTRACT_MD=$(read_file "$MISSION_DIR/contract.md" | escape_html)
POST_MORTEM_MD=""
[ -f "$MISSION_DIR/post-mortem.md" ] && POST_MORTEM_MD=$(cat "$MISSION_DIR/post-mortem.md" | escape_html)

# ── build features table ─────────────────────────────────────────────────────

features_rows() {
  local features_dir="$MISSION_DIR/features"
  # `return` with no code inherits the failed test's status, which under
  # `set -e` aborted the entire report for any mission with no features/ yet.
  [ -d "$features_dir" ] || return 0
  for feat_dir in "$features_dir"/*/; do
    [ -d "$feat_dir" ] || continue
    local slug; slug=$(basename "$feat_dir")
    local sf="$feat_dir/status.json"
    local id state scrutiny_verdict
    id=$(jq_field "$sf" '.id' "$slug")
    state=$(jq_field "$sf" '.state' 'unknown')

    scrutiny_verdict="-"
    if [ -f "$feat_dir/scrutiny.md" ]; then
      scrutiny_verdict=$(grep -oiE '(green|red|pass|fail|approved|rejected)' "$feat_dir/scrutiny.md" | head -1 || echo "-")
    fi

    local state_class
    case "$state" in
      done|complete|completed) state_class="done" ;;
      failed|rejected) state_class="failed" ;;
      in_progress) state_class="in-progress" ;;
      *) state_class="pending" ;;
    esac

    echo "        <tr>"
    echo "          <td><code>$id</code></td>"
    echo "          <td>$slug</td>"
    echo "          <td><span class=\"badge $state_class\">$state</span></td>"
    echo "          <td>$scrutiny_verdict</td>"
    echo "        </tr>"
  done
}

# ── validators summary ────────────────────────────────────────────────────────

validators_rows() {
  local features_dir="$MISSION_DIR/features"
  # `return` with no code inherits the failed test's status, which under
  # `set -e` aborted the entire report for any mission with no features/ yet.
  [ -d "$features_dir" ] || return 0
  for feat_dir in "$features_dir"/*/; do
    [ -d "$feat_dir" ] || continue
    local slug; slug=$(basename "$feat_dir")
    for vfile in "$feat_dir/scrutiny.md" "$feat_dir/user-test.md"; do
      [ -f "$vfile" ] || continue
      local vtype; vtype=$(basename "$vfile" .md)
      local verdict; verdict=$(grep -oiE '(green|red|pass|fail|approved|rejected)' "$vfile" | head -1 || echo "-")
      local verdict_class
      case "${verdict,,}" in
        green|pass|approved) verdict_class="done" ;;
        red|fail|rejected) verdict_class="failed" ;;
        *) verdict_class="pending" ;;
      esac
      echo "        <tr>"
      echo "          <td><code>$slug</code></td>"
      echo "          <td>$vtype</td>"
      echo "          <td><span class=\"badge $verdict_class\">$verdict</span></td>"
      echo "        </tr>"
    done
  done
}

# ── write HTML ────────────────────────────────────────────────────────────────

{
cat <<'HEADER'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mission Report</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 15px; line-height: 1.6; color: #1a1a2e; background: #f8f9fc; padding: 2rem 1.5rem;
  }
  .container { max-width: 960px; margin: 0 auto; }
  h1 { font-size: 1.8rem; font-weight: 700; margin-bottom: .25rem; color: #12122a; }
  h2 { font-size: 1.15rem; font-weight: 600; margin: 2rem 0 .75rem; color: #12122a;
       border-bottom: 2px solid #e2e6f0; padding-bottom: .35rem; }
  .meta { font-size: .85rem; color: #6b7280; margin-bottom: 1.5rem; }
  .meta span { margin-right: 1.25rem; }
  .badge {
    display: inline-block; padding: .15rem .55rem; border-radius: 999px;
    font-size: .75rem; font-weight: 600; text-transform: uppercase; letter-spacing: .04em;
  }
  .badge.done       { background: #dcfce7; color: #166534; }
  .badge.failed     { background: #fee2e2; color: #991b1b; }
  .badge.in-progress{ background: #dbeafe; color: #1e40af; }
  .badge.pending    { background: #f3f4f6; color: #6b7280; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; font-size: .875rem; }
  th { background: #f1f5f9; text-align: left; padding: .5rem .75rem; font-weight: 600;
       border-bottom: 2px solid #e2e6f0; }
  td { padding: .45rem .75rem; border-bottom: 1px solid #e2e6f0; vertical-align: top; }
  tr:last-child td { border-bottom: none; }
  pre {
    background: #f1f5f9; border: 1px solid #e2e6f0; border-radius: .375rem;
    padding: 1rem; overflow-x: auto; font-size: .8rem; line-height: 1.5;
    white-space: pre-wrap; word-break: break-word;
  }
  code { font-family: ui-monospace, "SFMono-Regular", Consolas, monospace; font-size: .85em; }
  .section { background: #fff; border: 1px solid #e2e6f0; border-radius: .5rem;
             padding: 1.25rem 1.5rem; margin-bottom: 1.5rem; }
  .generated { font-size: .75rem; color: #9ca3af; margin-top: 2rem; text-align: right; }
</style>
</head>
<body>
<div class="container">
HEADER

echo "  <h1>Mission Report: $MISSION_ID</h1>"
echo "  <div class=\"meta\">"
echo "    <span>State: <strong>$MISSION_STATE</strong></span>"
echo "    <span>Current feature: <strong>$CURRENT_FEATURE</strong></span>"
echo "    <span>Chain target: <strong>$CHAIN_TARGET</strong></span>"
echo "  </div>"

echo "  <h2>Mission Overview</h2>"
echo "  <div class=\"section\"><pre>$MISSION_MD</pre></div>"

echo "  <h2>Plan Summary</h2>"
echo "  <div class=\"section\"><pre>$PLAN_MD</pre></div>"

echo "  <h2>Features</h2>"
echo "  <div class=\"section\">"
echo "    <table>"
echo "      <thead><tr><th>ID</th><th>Slug</th><th>State</th><th>Scrutiny</th></tr></thead>"
echo "      <tbody>"
features_rows
echo "      </tbody>"
echo "    </table>"
echo "  </div>"

echo "  <h2>Contract Assertions</h2>"
echo "  <div class=\"section\"><pre>$CONTRACT_MD</pre></div>"

echo "  <h2>Validators Summary</h2>"
echo "  <div class=\"section\">"
echo "    <table>"
echo "      <thead><tr><th>Feature</th><th>Validator</th><th>Verdict</th></tr></thead>"
echo "      <tbody>"
validators_rows
echo "      </tbody>"
echo "    </table>"
echo "  </div>"

if [ -n "$POST_MORTEM_MD" ]; then
  echo "  <h2>Post-mortem</h2>"
  echo "  <div class=\"section\"><pre>$POST_MORTEM_MD</pre></div>"
fi

echo "  <p class=\"generated\">Generated $(date -u '+%Y-%m-%dT%H:%M:%SZ') by mission-html-report.sh</p>"

cat <<'FOOTER'
</div>
</body>
</html>
FOOTER
} > "$OUT"

echo "Report written: $OUT"

if $OPEN_AFTER; then
  if command -v open >/dev/null 2>&1; then
    open "$OUT"
  fi
fi
