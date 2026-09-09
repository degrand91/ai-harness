# Scout brief: {TASK_ID}

Ledger: {LEDGER_PATH}
Report: {HANDOFF_PATH}
Worktree: {WORKTREE}
Branch:  {BRANCH}

## Captain's intent

{CAPTAINS_INTENT}

## Harness spec

{HARNESS_SPEC}

## Report

Write your findings to the Report path above. You are investigating, not
building: **do not change any file** other than the report.

{DEFINITION_OF_DONE}

## Delivery contract

mode={MODE} yolo={YOLO} model={MODEL}

## Protocol

- Append `progress:` lines to the ledger as you learn things, and `blocked:` if
  you need a decision to continue.
- Finish with exactly one `done:` line naming the report path, then stop.
- No commit, no branch, no PR. Your branch is discarded at teardown; only the
  report survives.
