# Pattern: Audit-Driven Implementation

**Source:** a mission on a private project (preceded by a research/audit mission on the same project)
**Confidence:** high (5/5 first-pass, zero follow-ups)

## Context

When implementing fixes from a prior research/audit mission, the audit report serves as both the requirements document and the worker briefing material.

## Pattern

1. **Audit report recommendations map directly to features.** Group by theme (accessibility, design system, UX) rather than by individual recommendation number. A single feature handles 3-4 related recommendations that touch overlapping files.

2. **File paths and line numbers from the audit are gold — but verify at intake.** The audit cited one screen file for a modal component, but the modal actually lived in a different screen file. Run 1-2 explorers at intake to spot-check key file references.

3. **Baseline lint/typecheck at intake.** If `bun run lint` already exits 1, asserting "lint passes" is unenforceable. Assert "no new lint errors in modified files" instead, or explicitly exclude pre-existing errors.

4. **Baseline file sizes at intake.** C-019 (no file > 800 lines) caught 4 pre-existing violations. Scope structural assertions to files created/modified by the mission, not the entire codebase.

5. **`grep`-based contract assertions need multi-line awareness.** A close button that spans `<Pressable\n  onPress={onClose}` will fail a grep that requires both keywords on the same line. Use `grep -A` or `grep -P` with dotall for multi-line patterns, or validate with two separate greps.

6. **Workers that modify a React Native app with Expo Router typed routes** must edit `.expo/types/router.d.ts` manually (gitignored) when adding new routes, unless the Expo dev server is running. Brief workers about this.

## Anti-pattern

Don't treat an audit report as a specification. It identifies problems and suggests solutions, but the solutions need engineering judgment. A recommendation to rename an intimidating label was good because it addressed the audience's anxiety; a naive "just raise fontSize" would miss that context.
