#!/bin/sh
# Mock harness: source the real init script, then override its helpers,
# and exercise start_service across the core-version matrix.

INIT_SRC="/home/user/aether-openwrt-test-with-arena.ai/files/etc/init.d/aether"
MOCK_UCI_FILE="${MOCK_UCI_FILE:-/tmp/mock-uci.txt}"
FAILURES=0

# --- minimal procd/logger mocks (before sourcing; harmless) ---
PROCD_CMD=""
procd_open_instance() { :; }
procd_close_instance() { :; }
procd_set_param() { :; }
procd_append_param() {
	[ "$1" = "command" ] && shift
	PROCD_CMD="$PROCD_CMD $*"
}
logger() { :; }

. "$INIT_SRC"

# --- overrides AFTER sourcing (the file redefines these) ---
MOCK_CORE_VERSION="2.3.0"
core_version() { echo "$MOCK_CORE_VERSION"; }
config_load() { :; }
config_get() {
	local __var="$1" __opt="$3" __def="$4" __val
	__val=$(sed -n "s/^${__opt}=//p" "$MOCK_UCI_FILE" 2>/dev/null | head -n1)
	[ -z "$__val" ] && __val="$__def"
	eval "$__var=\"\$__val\""
}
config_get_bool() {
	local __var="$1" __opt="$3" __def="$4" __val
	__val=$(sed -n "s/^${__opt}=//p" "$MOCK_UCI_FILE" 2>/dev/null | head -n1)
	[ -z "$__val" ] && __val="$__def"
	eval "$__var=\"\$__val\""
}
fix_tor_state_owners() { :; }
select_perf_profile() { echo "low"; }
finish_service_instances() { :; }

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; echo "  got: $(echo "$PROCD_CMD" | tr -s ' ')"; FAILURES=$((FAILURES + 1)); }

run_case() {
	local label="$1" expect="$2" rc=0
	PROCD_CMD=""
	start_service >/dev/null 2>&1 || rc=$?
	if [ "$rc" -eq 0 ] && echo " $PROCD_CMD " | grep -F -- "$expect" >/dev/null 2>&1; then
		pass "$label"
	else
		fail "$label (expected '$expect', rc=$rc)"
	fi
}

expect_rc_fail() {
	local label="$1" rc=0
	PROCD_CMD=""
	start_service >/dev/null 2>&1 || rc=$?
	if [ "$rc" -ne 0 ]; then pass "$label"; else fail "$label (expected failure)"; fi
}

expect_absent() {
	local label="$1" bad="$2"
	case " $PROCD_CMD " in
		*"$bad"*) fail "$label (must not contain $bad; got:$PROCD_CMD)" ;;
		*) pass "$label" ;;
	esac
}

# ---- default v2.3.0 masque ----
printf 'protocol=masque\n' >"$MOCK_UCI_FILE"
run_case "v2.3.0 default masque" "--config /etc/aether/aether.toml --perf low --masque"

# ---- gool modern carrier ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=gool
gool_carrier=masque
wiw_outer=162.159.192.1:2408
wiw_inner=188.114.96.1:2408
gool_peer=188.114.97.1:2408
EOF
run_case "v2.3.0 gool masque carrier adds --gool --gool-peer" "--gool --gool-peer 188.114.97.1:2408"
expect_absent "v2.3.0 gool masque carrier omits --gool-classic" "--gool-classic"
expect_absent "v2.3.0 gool masque carrier omits --wiw-outer" "--wiw-outer"

# ---- gool classic carrier ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=gool
gool_carrier=classic
wiw_outer=162.159.192.1:2408
wiw_inner=188.114.96.1:2408
EOF
PROCD_CMD=""
start_service >/dev/null 2>&1
case " $PROCD_CMD " in
	*" --wiw-outer 162.159.192.1:2408 --wiw-inner 188.114.96.1:2408 --gool --gool-classic"*) pass "v2.3.0 gool classic carrier full line" ;;
	*) fail "v2.3.0 gool classic carrier full line (got:$PROCD_CMD)" ;;
esac
expect_absent "v2.3.0 gool classic omits --gool-peer" "--gool-peer"

# ---- v2.0.0 gool keeps old behavior ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=gool
gool_carrier=masque
wiw_outer=162.159.192.1:2408
wiw_inner=188.114.96.1:2408
EOF
MOCK_CORE_VERSION="2.0.0"
run_case "v2.0.0 gool keeps wiw endpoints" "--wiw-outer 162.159.192.1:2408 --wiw-inner 188.114.96.1:2408 --gool"
expect_absent "v2.0.0 gool gets no --gool-classic" "--gool-classic"
expect_absent "v2.0.0 gool gets no --gool-peer" "--gool-peer"
MOCK_CORE_VERSION="2.3.0"

# ---- psiphon tunnel with region/shape ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
psiphon_mode=tunnel
psiphon_region=DE
psiphon_shape=cdn
EOF
run_case "v2.3.0 psiphon tunnel" "--psiphon --psiphon-bind 127.0.0.1:1821 --psiphon-region DE --psiphon-mode cdn"

