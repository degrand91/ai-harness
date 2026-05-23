# Example: Data Migration — Postgres → Aurora with Zero Downtime

A worked example of a database migration mission. Key themes: staged features with independent
rollback contracts, a mandatory dry-run feature before any live data is touched, and assertions
that verify both the migration path and the rollback path.

This is **descriptive**, not prescriptive. The real protocol lives in [CLAUDE.md](../CLAUDE.md).

---

## Scenario

**User:** "Migrate our production Postgres 14 (self-hosted, 120 GB) to AWS Aurora PostgreSQL.
The app (Django) must stay live throughout. Target: zero data loss, less than 30 seconds of
read-only mode at cutover. We have a maintenance window on Saturday 02:00 UTC."

---

## Intake snapshot

**`missions/2026-05-23-postgres-aurora/mission.md` (excerpt)**

```markdown
# Mission: postgres-aurora
id: 2026-05-23-postgres-aurora
state: executing
goal: >
  Migrate production Postgres 14 (self-hosted, 120 GB) to AWS Aurora PostgreSQL.
  App must stay live throughout. Zero data loss.
  Max 30s read-only window at cutover (Saturday 02:00 UTC maintenance window).
approved_at: 2026-05-23T16:40Z
constraints:
  - rollback_plan: required at every stage
  - dry_run: required before live cutover
  - data_loss_tolerance: zero
```

---

## Explorer fanout (5 in parallel, read-only)

- **E1**: "Read `settings/base.py` and `settings/production.py`. How is DATABASE_URL injected?
  Is there a read replica already configured? Any custom Postgres extensions in use (PostGIS,
  hstore, pgvector)?"
- **E2**: "Run `pg_dump --schema-only` against dev DB (not prod). How many tables, sequences,
  indexes, foreign keys? Any table > 10 GB? List them."
- **E3**: "What Django migration version is HEAD? Is there an async task queue (Celery, RQ)
  that writes to the DB? List which queues/tasks perform writes."
- **E4**: "Is AWS DMS available in the account? What IAM permissions does the deploy role have?
  Is there a VPC peering or Direct Connect between self-hosted Postgres and the target VPC?"
- **E5**: "Is there a staging environment that mirrors production schema? Can we run a full
  migration dry-run against staging before touching prod?"

Explorer E4 determines the migration mechanism (DMS vs. pg_dump + restore vs. logical replication).
Explorer E5 confirms staging availability, which is required before the plan can proceed.

---

## Plan snapshot

**`missions/2026-05-23-postgres-aurora/plan.md` (excerpt)**

```markdown
## Migration strategy: logical replication + DNS cutover
Chosen because:
- DMS available but adds complexity; logical replication is closer to the stack.
- Aurora supports logical replication as a subscriber.
- DNS cutover (DATABASE_URL env var swap) gives a controlled read-only window.

## Feature order

F001  aurora-provision         — Terraform: Aurora cluster, parameter group, security groups.
                                  Outputs: AURORA_ENDPOINT, AURORA_REPLICA_ENDPOINT.
F002  replication-setup        — Enable logical replication on source Postgres. Create replication
                                  slot. Subscribe Aurora to source. Verify lag < 1 s on staging.
F003  app-dual-write-prep      — Add AURORA_DATABASE_URL to Django settings (read-only mode flag).
                                  App still writes to source Postgres only.
F004  dry-run-cutover          — Against staging: flip DATABASE_URL to Aurora, run smoke tests,
                                  flip back. Measure downtime window. Must complete in < 30 s.
F005  live-cutover             — Saturday 02:00 UTC: set app to read-only (maintenance mode),
                                  wait for replication lag = 0, flip DATABASE_URL to Aurora,
                                  disable read-only mode, verify smoke tests.
F006  decommission-source      — After 72-hour monitoring window: drop replication slot on source,
                                  snapshot source Postgres, terminate source instance.

## Rollback plan per feature
F001: Terraform destroy (no data touched).
F002: Drop replication slot (`SELECT pg_drop_replication_slot('aurora_sub')`). Source unchanged.
F003: Revert Django settings commit. No data change.
F004: Dry-run only; rollback is automatic (flip back).
F005: Flip DATABASE_URL back to source Postgres (lag is zero at cutover, so source is current).
      Re-enable writes on source. Aurora becomes stale; discard.
F006: No rollback — source is decommissioned. Only executed after 72-hour green window.
```

---

## Contract snapshot

**`missions/2026-05-23-postgres-aurora/contract.md` (excerpt)**

