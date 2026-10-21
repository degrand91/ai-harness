# Vendored skill: scroll-craft

This directory is a **vendored third-party skill**, not harness-authored code. It
is copied verbatim from the `nateherk-design` plugin so the harness ships with it
(the harness's "copy the folder, you have the harness" model), rather than
depending on a separately-installed Claude Code plugin.

| | |
|---|---|
| Upstream | https://github.com/nateherkai/scroll-craft |
| Plugin | `nateherk-design` v0.3.1 |
| Author | Nate Herk |
| License | MIT (see [LICENSE](LICENSE) in this folder) |
| Vendored from commit | `75d81f74e83692add18cd7a8a8e078b8a887a579` |
| Vendored on | 2026-10-21 |
| Source path | `plugins/nateherk-design/skills/scroll-craft/` |

## What it is

An agent skill for building premium, scroll-driven landing pages — layered
heroes, scroll-scrubbed video, pinned sections, a headless-browser verification
pass. Invoke it as `/scroll-craft`, or a worker can read `SKILL.md` and follow it.

## Prerequisites (NOT part of the core harness)

The core harness is dependency-free (bash, jq, coreutils). **This skill is not** —
it only runs when you actually invoke it, and then it needs:

- **Node 18+** — the `.mjs` scripts under `scripts/`.
- **ffmpeg** — `scripts/encode.sh`, for scroll-scrubbable video encoding.
- **playwright-core + Chrome** — `scripts/shoot.mjs` / `doctor.mjs`, installed in
  the *build* workspace (the project being built), not here.
- **`KIE_AI_API_KEY`** (optional) — only for generating photoreal assets via
  kie.ai. Building from your own supplied assets needs no key and no cost.

Run `node .claude/skills/scroll-craft/scripts/doctor.mjs` from inside a build
workspace to check what is present. Upstream notes it has been exercised on
Windows; macOS is untested there.

## Updating

Re-copy `plugins/nateherk-design/skills/scroll-craft/` from a newer upstream
commit, refresh the commit/date/version in the table above, and re-run
`scripts/harness-audit.sh`. Keep local edits to a minimum so the vendored copy
stays diffable against upstream; record any that are unavoidable here.

## Local modifications

None — verbatim copy, plus this `UPSTREAM.md` and the upstream `LICENSE` brought
into the folder for attribution.
