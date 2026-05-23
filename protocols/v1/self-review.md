# Protocol: Orchestrator Self-Review at Intake

Before scaffolding a plan, the Orchestrator reads its own past performance. This keeps recurring mistakes from compounding across missions and surfaces open proposals that belong in the current scope.

Run this procedure **after** capturing `mission.md` and **before** writing `plan.md`.

---

## Purpose

The harness accumulates institutional memory across missions in three stores:

- `.claude/agent-memory/orchestrator/MEMORY.md` — short-term scratchpad, updated each turn
- `learnings/patterns/*.md` — proven approaches worth repeating
- `learnings/anti-patterns/*.md` — failure modes confirmed across missions
- `learnings/proposals/*.md` — proposed protocol/template edits awaiting a decision

Without an explicit intake step, this memory sits unused. The Orchestrator repeats the same mistakes, misses applicable patterns, and ignores proposals that were meant for exactly this kind of mission.

---

## Procedure

Complete steps 1–6 in order. The whole procedure should take the Orchestrator 5–10 minutes of reasoning. It is not a literature review.

1. **Read `MEMORY.md` end-to-end.**
   Open `.claude/agent-memory/orchestrator/MEMORY.md`. Note any warnings, open decisions, or recurring notes flagged in previous sessions. Carry forward anything still applicable.

2. **Scan `learnings/patterns/` for relevant entries.**
   Read `learnings/INDEX.md` first — it indexes entries by tag and description. Pull the top-N entries whose `tags` or `description` overlap with the current mission's goal. Read those entries in full. Patterns are there to be reused — if one applies, build on it.

3. **Scan `learnings/anti-patterns/` for recent recurrences.**
   Same process: check `INDEX.md`, read the matches. If an anti-pattern was triggered in the last one or two missions, weight it heavily — recurrence suggests it is systemic, not a one-off.

4. **Scan `learnings/proposals/` for open proposals.**
   For each `.md` file with `status: open`, ask: "Does this mission have natural scope to land this change?" If yes, add the proposal as a feature in `plan.md` and note the proposal slug in the feature spec. If no, carry it forward unchanged.

5. **Compile findings into `plan.md`.**
   Add a short "Self-review at intake" or "References" section near the top of `plan.md`. List:
   - Patterns applied and where
   - Anti-patterns to guard against, with the specific features they affect
   - Open proposals being addressed (or explicitly deferred, with reason)

   Do not pad this section. If nothing relevant was found, write "Nothing relevant found." and continue.

6. **Open a new proposal if a recurring failure has no proposal yet.**
   If step 3 surfaces a failure that has appeared in two or more missions but has no corresponding `learnings/proposals/` entry, draft one now — in `learnings/proposals/<slug>.md` with `status: open` — before locking the plan. Use the template in `learnings/README.md`. Do not delay this to post-mortem; by then context is cold.

   If the Scout subagent is available (see Cross-references), delegate the cross-mission memory query in steps 2–4 to a Scout spawn rather than loading every entry yourself.

---

## What this is NOT

- **Not a deep retrospective.** Post-mortems happen at mission close (`/mission-review`). This is a targeted read, not a synthesis exercise.
- **Not optional reading.** The Orchestrator does not skim once and then ignore what it found. Findings must appear in `plan.md` — that is the paper trail.
- **Not a blocker on approval.** Self-review produces inputs to planning. It does not add a second approval gate. The only mandatory human gate remains `awaiting_approval → executing` (see `protocols/lifecycle.md`).
- **Not exhaustive coverage.** Read the top-N relevant entries, not the entire corpus. Use `INDEX.md` to filter. If the index is stale or absent, scan filenames and frontmatter `description` fields.

---

## When to skip

| Condition | Skip? |
|-----------|-------|
| Trivial smoke-test or single-command mission | Yes — skip steps 2–4; still read `MEMORY.md` (step 1) |
| Repeat of a mission run within the last 24 hours with no new failures | Yes — findings from the previous run are still warm |
| Substantive feature mission, any complexity | No — always run all six steps |

When in doubt, run the procedure. It is cheap. Skipping it and repeating a known anti-pattern is expensive.

---

## Cross-references

- **`protocols/lifecycle.md`** — this procedure sits in the `intake → planning` transition, after `mission.md` is captured and before `plan.md` is written.
- **`learnings/README.md`** — templates for pattern, anti-pattern, and proposal entries; hygiene rules.
- **`learnings/INDEX.md`** — machine-curated index; use this as the entry point for steps 2–4.
- **`.claude/agent-memory/orchestrator/MEMORY.md`** — step 1 target; also updated at mission close.
- **Scout subagent** (`.claude/agents/scout.md`, v0.4+) — read-only subagent for cross-mission memory queries. Spawn a Scout instead of loading large learning corpora directly when the relevant entry set is unclear. Pass the mission goal as the query; the Scout returns a ranked list of matching entries.
