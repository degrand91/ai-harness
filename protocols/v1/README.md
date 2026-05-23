# Protocols v1 — Frozen Snapshot

This directory is a **read-only, frozen snapshot** of all harness protocols as of the v1.0 release (2026-05-23).

## Purpose

`protocols/v1/` provides a stable reference for any mission, integration, or tooling that was designed against the v1.0 harness. It will not change after it is created.

## Contents

Every `.md` file from `protocols/` at the moment of the v1.0 release is reproduced here byte-for-byte:

- `lifecycle.md` — mission lifecycle phases
- `validation-contract.md` — how to write executable contracts
- `serial-execution.md` — one-worker-at-a-time rule and rationale
- `model-routing.md` — when to use haiku vs sonnet vs opus
- `orchestrator.md` — orchestrator role spec
- `worker.md` — worker role spec
- `scrutiny-validator.md` — scrutiny validator role spec
- `user-testing-validator.md` — user-testing validator role spec
- `parallel-exploration.md` — explorer fan-out protocol
- `handoff.md` — structured handoff format
- `self-review.md` — self-review checklist
- `design-quality.md` — design quality guidelines
- `headless-mode.md` — headless / CI execution
- `remote-trigger.md` — remote trigger protocol
- `ab-compare.md` — A/B comparison protocol
- `checkpoint-protocol.md` — checkpoint save/restore
- `multi-provider-validation.md` — cross-provider validation
- `snapshots-convention.md` — conventions for protocol snapshots

## How to use this snapshot

- **Reference only.** Do not edit any file inside `protocols/v1/`.
- When writing a mission against the v1.0 harness, you may cite these documents by their stable path (`protocols/v1/<file>.md`).
- If a live protocol in `protocols/` has changed and you need the old behavior, read the file here.

## How to create a future snapshot (v2, v3, …)

When a breaking change lands in `protocols/`, freeze a new snapshot:

```bash
mkdir -p protocols/v2
for f in protocols/*.md; do cp "$f" protocols/v2/; done
# then write protocols/v2/README.md describing what changed in v2
```

Tag the commit with the corresponding version (e.g., `v2.0.0`) so the snapshot is permanently addressable via git.

## Stability guarantee

Files under `protocols/v1/` are append-only in git history. No existing file will be modified or deleted. Only the addition of new snapshots (`protocols/v2/`, etc.) is ever expected.
