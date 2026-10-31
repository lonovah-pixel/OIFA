#!/usr/bin/env bash
# Static checks and headless server tests for SITE-VEIL.
#   tools/check.sh            lint + tests
#   tools/check.sh lint       glualint only
#   tools/check.sh test       tests only
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
GLUALINT="${GLUALINT:-$ROOT/tools/bin/glualint}"
status=0

run_lint() {
    if [ ! -x "$GLUALINT" ]; then
        echo "glualint not found at $GLUALINT (run tools/install_glualint.sh)" >&2
        return 1
    fi
    echo "== glualint"
    "$GLUALINT" lint gamemodes/siteveil addons tests || return 1
    # glualint prints warnings but exits 0; treat any output as failure.
    if [ -n "$("$GLUALINT" lint gamemodes/siteveil addons tests 2>&1)" ]; then return 1; fi
    echo "glualint: clean"
}

run_tests() {
    echo "== headless server tests (LuaJIT via lupa, SQLite in memory)"
    python3 -I tests/harness/runner.py
}

case "${1:-all}" in
    lint) run_lint || status=1 ;;
    test) run_tests || status=1 ;;
    *) run_lint || status=1; run_tests || status=1 ;;
esac
exit $status
