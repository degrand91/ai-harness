---
name: contract-defect-amend-not-patch
description: When the integration check (or a validator) surfaces a defect in the contract itself — not in the code — amend the contract through its amendments log and re-run. Do not paper over with a "the intent was clear" pass.
introduced_in_mission: 2026-05-23-ship-v0-3-multi-provider
tags: [contract, integration-check, validator, governance]
---

## Pattern

When a contract assertion exits non-zero but the failure is in **the assertion's command itself** (regex too broad, shell logic inverted, command checks the wrong thing) rather than in the code under test, the Orchestrator's response is:

1. **Acknowledge the defect explicitly** in writing — in `integration-check.md` or the relevant `scrutiny.md`. State the substantive invariant the assertion was *supposed* to enforce and confirm it is satisfied.
2. **Amend the contract** by appending an entry to the `## Amendments log` section of `contract.md` — with timestamp, trigger, the replacement assertion (full command), and verification result on the amended command.
3. **Re-run the amended command** in the same session and record exit code. Only after the amended assertion passes does the verdict flip to green.
4. **Do not silently mark the assertion green.** Do not delete the failing assertion. Do not weaken the substantive invariant. The amendment must be at least as strong as the original intent.

## Why

The contract is the single load-bearing artifact of the harness. Its credibility depends on assertions being honest. If the Orchestrator can silently pass an assertion that failed because "the intent was clear," the contract gate stops gating. Future missions reading past post-mortems can't tell which assertions actually held and which were waved through.

On `2026-05-23-ship-v0-3-multi-provider` F007, two assertions exited non-zero:
- C-013's regex matched `API_KEY` as a substring of `${OPENAI_API_KEY}` in commented YAML — not a secret value.
- C-014's shell logic `! <pipeline> | awk '... exit 1'` was inverted, failing on the clean state.

The Worker correctly flagged both as **contract defects, not feature failures**. The substantive invariants ("no real credentials in any commit", "no file in scope exceeds 800 lines") were always satisfied. But the temptation is to either (a) write "verdict: green (with notes)" and move on, or (b) edit the original assertion in place. Both are wrong:
- (a) leaves the next mission to discover the broken assertion again.
- (b) erases the history of what the contract said when it was approved.

The right move is the amendment-log workflow: history preserved, fix explicit, gate intact.

## How to apply

- **In the contract template, always include an Amendments log section** even if empty. The template at `templates/validation-contract.md` should make this default.
- **When the integration check (or any validator) surfaces a defect**, distinguish:
  - **Feature defect** (code is wrong) → open a follow-up feature using the validator's follow-up spec. Standard negotiation pattern.
  - **Contract defect** (assertion is wrong) → amend the contract and re-run. Use this pattern.
- The amendment entry must include:
  - **Trigger**: which assertion, surfaced by what, what the symptom was.
  - **Replacement assertion**: the corrected command, copy-paste-ready.
  - **Verification result after amendment**: exit code on the corrected command, on the same HEAD.
- After the amendment, the original assertion text in the body can remain (historical) or be replaced with a pointer to the amendment — either is fine, but the amendments log is the source of truth from that point.
- The `## Approval` block at the bottom of `contract.md` is NOT re-approved for amendments. Amendments are within-mission corrections, not re-scoping. If an amendment requires changing the substantive invariant, that's a re-scope and needs the user.

## Origin

`missions/2026-05-23-ship-v0-3-multi-provider/post-mortem.md` and `missions/2026-05-23-ship-v0-3-multi-provider/contract.md § Amendments log`. F007 integration check surfaced C-013 and C-014 as defective; both amended and re-run green in the same session.
