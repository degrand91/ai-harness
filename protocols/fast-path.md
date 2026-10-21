# Protocol: Fast Path (lanes + conditional validation)

Status: **active** (shipped 2026-10-21).

The full mission model — intake → plan → contract → approval gate → per-feature
worker + two validators → close — is built for **multi-day, high-stakes,
possibly-unattended runs**, where a bad merge at hour 30 is catastrophic and the
ceremony is cheap insurance. It is the wrong gear for a supervised one-line fix:
there, the contract, the `DH-000` hold, and a cold-context worker plus two
validators are pure process tax — tokens and wall-clock spent on the *process*
instead of the *task*.

This protocol adds a lighter gear **beside** the mission model, not in place of
it. Nothing here weakens the full lane; it just stops you paying full-lane
overhead on work that does not need it. [feature-loop.md](feature-loop.md) owns
how one feature runs; this protocol owns **which lane a mission takes** and
**how much validation a feature gets**.

---

## 1. Three lanes

The Orchestrator picks the lane at intake and records it as `lane` in
`status.json`. Like `execution`, it is decided once and not flip-flopped
mid-mission — but unlike `execution` it is a *ceremony* choice, not a *where the
worker runs* choice, and the two are independent.

| | `aside` | `quick` | `full` |
|---|---|---|---|
| For | trivial, reversible, no-logic edit | one small supervised change | large / multi-feature / high-risk / unattended |
| Mission folder | none | minimal (`mission.md` + `status.json` + `log.md`) | full scaffold |
| Contract | none | one-line **done-check**, inline | full `contract.md`, assertion IDs |
| Approval gate | none | inline "go" in the same turn | `DH-000` hold (survives restart) |
| Who writes the code | Orchestrator, directly | one worker (crew or subagent) | workers, one per feature |
| Validation | Orchestrator self-review of the diff | conditional — see §3 | conditional — see §3 |
| Close | show the diff | one-line log entry; learning only if one emerged | full `/mission-review` + post-mortem + learning |

### `aside` — no mission at all

Truly trivial, truly reversible, no behavior change worth verifying: a typo, a
comment, a doc wording fix, a single config value, a version bump, a rename the
tooling can check. The Orchestrator edits directly and shows the diff. This is
the one place the "Orchestrator never edits code" rule yields — because spawning
a fresh-context worker to fix a typo is exactly the waste this protocol exists to
remove. Keep it honest: if you are unsure whether it is trivial, it is not —
use `quick`.

### `quick` — the fast lane

One coherent change a single worker can finish in its context budget: a bug fix,
a small feature, a focused refactor. Minimal ceremony:

1. **Scaffold the minimum.** `missions/<id>/` with `mission.md` (verbatim goal),
   `status.json` (`state: "executing"`, `lane: "quick"`), `log.md`. No
   `plan.md`/`contract.md` files required — the done-check lives inline.
2. **State the done-check inline**, one to three executable lines: the command(s)
   and expected exit code, or the observable behavior, that mean "done". This is
   the contract, shrunk to what a one-feature change needs. Say it to the user.
3. **No `DH-000` hold.** The human is right there. Present the change in two or
   three lines and proceed on a plain "go" in the same conversation. Do **not**
   enter `awaiting_approval`; the quick lane uses `executing` throughout, so the
   turn-end guard never trips on it.
4. **One worker.** Dispatch exactly one worker/crewmate for the change (serial
   rule is trivially satisfied — there is one).
5. **Conditional validation** per §3.
6. **Land** under the project's registered delivery mode, same as full lane.
7. **Close light.** A one-line `log.md` entry. Distil a learning only if the work
   actually surfaced one; no mandatory post-mortem.

If the change turns out to be bigger than one worker can hold, **promote to
`full`**: scaffold the contract, open `DH-000`, and continue. Promotion is
cheap; discovering at hour 2 that you skipped the contract on a real mission is
not.

### `full` — the mission model

Unchanged. Everything in [lifecycle.md](lifecycle.md), [feature-loop.md](feature-loop.md),
and the `mission-start` skill. Use it for anything large, multi-feature,
high-risk, or **unattended**.

---

## 2. Choosing the lane at intake

Default by the shape of the request, then adjust:

- **`aside`** when the change is trivial, reversible, and has no behavior worth
  verifying.
- **`quick`** when the goal is a single coherent change a lone worker can finish,
  the human is supervising, and no item in the always-validate list (§3) is the
  *centre* of the work.
