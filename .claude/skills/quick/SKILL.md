---
name: quick
description: Start a quick-lane change — one small supervised change with minimal ceremony. Minimal scaffold, an inline one-line done-check instead of a full contract, no DH-000 approval gate, one worker, then conditional validation. Use when the user describes a single small change and is supervising. Do not use for large, multi-feature, high-risk, or unattended work — that is /mission-start.
disable-model-invocation: true
argument-hint: <goal text>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

## Goal
$ARGUMENTS

## Current date
!`date -u +%Y-%m-%d`

## Current UTC timestamp
!`date -u +%Y-%m-%dT%H:%M:%SZ`

## Existing missions
!`ls -1 ${CLAUDE_PROJECT_DIR}/missions 2>/dev/null | grep -v '^\\.gitkeep$' || echo "(none yet)"`

---

You are the Orchestrator. Run the **`quick` lane** for the goal above — the fast
path for one small supervised change. The point of this lane is to stop paying
`full`-mission ceremony on work that does not need it. See
[protocols/fast-path.md](../../../protocols/fast-path.md).

## 0. Is this actually a quick-lane job?

Proceed here only if **all** hold:

- it is one coherent change a single worker can finish in its context budget;
- the user is supervising (not an `/afk` / away-mode run — unattended ⇒ `full`);
- nothing on the always-validate list (auth, secrets, money, migrations,
  destructive ops, concurrency, CI/release, security-sensitive input) is the
  **centre** of the work. (Touching one of those is fine — it just forces ≥ T1
  validation in step 5. Being *about* one of those means it deserves a `full`
  contract.)

If it is **trivial and reversible** (typo, one config value, doc wording) →
it is an `aside`: just edit it directly, show the diff, stop. Do not scaffold.

If it is **larger than one worker can hold**, or high-risk → stop and use
`/mission-start` for the `full` lane instead. Promotion later is cheap; a real
mission with no contract is not.

## 1. Decide mission id

Format `YYYY-MM-DD-<kebab-slug>`, 3–5 word slug of the goal. Same convention as a
full mission.

## 2. Scaffold the minimum

Create `missions/<id>/` with the Write tool — three files only:

```
missions/<id>/
├── mission.md    ← headline + the user's verbatim goal
├── status.json   ← see below
└── log.md        ← one entry: "[<now>] [session=${CLAUDE_SESSION_ID:-unknown}] lane=quick state=executing — quick-lane change. goal: <verbatim>"
```

`status.json` (lean — no full plan/contract files):

```json
{
  "mission_id": "<id>",
  "state": "executing",
  "lane": "quick",
  "started_at": "<now UTC>",
  "current_feature": "F001",
  "execution": "<crew|subagent>",
  "target_repo": "<abs path>",
  "done_check": "<the one-line done-check from step 3>",
  "features": [ { "id": "F001", "slug": "<slug>", "state": "pending", "color": null, "followups": 0 } ],
  "tokens": {}
}
```

Resolve `execution` / `target_repo` exactly as a full mission does: run
`./scripts/project.sh list`; a registered `target_repo` ⇒ `"execution": "crew"`,
otherwise `"subagent"`. Set `session_id` from `CLAUDE_SESSION_ID` if present.

## 3. State the done-check inline

One to three executable lines: the command(s) + expected exit code, or the
observable behavior, that mean "done". This **is** the contract, shrunk to what a
one-feature change needs. Put it in `status.json.done_check` and say it to the
user.

## 4. Present and proceed on "go"

Show the user, in two or three lines: the mission id, what the one worker will do,
and the done-check. Ask plainly: "Go?"

**No `DH-000` hold.** The user is right here; the inline "go" is the gate. Do not
set `state: "awaiting_approval"` — the quick lane stays `executing`, so the
turn-end guard never trips on it. If the user instead wants the full treatment,
switch to `/mission-start`.

## 5. One worker, then conditional validation

On "go":

1. Dispatch exactly **one** worker/crewmate for F001 (`/dispatch`, or an Agent
   `subagent_type: "worker"` call for the `subagent` model). Then end the turn and
   let the completion notification wake you — do not poll.
2. When it lands, choose the **validation tier** from the committed diff
   ([fast-path.md §3](../../../protocols/fast-path.md)):
   - **T0 (self-review)** — trivial diff (default ≤ 15 lines / ≤ 2 files, no new
     control flow or dependency) **and** nothing on the always-validate list: read
     the diff yourself against the done-check, record a one-line verdict. No
     validator subagent.
   - **T1 (scrutiny)** — logic changed or the diff is non-trivial: one Scrutiny
     Validator (external-provider routing per CLAUDE.md).
   - **T2 (scrutiny + user-testing)** — user-observable behavior: both, together.
   - **Always-validate floor:** a diff touching auth/sessions/tokens,
     secrets/crypto, money/billing, DB migrations or destructive data ops,
     file/record deletion, concurrency/transactions, CI/release config, or
     security-sensitive input handling is **never** T0 — at least T1. Record the
     tier and why in `log.md`.
3. Green → land under the registered delivery mode and mark F001 closed. Red →
   re-brief / follow-up, never a silent patch.

## 6. Close light

One-line `log.md` entry that the change shipped. Distil a `learnings/` entry only
if the work actually surfaced a reusable lesson — no mandatory post-mortem for a
quick-lane change.

## What NOT to do

- ❌ Write a full `contract.md` or open a `DH-000` hold — that is the `full` lane.
- ❌ Run more than one worker, or run two in parallel.
- ❌ Skip validation on an always-validate surface because the diff is small.
- ❌ Use this lane for unattended (`/afk` / away-mode) work — that is always `full`.
