---
name: mission-start
description: Start a new harness mission. Walks the Orchestrator through Intake → Plan → Contract → Approval gate. Use when the user describes a software goal inside the harness folder. Do not invoke automatically — the user always starts a mission explicitly.
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

## Existing learnings to consult
!`ls -1 ${CLAUDE_PROJECT_DIR}/learnings/patterns 2>/dev/null | grep -v '^\\.gitkeep$' || echo "(no patterns yet)"`
!`ls -1 ${CLAUDE_PROJECT_DIR}/learnings/anti-patterns 2>/dev/null || echo "(no anti-patterns yet)"`

---

You are the Orchestrator. Start a new mission for the goal above. Follow this procedure exactly — no shortcuts.

## 1. Confirm goal

Restate the goal in the user's own words. Default to making reasonable calls — but if you are genuinely unsure about something that would significantly affect the plan (ambiguous scope, unclear tech stack choice, conflicting requirements), surface those questions. Bundle them with the plan presentation at step 10 — don't ask 10 questions before doing anything.

Resolve all relative dates to absolute dates.

**GitHub issue intake.** If the goal is or contains a GitHub issue URL (e.g., `https://github.com/owner/repo/issues/123`), fetch the issue details before doing anything else:

```bash
gh issue view <url> --json title,body,labels
```

Use the returned `title` as the mission slug basis and `body` as the verbatim goal text to record in `mission.md`. Store the original issue URL in `mission.md` under a `## Source` heading so it can be referenced at close. The `gh` CLI must be authenticated (`gh auth status`) for this to work — if it is not, fall back to treating the URL as a plain text goal and note the auth issue.

Example:

```
/mission-start https://github.com/owner/repo/issues/42
```

This fetches issue #42, uses its title and body to populate the mission, and records the URL for auto-close at review time.

## 2. Decide mission id

Format: `YYYY-MM-DD-<kebab-slug>` based on today's date and a 3–5 word slug of the goal. Strip filler words ("the", "a", "to", "of"). Examples:
- "Add OAuth login to the demo app" → `2026-05-23-add-oauth-login-demo`
- "Migrate auth middleware from cookies to JWT" → `2026-05-23-migrate-auth-jwt`

## 3. Scaffold the mission folder

Create `missions/<id>/` with the Write tool. Drop these files exactly:

```
missions/<id>/
├── mission.md       ← stub headline + the user's verbatim goal
├── plan.md          ← one-line stub ("populate from templates/plan.md")
├── contract.md      ← one-line stub ("populate from templates/validation-contract.md")
├── status.json      ← state="intake", started_at=<now UTC>, see templates/status-schema.md
├── log.md           ← one entry: "[<now>] [session=${CLAUDE_SESSION_ID:-unknown}] state=intake — folder created. goal: <verbatim>"
└── features/        ← empty (subdirs created per feature later)
```

`status.json` shape: see `templates/status-schema.md`.

**Record `execution` and `target_repo` now.** A mission that decides its execution model later, or changes it half way through, is one nobody can reason about afterwards:

- Set `target_repo` to the absolute path of the project this mission changes.
- Run `./scripts/project.sh list`. If that path is a **registered** project, set `"execution": "crew"` and add `"crew": {"max_concurrent": 1}`. Features will run as crewmates in their own worktrees, and you stay free while they work.
- If it is **not** registered, set `"execution": "subagent"` and say so to the captain, offering to register it: `./scripts/project.sh add <name> <path> --mode <no-mistakes|direct-PR|local-only>`. Do not register it for them — the delivery posture is their decision.

`status.json` shape: see `templates/status-schema.md`. Default the `models` block (orchestrator=opus, worker_default=sonnet, scrutiny_validator_default=haiku, user_testing_validator_default=sonnet, explorer_default=haiku). Token counters start at 0. If the environment variable `CLAUDE_SESSION_ID` is set, include `"session_id": "<value>"` in the status.json; otherwise set it to `"unknown"`.

## 4. Author `mission.md`

Use `templates/mission-spec.md`. Capture the user's words verbatim. Do not editorialise.

## 5. Read relevant learnings

If `learnings/patterns/` or `learnings/anti-patterns/` has any entries relevant to this goal, pull them into your planning context. Cite them in `plan.md` under "References" if they shape decisions.

## 6. (Recommended) Fan out Explorer subagents in parallel

Use the Agent tool with `subagent_type: "explorer"` to map the target repo. Send 3–5 explorers in a single message so they run concurrently. Ask one narrow question each:

- "What test runner, lint runner, typecheck runner is used in <target>? Cite config files."
- "What's the existing structure of `src/<area-related-to-goal>/`?"
- "Are there existing utilities that solve any subset of this goal?"
- (more depending on the mission)

For trivial missions, skip the fanout. For non-trivial ones, do it — the plan quality justifies the cost.

## 7. Author `plan.md`

Use `templates/plan.md`. Decompose into features, ordered serially. Each feature cites the contract assertion IDs it satisfies. Sizing: a single Worker subagent should be able to complete one feature in its context budget (~80k input tokens for Sonnet).

## 8. Author `contract.md`

Use `templates/validation-contract.md`. Cover:
- build / typecheck / test commands (real names — no vague "all tests pass")
- behavioral assertions per user-observable flow
- at least one negative assertion (no secrets, no swallowed errors)
- at least one structural assertion (file size budget, dep budget, etc.)
- accessibility/performance if relevant

Each assertion has a stable ID (C-001, C-002, …). Features in `plan.md` cite these IDs.

## 9. Update state

Set `status.json.state = "awaiting_approval"`. Append a line to `log.md` with timestamp and the transition. (The PostWrite hook may also append automatically — that's fine, idempotent.)

## 10. Present to user. Wait for approval.

Surface:
- Mission id and folder path.
- One-paragraph plan summary.
- Contract assertion count and the names of the highest-stakes assertions.
- If you have clarification questions from planning, list them here (max 3). These are things that, if answered differently, would change the plan. Label them clearly: "Questions before I proceed:"
- The explicit ask: "Approved?"

**File the approval as a decision before you ask for it.**

```
./scripts/hold.sh open <mission-id> --question "Approve this plan and contract?" --options "approve,revise"
```

Approval is `DH-000` — a decision like any other, so `awaiting_approval` stops being a special case and the answer survives a restart or a compaction. The turn-end guard refuses to end a turn on an `awaiting_approval` mission with nothing filed, which is what stops the question evaporating into chat.

When the captain approves, record it (`./scripts/hold.sh answer <mission-id> <id> "approved"`), set `state = "executing"`, and enter the feature loop with `/dispatch`.

**Do not proceed to feature execution until the user says approved.** This is the only mandatory human gate.

## What NOT to do

- ❌ Start writing application code in this session. The Orchestrator never edits application files — Workers do.
- ❌ Skip the contract because the plan is obvious.
- ❌ Skip the approval gate because Auto Mode is on.
- ❌ Ask 10 clarifying questions up front. Make reasonable calls, but surface 1-3 targeted questions at the approval gate if genuinely unsure about plan-altering decisions.

When done with this skill, you should have a fully scaffolded `missions/<id>/` and a question to the user.
