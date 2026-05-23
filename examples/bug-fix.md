# Example: Bug Fix — Memory Leak in Image Processing Service

A worked example of a diagnose-and-fix mission. Key themes: Explorer fanout for root-cause
diagnosis before any code is touched, a narrow-scope Worker that fixes exactly the identified
issue, and a contract assertion that targets the specific regression rather than just "tests pass."

This is **descriptive**, not prescriptive. The real protocol lives in [CLAUDE.md](../CLAUDE.md).

---

## Scenario

**User:** "Our image processing service (Python, Celery workers) leaks memory. A worker that
should sit at ~80 MB RSS after 100 tasks ends up at 1.2 GB after 500 tasks and OOMs. We think
it's in the thumbnail pipeline but we haven't pinpointed it. Fix it without changing the
public API surface."

---

## Intake snapshot

**`missions/2026-05-23-image-leak/mission.md` (excerpt)**

```markdown
# Mission: image-leak
id: 2026-05-23-image-leak
state: executing
goal: >
  Diagnose and fix the memory leak in the image processing Celery service.
  Workers grow from ~80 MB to ~1.2 GB over 500 tasks and OOM.
  Suspected area: thumbnail pipeline. Public API surface must not change.
approved_at: 2026-05-23T14:22Z
```

---

## Explorer fanout — diagnosis phase (6 in parallel, read-only)

For bug-fix missions, Explorers do **diagnosis** before the plan is written. The Orchestrator
holds off on decomposing into features until at least E1–E3 return.

- **E1**: "Read `services/imaging/thumbnails.py` in full. Identify any Pillow `Image` objects,
  file handles, or BytesIO buffers that are opened but not explicitly closed. Return file:line."
- **E2**: "Read `services/imaging/tasks.py`. How does the Celery task call the thumbnail
  pipeline? Is there any caching layer (lru_cache, module-level dict) that holds image data?"
- **E3**: "Search the entire `services/imaging/` tree for `Image.open`, `open(`, `BytesIO(`.
  For each, trace whether `.close()` or a context manager is used. Return a table."
- **E4**: "Is there a memory profiler already configured (memory_profiler, tracemalloc, pympler)?
  Any existing benchmark or load test for the imaging service?"
- **E5**: "Check `requirements.txt` and `requirements-dev.txt`. What version of Pillow?
  Are there known Pillow memory leak CVEs or changelogs for that version range?"
- **E6**: "Read the Celery worker config (`celeryconfig.py` or equivalent). What is
  `worker_max_tasks_per_child`? Is it set?"

---

## Explorer findings (hypothetical, realistic)

- E1 finds `thumbnails.py:47`: `img = Image.open(input_path)` — no context manager, no `.close()`.
- E1 finds `thumbnails.py:83`: `overlay = Image.open(WATERMARK_PATH)` called on every invocation —
  WATERMARK_PATH is a module-level constant but the Image object is re-opened each time.
- E3 confirms: 4 out of 7 `Image.open` calls lack explicit close or `with` block.
- E5 finds Pillow 9.4.0; known issue: JPEG decoder does not release internal buffer on `.close()`
  unless `.load()` is called first. Fixed in 9.5.0.
- E6: `worker_max_tasks_per_child` is not set (defaults to unlimited — workers never restart).

Three contributing causes identified. Plan can now be written.

---

## Plan snapshot

**`missions/2026-05-23-image-leak/plan.md` (excerpt)**

```markdown
## Root causes (from Explorer)
1. Unclosed Image objects in thumbnails.py (4 call sites).
2. Watermark image re-opened on every task instead of cached at module level with a single open.
3. Pillow 9.4.0 JPEG buffer leak; upgrade to 9.5.1 required.
4. worker_max_tasks_per_child unset — workers accumulate all leaks indefinitely.

## Feature order

F001  add-memory-benchmark   — Write `tests/perf/test_memory.py`: run 200 thumbnail tasks in-process,
                               assert RSS growth < 50 MB over the run. Must fail on current code (RED).
F002  fix-unclosed-images    — Wrap all Image.open calls in context managers or explicit .close() in
                               thumbnails.py. Do not change function signatures.
F003  cache-watermark        — Open WATERMARK_PATH once at module load; store as module-level constant.
                               Add .copy() call before compositing so the cached object is not mutated.
F004  upgrade-pillow         — Bump Pillow from 9.4.0 → 9.5.1 in requirements.txt.
F005  set-task-limit         — Set worker_max_tasks_per_child=500 in celeryconfig.py as a safety net.
F006  verify-benchmark       — Re-run F001 benchmark. Assert it is now green.
```

