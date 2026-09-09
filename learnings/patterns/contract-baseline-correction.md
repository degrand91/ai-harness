# Pattern: Establish the repo's clean-state baseline before writing absolute "exit 0" assertions

**Context:** Contracts that touch an existing repo (especially cross-repo missions where mission state lives in the harness and code lives elsewhere).

## Problem

It's tempting to write `<lint/test/build command> → expect exit 0` as a contract assertion. But if the target repo *already fails* that command on its default branch (pre-existing lint errors, skipped tests, flaky build), the assertion is unsatisfiable through no fault of the mission's work — and a worker/validator will either get falsely blocked or be tempted to "fix" unrelated code.

In `2026-06-10-add-about-us-section`, C-003 said `eslint . → exit 0`, but `main` already had a `react-hooks/immutability` error in an untouched file. The assertion had to be amended mid-mission to scope lint to **mission-changed files only** (`eslint $(git diff --name-only main...HEAD -- '*.ts' '*.tsx')`).

## Pattern

1. **At intake/contract time, run the build/lint/test commands on the untouched base branch** (cheap, an explorer or a single Bash call) and record the baseline.
2. For any command that isn't already green on the base, write the assertion to verify **"no new failures introduced by this mission"** — scope to changed files, or diff the failure set before/after — rather than absolute `exit 0`.
3. If you discover the baseline defect mid-mission, fix it via a **contract amendment with a logged reason** (baseline correction), not by silently weakening the assertion. Note explicitly that mission-changed files must still be fully clean — this is scoping, not lowering the bar.

## Payoff

Workers and validators get an achievable, honest target; pre-existing repo debt is flagged to the user as a separate concern instead of derailing the mission.

Related: [[verify-a11y-in-rendered-html]]
