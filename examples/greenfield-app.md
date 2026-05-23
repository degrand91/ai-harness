# Example: Greenfield App — TODO App with FastAPI + React

A worked example of a greenfield mission. This covers: scoping, feature decomposition, and
writing executable contract assertions from scratch when there is no existing codebase to read.

This is **descriptive**, not prescriptive. The real protocol lives in [CLAUDE.md](../CLAUDE.md).

---

## Scenario

**User:** "Build a TODO app. Python FastAPI backend, React + TypeScript frontend. Users can
create, complete, and delete tasks. Auth via email/password (JWT). Deploy target is a single
Docker Compose stack. Target turnaround: same-day."

---

## Intake snapshot

**`missions/2026-05-23-todo-app/mission.md` (excerpt)**

```markdown
# Mission: todo-app
id: 2026-05-23-todo-app
state: executing
goal: >
  Build a TODO app with a FastAPI backend and React + TypeScript frontend.
  Users can create, complete, and delete tasks. Auth via email/password + JWT.
  Delivered as a Docker Compose stack.
approved_at: 2026-05-23T09:14Z
```

---

## Explorer fanout (4 in parallel, read-only)

Since this is greenfield, Explorers examine the *environment*, not the target repo:

- **E1**: "What Python version is available? Is `uv` or `pip` present?"
- **E2**: "What Node/npm/pnpm version? Any existing `package.json` at the target path?"
- **E3**: "Is Docker + Compose available? What version?"
- **E4**: "Is there a `.env.example` or secrets file already present? Any port conflicts on 8000/5173?"

Explorer output feeds the plan's toolchain section.

---

## Plan snapshot

**`missions/2026-05-23-todo-app/plan.md` (excerpt)**

```markdown
## Feature order

F001  scaffold-backend        — FastAPI project skeleton, Pydantic models, SQLite via SQLModel
F002  auth-endpoints          — POST /auth/register, POST /auth/login → JWT in response body
F003  task-endpoints          — CRUD: POST /tasks, GET /tasks, PATCH /tasks/{id}, DELETE /tasks/{id}
F004  scaffold-frontend       — Vite + React + TypeScript, Tailwind, axios client wired to localhost:8000
F005  auth-ui                 — Register + Login forms, JWT stored in localStorage, protected routes
F006  task-ui                 — TaskList, TaskItem, AddTask components; optimistic updates on complete/delete
F007  docker-compose          — Dockerfile per service, docker-compose.yml, .env.example
F008  integration-smoke       — E2E happy path: register → login → add task → complete → delete

## Dependency order rationale
F002 depends on F001 (models + DB). F003 depends on F002 (auth middleware). F004 is independent of
F001–F003 (frontend can scaffold in parallel conceptually, but serial rule applies — schedule after
F003 so the API surface is stable before wiring). F007 depends on F001–F006.
```

---

## Contract snapshot

**`missions/2026-05-23-todo-app/contract.md` (excerpt)**

```markdown
## Assertions

C-001  exit 0   cd backend && python -m pytest -q
C-002  exit 0   cd backend && ruff check .
C-003  exit 0   cd frontend && pnpm typecheck
C-004  exit 0   cd frontend && pnpm test -- --run
C-005  exit 0   docker compose build
C-006  exit 0   docker compose up -d && sleep 5 && curl -fsS http://localhost:8000/healthz
C-007  exit 0   docker compose up -d && sleep 5 && curl -fsS http://localhost:5173 | grep -q "TODO"
C-008  behavioral   No JWT secret appears as a literal string in any source file (grep enforced)
C-009  behavioral   All passwords hashed with bcrypt before persistence; no plaintext in DB
C-010  exit 0   gitleaks detect --no-git -s . (exit 0 = no secrets detected)
C-011  behavioral   PATCH /tasks/{id} returns 403 when caller does not own the task
C-012  exit 0   cd backend && python -m pytest -q -k "test_ownership"
```

---

## Feature loop highlights

### F001 — scaffold-backend

Worker creates:
- `backend/main.py` (FastAPI app factory)
- `backend/models.py` (User, Task via SQLModel)
- `backend/database.py` (engine + session dependency)
- `backend/tests/test_models.py`

Contract slice: C-001, C-002.

Scrutiny looks for: no hardcoded DB path (must come from `settings.DATABASE_URL`), no mutation
of model fields in-place.

### F003 — task-endpoints

Worker creates `backend/routers/tasks.py`. The ownership check (C-011, C-012) is introduced
here. Scrutiny specifically verifies the ownership assertion exists in the test file — not just
that it was mentioned in a comment.

### F006 — task-ui

User-Testing Validator launches `docker compose up`, navigates to `localhost:5173`, creates a
task via the UI, marks it complete, verifies it appears struck-through, then deletes it. Evidence
screenshots stored in `features/006-task-ui/evidence/`.

### F008 — integration-smoke

This feature's only deliverable is the smoke test suite (`e2e/test_smoke.py`). It runs the full
user journey against the running stack. If the smoke tests fail, Orchestrator opens F008-followup-1
targeting the broken assertion — it never edits F001–F007 retroactively.

---

## Lessons reinforced by this shape

- **Greenfield needs an env Explorer pass.** Without it, workers discover toolchain mismatches
  mid-flight (wrong Python version, port in use).
- **Auth before CRUD.** F002 before F003 prevents the workers from inventing their own auth
  middleware and then having to rip it out.
- **Contract C-008 (no literal secrets) is cheap to add but expensive to miss.** Add it in every
  mission involving credentials. A grep suffices.
- **Ownership tests (C-011, C-012) belong in the contract, not in the worker's intuition.**
  Workers that are told "check ownership" without a contract assertion routinely write the check
  but skip the test.
