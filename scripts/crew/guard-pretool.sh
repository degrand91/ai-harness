#!/usr/bin/env bash
#
# PreToolUse hook INJECTED INTO A CREWMATE'S WORKTREE. Refuses the operations a
# crewmate must never perform, whatever its brief says and whatever it decides.
#
# Hooks fire regardless of permission mode, so this holds even if the tool
# allowlist is misconfigured. It is the last of the three sandbox layers: the
# worktree, the `-p` allowlist, and this.
#
# Usage (from the injected settings.local.json):
#   guard-pretool.sh <worktree-abs-path>
#
# Exit 0 = allow. Exit 2 = refuse, reason on stderr (the crewmate sees it).

set -uo pipefail
WORKTREE="${1:-}"
INPUT="$(cat 2>/dev/null || true)"

refuse() {
  printf '[crew guard] Refused: %s\n\nA crewmate does not land its own work. Finish the change, commit it, write your handoff, and end with a `done:` ledger line. The supervisor ships it under the project delivery mode.\n' "$1" >&2
  exit 2
}

TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$TOOL" = "Bash" ] || exit 0
CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

case "$CMD" in
  *"git push"*)            refuse "git push" ;;
  *"gh pr merge"*)         refuse "gh pr merge" ;;
  *"gh pr create"*)        refuse "gh pr create" ;;
  *"git merge"*)           refuse "git merge" ;;
  *"git worktree"*)        refuse "git worktree" ;;
  *"git reset --hard"*)    refuse "git reset --hard" ;;
  *"rm -rf /"*)            refuse "rm -rf on an absolute path" ;;
esac

# A `cd` above the worktree root leaves the sandbox. Only obvious escapes are
# matched; the worktree and the allowlist are the real boundaries.
if [ -n "$WORKTREE" ]; then
  case "$CMD" in
    *"cd /"*|*"cd .."*|*"cd ~"*) refuse "changing directory outside the worktree" ;;
  esac
fi
exit 0
