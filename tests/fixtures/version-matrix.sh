#!/bin/sh
# Prints the shell-side core-version gate results as
#   "<gate> <version> <0|1>"
# lines, so tests/test-luci-js.js can assert that the LuCI view's capability
# gates agree with the ones aether-ctl enforces. A disagreement means the web
# UI offers an option the CLI will reject (or hides one it would accept).
#
# The helpers are extracted from the real aether-ctl source, not copied.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CTL="$ROOT/files/usr/bin/aether-ctl"

GATES="core_supports_v16 core_supports_v17 core_supports_v18 core_supports_v19
core_supports_v20 core_supports_v21 core_supports_v23"

# Versions the core can actually report, plus inputs that must gate shut.
# Bare "x.y.z" form only: core_version() normalizes `aether --version` output
# before the gates ever see it (covered by tests/test-helpers-mock.sh), while
# the LuCI view parses the raw string itself.
VERSIONS="0.9.1 1.4.9 1.5.0 1.5.9 1.6.0 1.6.9 1.7.0 1.7.9 1.8.0 1.8.9
1.9.0 1.9.9 2.0.0 2.0.9 2.1.0 2.1.9 2.2.0 2.2.9 2.3.0 2.4.0 3.0.0 10.0.0
garbage nightly"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/aether-matrix.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

FNS="$TMP/fns.sh"
: >"$FNS"
for fn in $GATES; do
	sed -n "/^${fn}() {/,/^}/p" "$CTL" >>"$FNS"
	grep -q "^${fn}() {" "$FNS" || {
		echo "cannot extract ${fn}() from aether-ctl" >&2
		exit 1
	}
done

# shellcheck disable=SC1090
. "$FNS"

for fn in $GATES; do
	gate="${fn#core_supports_}"
	for v in $VERSIONS; do
		if "$fn" "$v" >/dev/null 2>&1; then
			r=1
		else
			r=0
		fi
		printf '%s %s %s\n' "$gate" "$v" "$r"
	done
done
