#!/bin/sh
# Lightweight source contract checks; runnable with BusyBox ash.

set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

assert_contains() {
	file="$1"
	text="$2"
	grep -F -e "$text" "$ROOT/$file" >/dev/null ||
		{ echo "missing '$text' in $file" >&2; exit 1; }
}

assert_contains install.sh 'CLIENT_VERSION="v0.4.2"'
assert_contains install.sh 'DEFAULT_VERSION="v1.6.0"'
assert_contains install.sh '--version'
assert_contains install.sh '--non-interactive'
assert_contains install.sh 'v1.5.0 or newer is required'
assert_contains update.sh 'Aether OpenWrt Client updater'
assert_contains files/usr/bin/aether-ctl 'do_update()'
assert_contains files/usr/bin/aether-ctl 'do_change_version()'
assert_contains files/usr/bin/aether-ctl 'change-version'
assert_contains files/usr/bin/aether-ctl 'core_supports_v16()'
assert_contains files/etc/config/aether "option socks_listen '0.0.0.0:1819'"
assert_contains files/etc/config/aether "option startup_secs '30'"
assert_contains files/etc/init.d/aether 'core_version()'
assert_contains files/etc/init.d/aether 'core_supports_v16()'
assert_contains files/etc/init.d/aether 'Ignoring HTTP CONNECT proxy'
assert_contains files/etc/init.d/aether '--http-proxy'
assert_contains files/etc/init.d/aether '--startup-secs'
assert_contains files/etc/init.d/aether '--no-profile-retry'
assert_contains files/www/luci-static/resources/view/aether.js "AETHER_CLIENT_VERSION = 'v0.4.2'"
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV16'
assert_contains files/www/luci-static/resources/view/aether.js 'Client Version'
assert_contains files/www/luci-static/resources/view/aether.js 'Core Version'
assert_contains files/www/luci-static/resources/view/aether.js 'Aether v1.5 compatibility mode'
assert_contains files/usr/libexec/rpcd/luci-app-aether 'core_is_v15()'

echo "static checks passed"
