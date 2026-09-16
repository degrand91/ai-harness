#!/usr/bin/env bash
# Single owner of the no-mistakes gate: whether a project HAS one, and what it
# said. Sourced by scripts/crew/teardown.sh.
#
# WHY THIS IS NOT JUST `no-mistakes check`:
#   `no-mistakes check` on a project with no configuration reports empty
#   findings and exits 0. Wiring the gate straight to it would produce a gate
#   that can never fail -- worse than having no gate, because the mission
#   record would then claim the work was verified. So an unconfigured project
#   is reported as UNAVAILABLE, never as passing.
#
# The tool is a per-project devDependency ("npm install --save-dev
# no-mistakes"), so this only ever runs the project's OWN pinned copy from
# node_modules/.bin. It never fetches one: a gate that downloads the thing it
# is gating with, at delivery time, over the network, is not a gate.
#
# Contract (see the package's check-report-types.d.ts):
#   check --json -> {react, queues, rules, integration, codebase,
#                    advisories, warnings}
#   The first five block. `advisories` and `warnings` do not -- they are
#   reported to the operator but never hold up a delivery.

GATE_BLOCKING_DOMAINS='["react","queues","rules","integration","codebase"]'

gate_bin() {  # <root> -> path of the project's own no-mistakes, or nothing
  local root="${1:?}" bin="$1/node_modules/.bin/no-mistakes"
  [ -x "$bin" ] || return 1
  printf '%s' "$bin"
}

gate_available() {  # <root> -> 0 only if a gate could actually fail here
  local root="${1:?}" bin cfg
  bin="$(gate_bin "$root")" || return 1
  # configPath is null when nothing configures the checks, which is the
  # always-passes case above.
  cfg="$("$bin" config resolve --root "$root" 2>/dev/null \
         | jq -r '.configPath // empty' 2>/dev/null || true)"
  [ -n "$cfg" ]
}

# gate_run <root>
#   0 = gate ran and found nothing blocking
#   1 = gate ran and found something; a summary is printed
#   2 = no usable gate here; nothing was checked and nothing may be claimed
gate_run() {
  local root="${1:?}" bin out n
  gate_available "$root" || return 2
  bin="$(gate_bin "$root")" || return 2
  out="$("$bin" check --json --root "$root" 2>/dev/null || true)"
  [ -n "$out" ] || { printf 'gate: no-mistakes produced no report\n' >&2; return 2; }
  n="$(printf '%s' "$out" | jq --argjson d "$GATE_BLOCKING_DOMAINS" \
        '[$d[] as $k | (.[$k] // []) | length] | add // 0' 2>/dev/null || true)"
  case "$n" in ''|*[!0-9]*) printf 'gate: unreadable report from no-mistakes\n' >&2; return 2 ;; esac
  if [ "$n" -gt 0 ]; then
    printf '%s' "$out" | jq -r --argjson d "$GATE_BLOCKING_DOMAINS" \
      '$d[] as $k | (.[$k] // [])[] | "  \($k): \(.rule // .framework // "finding") \(.file // "")\(if .line then ":\(.line)" else "" end) \(.message // "")"' 2>/dev/null || true
    return 1
  fi
  # Non-blocking, but the operator should still see them.
  printf '%s' "$out" | jq -r '(.warnings // [])[] | "  warning: \(.)"' 2>/dev/null || true
  return 0
}
