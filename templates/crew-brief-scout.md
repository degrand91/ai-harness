# Scout brief: {TASK_ID}

Report progress with:
  {SAY_CMD} {LEDGER_PATH} <verb> "<note>"
  verbs: progress · blocked · done · failed
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

- Report with the command above as you learn things, and `blocked` if you need
  a decision. It is the ONLY way to reach your supervisor.
- Finish with exactly one `done` naming the report path, then stop.
- No commit, no branch, no PR. Your branch is discarded at teardown; only the
  report survives.