# ---- psiphon reverse with wg -> error ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=wg
psiphon_mode=reverse
EOF
expect_rc_fail "psiphon reverse rejected on non-MASQUE"

# ---- psiphon reverse with masque ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
psiphon_mode=reverse
EOF
run_case "v2.3.0 psiphon reverse on masque" "--psiphon-reverse --psiphon-bind 127.0.0.1:1821"

# ---- psiphon-only works regardless of the WARP protocol ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=wg
psiphon_mode=only
EOF
run_case "v2.3.0 psiphon only on wg" "--psiphon-only"
expect_absent "psiphon only omits --psiphon-bind" "--psiphon-bind"

# ---- explicit disabled protocol runs Psiphon without any WARP transport ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=disabled
psiphon_mode=only
tor_mode=off
EOF
run_case "v2.3.0 disabled protocol runs Psiphon-only" "--psiphon-only"
expect_absent "disabled protocol omits --masque" "--masque"
expect_absent "disabled protocol omits --wg" "--wg"
expect_absent "disabled protocol omits --gool" "--gool"
expect_absent "disabled protocol omits --mim" "--mim"
expect_absent "disabled protocol omits Aether obfuscation" "--noize"

cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=disabled
psiphon_mode=off
EOF
expect_rc_fail "disabled protocol requires Psiphon-only mode"

cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=disabled
psiphon_mode=only
tor_mode=tunnel
EOF
expect_rc_fail "disabled protocol requires Tor off"

MOCK_CORE_VERSION="2.0.0"
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=disabled
psiphon_mode=only
EOF
expect_rc_fail "disabled protocol requires core v2.1+"
MOCK_CORE_VERSION="2.3.0"

# ---- exit_loc + stats ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
exit_loc=!IR,AZ,RU
stats=1
EOF
run_case "v2.3.0 exit_loc + stats" "--exit-loc !IR,AZ,RU --stats"

# ---- exit_loc/stats ignored on v2.0 ----
MOCK_CORE_VERSION="2.0.0"
PROCD_CMD=""
start_service >/dev/null 2>&1
expect_absent "v2.0.0 ignores exit_loc" "--exit-loc"
expect_absent "v2.0.0 ignores stats" " --stats"
MOCK_CORE_VERSION="2.3.0"

# ---- scan verified gating ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
scan_mode=verified
EOF
run_case "v2.3.0 scan verified" "--scan verified"
MOCK_CORE_VERSION="2.0.0"
PROCD_CMD=""
start_service >/dev/null 2>&1
case " $PROCD_CMD " in
	*" --scan verified"*) fail "v2.0.0 must not receive --scan verified" ;;
	*" --scan balanced"*) pass "v2.0.0 falls back to balanced for verified" ;;
	*) fail "v2.0.0 verified fallback missing (got:$PROCD_CMD)" ;;
esac
MOCK_CORE_VERSION="2.3.0"

# ---- tor v2.1 additions ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
tor_mode=tunnel
tor_http=127.0.0.1:1822
tor_relays=only
EOF
run_case "v2.3.0 tor tunnel + http + relays" "--tor --tor-bind 127.0.0.1:1820 --tor-http 127.0.0.1:1822 --tor-relays only"

# ---- tor relay count + auto omitted ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
tor_mode=tunnel
tor_relays=80
EOF
run_case "v2.3.0 tor relay count" "--tor-relays 80"
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
tor_mode=tunnel
tor_relays=auto
EOF
PROCD_CMD=""
start_service >/dev/null 2>&1
expect_absent "tor_relays auto passes no flag" "--tor-relays"

# ---- v2.0.0 tor gets no v2.1 tor flags ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=masque
tor_mode=tunnel
tor_http=127.0.0.1:1822
tor_relays=only
EOF
MOCK_CORE_VERSION="2.0.0"
PROCD_CMD=""
start_service >/dev/null 2>&1
expect_absent "v2.0.0 tor omits --tor-http" "--tor-http"
expect_absent "v2.0.0 tor omits --tor-relays" "--tor-relays"
MOCK_CORE_VERSION="2.3.0"

# ---- v1.9: no v2 flags at all ----
cat >"$MOCK_UCI_FILE" <<'EOF'
protocol=mim
psiphon_mode=tunnel
tor_mode=tunnel
exit_loc=DE,SE
stats=1
EOF
MOCK_CORE_VERSION="1.9.0"
PROCD_CMD=""
start_service >/dev/null 2>&1
expect_absent "v1.9 mim request gets no --mim" "--mim"
expect_absent "v1.9 gets no --psiphon" "--psiphon"
expect_absent "v1.9 gets no --tor" "--tor"
expect_absent "v1.9 gets no --exit-loc" "--exit-loc"
expect_absent "v1.9 gets no --stats" " --stats"
MOCK_CORE_VERSION="2.3.0"

echo "----"
if [ "$FAILURES" -eq 0 ]; then
	echo "all init mock scenarios passed"
else
	echo "$FAILURES scenario(s) FAILED"
	exit 1
fi
