# Protocol: Knowledge Routing

Every durable fact has exactly one right home. With a single project, `learnings/` as one bucket was fine. With a registry of projects, everything silts into one pile unless each fact is routed deliberately.

Adapted from firstmate's `AGENTS.md` §6.

---

## The routing table

| The fact is… | It belongs in… |
|---|---|
| how the captain likes to work; a standing preference or correction | `.claude/agent-memory/orchestrator/` |
| an operational fact about **this harness** — a pattern that worked, a trap that did not | `learnings/patterns/` · `learnings/anti-patterns/` |
| scoped to one task or feature | the mission: `missions/<id>/features/<n>/` |
| the finding of an investigation | that scout's report |
| useful to **anyone** working on project X, not just the harness | that project's committed `AGENTS.md` |
| a proposed change to a protocol, template, or prompt | `learnings/proposals/` |

---

## Rules

1. **Route before you write.** "Where does this belong?" is answered by the table, not by whichever file is already open.
2. **The harness never writes a project's `AGENTS.md` directly.** A crewmate does it, through that project's registered delivery path, and prefers a pointer to an authoritative source over copied detail that will rot.
3. **Keep fleet posture and captain-private strategy out of project memory.** A project's `AGENTS.md` is read by everyone who works on that project. How the captain feels about a vendor does not go there.
4. **One home, not several.** A fact copied into two places will be corrected in one. If it seems to belong in two, it is usually two different facts — split it.
5. **A note in the wrong place is worse than no note.** It is found by someone who then trusts it in a context where it does not hold.

---

## Where this is enforced

- `/stow` (Phase 5) sweeps a session for uncaptured durable knowledge and files each finding through this table, rather than dumping everything into `learnings/`.
- `learnings/` gains a lifecycle in Phase 5.1 — tiering, archival, and a budget — so the harness-local bucket cannot grow without bound.

See also [project-registry.md](project-registry.md).
