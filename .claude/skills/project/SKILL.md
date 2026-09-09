---
name: project
description: Register, inspect, or list the projects this harness delivers work to, with each project's standing delivery posture (no-mistakes, direct-PR, local-only, +yolo). Use when adding a new project or when you need to know how a project's work is allowed to ship.
argument-hint: [list | add <name> <path> --mode <mode> | mode <name>]
allowed-tools: Bash(./scripts/project.sh *), Read
---

## Registered projects

!`${CLAUDE_PROJECT_DIR}/scripts/project.sh list`

---

`$ARGUMENTS` says what the captain wants. With no arguments, present the list above and stop.

### The distinction that matters

The registry records **the posture the captain registered for a project**. It does *not* decide how a given task ships. That is resolved per task at intake and passed explicitly to the crew scripts.

So: a task may deviate from its project's registered mode when there is a reason, and you say so out loud and log it. What you must never do is quietly edit the registry to match what you were about to do — that turns a one-off decision into a standing policy the captain never chose.

### Modes

| Mode | Means |
|---|---|
| `no-mistakes` | full pipeline → PR → the no-mistakes gate → the configured merge authority |
| `direct-PR` | push and open a PR, no gate pipeline |
| `local-only` | local branch, guarded local merge, never a remote |

`+yolo` grants merge autonomy — it changes what the *supervisor* may land unattended, never what a crewmate may do.

`allow="<cmds>"` extends a crewmate's tool allowlist at spawn (Phase 3). Leave it off unless the project genuinely needs a build or test command; a crewmate that needs more reports `blocked:` rather than being handed it silently.

### Adding a project

```
./scripts/project.sh add <name> <path> --mode <mode> [--yolo] [--allow "bun *, make test"] [--desc "..."]
```

`add` refuses rather than repairs: an unknown mode, a path that is not a git checkout, a name or path already registered. Registering a project is a policy decision, and a policy silently corrected is a policy not chosen. Ask the captain which mode they want — never pick one for them.
