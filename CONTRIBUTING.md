# Contributing to the Harness

Welcome — and thank you for taking the time to contribute. The harness is a small, opinionated system and contributions are intentionally deliberate. This guide explains how to get changes in without breaking the discipline the project is built around.

## How the project is structured

Start with [CLAUDE.md](CLAUDE.md) — it is the operating manual every session reads automatically. Then read [ARCHITECTURE.md](ARCHITECTURE.md) for the full design. The short version: an Orchestrator plans missions, Workers implement features serially (one at a time), and Validators check the results against a contract written before any code is touched.

## How to propose changes

### Bugs and typos
Open an issue or submit a PR directly. Small, obviously-correct fixes do not need a discussion first.

### New features
Open an issue to discuss the design before submitting code. State what problem you are solving and why the harness is the right place to solve it. Many ideas are better handled as a wrapper or extension rather than a core change.

### New agents or protocols
This is a design discussion. Expect back-and-forth. A new agent or protocol changes the system's guarantees, so it needs to be justified against the architecture and tested against the contract discipline. Open an issue with a one-page sketch first.

## The dog-food rule

This project eats its own dog food. If you are adding or changing a protocol, an agent definition, a skill, or a hook, your PR must include a real mission folder that exercises the change.

At minimum your PR must contain:
- `missions/<date>-<slug>/contract.md` — what done means for your change
- `missions/<date>-<slug>/plan.md` — how you planned it
- The resulting code change

If you ran the harness while building your contribution, include the full mission folder. If you could not (because the harness itself was broken), explain why in the PR description.

## The test rule

A mission folder is evidence that a change worked once. It is not a regression gate. **Any change to a file under `scripts/` or `.claude/hooks/` must also ship a test**, because these are the files that run on every turn and fail silently when they fail.

```sh
./tests/run.sh                       # everything
./tests/run.sh --filter turnend-guard  # one hook
./tests/run.sh --list                # what exists
./scripts/lint.sh                    # shellcheck (skips cleanly if absent)
./scripts/doctor.sh --check          # tools and state roots
```

Tests are plain `*.test.sh` files under `tests/`, with no framework to install — `bash`, `jq`, and coreutils are all the harness itself requires, so they are all the suite may require. `tests/lib/fixtures.sh` gives you a throwaway harness home, mission builders, hook invocation, and assertions:

```bash
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/fixtures.sh"

home="$(mktmphome)"
mkmission "$home" 2026-01-01-demo '{"state":"executing","features":[]}' >/dev/null

it "allows a stop when nothing is red"
run_hook stop-turnend-guard.sh '{"hook_event_name":"Stop"}' "CLAUDE_PROJECT_DIR=$home"
assert_rc 0 "$HOOK_RC"

finish
```

Three rules learned from the hooks that were already broken when the suite was written:

1. **Resolve code from `BASH_SOURCE`, data from `CLAUDE_PROJECT_DIR`.** A hook that sources a library from `CLAUDE_PROJECT_DIR` silently disables itself the moment those two differ.
2. **Do not use `set -e` in a hook.** Malformed input made three separate hooks exit non-zero instead of doing nothing. Use `set -uo pipefail` and guard each `jq` with `|| true`.
3. **State comes from the state library, never from `.state` directly.** Mission files carry two vocabularies, and reading one of them is how a Stop guard came to report "all clear" on the only mission that was actually stuck. `scripts/lib/state-vocabulary.json` is the owner of the *rule*; `status-read.sh` (bash, for hooks) and `harness.py` (for batch readers) are two lookups over it, and `tests/state-vocabulary.test.sh` asserts they agree. `.features[].state` is an ordinary field and is read directly on purpose.

4. **Never hand-roll a delimited-string protocol in bash.** Four of this repo's defects were that one mistake: `IFS=$'\t' read` collapses consecutive tabs so an empty field shifts every later field left (twice), a space-joined list whose entries contain spaces got split back into fragments, and `python3 - <<'PY'` ate the stdin its own program needed. If you are passing a record, use a real script and pass structured data — `scripts/snapshot.py` and `scripts/crew/allowlist.py` exist for exactly this reason.

5. **Make relative file times explicit in tests.** Fixtures written in one run share a timestamp, so any assertion about "newest" is undefined and passes by luck until a different filesystem disagrees. It has bitten three times. Use `age_file`, `touch_now` and `age_mission_by` from `fixtures.sh` rather than writing two files and hoping.

CI runs the suite on Ubuntu and macOS. macOS ships bash 3.2, so no `mapfile`, no associative arrays, no `${var^^}`.

## Code style

Follow the same contract discipline the harness enforces on the code it produces:
- Assertions must be executable — commands with expected exit codes, not prose descriptions of what you hope is true.
- No grep-only evidence. If you claim a feature works, the contract slice must verify observable behavior.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat(scope): summary`, `fix(scope): summary`, `docs(scope): summary`, etc.

## PR process

1. Fork the repository and create a branch.
2. Run a real mission (or at minimum write a contract slice) for your change.
3. Open a PR with the mission folder included.
4. Describe what contract assertions your change satisfies and include the command output that proves them.

## Where to ask questions

Use GitHub Issues. Tag discussion-type issues with `question` or `discussion`. If GitHub Discussions is enabled on this repository, prefer that for open-ended topics.

## Code of conduct

This project is governed by the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating, you agree to its terms.
