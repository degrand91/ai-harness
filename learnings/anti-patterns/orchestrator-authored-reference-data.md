# Anti-pattern: orchestrator-authored reference data treated as ground truth

**Seen in:** 2026-09-21-creep-routes (F011, F011-followup-1, F011-followup-2)

## What happened

The orchestrator harvested item-drop pools from an external wiki and checked the result in as a reference file, then wrote a feature spec whose assertions compared the code's output against it. The harvest had a defect: a fixed-length cap ran past the end of the Items block and swallowed the next camp's icons.

A worker implemented the spec faithfully and *removed correct data* to match the bad reference. Scrutiny passed it — the contract said "match the reference", and it did. The error only surfaced when the user looked at the UI and said the icons were wrong.

Scored afterwards: the original data was right 2 of 12 times, the "fix" 3 of 12.

## Why it is seductive

Reference data feels like part of the contract — the fixed thing you validate *against*. But the orchestrator generated it with a script, under time pressure, without review. It is code output wearing the costume of ground truth, and it inverts the Creator–Verifier relationship: the verifier now checks the creator against the orchestrator's unreviewed artifact.

## Do this instead

- **Validate the reference before a worker sees it.** Give it its own assertion: re-derive a sample independently and require exact agreement. A 6-item pool checked by hand would have caught this in a minute.
- **Record confidence, not just values.** The corrected harvest stored an observed-occurrence count per entry; entries seen once are suspect. Bare values hide that.
- **Make the worker cite the primary source, not the reference.** The redo derived pools from the raw game tables and used the wiki only to confirm. It also caught that the spec's prose deltas had inverted signs — because it had a source of truth to check the prose against.
- **When a reference-driven feature goes red, re-score both versions.** Do not assume the newer one is better; the redo was only 3/12 before it was rebuilt properly.

## Tell

Any spec sentence of the form "match `<file the orchestrator just generated>`". If the orchestrator made it this session and no one checked it, it is not a contract — it is an untested dependency.
