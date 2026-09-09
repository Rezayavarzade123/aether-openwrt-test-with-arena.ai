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

assert_contains install.sh 'CLIENT_VERSION="v0.6.0"'
assert_contains install.sh 'DEFAULT_VERSION="v1.9.0"'
assert_contains install.sh '--version'
assert_contains install.sh '--non-interactive'
assert_contains install.sh 'v1.5.0 or newer is required'
assert_contains update.sh 'Aether OpenWrt Client updater'
assert_contains files/usr/bin/aether-ctl 'do_update()'
assert_contains files/usr/bin/aether-ctl 'do_change_version()'
assert_contains files/usr/bin/aether-ctl 'change-version'
assert_contains files/usr/bin/aether-ctl 'core_supports_v16()'
assert_contains files/usr/bin/aether-ctl 'core_supports_v17()'
assert_contains files/usr/bin/aether-ctl 'redact_url()'
assert_contains files/usr/bin/aether-ctl 'do_check_ip()'
assert_contains files/usr/bin/aether-ctl 'do_passwall_status()'
assert_contains files/usr/bin/aether-ctl 'do_passwall_localhost()'
assert_contains files/usr/bin/aether-ctl 'do_passwall_add_node()'
assert_contains files/usr/bin/aether-ctl 'passwall localhost on|off'
assert_contains files/www/luci-static/resources/view/aether.js 'Passwall2 Integration'
assert_contains files/etc/config/aether "option perf_profile 'low'"
assert_contains files/etc/config/aether "option wiw_outer ''"
assert_contains files/etc/config/aether "option wiw_inner ''"
assert_contains files/www/luci-static/resources/view/aether.js 'Disable Localhost Proxy'
assert_contains files/www/luci-static/resources/view/aether.js 'Create Aether Node'
assert_contains files/usr/bin/aether-ctl 'check-ip'
assert_contains files/etc/config/aether "option socks_listen '0.0.0.0:1819'"
assert_contains files/etc/config/aether "option startup_secs '30'"
assert_contains files/etc/config/aether "option upstream_proxy ''"
assert_contains files/etc/init.d/aether 'core_version()'
assert_contains files/etc/init.d/aether 'core_supports_v16()'
assert_contains files/etc/init.d/aether 'core_supports_v18()'
assert_contains files/etc/init.d/aether 'core_supports_v19()'
assert_contains files/etc/init.d/aether 'select_perf_profile()'
assert_contains files/etc/init.d/aether '--perf'
assert_contains files/etc/init.d/aether '--wiw-outer'
assert_contains files/etc/init.d/aether '--wiw-inner'
assert_contains files/etc/init.d/aether 'core_supports_v17()'
assert_contains files/etc/init.d/aether 'Ignoring HTTP CONNECT proxy'
assert_contains files/etc/init.d/aether 'Ignoring upstream proxy'
assert_contains files/etc/init.d/aether '--http-proxy'
assert_contains files/etc/init.d/aether '--startup-secs'
assert_contains files/etc/init.d/aether '--no-profile-retry'
assert_contains files/etc/init.d/aether '--upstream'
assert_contains files/www/luci-static/resources/view/aether.js "AETHER_CLIENT_VERSION = 'v0.6.0'"
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV16'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV17'
assert_contains files/www/luci-static/resources/view/aether.js "'upstream_proxy'"
assert_contains files/www/luci-static/resources/view/aether.js 'Client Version'
assert_contains files/www/luci-static/resources/view/aether.js 'Core Version'
assert_contains files/www/luci-static/resources/view/aether.js 'doCheckIp'
assert_contains files/www/luci-static/resources/view/aether.js 'Check Public IP'
assert_contains files/www/luci-static/resources/view/aether.js 'test-result-ip'
assert_contains files/www/luci-static/resources/view/aether.js 'Aether v1.5 compatibility mode'
assert_contains files/usr/libexec/rpcd/luci-app-aether 'core_is_v15()'
assert_contains files/usr/libexec/rpcd/luci-app-aether 'core_is_below_v17()'

assert_contains files/usr/bin/aether-ctl 'core_supports_v18()'
assert_contains files/usr/bin/aether-ctl 'core_supports_v19()'
assert_contains files/usr/bin/aether-ctl 'perf_profile'
assert_contains files/usr/bin/aether-ctl 'wiw_outer'
assert_contains files/usr/bin/aether-ctl 'auto-perf'
assert_contains install.sh 'select_perf_profile()'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV18'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV19'
assert_contains files/www/luci-static/resources/view/aether.js 'Performance Profile'
assert_contains files/www/luci-static/resources/view/aether.js 'gool Outer Hop'
echo "static checks passed"