- **`full`** when **any** of these holds:
  - the goal names three or more distinct deliverables, or is an epic/migration;
  - the user says "mission", or asks for an overnight / autonomous / unattended
    run;
  - the work will run under `/afk` or away mode — **unattended ⇒ full**, because
    the `DH-000` hold is what makes an unsupervised restart safe, and the full
    contract is what a validator checks against when you are not watching;
  - the change's blast radius is large or hard to reverse even if the diff is
    small (auth rewrite, data migration, release-pipeline change).

When you are genuinely torn between `quick` and `full`, pick `full` — the cost of
over-ceremony on a small task is a few minutes; the cost of under-ceremony on a
real mission is a silent wrong merge. When torn between `aside` and `quick`, pick
`quick`.

State the lane you picked and one line of why. The user can always say "just do
it" (→ `aside`/`quick`) or "treat this as a full mission" (→ `full`).

---

## 3. Conditional validation (how much a feature gets)

Validation is the biggest per-feature multiplier on wall-clock and tokens:
worker, then scrutiny, then maybe user-testing — two or three cold-context model
invocations per feature. Most of that is deserved on most features. It is **not**
deserved on a fifteen-line mechanical diff, and it is **never** skippable on a
change to an auth path. So choose a tier per feature, from the committed diff.

| Tier | What runs | When |
|---|---|---|
| **T0 — self-review** | Orchestrator reads the diff itself against the done-check; records a one-line verdict in the feature folder. No validator subagent. | Diff is below the trivial threshold **and** touches nothing in the always-validate list. |
| **T1 — scrutiny** | One Scrutiny Validator (routing per the external-provider rule). | The normal case: logic changed, or the diff is non-trivial, but nothing user-observable. |
| **T2 — scrutiny + user-testing** | Both, spawned together in one message. | The change has user-observable behavior (unchanged from today). |

**Trivial threshold** (T0 eligibility), overridable via `config/` single-value
files, same convention as `config/spend-cap-daily`:

- `config/fast-path-max-lines` — default **15** changed lines.
- `config/fast-path-max-files` — default **2** files.
- plus: no new dependency, no new exported symbol / public API, no new control
  flow worth a second pair of eyes. If in doubt, it is not T0 — use T1.

### The always-validate floor (overrides size, forces ≥ T1)

If the diff touches **any** of these surfaces, it is **never** T0 — run at least
scrutiny (T1), and T2 if it is also user-observable — no matter how few lines:

- authentication, authorization, sessions, tokens;
- secrets, credentials, crypto, key handling;
- money, billing, payments, pricing;
- database migrations, schema changes, destructive data ops (`DELETE`, `DROP`,
  mass `UPDATE`);
- file/record deletion, `rm`, other destructive filesystem ops;
- concurrency, locking, transactions;
- CI / release / deploy / publish configuration;
- security-sensitive input handling (deserialization, `eval`, shell exec,
  user-controlled fetch / SSRF-prone paths).

This floor is the whole safety argument for the fast path: speed removes
validation only where a mistake is *cheap to undo*, never where it is expensive.

### Accountability

Whatever tier you pick, **record it and why** in the feature's `log.md` / status
(e.g. `validation: T0 (self-review) — 8 lines, 1 file, no sensitive surface`).
A skipped validator is a deliberate, logged decision, not a silent omission.
Skipping validation to hit a deadline on a sensitive diff is exactly the kind of
corner the always-validate floor exists to forbid — do not route around it.

T0 applies in **every** lane, including `full`: a trivial feature inside a big
mission still only needs a self-review. The lane sets the ceremony; the tier sets
the validation; they are independent.

---

## 4. What does not change

- **Serial execution.** `quick` runs one worker; `full` runs one at a time.
  Nothing here lets two workers touch the same files at once.
- **Creator ≠ verifier where it matters.** T1/T2 keep the fresh-context,
  reasoning-blind validator. T0 is the Orchestrator reviewing a diff small enough
  that the separation buys nothing.
- **Never end red.** A failed T0/T1/T2 is a re-brief / follow-up, same as today.
- **Delivery.** `quick` lands under the same registered mode and sandbox as
  `full`. The fast path changes ceremony, not where code can go.
- **Unattended safety.** Away mode / `/afk` ⇒ `full` lane. The fast path is a
  supervised-work optimisation.
