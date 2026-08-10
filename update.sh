#!/bin/sh
# Aether OpenWrt Client updater — fetch the current installer safely.

set -u
umask 077

REPO_RAW="https://raw.githubusercontent.com/moein8668-git/aether-openwrt-client/main"

error() { printf '%s\n' "aether update: $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
	error "run as root on the OpenWrt device"
	exit 1
fi

[ -x /sbin/uci ] || [ -x /usr/sbin/uci ] || {
	error "this does not look like OpenWrt"
	exit 1
}

update_args="$*"
while [ "$#" -gt 0 ]; do
	arg="$1"
	case "$arg" in
		--start|--force-config|--no-curl|--non-interactive|--version=*) ;;
		--version)
			shift
			[ -n "${1:-}" ] || {
				error "--version requires a release tag"
				exit 1
			}
			;;
		*)
			error "unsupported installer option: $arg"
			exit 1
			;;
	esac
	shift
done

tmpdir="$(mktemp -d /tmp/aether-update.XXXXXX)" || {
	error "could not create temporary directory"
	exit 1
}
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

installer="$tmpdir/install.sh"
wget -4 -T 30 -O "$installer" "$REPO_RAW/install.sh" || {
	error "failed to download the current installer"
	exit 1
}

[ -s "$installer" ] && grep -q 'Aether OpenWrt Client' "$installer" || {
	error "downloaded installer is empty or invalid"
	exit 1
}

chmod 700 "$installer" || exit 1
# Arguments were validated above; intentional splitting preserves the approved
# installer option list after validation consumed this shell function's $@.
# shellcheck disable=SC2086
"$installer" $update_args
exit $?
