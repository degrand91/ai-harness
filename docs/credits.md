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

## scroll-craft (nateherk-design)

**Source:** https://github.com/nateherkai/scroll-craft
**License:** MIT, Copyright (c) 2026 Nate Herk

The `scroll-craft` skill at [`.claude/skills/scroll-craft/`](../.claude/skills/scroll-craft/) is a **verbatim vendored copy** of the `nateherk-design` plugin's skill (plugin v0.3.1, from upstream commit `75d81f7`, vendored 2026-10-21). It is an agent skill for building premium scroll-driven landing pages. It is bundled into the harness rather than installed as a separate Claude Code plugin so the harness stays self-contained.

Provenance, prerequisites (Node 18+, ffmpeg, playwright-core, optional `KIE_AI_API_KEY`), and update instructions are recorded in [`.claude/skills/scroll-craft/UPSTREAM.md`](../.claude/skills/scroll-craft/UPSTREAM.md). The upstream MIT license travels with the folder at [`.claude/skills/scroll-craft/LICENSE`](../.claude/skills/scroll-craft/LICENSE). Unlike the core harness (bash/jq/coreutils only), this skill carries its own runtime dependencies, which apply only when it is invoked.

---

## Official Anthropic skills (anthropics/skills)

**Source:** https://github.com/anthropics/skills
**License:** Apache 2.0 (each vendored folder keeps its own `LICENSE.txt`)

Four skills are **verbatim vendored copies** from the official Anthropic skills
repository (vendored 2026-10-21 from commit `dbd4588`), bundled so the harness
ships self-contained rather than depending on a separately-installed plugin:

- [`skill-creator`](../.claude/skills/skill-creator/) — create, edit, and eval new skills; accelerates extending the harness itself.
- [`mcp-builder`](../.claude/skills/mcp-builder/) — build MCP servers (the harness already leans on MCP: Playwright, external-validator provider).
- [`webapp-testing`](../.claude/skills/webapp-testing/) — Playwright-based local web-app testing; complements the `user-testing-validator`. Needs Python + Playwright when invoked.
- [`frontend-design`](../.claude/skills/frontend-design/) — distinctive, non-templated UI design guidance; pairs with `scroll-craft` and `design-quality.md`.

Per-skill provenance and dependencies are recorded in each folder's `UPSTREAM.md`.
These skills carry their own runtime dependencies (where any), which apply only
when the skill is invoked — the core harness stays bash/jq/coreutils-only.

---

## Inspirations

The harness's overall design draws on the **Factory.ai Missions pattern** — a multi-agent architecture that separates orchestration, implementation, and validation into distinct roles with fresh context per agent and a contract-first approach to defining "done." This design is documented in detail in [ARCHITECTURE.md](../ARCHITECTURE.md).
