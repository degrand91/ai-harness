# Troubleshooting

## Stop hook blocks session end

**Symptom.** Attempting to end the Claude Code session produces:

```
[Stop hook] Refusing to end — open red status detected:
  - Mission 2026-05-23-my-mission: red features without follow-ups: F003
```

**Cause.** `stop-no-red-status.sh` reads every `missions/*/status.json` and exits 2 if any active mission contains a feature with `color: "red"` and no closed follow-up.

**Fix options (pick one):**

1. **Open a follow-up feature.** This is the correct path. Spawn a Worker with the failing assertions as its acceptance criteria. When Scrutiny returns green, the Orchestrator updates `status.json`.
2. **Abandon or pause the mission.** If you intentionally want to stop, set `status.json`.`state` to `"abandoned"` or `"paused"`. The hook skips missions in those states.
3. **Mark the mission closed manually.** If work is actually complete but `status.json` was not updated, set `state: "closed"` and confirm no genuine failures remain.

Do not bypass the hook with `--no-verify`. Diagnose the root cause first.

---

## Worker hits a permissions block when writing to `.claude/`

**Symptom.** Worker returns a BLOCKED handoff or a Bash error like `permission denied` when trying to write to `.claude/agents/` or `.claude/hooks/`.

**Cause.** `settings.json` `permissions.allow` does not include `Write(./.claude/**)` or `Edit(./.claude/**)`. Workers are scoped to `missions/**` and `learnings/**` by default.

**Fix.** Workers should not be writing to `.claude/`. If the feature spec asks a Worker to modify harness internals (agents, hooks, settings), that is a spec error. The Orchestrator should implement such changes directly or open a dedicated meta-mission feature with elevated permissions. Update the spec before re-spawning.

---

## Validator returns prose preamble; verdict parsing fails

**Symptom.** The Scrutiny Validator returns something like:

```
I'll review the code and verify assertions now.

## Feature: my-feature — Scrutiny Verdict: green
...
```

The Orchestrator's downstream parser expects the reply to begin with `## Feature:` and fails.

**Cause.** Chat-optimised models default to a conversational pre-note even when instructed otherwise. Documented in `learnings/anti-patterns/validator-prose-preamble.md`. Recurred across 8 confirmed instances on Haiku as of v0.3.

**Fix (operational).** The Orchestrator applies defensive verdict parsing: extract the block starting at the first `## Feature:` heading, discard everything before it. If the verdict content itself is correct, this absorbs the drift without re-spawning.

**Fix (structural — not yet applied as of v1.0).** Tighten the Scrutiny Validator role prompt per the anti-pattern recommendation: replace the current "Return only the verdict markdown" instruction with a stricter gate that names the protocol violation explicitly.

---

## `settings.json` deny rule blocks `contract.md` writes

**Symptom.** Attempting to write `missions/<id>/contract.md` fails with a permission denial. Error may appear as a Write tool refusal.

**Cause.** An overbroad `Edit(./contract.md)` or `Write(./contract.md)` deny rule in `settings.json` matches `missions/<id>/contract.md` because the rule lacks a directory anchor. Documented in `learnings/anti-patterns/sanity-check-settings-deny-at-intake.md`.

**Fix.** At mission intake, run:

```bash
find . -name contract.md
```

If more than one result appears, any deny rule on `./contract.md` is overbroad. Either remove the rule, or scope it to the specific top-level file (e.g., `Edit(./top-level-contract.md)`).

Claude Code applies permission changes mid-session — no restart needed after editing `settings.json`.

---

## Mission cannot resume after session restart

**Symptom.** After restarting Claude Code, the Orchestrator does not pick up the in-progress mission.

**Cause.** The `SessionStart` hook (`session-start-inject-status.sh`) injects context only if the most-recently-modified mission directory contains a `status.json` with `state` other than `closed` or `abandoned`. If the state file is missing or stale, the hook emits `{}` and the Orchestrator starts with no context.

**Fix.** Run `/mission-status` or `/mission-resume` manually after restarting. Both skills read the filesystem directly and do not rely on the hook. If the mission folder has a `checkpoint.json`, `/mission-resume` will use it to reconstruct in-flight context.

---

## `pre-agent-spawn-serial.sh` blocks a valid Worker spawn

**Symptom.** A Worker spawn is rejected with:

```
[pre-agent-spawn-serial] Refusing concurrent non-explorer subagent spawn.
Already in-flight non-explorer subagent.
```

**Cause A.** A previous Worker genuinely crashed without releasing the lock. The `agent-spawn-state.json` file has `in_flight_non_explorer: true` but `updated_at` is more than 600 seconds ago. The hook has a stale-lock reset that should have handled this; check whether the timestamp is correct.

**Cause B.** Two Workers were attempted in the same session without the SubagentStop hook firing (e.g., the hook errored). The lock was never released.

**Fix.** Manually reset the state file:

```bash
echo '{"in_flight_non_explorer":false,"explorer_count":0,"updated_at":"2000-01-01T00:00:00Z"}' \
  > .claude/hooks/agent-spawn-state.json
```

Then re-spawn the Worker normally.

---

## Worker returns a non-structured handoff

**Symptom.** Worker reply does not begin with `## Feature:`.

**Cause.** The model drifted from its role prompt (same class as the Validator preamble issue), or the Worker encountered an unrecoverable error and returned a plain error message.

**Fix.** Treat the feature as incomplete. Re-spawn the Worker with the same spec plus a note:

> "Your previous attempt did not return a structured handoff. Your reply MUST begin with `## Feature:`. Do not add any prose before that heading."

If the same Worker fails twice in a row, escalate to the user — the spec may be genuinely ambiguous or the environment may be broken.

---

## Git commit is rejected by a pre-commit hook in the target repo

**Symptom.** Worker handoff reports exit code 1 on the commit step. Bash output shows a pre-commit hook (e.g., lint, type-check) failing.

**Cause.** The repository being modified has its own pre-commit hooks that the Worker's code does not satisfy.

**Fix.** Do not bypass with `--no-verify`. Fix the underlying issue (run the linter/formatter, fix the type error) and re-commit. The Worker's role prompt already forbids `--no-verify`; if the Worker ignored this, treat the handoff as non-compliant and re-spawn.
