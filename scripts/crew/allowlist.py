#!/usr/bin/env python3
"""allowlist.py - build a crewmate's tool allowlist.

Usage: allowlist.py --say <path> [--scout] [--project-allow "bun *, make test"]

Emits a JSON array, one entry per pattern.

TWO LESSONS ARE BAKED IN HERE, both from real failures:

1. Patterns contain spaces ("Bash(git add:*)"), so they must travel as a LIST,
   never as a space-joined string. Joining and re-splitting turned each pattern
   into argv fragments that matched nothing, and the first real crewmate could
   not commit, run its own test, or report progress.

2. Claude Code's syntax is Bash(<prefix>:*) with a COLON. A registry entry is
   written the way a human says it ("bun *"), so it is normalised here rather
   than making the operator learn the syntax.

Previously an inline heredoc inside spawn.sh. It lives in a file because an
embedded `python3 - <<'PY'` consumes the stdin its own program may need — the
trap that silently broke scripts/crew/render.
"""
from __future__ import annotations

import argparse
import json
import sys

BASE = [
    "Read", "Edit", "Write", "Glob", "Grep", "TodoWrite",
    "Bash(git add:*)", "Bash(git commit:*)", "Bash(git status:*)",
    "Bash(git diff:*)", "Bash(git log:*)", "Bash(git show:*)",
]

# A scout investigates: it may read anything and write only its report.
SCOUT = ["Read", "Glob", "Grep", "TodoWrite", "Write"]


def normalise(cmd: str) -> str:
    """'bun *' / 'bun' / 'bun:*' all mean the same thing to a human."""
    return cmd.strip().rstrip("*").rstrip().rstrip(":").strip()


def build(say: str, scout: bool, project_allow: str) -> list[str]:
    tools = list(SCOUT if scout else BASE)

    # The one command a crewmate may use to speak to its supervisor. Its ledger
    # lives outside the worktree, so without this the brief asks for progress
    # reports the sandbox forbids — which is exactly what happened on the first
    # real run: the work was done correctly and nobody was told.
    tools.append(f"Bash({say}:*)")

    for raw in (project_allow or "").split(","):
        c = normalise(raw)
        if c:
            tools.append(f"Bash({c}:*)")
    return tools


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--say", required=True, help="absolute path to scripts/crew/say.sh")
    ap.add_argument("--scout", action="store_true")
    ap.add_argument("--project-allow", default="")
    a = ap.parse_args()
    json.dump(build(a.say, a.scout, a.project_allow), sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
