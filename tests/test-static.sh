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

assert_contains install.sh 'CLIENT_VERSION="v0.9.1"'
assert_contains install.sh 'DEFAULT_VERSION="v2.3.0"'
assert_contains install.sh '--version'
assert_contains install.sh '--non-interactive'
assert_contains install.sh 'v1.5.0 or newer is required'
assert_contains update.sh 'Aether OpenWrt Client updater'
assert_contains install.sh 'fetch_retry()'
assert_contains install.sh 'mirror_url()'
assert_contains install.sh 'valid_checksum_file()'
assert_contains install.sh 'sums_extract_line()'
assert_contains install.sh 'SHA256SUMS.txt'
assert_contains install.sh '--mirror'
assert_contains install.sh 'AETHER_GH_MIRROR'
assert_contains update.sh '--mirror'
assert_contains update.sh 'AETHER_GH_MIRROR'
assert_contains files/usr/bin/aether-ctl 'do_update()'
assert_contains files/usr/bin/aether-run 'umask 077'
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
assert_contains files/etc/config/aether "option command_mode 'generated'"
assert_contains files/etc/config/aether "option wiw_inner ''"
assert_contains files/etc/config/aether "option mim_outer ''"
assert_contains files/etc/config/aether "option quic_v2 '1'"
assert_contains files/etc/config/aether "option tor_mode 'off'"
assert_contains files/etc/config/aether "option tor_http ''"
assert_contains files/etc/config/aether "option tor_relays 'auto'"
assert_contains files/etc/config/aether "option psiphon_mode 'off'"
assert_contains files/etc/config/aether "option psiphon_bind '127.0.0.1:1821'"
assert_contains files/etc/config/aether "option psiphon_shape 'auto'"
assert_contains files/etc/config/aether "option exit_loc ''"
assert_contains files/etc/config/aether "option stats '0'"
assert_contains files/etc/config/aether "option gool_carrier 'masque'"
assert_contains files/etc/config/aether "option gool_peer ''"
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
assert_contains files/etc/init.d/aether 'core_supports_v20()'
assert_contains files/etc/init.d/aether 'core_supports_v21()'
assert_contains files/etc/init.d/aether 'core_supports_v23()'
assert_contains files/etc/init.d/aether '--mim'
assert_contains files/etc/init.d/aether '--no-quic-v2'
assert_contains files/etc/init.d/aether '--ech'
assert_contains files/etc/init.d/aether '--tor-reverse'
assert_contains files/etc/init.d/aether '--tor-http'
assert_contains files/etc/init.d/aether '--tor-relays'
assert_contains files/etc/init.d/aether '--psiphon'
assert_contains files/etc/init.d/aether '--psiphon-reverse'
assert_contains files/etc/init.d/aether '--psiphon-bind'
assert_contains files/etc/init.d/aether '--psiphon-region'
assert_contains files/etc/init.d/aether '--exit-loc'
assert_contains files/etc/init.d/aether '--stats'
assert_contains files/etc/init.d/aether '--gool-classic'
assert_contains files/etc/init.d/aether '--gool-peer'
assert_contains files/etc/init.d/aether 'fix_tor_state_owners'
assert_contains files/etc/init.d/aether 'identity_sibling()'
assert_contains files/etc/init.d/aether 'select_perf_profile()'
assert_contains files/etc/init.d/aether 'finish_service_instances'
assert_contains files/etc/init.d/aether '"$command_mode" = "manual"'
assert_contains files/etc/init.d/aether 'manual_args'
assert_contains files/etc/init.d/aether 'chmod 755 "$d"'
assert_contains files/etc/init.d/aether 'ls -lad "$d"'
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
assert_contains files/www/luci-static/resources/view/aether.js "AETHER_CLIENT_VERSION = 'v0.9.1'"
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV16'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV17'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV21'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV23'
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
assert_contains files/usr/bin/aether-ctl 'core_supports_v20()'
assert_contains files/usr/bin/aether-ctl 'core_supports_v21()'
assert_contains files/usr/bin/aether-ctl 'core_supports_v23()'
assert_contains files/usr/bin/aether-ctl 'mim_outer|mim_inner|mim_peers|quic_v2|tor_mode|tor_bind|tor_dir|tor_bridges'
assert_contains files/usr/bin/aether-ctl 'psiphon_mode|psiphon_bind|psiphon_http|psiphon_region|psiphon_shape|tor_http|tor_relays|exit_loc|stats'
assert_contains files/usr/bin/aether-ctl 'gool_carrier|gool_peer'
assert_contains files/usr/bin/aether-ctl 'requires Aether core v2.1.0 or newer'
assert_contains files/usr/bin/aether-ctl 'requires Aether core v2.3.0 or newer'
assert_contains files/usr/bin/aether-ctl 'check-psiphon'
assert_contains files/usr/bin/aether-ctl 'Psiphon not in custom_command'
assert_contains files/usr/bin/aether-ctl 'Psiphon reverse mode requires protocol masque'
assert_contains files/usr/bin/aether-ctl 'Invalid exit_loc'
assert_contains files/usr/bin/aether-ctl 'Invalid gool_carrier'
assert_contains files/usr/bin/aether-ctl 'manual_has_psiphon()'
assert_contains files/usr/bin/aether-ctl 'auto-perf'
assert_contains files/usr/bin/aether-ctl 'perf_profile'
assert_contains files/usr/bin/aether-ctl 'wiw_outer'
assert_contains files/usr/bin/aether-ctl 'check-tor'
assert_contains files/usr/bin/aether-ctl 'Tor: true IP:'
assert_contains files/usr/bin/aether-ctl 'Invalid tor_bind'
assert_contains files/usr/bin/aether-ctl 'Invalid tor_dir'
assert_contains files/usr/bin/aether-ctl 'test)     do_test'
assert_contains files/usr/bin/aether-ctl 'manual_opt()'
assert_contains files/usr/bin/aether-ctl 'manual_has_tor()'
assert_contains files/usr/bin/aether-ctl 'Tor not in custom_command'
assert_contains files/usr/bin/aether-ctl 'Tor requires Aether core v2.0.0 or newer'
assert_contains files/usr/bin/aether-ctl 'Invalid command_mode'
assert_contains files/www/luci-static/resources/view/aether.js 'Custom Command'
assert_contains files/www/luci-static/resources/view/aether.js 'custom_command'
assert_contains files/www/luci-static/resources/view/aether.js 'form.DummyValue'
assert_contains files/www/luci-static/resources/view/aether.js 'form.TextValue'
assert_contains files/usr/bin/aether-ctl 'Tor reverse mode requires protocol masque'
assert_contains files/usr/bin/aether-ctl 'Show the effective profile'
assert_contains files/usr/bin/aether-ctl '(stored '
assert_contains install.sh 'select_perf_profile()'
assert_contains install.sh 'PT_BINARY'
assert_contains install.sh '/usr/bin/pt/lyrebird'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV18'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV19'
assert_contains files/www/luci-static/resources/view/aether.js 'Performance Profile'
assert_contains files/www/luci-static/resources/view/aether.js 'gool Outer Hop'
assert_contains files/www/luci-static/resources/view/aether.js 'aetherCoreSupportsV20'
assert_contains files/www/luci-static/resources/view/aether.js 'torBind'
assert_contains files/www/luci-static/resources/view/aether.js 'Needs core v2.0'
assert_contains files/www/luci-static/resources/view/aether.js 'Enabled at '
assert_contains files/www/luci-static/resources/view/aether.js 'MASQUE-in-MASQUE'
assert_contains files/www/luci-static/resources/view/aether.js 'Use QUIC v2 Opener'
assert_contains files/www/luci-static/resources/view/aether.js 'Encrypted Client Hello (ECH)'
assert_contains files/www/luci-static/resources/view/aether.js 'Tor (Core v2)'
assert_contains files/www/luci-static/resources/view/aether.js 'Check Tor IP'
assert_contains files/www/luci-static/resources/view/aether.js 'test-result-tor'
assert_contains files/www/luci-static/resources/view/aether.js 'Psiphon (Core v2.1+)'
assert_contains files/www/luci-static/resources/view/aether.js 'Check Psiphon IP'
assert_contains files/www/luci-static/resources/view/aether.js 'test-result-psiphon'
assert_contains files/www/luci-static/resources/view/aether.js 'Exit Location Policy'
assert_contains files/www/luci-static/resources/view/aether.js 'Traffic Stats Logging'
assert_contains files/www/luci-static/resources/view/aether.js 'gool Carrier'
assert_contains files/www/luci-static/resources/view/aether.js 'MASQUE-carried (default)'
assert_contains files/www/luci-static/resources/view/aether.js 'Verified (measured edges, v2.1+)'
assert_contains files/www/luci-static/resources/view/aether.js 'Tor Relay Sources'
assert_contains files/www/luci-static/resources/view/aether.js 'psiphonMode'
echo "static checks passed"
