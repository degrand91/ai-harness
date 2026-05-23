---
name: scaffold-feature
description: Create a feature folder under an active mission. Drops spec.md (stub) and status.json (state=pending). Append a line to the mission log. Use inside the feature loop, before spawning the Worker.
disable-model-invocation: true
argument-hint: <mission-id> <feature-num> <slug>
arguments: [mission_id, feature_num, slug]
allowed-tools: Read, Write, Bash(mkdir *), Bash(date *), Bash(printf *)
---

## Arguments
- mission_id: $mission_id
- feature_num: $feature_num
- slug:       $slug

## Current UTC timestamp
!`date -u +%Y-%m-%dT%H:%M:%SZ`

---

Scaffold a new feature folder. Use the Write tool — no shell script.

## Procedure

1. **Create the folder** `missions/$mission_id/features/$feature_num-$slug/evidence/` (Write the spec file; mkdir for evidence is fine via Bash).

2. **Write `spec.md`** using the `templates/feature-spec.md` shape:
   - Feature ID = `F$feature_num`.
   - Goal: one sentence (you fill this from the plan).
   - Scope: explicit file paths/globs.
   - Out of scope: explicit.
   - Contract slice: paste the relevant assertions from `missions/$mission_id/contract.md` verbatim.
   - Procedures (checklist the Worker reports y/n in handoff).
   - User-observable behavior?: yes/no.

3. **Write `status.json`** matching the per-feature shape in `templates/status-schema.md`:
   ```json
   {
     "feature_id": "F<num>",
     "slug": "<slug>",
     "state": "pending",
     "color": null,
     "worker":       { "started_at": null, "completed_at": null, "model": null, "handoff_path": null, "commit_shas": [] },
     "scrutiny":     { "started_at": null, "completed_at": null, "model": null, "verdict": null, "path": null },
     "user_testing": { "started_at": null, "completed_at": null, "model": null, "verdict": null, "path": null },
     "followups": []
   }
   ```

4. **Append to the mission log** (`missions/$mission_id/log.md`):
   ```
   [<timestamp>] feature F$feature_num ($slug) scaffolded
   ```

5. **Surface the feature folder path** to the Orchestrator (your caller) so it can spawn the Worker with the right spec.

Do not spawn the Worker from this skill — the Orchestrator does that as the next step.
