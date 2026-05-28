# status.json schema

> Each mission folder has a `status.json` at the root and one per feature under `features/NNN-slug/status.json`. The Orchestrator owns writes. Validators and Workers read what they're given via spawn prompt.

## Mission-level: `missions/<id>/status.json`

```json
{
  "mission_id": "2026-05-23-add-oauth",
  "state": "executing",
  "started_at": "2026-05-23T09:00:00Z",
  "approved_at": "2026-05-23T09:30:00Z",
  "closed_at": null,
  "abandoned_reason": null,
  "current_feature": "F003",
  "features": [
    { "id": "F001", "slug": "add-oauth-routes", "state": "closed", "color": "green", "followups": 0 },
    { "id": "F002", "slug": "add-token-store", "state": "closed", "color": "green", "followups": 1 },
    { "id": "F003", "slug": "wire-login-button", "state": "in_validation", "color": null, "followups": 0 }
  ],
  "models": {
    "orchestrator": "opus",
    "worker_default": "sonnet",
    "scrutiny_validator_default": "sonnet",
    "user_testing_validator_default": "sonnet",
    "explorer_default": "haiku"
  },
  "tokens": {
    "orchestrator": { "input": 0, "output": 0, "provider": "claude" },
    "workers": { "input": 0, "output": 0, "provider": "claude" },
    "scrutiny": { "input": 0, "output": 0, "provider": "claude" },
    "user_testing": { "input": 0, "output": 0, "provider": "claude" },
    "explorers": { "input": 0, "output": 0, "provider": "claude" }
  },
  "checkpoints": {
    "pause_every_n_features": null,
    "pause_after_k_followups_on_same_feature": 2
  }
}
```

### state enum
`intake | planning | contract | awaiting_approval | executing | feature_loop | closing | closed | abandoned | paused`

### feature.state enum
`pending | in_progress | in_validation | closed | abandoned`

### color enum
`green | red | null`

## Feature-level: `missions/<id>/features/NNN-slug/status.json`

```json
{
  "feature_id": "F003",
  "slug": "wire-login-button",
  "state": "in_validation",
  "color": null,
  "worker": {
    "started_at": "2026-05-23T14:10:00Z",
    "completed_at": "2026-05-23T14:55:00Z",
    "model": "sonnet",
    "handoff_path": "features/003-wire-login-button/handoff.md",
    "commit_shas": ["a1b2c3d"]
  },
  "scrutiny": {
    "started_at": "2026-05-23T14:55:00Z",
    "completed_at": "2026-05-23T15:05:00Z",
    "model": "sonnet",
    "verdict": "green",
    "path": "features/003-wire-login-button/scrutiny.md"
  },
  "validator_quality": {
    "tool_uses_count": 0,
    "prose_preamble_detected": false,
    "hallucination_detected": false,
    "re_spawned": false
  },
  "user_testing": {
    "started_at": null,
    "completed_at": null,
    "model": "sonnet",
    "verdict": null,
    "path": null
  },
  "followups": []
}
```

### validator_quality block

The `validator_quality` block is populated by the Orchestrator after each scrutiny pass. It is not written by the Validator itself.

| Field | Type | Description |
|-------|------|-------------|
| `tool_uses_count` | integer | Number of Bash tool invocations the scrutiny validator made. A value of 0 with non-empty assertion results indicates a suspected hallucination. |
| `prose_preamble_detected` | boolean | `true` if the validator's reply contained text before the required `## Feature:` header, suggesting the response format was not followed. |
| `hallucination_detected` | boolean | `true` if the Orchestrator determined the validator fabricated results (e.g. `tool_uses_count` is 0 but assertion verdicts were present) and triggered a re-spawn. |
| `re_spawned` | boolean | `true` if the validator was re-spawned for any reason (hallucination, timeout, malformed output). |

These metrics enable data-driven decisions about Haiku→Sonnet model routing for the scrutiny role (see ROADMAP v1.2). A pattern of `hallucination_detected: true` or high `re_spawned` rates on a given model signals that the model should be promoted.

### models block field notes

- `scrutiny_validator_default`: default scrutiny model for the mission. **Sonnet by default**; set to `"haiku"` only for missions where every assertion is purely mechanical. See [protocols/model-routing.md](../protocols/model-routing.md#scrutiny-model-selection).
- The orchestrator may override this per-feature if a feature's contract slice is mechanical even when the mission default is sonnet.

### Notes

- Timestamps are ISO-8601 UTC.
- `commit_shas` is an array but usually has one entry — one commit per feature.
- `followups` is an array of feature IDs (`["F003-followup-1"]`) that were opened due to this feature's validator failures.
- `provider` is optional per role in the `tokens` block; defaults to `"claude"` when omitted. Set to the external provider id (e.g. `"openai"`, `"gemini"`) when a non-Claude provider was used (controlled via `HARNESS_EXTERNAL_VALIDATOR_PROVIDER`).

### Token aggregation

The `tokens` block at the mission level is populated **automatically** by the `SubagentStop` hook (`subagent-stop-record.sh`):

- Whenever a subagent completes, the hook reads `input_tokens` / `output_tokens` from the SubagentStop event stdin payload and increments the matching role counter (`workers`, `scrutiny`, `user_testing`, `explorers`).
- Values **accumulate** across the full mission lifetime — they are not per-feature snapshots.
- Zero values indicate one of two things: (a) the mission was created before this feature shipped, or (b) the SubagentStop payload did not carry token data (e.g. an older Claude Code version or a local stub).
