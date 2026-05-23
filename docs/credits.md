# Credits

## ECC (Engineering Common Conventions)

**Source:** https://github.com/affaan-m/ECC
**License:** MIT, Copyright (c) 2026 Affaan Mustafa

The following harness components were imported from or directly inspired by ECC:

### Agents (8 — verbatim ports with frontmatter adjustment and attribution comments)

- `architect` — system design specialist (opus)
- `harness-optimizer` — meta-tuning agent (sonnet)
- `refactor-cleaner` — dead-code cleanup (sonnet)
- `doc-updater` — documentation automation (haiku)
- `security-reviewer` — OWASP / secrets / injection detection (sonnet)
- `code-reviewer` — general code review
- `silent-failure-hunter` — flaky test / hidden error detection
- `tdd-guide` — TDD workflow enforcement

### Skills (1 — ECC-inspired minimal implementation)

- `skill-stocktake` — audit harness `.claude/skills/` inventory

### Hooks (1 — ECC-inspired minimal implementation)

- `post-tool-use-failure.sh` — PostToolUseFailure event handler

### Scripts (1 — original POSIX bash, inspired by ECC's `harness-audit.js`)

- `harness-audit.sh` — operator-readiness audit script covering 9 checks; adapted from the design of ECC's `harness-audit.js` as an original POSIX bash reimplementation

### MIT License (short form)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Full license text: https://opensource.org/license/mit

---

## Inspirations

The harness's overall design draws on the **Factory.ai Missions pattern** — a multi-agent architecture that separates orchestration, implementation, and validation into distinct roles with fresh context per agent and a contract-first approach to defining "done." This design is documented in detail in [ARCHITECTURE.md](../ARCHITECTURE.md).
