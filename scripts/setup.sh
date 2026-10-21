#!/usr/bin/env bash
# setup.sh - one command to make the harness ready to use.
#
# Usage:
#   scripts/setup.sh            report readiness of everything, install nothing
#   scripts/setup.sh --check    alias for the default (CI-safe, mutates nothing)
#   scripts/setup.sh --install  attempt to install the missing OPTIONAL tools
#                               via the detected package manager, then re-check
#
# Builds on doctor.sh (required tools + state roots) and adds the per-skill
# capability deps the vendored skills need: node, ffmpeg, python+playwright, the
# Playwright MCP, and gh. --check never changes your system; --install only ever
# touches OPTIONAL capability tools and never required ones, echoing each command
# before it runs. gh auth is always left to you (it is interactive).

set -uo pipefail
CODE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# doctor.sh reads CLAUDE_PROJECT_DIR itself (inherited through the env); setup.sh
# only needs CODE_ROOT to locate the scripts it wraps.

MODE=check
case "${1:-}" in
  -h|--help) sed -n '2,14{s/^# \{0,1\}//;s/^#$//;p;}' "$0"; exit 0 ;;
  --check)   MODE=check ;;
  --install) MODE=install ;;
  "")        MODE=check ;;
  *)         printf 'setup.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
esac

have() { command -v "$1" >/dev/null 2>&1; }

# Find a REAL Python 3 interpreter. Windows exposes a `python3` execution-alias
# stub that is on PATH but only prints a "not found" message, so verify the
# interpreter actually runs rather than trusting `command -v`.
PY=""
find_python() {
  local c
  for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; assert sys.version_info[0]==3' >/dev/null 2>&1; then
      PY="$c"; return 0
    fi
  done
  PY=""; return 1
}
find_python || true

ok()    { printf '  ok       %s\n' "$1"; }
miss()  { printf '  MISSING  %s — %s\n' "$1" "$2"; }
doing() { printf '  install  %s\n' "$1"; }

MISSING_LIST=""
note_missing() { MISSING_LIST="$MISSING_LIST $1"; }

# --- package manager detection (bash 3.2-safe: no associative arrays) --------
PM=""
case "$(uname -s)" in
  Darwin*) have brew && PM=brew ;;
  Linux*)  if   have apt-get; then PM=apt
           elif have dnf;     then PM=dnf
           elif have pacman;  then PM=pacman
           fi ;;
  *)       # Windows (Git Bash / MSYS) and anything else
           if   have winget; then PM=winget
           elif have choco;  then PM=choco
           elif have scoop;  then PM=scoop
           fi ;;
esac

# install_cmd <winget-id> <brew-formula> <apt/dnf/pacman-pkg> <scoop-pkg>
# Echoes the install command for the detected PM, or nothing if none is known.
install_cmd() {
  case "$PM" in
    brew)   printf 'brew install %s' "$2" ;;
    apt)    printf 'sudo apt-get install -y %s' "$3" ;;
    dnf)    printf 'sudo dnf install -y %s' "$3" ;;
    pacman) printf 'sudo pacman -S --noconfirm %s' "$3" ;;
    winget) printf 'winget install --silent --accept-package-agreements --accept-source-agreements %s' "$1" ;;
    choco)  printf 'choco install -y %s' "$3" ;;
    scoop)  printf 'scoop install %s' "$4" ;;
  esac
}

# try_install <label> <winget-id> <brew-formula> <nix-pkg> <scoop-pkg>
# In --install mode, runs the mapped command if a PM is known; otherwise prints
# the manual hint. Returns 0 if it (re)made the tool available.
try_install() {
  local label="$1"; shift
  local cmd; cmd="$(install_cmd "$@")"
  if [ -z "$PM" ] || [ -z "$cmd" ]; then
    miss "$label" "no known package manager — install it manually"
    return 1
  fi
  doing "$label  ($cmd)"
  # shellcheck disable=SC2086
  eval "$cmd" >/dev/null 2>&1 || { miss "$label" "install command failed: $cmd"; return 1; }
  return 0
}

# capability <label> <probe-cmd> <winget> <brew> <nix> <scoop> <hint>
# One optional capability tool: report, and in --install mode try to install it.
capability() {
  local label="$1" probe="$2" wg="$3" br="$4" nx="$5" sc="$6" hint="$7"
  if have "$probe"; then ok "$label ($("$probe" --version 2>&1 | head -n1))"; return 0; fi
  if [ "$MODE" = install ]; then
    if try_install "$label" "$wg" "$br" "$nx" "$sc" && have "$probe"; then
      ok "$label (installed)"; return 0
    fi
  else
    miss "$label" "$hint"
  fi
  note_missing "$label"
  return 1
}

# ---------------------------------------------------------------------------
printf '== Core harness (doctor) ==\n'
if [ "$MODE" = check ]; then
  bash "$CODE_ROOT/scripts/doctor.sh" --check; CORE_RC=$?
else
  bash "$CODE_ROOT/scripts/doctor.sh";         CORE_RC=$?
fi

