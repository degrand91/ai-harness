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
    "orchestrator": { "input": 0, "output": 0 },
    "workers": { "input": 0, "output": 0 },
    "scrutiny": { "input": 0, "output": 0 },
    "user_testing": { "input": 0, "output": 0 },
    "explorers": { "input": 0, "output": 0 }
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

### Notes

- Timestamps are ISO-8601 UTC.
- `commit_shas` is an array but usually has one entry — one commit per feature.
- `followups` is an array of feature IDs (`["F003-followup-1"]`) that were opened due to this feature's validator failures.
