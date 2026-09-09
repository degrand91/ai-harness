# Brief: {TASK_ID}

Ledger:  {LEDGER_PATH}
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

- Append to the ledger as you go: `progress:`, and `blocked:` if you need a
  decision. Finish with exactly one `done:` or `failed:` line, then write the
  handoff, then stop.
- Commit once, conventional format. Do not push, do not merge, do not open a PR.
- Anything outside `## Harness spec` scope goes in the handoff as a note, not in
  the diff.
