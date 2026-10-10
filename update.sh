#!/bin/sh
# Aether OpenWrt Client updater — fetch the current installer safely.

set -u
umask 077

REPO_RAW="https://raw.githubusercontent.com/Rezayavarzade123/aether-openwrt-test-with-arena.ai/main"

# Optional ghproxy-style mirror prefix, from --mirror or AETHER_GH_MIRROR.
GH_MIRROR="${AETHER_GH_MIRROR:-}"

error() { printf '%s\n' "aether update: $*" >&2; }
warn() { printf '%s\n' "aether update: $*" >&2; }

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
		--mirror=*) GH_MIRROR="${arg#--mirror=}" ;;
		--mirror)
			shift
			[ -n "${1:-}" ] || {
				error "--mirror requires a URL prefix"
				exit 1
			}
			GH_MIRROR="$1"
			;;
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

# Normalize the mirror prefix for this script's own installer fetch.
case "$GH_MIRROR" in
	""|*/) ;;
	*) GH_MIRROR="$GH_MIRROR/" ;;
esac

tmpdir="$(mktemp -d /tmp/aether-update.XXXXXX)" || {
	error "could not create temporary directory"
	exit 1
}
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

installer="$tmpdir/install.sh"
wget -4 -T 30 -O "$installer" "$GH_MIRROR$REPO_RAW/install.sh" || {
	error "failed to download the current installer"
	warn "if GitHub is blocked on your network, retry with a mirror: aether-ctl update --mirror https://ghproxy.net/"
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
