---
name: spec-fix-recipe-contradicts-contract-sequence
description: A follow-up spec that prescribes a fix recipe and unit tests derived from the bug report — instead of from the contract's step sequence — can be "green" on its own tests while still failing the contract, or over-correct into a new UX bug. Write follow-up tests as the contract sequence first, then check the recipe against them.
introduced_in_mission: 2026-09-17-wc3-build-order-overlay
tags: [contract, follow-up, spec, validator]
---

## Anti-pattern

On a red user-test verdict (C-015 step 5: first `step_next` skipped a `0:00` first step), the orchestrator wrote the follow-up spec from the validator's root-cause note: "add an `engaged` flag; `startTimer` and `jumpToStep` set it; from reset, next → first timed step". The listed unit tests all started from `resetTimer()`. The worker implemented the recipe, all unit tests went green, and its own browser re-check of the contract sequence (Play → wait 1.5 s → next) still failed — because after Play the 0:00 row was already active and the recipe's tests never covered that path. The worker then "fixed" it by making `startTimer` not engage, which made the **first-ever** next press rewind to 0:00 even mid-game: a worse UX bug that was invisible to the spec's tests and to the literal contract step.

The real defect was in the contract: step 5 assumed no row was active after Play, which is false whenever the first step is `0:00`. Two rounds were spent implementing around a wrong expectation.

## Do instead

1. On a red behavioural verdict, before writing the follow-up, **replay the contract sequence by hand against the intended semantics** and ask: is the expectation itself right for this data? If not, amend the contract first (log it), then spec.
2. Write the follow-up's tests as **the contract's step sequence** (Play → wait → next; reset → next; next while playing) — not as abstract calls from a reset state.
3. Prefer defining the invariant ("next = the timed step after the active row; from reset, the first timed step") over prescribing which functions set which flag; let the worker choose the mechanism.

## Origin

`missions/2026-09-17-wc3-build-order-overlay/post-mortem.md` — F004 → F004-followup-1 (two commits, `9fae97b` over-correction, `7571803` correct), contract amendment to C-015 steps 4/5/5b.

Related: [[contract-defect-amend-not-patch]], [[spec-prescribe-framework-idioms]]
