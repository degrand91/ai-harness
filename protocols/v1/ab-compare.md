# Protocol: A/B Comparison of Paired Mission Post-Mortems

The harness improves over time only if improvement is measured. This protocol compares two structurally similar missions by reading their `post-mortem.md` files and surfacing a structured delta across key axes. The result is a written artifact and, when regressions are found, a proposal for the next planning cycle.

Run this procedure **after** a milestone (v-bump, quarterly review) or on demand from the operator.

---

## Purpose

Post-mortems capture per-mission insight. A/B comparison turns that per-mission data into a longitudinal signal: is the harness getting faster? Are first-pass green rates rising? Are the same validator assertions failing repeatedly?

Without explicit comparison, patterns of improvement or regression stay invisible. This protocol makes them legible.

---

## When to Run

| Trigger | Notes |
|---------|-------|
| Quarterly self-review | Pick the two most recent missions with comparable scope |
| After a major version milestone (v1.0, v2.0, …) | Compare the mission that shipped the milestone against its immediate predecessor |
| On operator demand | Operator specifies mission A and mission B explicitly |
| Two or more consecutive validator failures on the same assertion | Run immediately, single axis only |

Do not run if no second comparable mission exists yet. A comparison of N=1 is not a comparison.

---

## Procedure

Complete steps 1–5 in order. Record all findings; do not edit as you go.

1. **Select mission A and mission B.**
   Missions must be structurally similar: same order-of-magnitude feature count, same mission type (feature-shipping, refactor, documentation, etc.). If the operator has specified both, use those. Otherwise choose the two most recent missions of matching type from `missions/`. Note the selection rationale in the output artifact.

2. **Read both `post-mortem.md` files end-to-end.**
   Locate `missions/<id>/post-mortem.md` for each mission. Read fully before building the comparison table. Do not skim — surface-level numbers without context produce misleading deltas.

3. **Construct the structured comparison table.**
   The table must cover at minimum these axes:

   | Axis | Mission A value | Mission B value | Delta | Direction |
   |------|-----------------|-----------------|-------|-----------|
   | Feature count | | | | |
   | First-pass green rate (%) | | | | |
   | Follow-up feature count | | | | |
   | Validator failures by assertion | | | | |
   | Estimated token spend per role | | | | |
   | Wall-clock duration (hours) | | | | |

   "Direction" is `improved`, `regressed`, or `neutral`. Populate all cells; use `n/a` if the post-mortem did not record a value, and note the gap — missing data is itself a signal.

4. **Identify regressions and improvements.**
   Write a short narrative paragraph (3–6 sentences) for each axis that moved in a meaningful direction. "Meaningful" means: first-pass green rate moved more than 5 percentage points, follow-up feature count changed by more than 1, or wall-clock duration changed by more than 20%. Ignore noise-level variation.

5. **Act on regressions.**
   For each regression axis:
   - If a `learnings/anti-patterns/` entry already covers it, update the entry with the new data point.
   - If no entry exists, create one at `learnings/anti-patterns/<slug>.md` using the template in `learnings/README.md`.
   - If the regression is likely addressable by a protocol or template change, open `learnings/proposals/<slug>.md` with `status: open`. Flag it for the next mission's self-review (see Cross-references).

---

## Output Shape

Produce a single file: `missions/<id>/comparison.md` (where `<id>` is the mission that triggered this run, or a dedicated comparison record if run outside a mission context). The file must contain:

1. **Header** — date, mission A id, mission B id, selection rationale.
2. **Comparison table** — from step 3.
3. **Narrative** — per-axis paragraphs from step 4.
4. **Actions taken** — list of anti-pattern entries created/updated and proposals opened (or "None" if clean).

Keep it concise. The table is the primary artifact; the narrative explains non-obvious deltas. No padding.

---

## Cross-references

- **`protocols/self-review.md`** — intake-time self-review; reads learnings at the start of a mission. A/B compare feeds learnings entries that self-review will later consume.
- **`learnings/README.md`** — templates for pattern, anti-pattern, and proposal entries; hygiene rules for the learnings corpus.
- **`learnings/INDEX.md`** — use to locate existing entries before opening a new anti-pattern or proposal.
- **`protocols/lifecycle.md`** — the `/mission-review` close step is the natural trigger for this protocol when run at mission end.