printf '\n== Capability tools ==\n'
capability "node"   node   "OpenJS.NodeJS.LTS" "node"   "nodejs"            "nodejs"  "Node 18+ — scroll-craft, skill scripts, Playwright MCP"
capability "ffmpeg" ffmpeg "Gyan.FFmpeg"       "ffmpeg" "ffmpeg"            "ffmpeg"  "scroll-craft video encoding (not needed for your-own-asset builds)"
# Python: use the verified interpreter from find_python, not the generic probe
# (which the Windows python3 Store stub would fool into a false "ok").
if [ -n "$PY" ]; then
  ok "python ($("$PY" --version 2>&1 | head -n1))"
elif [ "$MODE" = install ]; then
  if try_install "python" "Python.Python.3.12" "python" "python3" "python" && find_python; then
    ok "python (installed: $("$PY" --version 2>&1 | head -n1))"
  else
    miss "python" "installed, but no python3 on PATH yet — reopen your shell"; note_missing "python"
  fi
else
  miss "python" "webapp-testing (Python Playwright scripts)"; note_missing "python"
fi

# Playwright for Python (webapp-testing) — pip module, not a system package.
printf '\n== Playwright (Python, for webapp-testing) ==\n'
if [ -n "$PY" ] && "$PY" -c 'import playwright' >/dev/null 2>&1; then
  ok "playwright (python module)"
elif [ "$MODE" = install ] && [ -n "$PY" ]; then
  doing "playwright ($PY -m pip install playwright && $PY -m playwright install chromium)"
  if "$PY" -m pip install --quiet playwright >/dev/null 2>&1 \
     && "$PY" -m playwright install chromium >/dev/null 2>&1; then
    ok "playwright (python module + chromium)"
  else
    miss "playwright (python)" "pip install playwright failed"; note_missing "playwright-python"
  fi
else
  miss "playwright (python)" "install python first, then: python3 -m pip install playwright && python3 -m playwright install chromium"
  note_missing "playwright-python"
fi

# Playwright MCP (browser-qa, user-testing-validator, /pr-evidence) — via npx.
printf '\n== Playwright MCP (browser QA / evidence) ==\n'
if have node && have npx; then
  if [ "$MODE" = install ]; then
    doing "prefetch @playwright/mcp@latest (npx --yes @playwright/mcp@latest --help)"
    npx --yes @playwright/mcp@latest --help >/dev/null 2>&1 \
      && ok "@playwright/mcp (resolved)" \
      || { miss "@playwright/mcp" "could not resolve via npx — check network/registry"; note_missing "playwright-mcp"; }
  else
    ok "node+npx present (run with --install to prefetch @playwright/mcp)"
  fi
else
  miss "node+npx" "needed for the Playwright MCP — install node first"; note_missing "playwright-mcp"
fi

# GitHub CLI + auth (PR delivery, /pr-evidence). Auth is always manual.
printf '\n== GitHub (gh) ==\n'
if have gh; then
  if gh auth status >/dev/null 2>&1; then ok "gh (authenticated)"
  else miss "gh auth" "interactive — run: gh auth login"; note_missing "gh-auth"; fi
else
  if [ "$MODE" = install ]; then
    try_install "gh" "GitHub.cli" "gh" "gh" "gh" && ok "gh (installed — now run: gh auth login)" || note_missing "gh"
  else
    miss "gh" "GitHub integration & /pr-evidence — https://cli.github.com"; note_missing "gh"
  fi
fi

# ---------------------------------------------------------------------------
printf '\n== Skill readiness ==\n'
ready() { printf '  READY    %s — %s\n' "$1" "$2"; }
part()  { printf '  PARTIAL  %s — %s\n' "$1" "$2"; }

# core mission-loop skills have no extra deps
ready "mission-loop skills" "no extra deps (mission-start, dispatch, validators, review, …)"
ready "skill-creator / mcp-builder / frontend-design" "guidance skills — no runtime deps"

if have node; then
  if have ffmpeg; then ready "scroll-craft" "node + ffmpeg present (build + video)"
  else part "scroll-craft" "builds + screenshots work; video encoding needs ffmpeg"; fi
else
  part "scroll-craft" "needs node (and ffmpeg for video)"
fi

if [ -n "$PY" ] && "$PY" -c 'import playwright' >/dev/null 2>&1; then
  ready "webapp-testing" "python + playwright present"
else
  part "webapp-testing" "needs python3 + playwright"
fi

if have node && have npx && have gh && gh auth status >/dev/null 2>&1; then
  ready "/pr-evidence + browser-qa" "node + gh (authed) present"
else
  part "/pr-evidence + browser-qa" "needs node, and gh authenticated to post evidence"
fi

# ---------------------------------------------------------------------------
printf '\n'
if [ "$CORE_RC" -ne 0 ]; then
  printf 'NOT READY — required tools are missing (see Core harness above).\n' >&2
  exit 1
fi
if [ -n "$MISSING_LIST" ]; then
  if [ "$MODE" = check ]; then
    printf 'Core is ready. Optional capabilities missing:%s\n' "$MISSING_LIST"
    printf 'Run  scripts/setup.sh --install  to attempt installing them'
    [ -z "$PM" ] && printf ' (no package manager detected — installs will be manual)'
    printf '.\n'
  else
    printf 'Core is ready. Still missing after install:%s — see the hints above.\n' "$MISSING_LIST"
  fi
  exit 0
fi
printf 'Ready — core and all optional capabilities are present.\n'
