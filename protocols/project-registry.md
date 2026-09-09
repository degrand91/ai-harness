# Protocol: Project Registry

The harness delivers work to projects it does not own. `data/projects.md` records, for each one, the **standing delivery posture the captain registered**. `scripts/lib/registry.sh` is the single owner of the file format.

---

## The distinction this protocol exists to protect

The registry answers **"what posture did the captain register for this project"**.

It does **not** answer **"how does this task ship"**. That is resolved per task at intake and passed explicitly to the crew scripts (Phase 3), which cross-check it against the brief and refuse a mismatch.

Keeping these apart is what allows a task to deviate — with a stated reason, in the open — instead of the deviation silently rewriting the captain's standing policy. Editing the registry to match what you were about to do turns a one-off decision into a policy nobody chose.

---

## Format

```
- <name> [<mode>[ +yolo]] <path> [allow="<cmd>, <cmd>"] - <description> (added <date>)
```

Everything else in the file is prose and is ignored, so the file stays hand-editable.

| Field | Meaning |
|---|---|
| `name` | how the captain refers to the project |
| `mode` | `no-mistakes` · `direct-PR` · `local-only` |
| `+yolo` | merge autonomy for the **supervisor**; changes nothing about a crewmate |
| `path` | the project's **primary checkout**. Crew worktrees are linked worktrees of this, placed under `data/worktrees/<project>/<task>`, so the project tree is never polluted |
| `allow=` | extends a crewmate's tool allowlist at spawn. Absent means the base allowlist only |

## Modes

| Mode | Delivery |
|---|---|
| `no-mistakes` | full pipeline → PR → the `no-mistakes` gate → the configured merge authority |
| `direct-PR` | push + PR, no gate pipeline |
| `local-only` | local branch, guarded local merge, never a remote |

---

## Rules

1. **An unregistered project has no posture.** `registry_resolve` exits 1 rather than defaulting. Defaulting to the safest mode would still ship work under a policy the captain never chose. Ask.
2. **A malformed entry is a loud refusal, not a skip.** Exit 2, naming the project. A registry the tooling half-understands is worse than one it rejects.
3. **`add` refuses rather than repairs.** Unknown mode, a path that is not a git checkout, a duplicate name or path — all errors.
4. **The harness never writes into a project directly.** Every change to a project goes through a crewmate in a worktree and lands through the registered mode.
5. **`allow=` is granted, never assumed.** A crewmate that needs a command it does not have reports `blocked:` — it does not get it silently.

---

## Commands

```sh
./scripts/project.sh list
./scripts/project.sh add <name> <path> --mode <mode> [--yolo] [--allow "bun *"] [--desc "..."]
./scripts/project.sh resolve <name>     # "<mode> <yolo> <path>"
./scripts/project.sh mode|yolo|path|allow <name>
./scripts/project.sh validate
```

Exit codes are the contract: `0` resolved · `1` not registered · `2` refused.

## What a crewmate costs

Measured on this machine: a **trivial** `haiku` crewmate turn cost **$0.05**, and
a small real feature **$0.07**. Every launch pays for the system prompt, the
global `CLAUDE.md`, and hook context before it does any work.

So the floor per crewmate is *cents, not fractions of a cent*. Set
`config/spend-cap-daily` against that number rather than against per-token
intuition — `scripts/snapshot.sh` rolls real spend up per mission and per day
from what each crewmate actually reported.

See also [knowledge-routing.md](knowledge-routing.md) for where facts about a project belong.
