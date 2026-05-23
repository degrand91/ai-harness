# Protocol: Visual Regression Snapshot Convention

This protocol defines how visual regression snapshots are named, stored, and used within the harness.

---

## Purpose

UI missions generate visual regression baselines and comparison images to detect unintended rendering changes and to provide evidence for the user-testing-validator. Snapshot files are mission-scoped and feature-scoped so each feature's visual evidence stays isolated, reproducible, and diff-friendly.

---

## Layout

All snapshots live under the mission state tree, never in the application source tree.

```
missions/<id>/snapshots/<feature-id>/<viewport>-<state>.png
```

Examples:

```
missions/2026-05-23-foo/snapshots/F003/375-baseline.png
missions/2026-05-23-foo/snapshots/F003/768-baseline.png
missions/2026-05-23-foo/snapshots/F003/1440-baseline.png
missions/2026-05-23-foo/snapshots/F003/1440-hover.png
missions/2026-05-23-foo/snapshots/F003/375-focus.png
```

- `<id>` — the mission identifier in `YYYY-MM-DD-<kebab-slug>` format.
- `<feature-id>` — the zero-padded feature number with its slug, e.g. `F003` or `003-add-auth-ui`.
- `<viewport>` — viewport width in pixels, using the names below.
- `<state>` — the rendering state, using the names below.

---

## Viewport conventions

| Name | Width (px) | Represents |
|------|-----------|------------|
| `375` | 375 | Mobile |
| `768` | 768 | Tablet |
| `1440` | 1440 | Desktop |

These three are the minimum required set. Additional widths (e.g. `320`, `1024`, `1920`) may be added when the contract demands them. Always use the raw pixel width as the name — never descriptive labels like `mobile` or `desktop` in the filename.

---

## State conventions

| State name | When to capture |
|------------|-----------------|
| `baseline` | First run on a fresh feature; establishes the reference. |
| `before` | Current state immediately before a change is applied (re-baseline trigger). |
| `after` | State after a change is applied; diff'd against `before` or `baseline`. |
| `hover` | Interactive hover state on a key element. |
| `focus` | Keyboard focus visible on a key interactive element. |
| `active` | Active / pressed state. |
| `error` | Error or validation state of the surface. |
| `empty` | Empty or zero-data state. |

Interaction states (`hover`, `focus`, `active`, etc.) are captured in addition to the lifecycle states (`baseline`, `before`, `after`), not instead of them.

---

## When to capture

1. **Baseline** — The user-testing-validator captures the baseline set (`375-baseline.png`, `768-baseline.png`, `1440-baseline.png`) on the first run of any UI feature. If no baseline exists yet, the first run creates it; no diff is produced.
2. **After** — On subsequent runs, `after` images are captured and diff'd against the stored `baseline` or `before`. A pixel difference above the contract-defined threshold is a finding.
3. **Interaction states** — Captured on each run when the contract includes flows that exercise hover, focus, or other interactive states.
4. **Re-baseline** — If a visual change is intentional (e.g. a design update), the Orchestrator explicitly promotes `after` images to `baseline` by overwriting. A `before` image is kept alongside for audit.

Non-UI features (backend-only, doc-only, test-only) do not produce snapshots.

---

## Storage

- **Format**: PNG only. Lossless compression is required. JPEG and WebP are not accepted.
- **Location**: `missions/<id>/snapshots/<feature-id>/` — inside the mission state tree, not inside the application source tree.
- **Git**: Snapshot files are **not committed**. Add the following entry to `.gitignore` if it is not already present:

  ```
  missions/*/snapshots/
  ```

- **Retention**: Snapshots persist for the lifetime of the mission folder. After `mission-review` closes the mission, the folder (including snapshots) may be archived or deleted at the operator's discretion.

---

## Cross-references

- **`protocols/design-quality.md`** — defines the design quality gate that drives screenshot capture at 375 / 768 / 1440 px and specifies the evidence path format `features/NNN/evidence/design-<breakpoint>.png` used within the feature folder. The snapshots described here are the mission-level storage; evidence inside `features/NNN/evidence/` is the feature-level copy referenced by the validator verdict.
- **`.claude/agents/user-testing-validator.md`** — the agent responsible for capturing all snapshots. The anti-template gate in that agent stores its breakpoint screenshots under `features/NNN/evidence/anti-template-<viewport>.png`; those files are copies or symlinks of the canonical snapshots stored here.
