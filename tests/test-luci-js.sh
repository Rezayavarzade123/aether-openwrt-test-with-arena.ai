#!/bin/sh
# Wrapper so tests/run-all.sh can treat the LuCI view tests like every other
# suite. Skips cleanly when Node.js is not installed.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

if ! command -v node >/dev/null 2>&1; then
	echo "SKIP: node is unavailable; the LuCI view was not exercised."
	echo "luci-js checks skipped"
	exit 0
fi

exec node "$ROOT/tests/test-luci-js.js"
