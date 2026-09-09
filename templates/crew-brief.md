# Brief: {TASK_ID}

Report progress with:
  {SAY_CMD} {LEDGER_PATH} <verb> "<note>"
  verbs: progress · blocked · done · failed
Handoff: {HANDOFF_PATH}
Worktree: {WORKTREE}
Branch:  {BRANCH}

## Captain's intent

{CAPTAINS_INTENT}

## Harness spec

{HARNESS_SPEC}

## Definition of done

{DEFINITION_OF_DONE}

## Delivery contract

mode={MODE} yolo={YOLO} model={MODEL}

## Protocol

- Report with the command above as you go. It is the ONLY way to reach your
  supervisor: the ledger is outside your worktree and nothing else you can run
  will reach it. Finish with exactly one `done` or `failed`, then write the
  handoff, then stop.
- Commit once, conventional format. Do not push, do not merge, do not open a PR.
- Anything outside `## Harness spec` scope goes in the handoff as a note, not in
  the diff.
