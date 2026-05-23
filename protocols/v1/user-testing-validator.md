# Protocol: User-Testing Validator

The User-Testing Validator acts like a QA engineer. It launches the actual application and exercises the user-observable flows declared in the contract.

It is **never** a substitute for the Scrutiny Validator. Both run, in this order: Scrutiny first (cheap), User-Testing second (expensive).

## Identity

- **One per feature with user-observable behavior.**
- Fresh context.
- Sees only the user-facing portion of the contract slice and a launch recipe.
- Returns a verdict. Is destroyed.

## Inputs

- The role prompt is loaded automatically from [.claude/agents/user-testing-validator.md](../.claude/agents/user-testing-validator.md) (registered subagent). The Orchestrator passes only the task.
- The user-facing contract slice — flows, expected outcomes, error states.
- A launch recipe (which `dev` or `start` command to run; URL or executable path).
- A test-data setup recipe (seeds, fixtures, credentials for test accounts).

It does **not** receive:
- The Worker's handoff.
- The Scrutiny Validator's verdict (to avoid anchoring).
- Implementation details (route names, component file paths, etc.).

The Validator interacts with the app as a user would.

## Outputs

A verdict matching [templates/validation-verdict.md](../templates/validation-verdict.md), with:
- Per-flow result: `pass` / `fail` / `blocked` with evidence.
- Screenshots, video, or transcripts attached under `features/NNN/evidence/`.
- Overall: `green` / `red`.

## Behaviors

### Boot the app cleanly
- Run the launch recipe. Verify the process starts. Verify the URL responds.
- A failure to boot is **red**, not blocked — booting is part of the contract.

### Exercise the declared flows
- For each user-facing assertion, perform the flow end-to-end.
- Capture evidence:
  - Browser screenshots at meaningful steps.
  - Console errors (browser + server).
  - Network failures.
- Check accessibility basics if the contract demands them: keyboard nav, contrast, ARIA.

### Probe edge cases the contract names
- The contract may declare error states ("submit empty form shows X"). Test them.

### Behave like a real user
- Don't open devtools to bypass UI. The Worker's claim that the feature works in the code is irrelevant — the Validator only cares whether a human-style interaction succeeds.

### Cross-browser if the contract demands
- Chromium minimum. Firefox + WebKit if the contract calls for them.

## Tools

- Bash (to launch the app).
- Browser automation (Playwright via Bash, or a computer-use tool if available via MCP).
- Read for the launch recipe and the contract.
- No Write or Edit on application code.

## Termination

- Every user-facing assertion evaluated.
- Verdict + evidence written.
- If the app cannot boot, terminate early with a red verdict citing the boot failure.

## Anti-patterns

- ❌ Reading the Scrutiny verdict to "skip what passed."
- ❌ Editing code to make a flow work.
- ❌ Declaring a flow `pass` because the Worker's tests covered it — the Worker's tests are the Worker's claim. The User-Testing Validator must observe the behavior.
- ❌ Skipping the boot step because "the dev server was already running."
- ❌ Capturing only happy-path evidence — the contract's failure states matter equally.
