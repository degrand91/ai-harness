---
name: pin-prerelease-alias-with-guard
description: When a lockfile refresh keeps moving a transitive prerelease (alpha/beta dist-tag), find the exact edge that floats (often an npm alias like "lib5": "npm:lib@alpha"), pin only that edge with a package-manager override, and commit a guard test that reads the lockfile so the next drift fails CI instead of a reviewer's eye.
introduced_in_mission: private
tags: [pnpm, lockfile, dependencies, ci, guard-test]
---

## Pattern

1. **Find the floating edge, not the package.** A dependency declares both
   `"lib": "^4.0.3"` and `"lib5": "npm:lib@alpha"`. Only the alias floats:
   every re-resolve picks the newest `5.0.0-alpha.*`.
2. **Pin that edge only.** In `pnpm-workspace.yaml`:
   `overrides: { lib5: "npm:lib@5.0.0-alpha.12" }`. A blanket
   `"lib": "5.0.0-alpha.12"` override rewrites every edge and silently deletes
   the legitimate `lib@4.x` line (caught only by a name@version diff of the
   lockfile).
3. **Regenerate from the base lockfile**, not from scratch: start from
   `origin/main`'s `pnpm-lock.yaml`, add the override, install. Then diff the
   `packages:` and `snapshots:` keys against main: zero removed, zero changed,
   only the intended additions.
4. **Prove it is load-bearing**: remove the override, reinstall, watch the drift
   come back; restore.
5. **Guard it**: a test that reads `pnpm-lock.yaml` and fails if any
   `lib@5.0.0-alpha.*` other than the pinned one appears, or the lockfile's own
   `overrides:` block lost the pin. Scope the regex to the pinned line so the
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

A mission on a private project; the post-mortem stays local.
