# Protocol: Design Quality Gate for UI Missions

The design quality gate gives the user-testing-validator a concrete taste-gate beyond pure functional checks. Functional green is necessary but not sufficient when a feature ships user-observable UI.

---

## Purpose

Harness missions that ship UI surfaces have two orthogonal failure modes:

1. **Broken behavior** — a flow doesn't work. Caught by Scrutiny and functional contract assertions.
2. **Template-default appearance** — a flow works but the output looks like an unmodified library scaffold, a stock hero section, or a generic card grid. Not caught by any executable assertion unless this protocol is active.

This protocol defines the checks the user-testing-validator runs to catch failure mode 2.

---

## When this protocol applies

This protocol is **active only when a feature's spec includes `user-observable behavior: yes`**. The Orchestrator flags this in the feature spec at plan time.

Skip this protocol entirely for:
- Protocol/doc-only features (no UI surface).
- Backend-only features (API, DB, build tooling).
- Test-only features.

---

## Deference to ECC global rules

The underlying principles — anti-template policy, banned UI patterns, required design qualities — are defined in the user's global rules at `~/.claude/rules/ecc/web/design-quality.md`. This protocol does **not** duplicate them. It only adds harness-specific gate mechanics on top.

Before applying harness gates, the user-testing-validator reads and internalises the ECC design quality standard. The ECC rules are authoritative; this protocol is additive.

Key ECC references the validator must apply:
- **Anti-template policy**: banned patterns, required qualities checklist (four or more of ten must be demonstrated).
- **Style direction**: the feature spec must declare a specific visual direction. Generic "clean minimal" is not a direction.
- **Component checklist**: hover/focus/active states, intentional hierarchy, plausible product screenshot test.

---

## Harness-specific gates

These are in addition to the ECC global checklist.

### Gate 1 — Screenshot evidence at three breakpoints

The validator captures screenshots at **375 px**, **768 px**, and **1440 px** (mobile, tablet, desktop). Evidence is stored at `features/NNN/evidence/design-<breakpoint>.png`.

A gate failure is recorded if:
- Screenshots are missing for any required breakpoint.
- The surface renders identically across all three breakpoints with no meaningful layout adaptation.

### Gate 2 — Template-default check

The validator applies a negative test: does this surface look like an unmodified starter template, a shadcn/ui or Tailwind UI default, or a stock component library output?

Red indicators (any one is a finding):
- Centered `h1` + gradient blob + generic CTA with default shadow.
- Uniform card grid where all cards share identical radius, padding, shadow, and font size.
- No visual hierarchy — every element receives the same emphasis.
- Default font stack in use with no declared reason.

The validator writes a one-sentence verdict for this gate: `pass — no template-default indicators observed` or `fail — <specific indicator>`.

### Gate 3 — Declared style direction

The feature spec must name a specific style direction (e.g., editorial, neo-brutalism, bento, dark luxury). The validator checks:
- The spec contains a `style-direction:` field.
- The rendered surface is consistent with that direction. "Consistent" means at least two of the ECC required qualities visible to a non-designer.

If the spec omits `style-direction:`, this gate is a **red finding**. The Orchestrator must amend the spec before re-spawning.

---

## Verdict format additions

When this protocol is active, the user-testing-validator appends a **Design Quality** section to its standard verdict:

```markdown
### Design Quality (protocol: design-quality.md)

| Gate | Result | Notes |
|------|--------|-------|
| G-1 screenshot evidence (375/768/1440) | pass/fail | evidence paths or missing breakpoints |
| G-2 template-default check | pass/fail | one-sentence finding |
| G-3 declared style direction | pass/fail | direction named + consistency verdict |

**ECC component checklist** (pass count / 4 minimum required):
- [ ] hierarchy through scale contrast
- [ ] intentional spacing rhythm
- [ ] depth or layering
- [ ] typography character
- [ ] semantic color use
- [ ] designed hover/focus/active states
- [ ] grid-breaking or bento composition
- [ ] texture or atmosphere
- [ ] clarifying motion
- [ ] data visualization in system

Design quality verdict: **green** / **red**
```

A red design quality verdict makes the overall feature verdict red, the same as a failed functional flow.

---

## Anti-patterns

- Do not mark design quality green because the functional flows passed.
- Do not skip the ECC component checklist if fewer than four items are demonstrably present.
- Do not accept "clean and minimal" as a style direction — require a named direction from the ECC worthwhile styles list or a justified equivalent.
- Do not skip screenshots because the app "looks fine." Evidence is required.

---

## Cross-references

- **`~/.claude/rules/ecc/web/design-quality.md`** — ECC global design quality standard. Authoritative source for anti-template policy, banned patterns, and required qualities.
- **`.claude/agents/user-testing-validator.md`** — the agent that runs this protocol. Gates defined here are appended to its standard verdict workflow.
- **`protocols/user-testing-validator.md`** — orchestrator-level description of when and how to spawn the user-testing-validator.
- **`protocols/validation-contract.md`** — contract structure; design quality assertions should appear as behavioral assertions with type `behavioral` and owner pointing to the relevant UI feature.
