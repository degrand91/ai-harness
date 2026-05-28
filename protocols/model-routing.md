# Protocol: Model Routing

No single model is best at planning, implementation, and validation. The Orchestrator routes each role to a model that fits.

## Default routing table

| Role | Model | Why | Cost shape |
|------|-------|-----|------------|
| Orchestrator | Opus | Slow careful reasoning, strategic decomposition, contract authoring | High per token, low token count |
| Worker | Sonnet | Code fluency, fast generation, strong tool use | Medium per token, high token count |
| Scrutiny Validator | **Sonnet by default**; Haiku only for purely mechanical contracts | Adversarial verification benefits from stronger judgment; Haiku is opt-in for cost-bounded mechanical checks | Medium (Sonnet) / Low (Haiku) |
| User-Testing Validator | Sonnet | Tool use (browser, computer-use), evidence capture | Medium |
| Explorer | Haiku | Cheap, parallel, read-only | Low |
| Sub-Orchestrator (rare) | Opus | Same reasoning quality as parent | High |

## Scrutiny model selection

The Scrutiny Validator is the only adversarial check on the worker's claims. Its job is to disbelieve and run the assertions. Haiku has been observed fabricating bash command outputs with zero tool calls (see `learnings/anti-patterns/haiku-scrutiny-hallucination.md`). The orchestrator-side guard catches this, but the underlying model unreliability remains.

The rule:

- **Default: Sonnet.** Use Sonnet for scrutiny on any mission whose contract contains judgment-call assertions, subjective verification, or any check more complex than `exit 0` / `grep -q`.
- **Exception: Haiku.** Use Haiku only when ALL contract assertions are purely mechanical: shell exit codes, file existence, grep with fixed strings, JSON field presence. No subjective wording ("substantive content", "well-formed", "follows best practices").

### What counts as a judgment call

If any of these appear in your contract, route scrutiny to Sonnet:
- Anti-template gate (design quality, banned patterns)
- "Substantive content" / "covers at least N topics" / "well-written"
- Behavioral assertions that require interpreting output (not just exit codes)
- Security review patterns (anything from `security-reviewer`)
- User-facing flows where pass/fail depends on observed UX

### What is mechanical

These can stay on Haiku:
- `test -f path && exit 0`
- `grep -q 'exact-string' file`
- `jq -e '.field' file > /dev/null`
- `wc -l file | xargs test 50 -lt`
- `bash scripts/harness-audit.sh` exit code

### Cost trade-off

Sonnet scrutiny costs ~10x Haiku per pass. Scrutiny is the cheap part of any mission's budget (typical: 30k input, 8k output). The cost delta is small in absolute terms. The quality delta on judgment-call assertions is large.

### Setting the model at spawn time

```
const SCRUTINY_MODEL = contractIsAllMechanical(contract) ? "haiku" : "sonnet";

Agent({
  subagent_type: "scrutiny-validator",
  model: SCRUTINY_MODEL,
  description: `Scrutiny — F${nnn} ${slug}`,
  prompt: <feature spec> + <contract slice> + <diff>
})
```

## How to specify

When spawning a subagent via the Agent tool, set the `model` parameter explicitly. Do not rely on inheritance — inheritance is fine for one-offs, but cost-accounting wants intent.

```
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",       // worker
  description: "Worker — feature 003-add-oauth-routes",
  prompt: <feature spec> + <contract slice>   // role prompt loaded from .claude/agents/worker.md automatically
})
```

## Provider isolation (v0.3)

The strongest version of Creator-Verifier puts the Worker and the Validator on **different providers** so the Validator doesn't inherit Worker training-data biases. This is shipped in v0.3 via the two-agent-file pattern — see [`protocols/multi-provider-validation.md`](multi-provider-validation.md) for the full design.

The mechanism: two agent files (`scrutiny-validator.md` and `scrutiny-validator-external.md`), selected at scrutiny-spawn time by inspecting the `HARNESS_EXTERNAL_VALIDATOR_PROVIDER` env var. External path is opt-in; default path (Haiku, no MCP) is unchanged.

Approximate isolation via different model tiers remains a complementary defence — not a substitute:
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
- **Default scrutiny to Sonnet.** Use Haiku only for missions where every assertion is mechanical (exit codes, fixed grep patterns). See "Scrutiny model selection" above.
- **Use Opus for Validators on safety-critical features** (auth, payments, migrations). Different model than the Worker is still the point.
- **Use Sonnet for Explorers on hard questions** that need real synthesis, not just grep.

## Anti-patterns

- ❌ Running every role on the same model "because it's simpler" — defeats the entire point of role-tiered routing.
- ❌ Routing the Validator to the **same** model and context style as the Worker — bias inheritance.
- ❌ Using Opus as Worker because "more intelligence = better" — code fluency, not reasoning, is the bottleneck for implementation.
- ❌ No budget. The Orchestrator should be tracking spend per role per feature; "I'll worry about cost later" is the path to a $5,000 mission.
