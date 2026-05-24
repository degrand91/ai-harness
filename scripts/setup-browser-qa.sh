#!/usr/bin/env bash
# setup-browser-qa.sh — Verify Playwright MCP dependencies for the harness.
# Usage: bash scripts/setup-browser-qa.sh
# Exits 0 on success, 1 on any failure.

set -euo pipefail

PASS="[PASS]"
FAIL="[FAIL]"
INFO="[INFO]"

ok=0

# ---------------------------------------------------------------------------
# 1. Node.js availability
# ---------------------------------------------------------------------------
if node --version > /dev/null 2>&1; then
  NODE_VER="$(node --version)"
  echo "${PASS} node found: ${NODE_VER}"
else
  echo "${FAIL} node not found."
  echo "       Install Node.js 18+ from https://nodejs.org and re-run this script."
  ok=1
fi

# ---------------------------------------------------------------------------
# 2. npx availability
# ---------------------------------------------------------------------------
if npx --version > /dev/null 2>&1; then
  NPX_VER="$(npx --version)"
  echo "${PASS} npx found: ${NPX_VER}"
else
  echo "${FAIL} npx not found."
  echo "       npx ships with Node.js 5.2+. Upgrade Node.js or install npx separately."
  ok=1
fi

# ---------------------------------------------------------------------------
# 3. .mcp.json exists and is valid JSON
# ---------------------------------------------------------------------------
MCP_JSON="$(dirname "$0")/../.mcp.json"
MCP_JSON="$(cd "$(dirname "$0")/.." && pwd)/.mcp.json"

if [ -f "${MCP_JSON}" ]; then
  if jq -e '.mcpServers.playwright' "${MCP_JSON}" > /dev/null 2>&1; then
    echo "${PASS} .mcp.json found and contains a valid .mcpServers.playwright entry."
  else
    echo "${FAIL} .mcp.json exists but is missing or has an invalid .mcpServers.playwright entry."
    echo "       Expected shape: { \"mcpServers\": { \"playwright\": { \"command\": \"npx\", \"args\": [\"@playwright/mcp@latest\"] } } }"
    ok=1
  fi
else
  echo "${FAIL} .mcp.json not found at project root (${MCP_JSON})."
  echo "       Run: cp harness/.mcp.json /path/to/your/project/.mcp.json"
  ok=1
fi

# ---------------------------------------------------------------------------
# 4. @playwright/mcp package can be resolved via npx
# ---------------------------------------------------------------------------
echo "${INFO} Checking @playwright/mcp package resolution via npx (this may download the package) ..."
if npx --yes @playwright/mcp@latest --help > /dev/null 2>&1; then
  echo "${PASS} @playwright/mcp@latest resolved and responded to --help."
else
  echo "${FAIL} @playwright/mcp@latest could not be resolved or exited with an error."
  echo "       Ensure you have an internet connection and that npx can reach the npm registry."
  echo "       Manual check: npx @playwright/mcp@latest --help"
  ok=1
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo ""
if [ "${ok}" -eq 0 ]; then
  echo "${PASS} All checks passed. Browser QA via Playwright MCP is ready."
else
  echo "${FAIL} One or more checks failed. Fix the issues above and re-run this script."
fi

exit "${ok}"
