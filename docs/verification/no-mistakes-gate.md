# The `no-mistakes` gate — what the tool actually is

Run 2026-09-09 against **no-mistakes@0.61.2** (`jonathanong/no-mistakes`), on a
throwaway TS fixture. This closes row (e) of `crew-spike.md`, which was
**NOT VERIFIED — tool not installed**.

## What it is

Not a PR-approval service, which is what the `no-mistakes` mode was designed
against. It is a **local AST graph for coding agents** — impact maps, focused
test plans, Playwright coverage, repository checks — for TS/JS, plus Swift,
Terraform, and a few frameworks. It ships as a **per-project devDependency**
(`npm install --save-dev no-mistakes`), selecting a platform-specific native
package. macOS ARM64 is supported; Intel Macs are not.

The relevant subcommand for a gate is `check`, whose `--json` report is typed
in the package's `check-report-types.d.ts`:

```
{react[], queues[], rules[], integration[], codebase[], advisories[], warnings[]}
```

The first five block. `advisories` and `warnings` do not.

## The finding that shaped the implementation

```console
$ npx no-mistakes@0.61.2 check --json      # project with no .no-mistakes.json
{"advisories":[],"codebase":[],"integration":[],"queues":[],"react":[],"rules":[],"warnings":[]}
$ echo $?
0
```

**On an unconfigured project, `check` reports nothing and exits 0.** It is a
no-op that always passes. A gate wired straight to it could never fail — worse
than no gate, because the mission record would then claim a delivery was
verified when nothing was checked.

So `scripts/lib/gate.sh` treats "tool present but project unconfigured" as
**unavailable** (rc 2), never as a pass. Configuration is detected the way the
tool itself reports it:

```console
$ npx no-mistakes@0.61.2 config resolve | jq .configPath
null                          # nothing configured
".no-mistakes.json"           # configured
```

`.no-mistakes.json` is the filename; `no-mistakes.json` and
`no-mistakes.config.json` are **not** picked up (all three were tried).

## Consequences for the harness

| Decision | Why |
|---|---|
| The gate runs **before** landing, in the worktree | Gating after the PR is open only tells the operator what they already merged. |
| Only the project's own `node_modules/.bin/no-mistakes` is run | It is a per-project devDependency, and a gate that downloads its own implementation at delivery time, over the network, is not a gate. |
| Unconfigured ⇒ degrade to `direct-PR` **and file a decision** | Silence would be indistinguishable from a pass. |
| Findings ⇒ nothing is pushed; branch and worktree kept | The crewmate's branch is still there to fix. |
| `advisories`/`warnings` never block | They are the tool's non-blocking channel; blocking on them trains the operator to override the gate. |

## Re-running this

`tests/gate.test.sh` drives a stub at the real path
(`node_modules/.bin/no-mistakes`) speaking the contract above, so the suite
needs no network and no install. If the tool's report shape changes, this page
and that stub are what must be re-checked together.
