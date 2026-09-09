# Crew spike — Claude Code behaviours the headless design rests on

Run 2026-09-09 against **Claude Code 2.1.266**, in a throwaway git worktree.
§3.0 of `docs/plans/2026-09-09-firstmate-imports.md` required these before any
Phase 3 code was written. Re-run this page's commands if the CLI major version
changes.

| # | Check | Result |
|---|---|---|
| a | SIGINT a `-p` run mid-flight, then `claude --resume <id> -p "<steer>"` | **PASS** |
| b | `-p` with `--disallowed-tools` — no hang, no prompt | **PASS** |
| c | Hooks in the worktree's `.claude/settings.local.json` fire under `-p` | **PASS** |
| d | `--output-format stream-json` yields `session_id`, `usage`, `total_cost_usd` | **PASS** |
| e | The `no-mistakes` gate invocation | **NOT VERIFIED — tool not installed** |

## New finding: the prompt must come from stdin

`--allowed-tools` and `--disallowed-tools` are **variadic** (`<tools...>`), so a
positional prompt after them is swallowed as another tool name:

```
$ claude -p --disallowed-tools "Bash,Write" "Reply with OK"
Error: Input must be provided either through stdin or as a prompt argument when using --print
```

`spawn.sh` therefore pipes the launch prompt on **stdin**, never as a positional
argument. This is a silent failure mode: the flags parse, the run exits 1, and
the error names stdin rather than the real cause.

## (a) Interrupt and resume

SIGINT to a `-p` process mid-generation, then resume with a steer:

```sh
printf 'Count slowly from 1 to 40...' | claude -p --output-format stream-json --verbose &
# capture session_id from the init event, SIGINT the pid
printf 'Stop counting. Reply with exactly: RESUMED-OK' | \
  claude -p --resume "$SID" --output-format stream-json --verbose
```

The resumed run reports the **same `session_id`**, `is_error: false`, and obeys
the steer rather than continuing the interrupted work. This is the mechanism
behind `scripts/crew/run.sh`'s interrupt-drain-resume loop, and it means a steer
is deterministic rather than a keystroke landing somewhere in a TUI composer.

## (b) Disallowed tools

`--disallowed-tools Bash` removes the tool from the model's list entirely — it
does not attempt the call and then fail. Asked to run a shell command it replied
`BLOCKED`, `num_turns: 1`, `is_error: false`, `permission_denials: []`.

Better than the design assumed: the crew sandbox is enforced by absence, not by
a refusal the model has to handle. **No `--dangerously-skip-permissions` is
needed**, which was the whole point of the redesign.

## (c) Worktree-scoped hooks

A `.claude/settings.local.json` written into the worktree before launch fires
under `-p`. Observed, in order: `UserPromptSubmit` → `Stop` → `SessionEnd`.

That is the crewmate ledger: `busy:` on prompt submit, `idle:` at turn end,
`exited:` at session end, written by the crewmate's own process into a file the
supervisor polls. The harness reaches a process running in someone else's repo
without touching that repo.

## (d) stream-json

`init` carries `session_id` and the resolved tool list. `result` carries
`session_id`, `total_cost_usd`, `usage` (`input_tokens`, `output_tokens`, cache
counters), `num_turns`, `is_error`, and `permission_denials`.

`run.sh` reads cost and tokens straight from the result event — no transcript
scraping, which the pre-spike draft had assumed would be necessary.

**Cost note:** a trivial `haiku` call ("reply with OK") cost **$0.052**, because
every launch pays for the system prompt, global CLAUDE.md and hook context. The
floor per crewmate turn is cents, not fractions of a cent. Phase 1's
`config/spend-cap-daily` should be set with that in mind.

## (e) no-mistakes — not verified

`no-mistakes` is not installed on this machine (`scripts/doctor.sh` reports it
missing), so the gate invocation and its status-reading contract are unverified.

Per the plan's stated fallback, a project registered `[no-mistakes]` **degrades
to `direct-PR` and files a blocking decision** rather than guessing at a gate
command. `scripts/crew/teardown.sh` implements that degradation; when the tool is
installed, verify the invocation here and remove it.