---

## Contract snapshot

**`missions/2026-05-23-image-leak/contract.md` (excerpt)**

```markdown
## Assertions

C-001  exit 0   python -m pytest tests/ -q (full suite)
C-002  exit 0   ruff check services/imaging/
C-003  behavioral   After F002: no bare Image.open() call in thumbnails.py outside a with-block
                    or followed by .close() within the same scope
C-004  exit 0   grep -n "Image\.open" services/imaging/thumbnails.py \
                  | grep -vE "(with Image\.open|\.close\(\))" (must return empty = exit 1)
                  Wrapped: [ -z "$(grep -n 'Image\.open' services/imaging/thumbnails.py \
                  | grep -vE '(with Image\.open|\.close\(\))')" ]
C-005  behavioral   WATERMARK_PATH image is opened exactly once per worker process (module-level)
C-006  exit 0   grep -c "Image\.open.*WATERMARK_PATH" services/imaging/thumbnails.py \
                  should return 1 (one open in module scope, zero inside functions)
C-007  exit 0   grep "pillow" requirements.txt | grep "9\.5\."
C-008  exit 0   grep "worker_max_tasks_per_child" celeryconfig.py
C-009  exit 0   python -m pytest tests/perf/test_memory.py -q
                  (the benchmark introduced in F001; must be RED before F002, GREEN after F006)
C-010  behavioral   Public function signatures in thumbnails.py unchanged (no new required params)
C-011  exit 0   python -m pytest tests/perf/test_memory.py -q --tb=short 2>&1 \
                  | grep "RSS growth" (assert value < 50 MB)
```

---

## Feature loop highlights

### F001 — add-memory-benchmark

This is written **before any fix**. The Worker uses `tracemalloc` or `psutil` to measure RSS
before and after 200 in-process calls to the thumbnail function. The test is expected to **fail**
on current code — that is the point. Scrutiny Validator confirms the test actually fails by
checking the handoff's exit-code table.

```python
# tests/perf/test_memory.py (sketch)
import psutil, os, pytest
from services.imaging.thumbnails import generate_thumbnail

def test_no_memory_growth():
    process = psutil.Process(os.getpid())
    rss_before = process.memory_info().rss / 1024 / 1024  # MB
    for _ in range(200):
        generate_thumbnail("tests/fixtures/sample.jpg", "/tmp/out.jpg", size=(128, 128))
    rss_after = process.memory_info().rss / 1024 / 1024
    growth = rss_after - rss_before
    assert growth < 50, f"RSS growth {growth:.1f} MB exceeds 50 MB threshold"
```

### F002 — fix-unclosed-images

Worker touches only `thumbnails.py`. Scrutiny checks:
1. C-004 (grep assertion) is satisfied.
2. No function signatures changed (C-010).
3. No new module-level mutable state introduced (immutability rule).

### F003 — cache-watermark

Worker adds one module-level line:
```python
_WATERMARK: Image.Image = Image.open(WATERMARK_PATH).convert("RGBA")
```

And replaces in-function opens with `_WATERMARK.copy()`. Scrutiny verifies C-006 (exactly one
`Image.open` for the watermark path, at module scope).

### F006 — verify-benchmark

This feature contains no code changes — its only artifact is the benchmark run output captured
in `features/006-verify-benchmark/evidence/pytest-perf.txt`. If C-009 is still red, F006 opens
a follow-up feature targeting the remaining cause.

---

## Lessons reinforced by this shape

- **Explorer before plan.** For bug fixes, skip the plan phase until Explorers return root causes.
  Writing a plan from intuition ("probably a Pillow version issue") risks a Worker that fixes the
  wrong thing.
- **The regression test (F001) must fail on current code.** A benchmark that passes before the fix
  is not a benchmark — it is a false negative. Scrutiny should explicitly confirm the red state.
- **Narrow scope per feature.** F002 only closes image handles. F003 only caches the watermark.
  F004 only bumps Pillow. If they are merged into one feature, a Scrutiny failure cannot identify
  *which* fix introduced a new problem.
- **Grep-as-assertion catches structural problems.** C-004 and C-006 are grep checks, not test
  assertions. They enforce the shape of the code, not just its behavior.
- **worker_max_tasks_per_child is a safety net, not a fix.** F005 is included because it prevents
  a future leak from going unnoticed for 10,000+ tasks. The contract (C-008) simply asserts it
  is set; the value is a policy decision left to the operator.
