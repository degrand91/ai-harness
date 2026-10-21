# Vendored skill: mcp-builder

Verbatim vendored copy of an **official Anthropic skill**, bundled so the harness
ships with it rather than depending on a separately-installed plugin.

| | |
|---|---|
| Upstream | https://github.com/anthropics/skills/tree/main/skills/mcp-builder |
| Author | Anthropic |
| License | Apache 2.0 (see [LICENSE.txt](LICENSE.txt) in this folder) |
| Vendored from commit | `dbd4588f9e1033efb41dad4bef2f7947c8993d44` |
| Vendored on | 2026-10-21 |
| Source path | `skills/mcp-builder/` |

## Dependencies (NOT part of the core harness)

Primarily guidance + reference. `scripts/` carry optional evaluation helpers (Python / Node) used only when explicitly run.

## Updating

Re-copy `skills/mcp-builder/` from a newer upstream commit, refresh the table above, and
re-run `scripts/harness-audit.sh`. Keep local edits minimal so the copy stays
diffable against upstream; record any unavoidable ones here.

## Local modifications

None — verbatim copy, plus this `UPSTREAM.md`.
