# Command: mission-start

> Invoke this when the user describes a new software goal inside the harness folder. This is the canonical entry point.

## What it does

Walks the Orchestrator through Intake → Plan → Contract → Approval gate. It does **not** execute features — that's the loop the Orchestrator enters on approval.

## Procedure

1. **Confirm goal.** Restate the user's goal in their own words. Ask only the questions you cannot infer.

2. **Decide mission id.** `YYYY-MM-DD-<kebab-slug>` based on today's date and a 3–5 word slug of the goal. Strip filler words ("the", "a", "to", "of"). Example: goal = "Add OAuth login to the demo app" → `2026-05-23-add-oauth-login-demo`.

3. **Scaffold the folder yourself.** No shell script. Create exactly these files with the Write tool:

   ```
   missions/<id>/
   ├── mission.md       ← stub headline + the user's verbatim goal
   ├── plan.md          ← one-line stub ("populate from templates/plan.md")
   ├── contract.md      ← one-line stub ("populate from templates/validation-contract.md")
   ├── status.json      ← state="intake", started_at=<now UTC>, see templates/status-schema.md
   ├── log.md           ← one entry: "[<now>] state=intake — folder created. goal: <verbatim>"
   └── features/        ← empty
   ```

   The `status.json` shape is exactly what's in [templates/status-schema.md](../templates/status-schema.md). Default the `models` block to the defaults declared there. Token counters start at 0.

4. **Author `mission.md`** using [templates/mission-spec.md](../templates/mission-spec.md). Capture the user's words verbatim where possible. Do not editorialise.

5. **Read `learnings/patterns/` and `learnings/anti-patterns/`** if any exist. Pull anything topical into the planning context.

6. **(Optional but recommended) Fan out 3–5 Explorer subagents** in parallel against the target repo to surface what you need for the plan:
   - "What test runner, lint runner, typecheck runner is used? Cite config files."
   - "What's the existing structure of `src/<area-touching-mission>/`?"
   - "Are there existing utilities that solve any subset of this?"
   - (more depending on the mission)

7. **Author `plan.md`** using [templates/plan.md](../templates/plan.md). Decompose into features, ordered serially. Each feature cites the contract assertion IDs it will satisfy.

8. **Author `contract.md`** using [templates/validation-contract.md](../templates/validation-contract.md). Cover: build/typecheck/test, behavioral, negative, structural, accessibility/performance if applicable.

9. **Update `status.json`** to `state = "awaiting_approval"`. Append to `log.md`.

10. **Present to user.** Surface plan + contract paths and a one-paragraph summary. Wait for explicit approval.

11. **On approval**, transition to `state = "executing"`, record the approval timestamp in both `status.json` and `mission.md`, then enter the feature loop (see [protocols/orchestrator.md](../protocols/orchestrator.md) §Feature loop).

## Scaffolding rules (so this stays reproducible)

- Use the Write tool, not Bash. The harness has no scaffolding script.
- Timestamps are ISO-8601 UTC. Use the actual current time, not a placeholder.
- `mission_id` in `status.json` must match the folder name exactly.
- Don't author content into the stubs before steps 4/7/8 — keep intake/plan/contract phases distinct so each one gets full attention.

## Inputs the Orchestrator collects

- Repository path (absolute).
- Branch base (existing branch or "create new").
- Test/lint/typecheck commands (Explorer can find these).
- Launch recipe if the mission is user-facing.
- Any user-provided files/URLs.

## What NOT to do

- ❌ Start writing application code in the same session. The Orchestrator never edits application files.
- ❌ Skip the contract because "the plan is obvious."
- ❌ Skip the approval gate because Auto Mode is on. The approval gate is mandatory; it's the user's single point of leverage.
- ❌ Ask 10 clarifying questions. Make the reasonable calls; the user will redirect.
- ❌ Shell out to a script for scaffolding — the templates are the source of truth, and Write is the tool.

## Output

A folder at `missions/<id>/` with:
- `mission.md` — populated.
- `plan.md` — populated.
- `contract.md` — populated.
- `status.json` — `state: "awaiting_approval"`.
- `log.md` — at least one entry.

…and a message to the user with the path and a one-paragraph summary, asking for explicit approval.
