# Decision hold

One file per open decision: `missions/<id>/decisions/DH-NNN.json`. Answering
**moves** it to `missions/<id>/decisions/answered/DH-NNN.json`.

```json
{
  "id": "DH-001",
  "mission_id": "2026-06-29-store-review-remediation",
  "opened_at": "2026-09-09T10:00:00Z",
  "blocking": true,
  "question": "Reword the listing, or change the store category?",
  "options": ["reword the listing", "change category"],
  "recommendation": "reword — smaller diff, no category re-review",
  "context_path": "features/003-reachability/scrutiny.md",
  "answered_at": null,
  "answer": null
}
```

| Field | Notes |
|---|---|
| `id` | `DH-NNN`, numbered **per mission**. Two missions both having a `DH-001` is normal; a hold is only ever addressed together with its mission. |
| `blocking` | `true` stops work until answered. `false` is advisory: it appears in `/decide` and `/fleet`, but neither the crew nor the watcher waits on it. |
| `question` | One sentence. If it needs a paragraph, it is two decisions. |
| `options` | Optional. Omit when the answer is open-ended. |
| `recommendation` | What you would do, and why. A decision presented without one is work handed back. |
| `context_path` | Optional, relative to the mission folder — the scrutiny report or diff the captain will want. |
| `answered_at` / `answer` | Written by `hold.sh answer`. Never edited by hand. |

## Why answering moves the file

Counting open decisions is then a file count, so `scripts/snapshot.sh` reports
them without parsing any of them and keeps its constant-`jq` contract. It also
means an answer is never lost to an in-place rewrite going wrong.

## DH-000

Mission approval is a decision like any other, filed as `DH-000` by
`/mission-start`. The `awaiting_approval` state stops being a special case: one
mechanism, one skill, one place to look. The Stop guard refuses to end a session
on an `awaiting_approval` mission with no decision filed.
