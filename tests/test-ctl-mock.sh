#!/bin/sh
# Mock harness for aether-ctl do_set validation paths.

CTL_SRC="/home/user/aether-openwrt-test-with-arena.ai/files/usr/bin/aether-ctl"
MOCK_UCI_FILE="${MOCK_UCI_FILE:-/tmp/mock-ctl-uci.txt}"
MOCK_BIN="${MOCK_BIN:-/tmp/mock-ctl-bin}"
FAILURES=0
: >"$MOCK_UCI_FILE"
mkdir -p "$MOCK_BIN"
printf '#!/bin/sh\nexit 0\n' >"$MOCK_BIN/uci"
chmod +x "$MOCK_BIN/uci"

set -- help   # run the help branch only; functions stay defined
. "$CTL_SRC" >/dev/null

# --- overrides after sourcing ---
MOCK_CORE_VERSION="2.3.0"
core_version() { echo "$MOCK_CORE_VERSION"; }
is_running() { return 1; }
UCI="$MOCK_BIN/uci"
uci_get() { sed -n "s/^$1=//p" "$MOCK_UCI_FILE" 2>/dev/null | head -n1; }
uci_set() { sed -i "\#^$1=#d" "$MOCK_UCI_FILE"; printf '%s=%s\n' "$1" "$2" >>"$MOCK_UCI_FILE"; }

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILURES=$((FAILURES + 1)); }

run_set() {
	out=$(do_set "$1" "$2" 2>&1)
	rc=$?
}

expect_ok() {
	local label="$1" key="$2" value="$3"
	run_set "$key" "$value"
	if [ "$rc" -eq 0 ]; then pass "$label"; else fail "$label (rc=$rc: $out)"; fi
}

expect_reject() {
	local label="$1" key="$2" value="$3" needle="$4"
	run_set "$key" "$value"
	if [ "$rc" -ne 0 ] && echo "$out" | grep -Fq -- "$needle"; then
		pass "$label"
	else
		fail "$label (rc=$rc, out: $out)"
	fi
}

# ---- v2.3.0 core accepts all new keys ----
expect_ok "accept psiphon_mode tunnel" psiphon_mode tunnel
expect_ok "accept psiphon_mode reverse on masque" psiphon_mode reverse
expect_ok "accept psiphon_bind" psiphon_bind 127.0.0.1:1821
expect_ok "accept psiphon_http" psiphon_http 127.0.0.1:1823
expect_ok "accept psiphon_region" psiphon_region DE
expect_ok "accept psiphon_region clear" psiphon_region auto
expect_ok "accept psiphon_shape cdn" psiphon_shape cdn
expect_ok "accept tor_http" tor_http 127.0.0.1:1822
expect_ok "accept tor_relays only" tor_relays only
expect_ok "accept tor_relays count" tor_relays 80
expect_ok "accept tor_relays auto" tor_relays auto
expect_ok "accept exit_loc block list" exit_loc '!IR,AZ,RU'
expect_ok "accept exit_loc allow list" exit_loc DE,SE
expect_ok "accept stats on" stats on
expect_ok "accept gool_carrier classic" gool_carrier classic
expect_ok "accept gool_peer" gool_peer 188.114.97.1:2408
expect_ok "accept scan_mode verified" scan_mode verified

# ---- disabled transport is a guarded Psiphon-only choice ----
uci_set psiphon_mode only
uci_set tor_mode off
expect_ok "accept disabled protocol with Psiphon only" protocol disabled
expect_reject "disabled protocol cannot turn Psiphon off" psiphon_mode off "requires psiphon_mode=only"
expect_reject "disabled protocol cannot enable Tor" tor_mode tunnel "requires tor_mode=off"
expect_ok "restore protocol masque" protocol masque
expect_ok "restore Psiphon tunnel mode" psiphon_mode tunnel

# ---- validation rejections ----
expect_reject "reject bad psiphon_mode" psiphon_mode maybe "Invalid psiphon_mode"
expect_reject "reject bad psiphon_bind" psiphon_bind 127.0.0.1 "Invalid psiphon_bind"
expect_reject "reject bad psiphon_region" psiphon_region DEU "Invalid psiphon_region"
expect_reject "reject bad psiphon_shape" psiphon_shape meek "Invalid psiphon_shape"
expect_reject "reject bad tor_http" tor_http localhost "Invalid tor_http"
expect_reject "reject bad tor_relays" tor_relays many "Invalid tor_relays"
expect_reject "reject bad exit_loc" exit_loc '!IR AZ' "Invalid exit_loc"
expect_reject "reject stats garbage" stats maybe "Invalid value"
expect_reject "reject bad gool_carrier" gool_carrier tcp "Invalid gool_carrier"
expect_reject "reject bad gool_peer" gool_peer 188.114.97.1 "Invalid gool_peer"

# ---- psiphon reverse cross-check ----
sed -i '/^protocol=/d' "$MOCK_UCI_FILE"; printf 'protocol=wg\n' >>"$MOCK_UCI_FILE"
expect_reject "reject psiphon reverse on wg protocol" psiphon_mode reverse "requires protocol masque"
sed -i '/^protocol=/d' "$MOCK_UCI_FILE"; printf 'protocol=masque\n' >>"$MOCK_UCI_FILE"

# ---- version gates ----
MOCK_CORE_VERSION="2.0.0"
expect_reject "psiphon_mode gated to v2.1" psiphon_mode tunnel "requires Aether core v2.1.0"
uci_set psiphon_mode only
uci_set tor_mode off
expect_reject "disabled protocol gated to v2.1" protocol disabled "requires Aether core v2.1.0"
expect_reject "exit_loc gated to v2.1" exit_loc DE,SE "requires Aether core v2.1.0"
expect_reject "stats gated to v2.1" stats 1 "requires Aether core v2.1.0"
expect_reject "tor_relays gated to v2.1" tor_relays only "requires Aether core v2.1.0"
expect_reject "tor_http gated to v2.1" tor_http 127.0.0.1:1822 "requires Aether core v2.1.0"
expect_reject "scan verified gated to v2.1" scan_mode verified "requires Aether core v2.1.0"
MOCK_CORE_VERSION="2.1.0"
expect_reject "gool_carrier gated to v2.3" gool_carrier classic "requires Aether core v2.3.0"
expect_reject "gool_peer gated to v2.3" gool_peer 188.114.97.1:2408 "requires Aether core v2.3.0"

# v2.1 core accepts v2.1 features
expect_ok "v2.1 core accepts psiphon_mode" psiphon_mode tunnel
MOCK_CORE_VERSION="2.3.0"

echo "----"
if [ "$FAILURES" -eq 0 ]; then
	echo "all ctl mock scenarios passed"
else
	echo "$FAILURES ctl scenario(s) FAILED"
	exit 1
fi
