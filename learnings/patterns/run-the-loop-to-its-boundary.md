---
name: run-the-loop-to-its-boundary
description: A supervision loop's defects live at its edges — expiry, handover, the gap after it stops — and single-tick tests cannot reach them; run it to its deadline on a compressed clock.
introduced_in_mission: 2026-09-09-close-open-items
tags: [away-mode, watcher, testing, supervision, handover]
---

## Pattern

Test a long-running supervision loop by **running it to its boundary**, not by
driving one iteration at a time. Compress its clock with the intervals it
already exposes and let it reach its own deadline, unattended.

The interesting failures are not in the tick. They are at the edges: what
stops, what is left behind, and who is supposed to take over.

## Why

Away mode had fifteen tests. Every one called `afk.sh tick` once by hand, and
every one passed. The loop itself — daemon, digest, escalation ladder, wedge
alarm — had never run.

A four-minute run with `HARNESS_AFK_POLL=5` and `HARNESS_WEDGE_MINUTES=1`
confirmed the ladder was sound, and then found what no single-tick test could
reach:

> The daemon stops at its deadline. Its marker file survives until the operator
> returns. The watcher stands down while that marker exists. So between
> expiry and the operator's return, **nothing supervises the fleet at all** —
> after one expiry notification that may have gone nowhere.

That gap is unbounded, and an 8h away mode expiring overnight lands squarely in
it. No test of `tick` could have found it, because `tick` is not where it
lives — it lives in what happens *after the loop stops*.

## How to apply

- Compress the clock, don't fake it. Use the intervals the loop already reads
  from the environment, so the code under test is the real code.
- Let it hit its **own** deadline rather than killing it. What the loop does on
  the way out is the part nothing else exercises.
- Then ask the handover question: when this stops, who takes over, and what
  tells them to? If the answer is a single notification, that is the wedge the
  system was built to prevent, reappearing at the boundary.
- A marker that means "X is running" must carry a deadline, and readers must
  ask about the deadline. Presence alone outlives the thing it marks.

## Related

[[ledger-first-over-process-state]] — the same shape one level down: a file
that outlives the process it describes, and readers that must know which
question they are asking.