```markdown
## Assertions

C-001  exit 0   terraform -chdir=infra/aurora plan -detailed-exitcode (exit 2 = changes pending, 0 = no drift)
                  After F001: terraform apply must exit 0.
C-002  exit 0   python manage.py migrate --check (no pending migrations on Aurora after F001)
C-003  behavioral   Replication lag on Aurora subscriber < 1000 ms (checked via pg_stat_replication)
C-004  exit 0   psql $AURORA_DATABASE_URL -c "SELECT count(*) FROM pg_stat_subscription" \
                  | grep -qE "^\s+1" (exactly one subscription active)
C-005  exit 0   python manage.py test apps.core.tests.SmokeTest --keepdb (against Aurora)
C-006  exit 0   python manage.py test apps.core.tests.SmokeTest --keepdb (against source Postgres)
                  C-005 and C-006 must both pass simultaneously during F003 window.
C-007  behavioral   Dry-run cutover window (F004) measured < 30 seconds
C-008  exit 0   bash scripts/measure-cutover-window.sh (writes elapsed seconds to evidence/; asserts < 30)
C-009  behavioral   Row counts match between source and Aurora on all tables after F004 dry run
C-010  exit 0   bash scripts/row-count-diff.sh $SOURCE_URL $AURORA_URL (exits 1 if any table differs)
C-011  exit 0   bash scripts/measure-cutover-window.sh (live, F005) — same < 30 s assertion
C-012  behavioral   No application errors (5xx) in CloudWatch logs in the 5 minutes following F005
C-013  exit 0   aws logs filter-log-events --log-group-name /app/prod \
                  --start-time $(date -d '5 minutes ago' +%s000) \
                  --filter-pattern "\"ERROR\" \"500\"" | jq '.events | length == 0'
C-014  behavioral   After F006, source Postgres instance is stopped (not deleted — snapshot retained)
C-015  exit 0   aws rds describe-db-instances --db-instance-identifier prod-postgres \
                  | jq '.DBInstances[0].DBInstanceStatus == "stopped"'
```

---

## Dry-run feature detail (F004)

F004 is the only feature whose *entire purpose* is to rehearse F005 against staging. It is
**not** skippable even if staging is "close enough." The contract requires:

1. Staging app put in read-only mode (maintenance page served).
2. Replication lag confirmed at 0 (blocking wait, max 60 s).
3. `DATABASE_URL` flipped to staging Aurora.
4. Read-only mode disabled.
5. Smoke tests run (`C-005` variant against staging Aurora).
6. Elapsed time recorded to `evidence/cutover-elapsed.txt`.
7. `DATABASE_URL` flipped back to staging source.

The Worker for F004 produces a script (`scripts/cutover.sh`) that encodes steps 1–7. F005 calls
the same script with `--env=production` flag. This means F005 contains zero new logic — it only
calls the rehearsed script.

---

## Staged rollback contract

Each feature's `spec.md` contains a `rollback_command` field. The Scrutiny Validator for
migration features is instructed (via the contract slice) to verify the rollback command is
present and executable (dry-run `--help` or `--check`), not just documented.

Example from F002's `spec.md`:

```markdown
## Rollback command
```bash
psql $SOURCE_DATABASE_URL \
  -c "SELECT pg_drop_replication_slot('aurora_sub');"
```
Precondition: Aurora subscriber must be stopped first.
Postcondition: Source Postgres returns to standalone mode. No data loss.
```

---

## Feature loop highlights

### F002 — replication-setup

User-Testing Validator verifies replication lag in real time:
1. Inserts 1,000 rows into a canary table on source.
2. Waits up to 10 s.
3. Counts rows on Aurora replica.
4. Asserts count matches.

Evidence: `features/002-replication-setup/evidence/lag-test.txt`.

### F005 — live-cutover

This feature runs during the maintenance window. The Worker is pre-staged (spawned and waiting
in a subagent) so there is no cold-start latency at 02:00 UTC. The Worker's only task is to
call `bash scripts/cutover.sh --env=production` and capture output to evidence.

Scrutiny Validator for F005 has an extended timeout (the contract window is 30 s, but the
Validator has 5 minutes to confirm C-012 and C-013 after the cutover).

### F006 — decommission

F006 is explicitly gated on a 72-hour monitoring window. `status.json` for F006 enters state
`"pending"` at the end of F005, and the Orchestrator does not proceed until the monitoring
window passes and C-012/C-013 are confirmed green over that full period. The `spec.md` for F006
records the gate condition:

```json
"gate": {
  "type": "time_elapsed",
  "hours": 72,
  "condition": "no_5xx_in_cloudwatch"
}
```

---

## Lessons reinforced by this shape

- **Dry-run is a feature, not a step.** F004 produces a reusable script. If the dry run reveals
  that the cutover takes 45 s instead of 30, the mission opens F004-followup-1 to optimize before
  touching prod — not a rushed in-place fix at 02:00 UTC.
- **Row-count assertions are cheap and catch silent data loss.** C-009/C-010 use a simple diff
  script. A 5-line bash script checking `SELECT count(*)` on every table has caught partial
  replication failures that application smoke tests missed.
- **Rollback commands belong in the contract, not just the post-mortem.** Scrutiny validates
  rollback presence per-feature. A migration that is well-executed going forward but un-rollbackable
  is a ticking clock, not a success.
- **F006 is gated on time, not just on green tests.** Some failures (connection pool exhaustion,
  cache warming lag) only manifest under sustained load. The 72-hour gate is not bureaucracy —
  it is the contract enforcing that "done" means "stable under production traffic," not just
  "smoke tests passed at cutover."
