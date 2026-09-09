#!/usr/bin/env bash
# fleet-html.sh - render the snapshot as one static page.
#
# Usage: fleet-html.sh [<output.html>]     default: state/fleet.html
#
# Like scripts/fleet.sh, this PARSES NO MISSION STATE. Everything comes from
# scripts/snapshot.sh. It is a second renderer over the same contract, which is
# the whole point of having the contract.

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_ROOT="${CLAUDE_PROJECT_DIR:-$CODE_ROOT}"
OUT="${1:-$HARNESS_ROOT/state/fleet.html}"
mkdir -p "$(dirname "$OUT")" 2>/dev/null || true

SNAP="$("$CODE_ROOT/scripts/snapshot.sh")" || { printf 'fleet-html: snapshot failed\n' >&2; exit 1; }

printf '%s' "$SNAP" | jq -r '
  def esc: tostring | gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;");
  def badge($s):
    "<span class=\"b b-" + ($s|esc) + "\">" + ($s|esc) + "</span>";
  "<!doctype html><meta charset=\"utf-8\"><title>Fleet</title>",
  "<style>",
  ":root{--bg:#fbfaf8;--fg:#1c1a17;--dim:#6b655c;--line:#e5e0d8;--card:#fff}",
  "@media(prefers-color-scheme:dark){:root{--bg:#16150f;--fg:#ece7dd;--dim:#948d80;--line:#2e2b24;--card:#1e1c16}}",
  "*{box-sizing:border-box}body{margin:0;padding:2.5rem 1.5rem;background:var(--bg);color:var(--fg);",
  "font:15px/1.55 ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif}",
  "main{max-width:60rem;margin:0 auto}h1{font-size:1.6rem;margin:0 0 .25rem;letter-spacing:-.02em}",
  ".sub{color:var(--dim);font-size:.85rem;margin-bottom:2rem}",
  "h2{font-size:.75rem;text-transform:uppercase;letter-spacing:.08em;color:var(--dim);margin:2rem 0 .75rem}",
  ".card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:.9rem 1.1rem;margin-bottom:.5rem}",
  ".row{display:flex;gap:.75rem;align-items:baseline;flex-wrap:wrap}",
  ".id{font-weight:600}.dim{color:var(--dim);font-size:.85rem}",
  ".b{font-size:.7rem;padding:.15rem .5rem;border-radius:999px;border:1px solid var(--line);text-transform:uppercase;letter-spacing:.04em}",
  ".b-executing{background:#1b7f5a1a;border-color:#1b7f5a55}",
  ".b-unknown{background:#a8321f1a;border-color:#a8321f66}",
  ".b-paused,.b-awaiting_approval{background:#9a6b0a1a;border-color:#9a6b0a55}",
  ".f{display:inline-block;font-size:.75rem;color:var(--dim);margin-right:.6rem}",
  ".tot{display:flex;gap:2rem;flex-wrap:wrap;border-top:1px solid var(--line);padding-top:1rem;margin-top:2rem;font-size:.85rem;color:var(--dim)}",
  ".tot b{color:var(--fg);font-variant-numeric:tabular-nums}",
  "</style><main>",
  "<h1>Fleet</h1><div class=\"sub\">snapshot " + (.generated_at|esc) + "</div>",
  (if (.projects|length) > 0 then
     "<h2>Projects</h2>" + ([ .projects[] |
       "<div class=\"card\"><div class=\"row\"><span class=\"id\">" + (.name|esc) + "</span>"
       + badge(.mode) + (if .yolo == "on" then badge("yolo") else "" end)
       + "<span class=\"dim\">" + (.path|esc) + "</span></div></div>" ] | join(""))
   else "" end),
  "<h2>Missions</h2>",
  ([ .missions[] | select(.active or .state == "unknown") |
     "<div class=\"card\"><div class=\"row\"><span class=\"id\">" + (.id|esc) + "</span>"
     + (if .title and .title != .id then "<span class=\"dim\">" + (.title|esc) + "</span>" else "" end)
     + badge(.state)
     + (if .project then "<span class=\"dim\">" + (.project|esc) + "</span>" else "" end)
     + (if .open_holds > 0 then badge((.open_holds|tostring) + " open decision(s)") else "" end)
     + "</div>"
     + (if (.features|length) > 0 then "<div style=\"margin-top:.5rem\">"
         + ([ .features[] | "<span class=\"f\">" + ((.id // "?")|esc) + " " + ((.color // .state // "?")|esc) + "</span>" ] | join(""))
         + "</div>" else "" end)
     + "</div>" ] | join("")),
  "<div class=\"tot\">"
    + "<div>missions <b>" + (.totals.missions|tostring) + "</b></div>"
    + "<div>active <b>" + (.totals.active_missions|tostring) + "</b></div>"
    + "<div>open decisions <b>" + (.totals.open_holds|tostring) + "</b></div>"
    + "<div>tokens <b>" + (.totals.tokens.input|tostring) + "</b> in / <b>" + (.totals.tokens.output|tostring) + "</b> out</div>"
    + "</div>",
  "</main>"
' > "$OUT" || { printf 'fleet-html: render failed\n' >&2; exit 1; }

printf '%s\n' "$OUT"
