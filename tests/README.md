# tests

Dependency-free behaviour tests for the harness's own shell: `bash`, `jq`, and
coreutils, nothing else. No bats, no shunit2 — the suite may not require more
than the harness does.

```sh
./tests/run.sh                        # every tests/*.test.sh
./tests/run.sh --filter session-lock  # matching files only
./tests/run.sh --list                 # discovery, no execution
./tests/run.sh tests/one.test.sh      # named files
```

Each file runs in its own process, so a crash or stray `exit` in one cannot
affect another. `run.sh` exits 0 only when every file passed.

## Writing one

Source `lib/fixtures.sh`, use `it` to name each behaviour, assert, and call
`finish` last. Every temp home is removed on exit, including on failure.

| Helper | Purpose |
|---|---|
| `mktmphome` | throwaway `CLAUDE_PROJECT_DIR` with the four state roots |
| `mkmission <home> <id> [json]` | mission fixture; prints its directory |
| `run_hook <name> <stdin-json> [env...]` | sets `HOOK_OUT`, `HOOK_ERR`, `HOOK_RC` |
| `run_script <rel-path> <args...>` | same capture shape for `scripts/` |
| `assert_eq` `assert_rc` `assert_contains` `assert_not_contains` | |
| `assert_file_exists` `assert_file_missing` | |

## Coverage

Every file under `.claude/hooks/` has a test file, plus `scripts/lib/status-read.sh`,
`scripts/lib/session-lock.sh`, and `scripts/status.sh`. Tests named
"(§N regression)" pin a specific defect found during Phase 0 — do not delete one
without understanding which bug it re-admits.
