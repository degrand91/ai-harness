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
