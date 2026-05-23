# Protocol: Model Routing

No single model is best at planning, implementation, and validation. The Orchestrator routes each role to a model that fits.

## Default routing table

| Role | Model | Why | Cost shape |
|------|-------|-----|------------|
| Orchestrator | Opus | Slow careful reasoning, strategic decomposition, contract authoring | High per token, low token count |
| Worker | Sonnet | Code fluency, fast generation, strong tool use | Medium per token, high token count |
| Scrutiny Validator | Sonnet (or Haiku if contract is mechanical) | Strict instruction-following on a list of assertions | Medium-low |
| User-Testing Validator | Sonnet | Tool use (browser, computer-use), evidence capture | Medium |
| Explorer | Haiku | Cheap, parallel, read-only | Low |
| Sub-Orchestrator (rare) | Opus | Same reasoning quality as parent | High |

## How to specify

When spawning a subagent via the Agent tool, set the `model` parameter explicitly. Do not rely on inheritance — inheritance is fine for one-offs, but cost-accounting wants intent.

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",       // worker
  description: "Worker — feature 003-add-oauth-routes",
  prompt: <agents/worker.md prefix> + <feature spec> + <contract slice>
})
```

## Provider isolation (v0.5)

The strongest version of Creator-Verifier puts the Worker and the Validator on **different providers** so the Validator doesn't inherit Worker training-data biases. This isn't trivial inside Claude Code — we approximate it via:

1. **Different models within Claude** (Opus vs Sonnet vs Haiku) — partial isolation.
2. **MCP integration** with an external provider's CLI for the Validator role — full isolation, planned for v0.5.

Until v0.5, isolate via:
- Different model tier (Worker = Sonnet, Validator = Haiku).
- Fresh context per role (already done).
- Strict role prompts that prevent the Validator from inheriting Worker reasoning (already done).

## Budgets

Each role has a soft budget. The Orchestrator records actual spend in `status.json` and aggregates in `post-mortem.md`.

| Role | Tokens (soft cap per feature) |
|------|------------------------------|
| Worker | 80k input + 20k output |
| Scrutiny Validator | 30k input + 8k output |
| User-Testing Validator | 50k input + 15k output |
| Explorer (per question) | 10k input + 3k output |

A Worker that hits its cap should hand off **what it has** and escalate via the handoff. A Validator that hits its cap is suspicious — the contract may be too vague.

## When to deviate

- **Use Haiku for Workers on trivial features** (e.g., a typo fix, a config update). The Worker prompt allows this; the contract still gates it.
- **Use Opus for Validators on safety-critical features** (auth, payments, migrations). Different model than the Worker is the point.
- **Use Sonnet for Explorers on hard questions** that need real synthesis, not just grep.

## Anti-patterns

- ❌ Running every role on the same model "because it's simpler" — defeats the entire point of role-tiered routing.
- ❌ Routing the Validator to the **same** model and context style as the Worker — bias inheritance.
- ❌ Using Opus as Worker because "more intelligence = better" — code fluency, not reasoning, is the bottleneck for implementation.
- ❌ No budget. The Orchestrator should be tracking spend per role per feature; "I'll worry about cost later" is the path to a $5,000 mission.
