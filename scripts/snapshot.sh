#!/usr/bin/env bash
# snapshot.sh - thin wrapper over scripts/snapshot.py.
#
# The implementation moved to Python: the bash version orchestrated fourteen jq
# call sites and a hand-rolled field protocol, and that protocol is where two of
# this repo's bugs lived. This wrapper exists so callers, tests and permission
# entries that name snapshot.sh keep working.
set -uo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/snapshot.py" "$@"
