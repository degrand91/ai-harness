# Walkthrough: a mission from start to close

A worked example showing the exact moves the Orchestrator makes. This is **descriptive**, not prescriptive — the real protocol is in [CLAUDE.md](../CLAUDE.md) and `protocols/`.

The scenario: the user asks for an OAuth login feature in a fictional Next.js app at `~/projects/demo-app`.

---

## Day 0 — intake

**User:** "Add OAuth login (Google + GitHub) to the demo app at `~/projects/demo-app`. Existing email/password should keep working."

**Orchestrator (this Claude session):**
1. Invokes `/mission-start "Add OAuth login (Google + GitHub) to the demo app"` (see [.claude/skills/mission-start/SKILL.md](../.claude/skills/mission-start/SKILL.md)). The skill drives the Orchestrator through scaffold + intake:
   - Picks the id `2026-05-23-add-oauth-login`.
   - Writes `missions/2026-05-23-add-oauth-login/{mission.md, plan.md, contract.md, status.json, log.md}` as stubs.
   - `status.json` starts at `state="intake"`.
2. Authors `mission.md` from `templates/mission-spec.md`, capturing the user's words verbatim.
3. Fans out 4 Explorer subagents **in parallel**:
   - E1: "What auth library does demo-app use today? Cite config files."
   - E2: "Which routes handle auth? Return file:line."
   - E3: "What test runner, lint, typecheck does this repo use?"
   - E4: "Is there an existing OAuth integration anywhere in the repo (any provider)?"
4. Synthesises Explorer findings into `plan.md`:
   - F001: add `next-auth` dependency, configure base
   - F002: implement Google provider + callback
   - F003: implement GitHub provider + callback
   - F004: surface "Sign in with Google / GitHub" buttons on `/login`
   - F005: regression: confirm email/password flow unchanged
5. Authors `contract.md` with assertions like:
   - **C-001 (executable)**: `pnpm typecheck` exit 0.
   - **C-002 (executable)**: `pnpm test` exit 0 with no new skipped tests.
   - **C-003 (executable)**: `pnpm build` exit 0.
   - **C-004 (executable)**: `gitleaks detect` exit 0 (no secrets in diff).
   - **C-005 (behavioral)**: All client IDs/secrets come from `process.env`, never literals.
   - **C-006 (executable)**: After launch, `curl -fsS http://localhost:3000/login` returns 200.
   - **C-007 (user-flow)**: Click "Sign in with Google" → redirect to Google → consent → return to `/dashboard` authenticated.
   - **C-008 (user-flow)**: Existing email/password flow on `/login` still succeeds.
   - **C-009 (negative)**: No file in `src/` exceeds 800 lines after this mission.
6. Updates `status.json` → `state: "awaiting_approval"`. Appends to `log.md`.
7. Surfaces plan + contract to the user.

**User:** "Approved. Go."

Orchestrator records the approval in `mission.md` and `status.json`, transitions to `executing`.

---

## Day 0 → 1 — feature loop, F001

1. Orchestrator scaffolds the feature folder inline with Write:
   - Creates `missions/2026-05-23-add-oauth-login/features/001-add-next-auth-base/` with `spec.md` (from `templates/feature-spec.md`), `status.json` (state="pending"), and `evidence/`.
   - Spec cites `C-001, C-002, C-003, C-005, C-009`.

2. Spawns a Worker via the Agent tool:
   - `model: "sonnet"`
   - `description: "Worker — F001 add-next-auth-base"`
   - prompt = the spec + the contract slice. The Worker's role prompt is loaded from `.claude/agents/worker.md` automatically by `subagent_type: "worker"`. (No previous handoff — this is feature 1.)

3. Worker returns a structured handoff. Orchestrator persists it at `features/001-add-next-auth-base/handoff.md`. Sections all present.

4. Spawns a Scrutiny Validator (`subagent_type: "scrutiny-validator"`, role prompt from `.claude/agents/scrutiny-validator.md`; passed contract slice + diff). Verdict: **green**.

5. F001 has no user-observable behavior. Orchestrator skips User-Testing.

6. Updates `features/001-add-next-auth-base/status.json` → `state: "closed"`, `color: "green"`. Appends to mission `log.md`.

7. Moves to F002.

---

## Day 1 → 2 — feature loop, F002 (with a follow-up)

1. Worker for F002 (Google provider) returns handoff. Scrutiny: **red**.
   - C-005 failed: hardcoded `GOOGLE_CLIENT_SECRET` in `src/lib/auth/providers/google.ts:14`.
   - Validator writes a follow-up spec in its verdict.

2. Orchestrator **does not patch in place**. It scaffolds F002-followup-1 inline (folder + `spec.md` + `status.json`), populating the spec from the Validator's follow-up. Spawns a new Worker (fresh context).

3. Follow-up Worker returns handoff. Scrutiny: **green**.

4. F002 marked closed. `followups: ["F002-followup-1"]`. Moves to F003.

---

## Day 2 → 3 — F003, F004, F005

Similar shape. F004 is user-facing, so:
- Scrutiny Validator runs first.
- **In parallel**, User-Testing Validator launches `pnpm dev`, navigates to `/login`, clicks "Sign in with Google" (using a test account from `.env.test`), follows the consent flow, lands on `/dashboard`. Captures screenshots at each step into `features/004-.../evidence/`.

F005 runs the existing email/password flow as a regression. Green.

---

## Day 3 — close

1. Orchestrator runs the **full** `contract.md` as integration check. All assertions green.
2. Updates `status.json` → `state: "closing"`, then `state: "closed"`, sets `closed_at`.
3. Authors `post-mortem.md` from `templates/post-mortem.md`:
   - Slowest feature: F002 (the follow-up). Why: the contract didn't explicitly flag "no literal credentials" upfront in a way the Worker noticed.
   - Costliest validator: User-Testing, predictably.
   - Distilled learning: a new entry at `learnings/patterns/contract-explicit-no-literal-secrets.md`.
4. Updates `learnings/INDEX.md`.
5. Reports to user.

---

## What the user did

Approved once. That's it.

The mission ran across ~3 days. Each Worker was a fresh subagent. Each Validator was adversarial. State lived on the filesystem, not in any Claude context window. A new Claude session on day 2 could have read `status.json` and continued seamlessly.

## What the harness gained

- A new pattern in `learnings/patterns/`.
- A post-mortem with token/cost data per role.
- A concrete artifact (`missions/2026-05-23-add-oauth-login/`) future missions can grep for prior art.

That's the loop. Repeat for the next mission.
