## Feature: F001 — protocol-parallel-exploration

### What was implemented
- Created `/Users/stefanodegrandis/projects/ai/harness/protocols/parallel-exploration.md` (~90 lines) documenting:
  - The explorer-only concurrency rule (matching regex `only.*explorer.*may.*(spawned|run).*concurrent`)
  - A phase table showing when fanout is allowed vs. banned
  - Recommended maximum concurrency of 3–5 explorers per fanout (matching regex `(max|maximum|recommended).*(3|5|concurrency)`)
  - One-narrow-question-per-explorer guidance with concrete examples
  - Background mode (`run_in_background: true`) dispatch guidance
  - Synthesis steps (collect, merge, flag contradictions, distil into decisions)
  - Anti-patterns section
  - Cross-references to `protocols/serial-execution.md` and `protocols/lifecycle.md`

### What was left undone
- Nothing

### Commands run
| # | Command | Exit code | Notes |
|---|---------|-----------|-------|
| 1 | `test -f protocols/parallel-exploration.md && grep -qiE 'only.*explorer.*may.*(spawned\|run).*concurrent' protocols/parallel-exploration.md && grep -qiE '(max\|maximum\|recommended).*(3\|5\|concurrency)' protocols/parallel-exploration.md` | 0 | File exists, both required regex lines present |
| 2 | `for f in .claude/agents/*.md; do stem=$(basename "$f" .md); head -1 "$f" \| grep -qE '^---$' && grep -qE "^name: ${stem}$" "$f" \|\| exit 1; done` | 0 | All agent frontmatter intact |
| 3 | `diff <(git show 05b57a0:.claude/agents/scrutiny-validator.md) .claude/agents/scrutiny-validator.md` | 0 | scrutiny-validator.md unchanged |

### Issues discovered
- None

### Procedures followed
| Procedure | Followed | Notes |
|-----------|----------|-------|
| Read all referenced files before editing | yes | Read serial-execution.md and lifecycle.md for tone and structure |
| One file only, diff = exactly protocols/parallel-exploration.md | yes | No other files touched |
| Did not modify .claude/agents/*.md | yes | Verified via self-check 2 and 3 |
| Commit: conventional commits format | yes | See below |

### Commits
- (see commit created below)
