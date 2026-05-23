---
name: explore
description: Fan out N concurrent Explorer subagents (one question each) and synthesise their findings into a single exploration brief.
argument-hint: "<q1>" "<q2>" ... ("<qN>")
allowed-tools: Agent
disable-model-invocation: true
---

## Goal

Answer multiple read-only recon questions about the codebase in parallel. Each question goes to a dedicated Explorer subagent (model: haiku, read-only tools only). Their findings are collected and synthesised into a single "Exploration brief" before the Orchestrator continues planning.

This is the canonical way to fill knowledge gaps before writing `plan.md` or `contract.md`. It is not for implementation work.

---

## Procedure

### 1. Parse questions from `$ARGUMENTS`

`$ARGUMENTS` is expected to be a list of quoted strings, one per question:

```
/explore "What test runner is configured in this repo?" "Does src/lib/ contain any auth utilities?" "What does the status.json schema look like?"
```

If the user passed a single unquoted block, best-effort split on `;` or `?` boundaries. Trim whitespace from each resulting question. Drop empty entries.

### 2. Cap concurrency at 5

Count the questions. If N ≤ 5, dispatch all in a single batch. If N > 5, split into sequential batches of 5 and wait for each batch to finish before dispatching the next. Document batch boundaries in the exploration brief.

### 3. Dispatch one Explorer per question (background mode)

For each question in the current batch, spawn an Agent call:

```
subagent_type: "explorer"
model:         "haiku"
run_in_background: true
prompt: |
  Answer the following question about this codebase. Return ONLY the four-section format:
  ## Question / ## Answer / ## Evidence / ## Caveats

  Question: <question text>
```

Use `run_in_background: true` so Explorer output stays out of the Orchestrator's active context until all agents in the batch have finished. This prevents partial synthesis and keeps the Orchestrator's context window clean. See [protocols/parallel-exploration.md](../../protocols/parallel-exploration.md) for the rationale.

Dispatch all Explorers in the batch inside a **single message** (multiple Agent tool calls at once) so they actually run concurrently.

### 4. Wait for all Explorers in the batch to return

Do not synthesise until every Explorer in the current batch has returned its four-section response. If a background Explorer's result is not yet available, wait — do not proceed on a partial set.

### 5. Collect `## Answer` sections

From each Explorer result, extract:
- The verbatim `## Question` (for labelling)
- The `## Answer` paragraph
- Any noteworthy `## Evidence` items (file:line references)
- Any `## Caveats`

Discard raw Explorer output once you have extracted these fields.

### 6. Repeat for additional batches (if N > 5)

If there are remaining questions, dispatch the next batch of up to 5 and repeat steps 3–5.

### 7. Synthesise into an Exploration brief

Return a single structured brief:

```markdown
## Exploration brief

### Q1: <question text>
**Verdict:** <one sentence direct answer>
<2–3 lines summarising the key evidence>

### Q2: <question text>
**Verdict:** ...
...

### Open gaps
- <anything that could not be answered from the evidence — flag for manual inspection>
- (or "None")
```

Surface the brief directly as output. Do not write it to a file unless the Orchestrator explicitly asks for it to be persisted.

---

## Background-mode rationale

Per [protocols/parallel-exploration.md](../../protocols/parallel-exploration.md), Explorer subagents must be dispatched with `run_in_background: true`. This ensures:

1. Their intermediate streamed output does not fill the Orchestrator's context window with low-signal lines.
2. Synthesis happens only after all results are in — no premature merging.
3. The raw Explorer messages are discarded after extraction; only the distilled brief travels forward into `plan.md`.

If the current client does not support background mode, dispatch the Explorers in a single message and hold synthesis until all have returned.

---

## Cross-references

- [protocols/parallel-exploration.md](../../protocols/parallel-exploration.md) — concurrency rule, recommended batch size, synthesis steps
- [protocols/serial-execution.md](../../protocols/serial-execution.md) — why only Explorers (not Workers or Validators) may run in parallel

---

## Anti-patterns

- Do not use `/explore` for implementation or validation work. Explorers are read-only; they carry no `Write`, `Edit`, or `Bash` tools.
- Do not ask vague, broad questions ("explain the whole codebase"). Each question must be narrow enough that a single Explorer can answer it with 3–5 file:line evidence items. Broad prompts produce overlapping, hard-to-synthesise answers.
- Do not synthesise prematurely — wait for every Explorer in the batch to return before merging findings. Partial synthesis produces contradictory or incomplete verdicts.
- Do not exceed 5 concurrent Explorers per batch. Beyond 5, synthesis overhead outweighs speedup and context pressure increases.
- Do not persist raw Explorer output into `plan.md`. Distil into decisions; discard the raw form.
- Do not spawn Explorers while a Worker or Validator is active. The canonical window is `intake → planning`. See [protocols/parallel-exploration.md](../../protocols/parallel-exploration.md) for the allowed phases.
