#!/usr/bin/env bash
# scripts/harness-audit.sh
#
# Inspired by ECC's harness-audit.js (https://github.com/affaan-m/ECC)
# Copyright (c) 2026 Affaan Mustafa — Licensed under MIT
# This implementation is an original POSIX bash adaptation for the harness.
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASSED=0
FAILED=0

pass() { echo "[PASS] $1"; PASSED=$((PASSED + 1)); }
fail() { echo "[FAIL] $1: $2"; FAILED=$((FAILED + 1)); }

# ── jq guard ──────────────────────────────────────────────────────────────────
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required but not installed." >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Debian: apt install jq" >&2
  exit 2
fi

SETTINGS="${HARNESS_ROOT}/.claude/settings.json"

# ── Check 1: Settings sanity ──────────────────────────────────────────────────
if jq -e . "${SETTINGS}" > /dev/null 2>&1; then
  pass "settings.json is valid JSON"
else
  fail "settings.json is valid JSON" "file is missing or not valid JSON"
fi

# ── Check 2: No overbroad deny rules ─────────────────────────────────────────
overbroad=""
while IFS= read -r rule; do
  # Match Edit(./X) or Write(./X) where X has no path separator after ./
  # i.e. patterns like Edit(./filename.ext) that are not anchored to a subdir
  if echo "${rule}" | grep -qE '^(Edit|Write)\(\./[^/]+\)$'; then
    filename=$(echo "${rule}" | sed 's|^.*(\./||;s|)$||')
    # Check if this filename appears in subdirectories
    match_count=$(find "${HARNESS_ROOT}" -name "${filename}" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${match_count}" -gt 1 ]; then
      overbroad="${overbroad} ${rule}(${match_count} matches)"
    fi
  fi
done < <(jq -r '.permissions.deny[]? // empty' "${SETTINGS}" 2>/dev/null)

if [ -z "${overbroad}" ]; then
  pass "No overbroad deny rules in settings.json"
else
  fail "No overbroad deny rules in settings.json" "potentially overbroad rules:${overbroad}"
fi

# ── Check 3: All agent files parse ───────────────────────────────────────────
agents_dir="${HARNESS_ROOT}/.claude/agents"
agent_errors=""
if [ -d "${agents_dir}" ]; then
  for f in "${agents_dir}"/*.md; do
    [ -f "${f}" ] || continue
    stem=$(basename "${f}" .md)
    first_line=$(head -1 "${f}")
    if [ "${first_line}" != "---" ]; then
      agent_errors="${agent_errors} ${stem}(missing --- opener)"
      continue
    fi
    if ! grep -q "^name: ${stem}$" "${f}"; then
      agent_errors="${agent_errors} ${stem}(name mismatch)"
    fi
  done
fi

if [ -z "${agent_errors}" ]; then
  pass "All agent files have valid frontmatter"
else
  fail "All agent files have valid frontmatter" "problems:${agent_errors}"
fi

# ── Check 4: All hook scripts executable ─────────────────────────────────────
hooks_dir="${HARNESS_ROOT}/.claude/hooks"
non_exec_hooks=""
if [ -d "${hooks_dir}" ]; then
  for f in "${hooks_dir}"/*.sh; do
    [ -f "${f}" ] || continue
    if [ ! -x "${f}" ]; then
      non_exec_hooks="${non_exec_hooks} $(basename "${f}")"
    fi
  done
fi

if [ -z "${non_exec_hooks}" ]; then
  pass "All hook scripts are executable"
else
  fail "All hook scripts are executable" "not executable:${non_exec_hooks}"
fi

# ── Check 5: All hooks wired in settings.json ─────────────────────────────────
hook_errors=""
orphans=""
if [ -d "${hooks_dir}" ]; then
  settings_content=$(cat "${SETTINGS}")
  for f in "${hooks_dir}"/*.sh; do
    [ -f "${f}" ] || continue
    hook_name=$(basename "${f}")
    if ! echo "${settings_content}" | grep -q "${hook_name}"; then
      orphans="${orphans} ${hook_name}"
    fi
  done
fi

if [ -z "${orphans}" ]; then
  pass "All hook scripts are referenced in settings.json"
else
  fail "All hook scripts are referenced in settings.json" "orphaned (not wired):${orphans}"
fi

# ── Check 6: All skills have SKILL.md with correct frontmatter ───────────────
skills_dir="${HARNESS_ROOT}/.claude/skills"
skill_errors=""
if [ -d "${skills_dir}" ]; then
  for skill_dir in "${skills_dir}"/*/; do
    [ -d "${skill_dir}" ] || continue
    skill_name=$(basename "${skill_dir}")
    skill_md="${skill_dir}SKILL.md"
    if [ ! -f "${skill_md}" ]; then
      skill_errors="${skill_errors} ${skill_name}(SKILL.md missing)"
      continue
    fi
    if ! grep -q "^name: ${skill_name}$" "${skill_md}"; then
      skill_errors="${skill_errors} ${skill_name}(name mismatch in SKILL.md)"
    fi
  done
fi

if [ -z "${skill_errors}" ]; then
  pass "All skills have valid SKILL.md"
else
  fail "All skills have valid SKILL.md" "problems:${skill_errors}"
fi

# ── Check 7: Mission state consistency ───────────────────────────────────────
valid_states="intake|planning|contract|awaiting_approval|executing|feature_loop|closing|closed|abandoned|paused"
missions_dir="${HARNESS_ROOT}/missions"
state_errors=""
if [ -d "${missions_dir}" ]; then
  for status_file in "${missions_dir}"/*/status.json; do
    [ -f "${status_file}" ] || continue
    mission_id=$(basename "$(dirname "${status_file}")")
    state=$(jq -r '.state // "missing"' "${status_file}" 2>/dev/null || echo "parse_error")
    if ! echo "${state}" | grep -qE "^(${valid_states})$"; then
      state_errors="${state_errors} ${mission_id}(invalid state: ${state})"
    fi
  done
fi

if [ -z "${state_errors}" ]; then
  pass "All mission state fields are valid enum values"
else
  fail "All mission state fields are valid enum values" "problems:${state_errors}"
fi

# ── Check 8: No red mission features without follow-up ───────────────────────
red_errors=""
if [ -d "${missions_dir}" ]; then
  for status_file in "${missions_dir}"/*/status.json; do
    [ -f "${status_file}" ] || continue
    mission_id=$(basename "$(dirname "${status_file}")")
    mission_state=$(jq -r '.state // "unknown"' "${status_file}" 2>/dev/null || echo "unknown")
    # Skip closed and abandoned missions
    if echo "${mission_state}" | grep -qE "^(closed|abandoned)$"; then
      continue
    fi
    # Look for features with state "red"
    red_features=$(jq -r '.features[]? | select(.color == "red" or .state == "red") | .slug // .id' "${status_file}" 2>/dev/null || true)
    if [ -n "${red_features}" ]; then
      while IFS= read -r feat; do
        [ -n "${feat}" ] || continue
        red_errors="${red_errors} ${mission_id}/${feat}"
      done <<< "${red_features}"
    fi
  done
fi

if [ -z "${red_errors}" ]; then
  pass "No red mission features in active missions"
else
  fail "No red mission features in active missions" "red features:${red_errors}"
fi

# ── Check 9: Scripts directory health ────────────────────────────────────────
scripts_dir="${HARNESS_ROOT}/scripts"
non_exec_scripts=""
if [ -d "${scripts_dir}" ]; then
  for f in "${scripts_dir}"/*.sh; do
    [ -f "${f}" ] || continue
    if [ ! -x "${f}" ]; then
      non_exec_scripts="${non_exec_scripts} $(basename "${f}")"
    fi
  done
fi

if [ -z "${non_exec_scripts}" ]; then
  pass "All scripts/*.sh are executable"
else
  fail "All scripts/*.sh are executable" "not executable:${non_exec_scripts}"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "SUMMARY: ${PASSED} passed, ${FAILED} failed"

if [ "${FAILED}" -gt 0 ]; then
  exit 1
fi
exit 0
