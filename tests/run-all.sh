#!/bin/sh
# Run every test suite in this repository.
#
#   tests/run-all.sh                run all suites with /bin/sh
#   tests/run-all.sh --portability  additionally re-run each suite under every
#                                   other shell found on the system (dash,
#                                   bash, BusyBox ash). OpenWrt executes these
#                                   scripts with BusyBox ash, so this is the
#                                   mode that proves router compatibility.
#
# Exits non-zero if any suite fails under any shell.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/aether-tests.XXXXXX")"

PORTABILITY=0
for arg in "$@"; do
	case "$arg" in
		--portability) PORTABILITY=1 ;;
		-h | --help)
			echo "Usage: $0 [--portability]"
			exit 0
			;;
		*)
			echo "Unknown option: $arg" >&2
			exit 1
			;;
	esac
done

cleanup() { rm -rf "$LOGDIR"; }
trap cleanup EXIT INT TERM

# Order matters: the cheap source checks run first so a broken tree fails fast.
SUITES="test-static.sh test-helpers-mock.sh test-luci-js.sh test-ctl-mock.sh test-init-mock.sh test-install-mock.sh"

FAILED=0
RAN=0

run_all_for_shell() {
	shell_spec="$1"
	echo "=============================================================="
	echo " shell: $shell_spec"
	echo "=============================================================="
	for suite in $SUITES; do
		logf="$LOGDIR/$suite.log"
		# Intentional word splitting: shell_spec may be "busybox ash".
		# shellcheck disable=SC2086
		if (set -- $shell_spec; "$@" "$ROOT/tests/$suite") >"$logf" 2>&1; then
			summary="$(grep -E 'passed' "$logf" | tail -n 1)"
			printf 'PASS  %-24s %s\n' "$suite" "$summary"
		else
			printf 'FAIL  %-24s (under %s)\n' "$suite" "$shell_spec"
			sed 's/^/        /' "$logf" | tail -n 40
			FAILED=$((FAILED + 1))
		fi
		RAN=$((RAN + 1))
	done
	echo ""
}

run_all_for_shell "sh"

if [ "$PORTABILITY" -eq 1 ]; then
	command -v dash >/dev/null 2>&1 && run_all_for_shell "dash"
	command -v bash >/dev/null 2>&1 && run_all_for_shell "bash"
	command -v busybox >/dev/null 2>&1 && run_all_for_shell "busybox ash"
fi

echo "=============================================================="
if [ "$FAILED" -eq 0 ]; then
	echo "all $RAN suite run(s) passed"
else
	echo "$FAILED of $RAN suite run(s) FAILED"
	exit 1
fi
