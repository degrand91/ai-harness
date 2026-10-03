---
name: pin-prerelease-alias-with-guard
description: When a lockfile refresh keeps moving a transitive prerelease (alpha/beta dist-tag), find the exact edge that floats (often an npm alias like "ui5": "npm:pkg@alpha"), pin only that edge with a package-manager override, and commit a guard test that reads the lockfile so the next drift fails CI instead of a reviewer's eye.
introduced_in_mission: 2026-09-30-extract-overlay-dedicated-repo
tags: [pnpm, lockfile, dependencies, sanity, ci, guard-test]
---

## Pattern

1. **Find the floating edge, not the package.** `sanity@6.10.1` declares both
   `"@sanity/ui": "^4.0.3"` and `"ui5": "npm:@sanity/ui@alpha"`. Only the alias
   floats: every re-resolve picks the newest `5.0.0-alpha.*`.
2. **Pin that edge only.** In `pnpm-workspace.yaml`:
   `overrides: { ui5: "npm:@sanity/ui@5.0.0-alpha.12" }`. A blanket
   `"@sanity/ui": "5.0.0-alpha.12"` override rewrites every edge and silently
   deleted the legitimate `@sanity/ui@4.0.6` line (caught only by a
   name@version diff of the lockfile).
3. **Regenerate from the base lockfile**, not from scratch: start from
   `origin/main`'s `pnpm-lock.yaml`, add the override, install. Then diff the
   `packages:` and `snapshots:` keys against main: zero removed, zero changed,
   only the intended additions.
4. **Prove it is load-bearing**: remove the override, reinstall, watch the drift
   come back; restore.
5. **Guard it**: a node test that reads `pnpm-lock.yaml` and fails if any
   `@sanity/ui@5.0.0-alpha.*` other than the pinned one appears, or the lockfile's
   own `overrides:` block lost the pin. Scope the regex to the pinned line so the
   legitimate 4.x line is not flagged.

## Why it works

The drift was invisible in the diff of any feature (it rode along with
unrelated devDependency additions) and recurred three times in one mission. A
reviewer checking "only my packages changed" catches it once; a test catches it
forever, including in PRs nobody reviews closely.

## How to apply

Any time a scrutiny report says an existing package changed version as a side
effect, do not just revert the lockfile: open a follow-up that finds the
floating edge and pins it with a guard. Ask the validator for the full
added/removed/changed name@version list, not a yes/no.

## Origin

[post-mortem](../../missions/2026-09-30-extract-overlay-dedicated-repo/post-mortem.md), features F006 and F009a.
