# Protocols — Navigation Index

Each file in this directory is an executable protocol: a binding spec that governs exactly one aspect of harness behaviour. The Orchestrator reads the relevant protocol before acting in each phase.

If you are new to the harness, start with [lifecycle.md](lifecycle.md), then read the role specs for each agent you plan to spawn.

---

## Role Specs

These documents define what each agent role is and how it behaves. Read before spawning.

| File | Description |
|------|-------------|
| [orchestrator.md](orchestrator.md) | Orchestrator role: strategic intent, mission state ownership, approval gate, and hard rules |
| [worker.md](worker.md) | Worker role: single-feature implementation, commit discipline, handoff format |
| [scrutiny-validator.md](scrutiny-validator.md) | Scrutiny Validator role: adversarial contract-only review, no worker reasoning visible |
| [user-testing-validator.md](user-testing-validator.md) | User-Testing Validator role: live QA of user-observable behaviour via Bash |
| [scout.md](scout.md) | Scout role: cross-mission memory, intake orientation, memory file conventions |

---

## Workflow Protocols

These documents govern the sequencing and coordination rules for mission execution.

| File | Description |
|------|-------------|
| [lifecycle.md](lifecycle.md) | End-to-end mission phases: intake → plan → contract → approval → feature loop → close |
| [handoff.md](handoff.md) | Handoff format contract between Worker and Orchestrator; required sections and failure modes |
| [validation-contract.md](validation-contract.md) | How to write a validation contract: executable assertions, contract slices, amendment rules |
| [serial-execution.md](serial-execution.md) | Why features run one at a time and how the spawn-lock enforces it |
| [parallel-exploration.md](parallel-exploration.md) | When and how to fan out Explorer subagents in parallel during the planning phase |
| [checkpoint-protocol.md](checkpoint-protocol.md) | Mid-mission checkpoints: when to surface state to the user and what to include |

---

## Quality Protocols

These documents define quality standards applied during or after feature execution.

| File | Description |
|------|-------------|
| [design-quality.md](design-quality.md) | UI/frontend quality bar: anti-template policy, required design qualities, component checklist |
| [snapshots-convention.md](snapshots-convention.md) | Visual regression snapshot naming, storage location, and update workflow |
| [self-review.md](self-review.md) | Worker self-review checklist to run before committing and generating a handoff |
| [ab-compare.md](ab-compare.md) | A/B comparison protocol for evaluating two implementation approaches side by side |
| [browser-qa.md](browser-qa.md) | Browser-based QA steps for features with user-observable UI behaviour |

---

## Configuration

These documents govern runtime configuration and deployment variants of the harness.

| File | Description |
|------|-------------|
| [model-routing.md](model-routing.md) | Which model (opus/sonnet/haiku) routes to which agent role and why |
| [multi-provider-validation.md](multi-provider-validation.md) | How to enable external-provider scrutiny via HARNESS_EXTERNAL_VALIDATOR_PROVIDER |
| [headless-mode.md](headless-mode.md) | Running the harness non-interactively: CI triggers, environment flags, approval bypass |
| [remote-trigger.md](remote-trigger.md) | Triggering missions remotely: webhook schema, authentication, and safety constraints |
