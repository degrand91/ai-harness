---
name: stow
description: Sweep the session for durable knowledge that has not been written down, file each finding to its correct home, and curate the learnings corpus so it does not grow without bound. Use at the end of a session or a mission, or when the captain says to write something down.
argument-hint: [--apply]
allowed-tools: Bash(./scripts/learnings-curate.sh *), Bash(./scripts/learnings-index.sh *), Read, Write, Edit
---

## Corpus health

!`${CLAUDE_PROJECT_DIR}/scripts/learnings-curate.sh`

---

Two jobs, in order.

### 1. Sweep

Go back over this session and find what is **durable and unwritten**. Not a summary — the specific things a future session would have to rediscover:

- a trap that cost real time, and what the tell was
- an approach that worked and would work again
- a fact about the captain's preferences or working style
- something about a project that anyone touching it should know

Ignore anything the repo already records. Code structure, git history, what a file does — a future session can read those. A note that restates the readable is noise that crowds out the notes that are not.

### 2. Route

Each finding goes to **exactly one** home ([protocols/knowledge-routing.md](../../../protocols/knowledge-routing.md)):

| The fact is… | It belongs in… |
|---|---|
| how the captain likes to work | `.claude/agent-memory/orchestrator/` |
| an operational fact about **this harness** | `learnings/patterns/` or `learnings/anti-patterns/` |
| scoped to one task or feature | the mission folder |
| the finding of an investigation | that scout's report |
| useful to anyone working on project X | that project's committed `AGENTS.md` — **via a crewmate**, through its registered delivery path. The harness never writes into a project directly. |
| a proposed change to a protocol or prompt | `learnings/proposals/` |

A fact copied into two places will be corrected in one. If it seems to belong in two, it is usually two different facts — split it.

### 3. Curate

The report above tiers the corpus. Read the verdict, do not fight it:

- **Within budget** — say so and stop. Do not tidy for its own sake.
- **Over budget** — the report names the coldest entries. Present them to the captain and ask. Only run `--apply` if they agree.
- **"needs a human decision"** — every cold entry is an anti-pattern. Say that plainly; do not look for something else to trim.

**Anti-patterns are never archived automatically.** A trap you stopped hitting is exactly the one you are about to hit again; its absence from recent missions is evidence it is *working*, not evidence it is stale.

Archiving moves a file to `learnings/archive/`. Nothing is ever deleted.

After adding or moving anything, regenerate the index:

```
./scripts/learnings-index.sh
```
