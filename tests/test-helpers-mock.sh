#!/bin/sh
# Unit tests for the pure helper functions shipped in install.sh, aether-ctl
# and aether-watchdog.
#
# Each helper is EXTRACTED from the real source file (sed from "fn() {" to the
# closing "}") rather than copied, so these tests exercise the code that ships
# to routers. Extraction is verified: a helper that is renamed or reformatted
# fails the suite instead of silently testing nothing.
#
# Runs under BusyBox ash as well as dash/bash.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aether-helpers.XXXXXX")"
HELPERS="$TMP/helpers.sh"

FAILURES=0
PASS_COUNT=0

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { FAILURES=$((FAILURES + 1)); echo "FAIL: $1"; }

# Globals the extracted helpers read.
GH_MIRROR=""
AVAILABLE_TAGS=""
MOCK_SOCKS=""
get_config() { printf '%s' "$MOCK_SOCKS"; }

: >"$HELPERS"
add_fns() {
	src="$1"
	shift
	for fn in "$@"; do
		sed -n "/^${fn}() {/,/^}/p" "$ROOT/$src" >>"$HELPERS"
		grep -q "^${fn}() {" "$HELPERS" || {
			echo "cannot extract ${fn}() from $src" >&2
			exit 1
		}
	done
}

add_fns install.sh mirror_url valid_checksum_file sums_extract_line \
	valid_tag supported_core_version supports_psiphon_core contains_tag
add_fns files/usr/bin/aether-ctl redact_url core_version core_supports_v16 \
	core_supports_v17 core_supports_v18 core_supports_v19 \
	core_supports_v20 core_supports_v21 core_supports_v23
add_fns files/usr/bin/aether-watchdog local_socks_address

# shellcheck disable=SC1090
. "$HELPERS"

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
ok_true() { if "$@" >/dev/null 2>&1; then pass; else fail "$* should succeed"; fi; }
ok_false() { if "$@" >/dev/null 2>&1; then fail "$* should fail"; else pass; fi; }
ok_eq() {
	label="$1" want="$2" got="$3"
	if [ "$want" = "$got" ]; then pass; else
		fail "$label (want '$want', got '$got')"
	fi
}

GOOD="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHORT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
UPPER="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

# --- install.sh: mirror_url -------------------------------------------------
GH_MIRROR=""
ok_eq "mirror_url without a mirror" "https://github.com/x" "$(mirror_url "https://github.com/x")"
GH_MIRROR="https://ghproxy.net/"
ok_eq "mirror_url with a mirror" "https://ghproxy.net/https://github.com/x" \
	"$(mirror_url "https://github.com/x")"
GH_MIRROR=""

# --- install.sh: valid_checksum_file ----------------------------------------
printf '%s  aether-linux-x86_64-musl.tar.gz\n' "$GOOD" >"$TMP/ok.sha"
printf '%s  aether-linux-x86_64-musl.tar.gz\n' "$UPPER" >"$TMP/upper.sha"
printf '%s  aether-linux-x86_64-musl.tar.gz\n' "$SHORT" >"$TMP/short.sha"
printf '<html><body>404: Not Found</body></html>\n' >"$TMP/html.sha"
printf '%s\n' "$GOOD" >"$TMP/noname.sha"
: >"$TMP/empty.sha"

ok_true valid_checksum_file "$TMP/ok.sha"
ok_true valid_checksum_file "$TMP/upper.sha"
ok_false valid_checksum_file "$TMP/short.sha"
ok_false valid_checksum_file "$TMP/html.sha"
ok_false valid_checksum_file "$TMP/noname.sha"
ok_false valid_checksum_file "$TMP/missing-file.sha"
# Regression: an empty file used to pass, because the awk rule never ran and
# awk exits 0 when it reads no records at all.
ok_false valid_checksum_file "$TMP/empty.sha"

# --- install.sh: sums_extract_line ------------------------------------------
{
	printf '%s  aether-linux-armv7-musl.tar.gz\n' "$SHORT"
	printf '%s  aether-linux-x86_64-musl.tar.gz\n' "$GOOD"
	printf '%s  aether-linux-aarch64-musl.tar.gz\n' "$UPPER"
} >"$TMP/SHA256SUMS.txt"

ok_eq "sums_extract_line picks the right entry" \
	"$GOOD  aether-linux-x86_64-musl.tar.gz" \
	"$(sums_extract_line "$TMP/SHA256SUMS.txt" aether-linux-x86_64-musl.tar.gz)"
ok_true sums_extract_line "$TMP/SHA256SUMS.txt" aether-linux-x86_64-musl.tar.gz
ok_false sums_extract_line "$TMP/SHA256SUMS.txt" aether-linux-mips-musl.tar.gz
# The extracted line must itself be accepted as a valid checksum file.
sums_extract_line "$TMP/SHA256SUMS.txt" aether-linux-x86_64-musl.tar.gz >"$TMP/derived.sha"
ok_true valid_checksum_file "$TMP/derived.sha"

# sha256sum writes binary-mode entries as "digest  *name"; those must match too.
printf '%s *aether-linux-x86_64-musl.tar.gz\n' "$GOOD" >"$TMP/binary-mode.txt"
ok_eq "sums_extract_line accepts sha256sum binary-mode entries" \
	"$GOOD  aether-linux-x86_64-musl.tar.gz" \
	"$(sums_extract_line "$TMP/binary-mode.txt" aether-linux-x86_64-musl.tar.gz)"

# A name must not match as a substring of a longer entry.
ok_false sums_extract_line "$TMP/SHA256SUMS.txt" aether-linux-x86_64-musl.tar

# --- install.sh: valid_tag --------------------------------------------------
ok_true valid_tag v2.3.0
ok_true valid_tag v1.5.0
ok_true valid_tag v10.20.30
ok_false valid_tag 2.3.0
ok_false valid_tag v2.3
ok_false valid_tag v2.3.0-rc1
ok_false valid_tag nightly
ok_false valid_tag ""
ok_false valid_tag "v2.3.0 v1.9.0"

# --- install.sh: supported_core_version -------------------------------------
ok_true supported_core_version v1.5.0
ok_true supported_core_version v1.5.1
ok_true supported_core_version v1.9.0
ok_true supported_core_version v2.0.0
ok_true supported_core_version v2.3.0
ok_true supported_core_version v10.0.0
ok_false supported_core_version v1.4.9
ok_false supported_core_version v1.0.0
ok_false supported_core_version v0.9.1
ok_false supported_core_version nightly
ok_false supported_core_version ""

# The release helper is mandatory for Psiphon-capable cores from v2.1 onward.
ok_true supports_psiphon_core v2.1.0
ok_true supports_psiphon_core v2.3.0
ok_true supports_psiphon_core v3.0.0
ok_false supports_psiphon_core v2.0.9
ok_false supports_psiphon_core v1.9.0
ok_false supports_psiphon_core garbage
ok_false supports_psiphon_core ""

# --- install.sh: contains_tag -----------------------------------------------
AVAILABLE_TAGS="$(printf 'v2.3.0\nv2.1.0\nv1.5.0')"
ok_true contains_tag v2.3.0
ok_true contains_tag v1.5.0
ok_false contains_tag v2.2.0
# Exact-line matching only: a prefix of a real tag must not match.
ok_false contains_tag v2.3
ok_false contains_tag ""
AVAILABLE_TAGS=""

# --- aether-ctl: redact_url -------------------------------------------------
ok_eq "redact_url masks credentials" "socks5://***@host:1080" \
	"$(redact_url "socks5://user:pass@host:1080")"
ok_eq "redact_url keeps a clean URL" "https://host/path" \
	"$(redact_url "https://host/path")"
ok_eq "redact_url handles a bare user@host" "***@host" "$(redact_url "user@host")"
ok_eq "redact_url on empty input" "" "$(redact_url "")"
case "$(redact_url "socks5://user:supersecret@host:1080")" in
	*supersecret*) fail "redact_url leaks the password" ;;
	*) pass ;;
esac

# --- aether-ctl: core_supports_vNN version matrix ---------------------------
matrix() {
	fn="$1" last_unsupported="$2" first_supported="$3"
	ok_false "$fn" "$last_unsupported"
	ok_true "$fn" "$first_supported"
	ok_true "$fn" "3.0.0"
	ok_false "$fn" ""
	ok_false "$fn" "garbage"
}
matrix core_supports_v16 1.5.9 1.6.0
matrix core_supports_v17 1.6.9 1.7.0
matrix core_supports_v18 1.7.9 1.8.0
matrix core_supports_v19 1.8.9 1.9.0
matrix core_supports_v20 1.9.9 2.0.0
matrix core_supports_v21 2.0.9 2.1.0
matrix core_supports_v23 2.2.9 2.3.0

# Monotonicity: a core new enough for v2.3 must satisfy every older gate.
for v in 2.3.0 2.4.1 3.0.0; do
	for fn in core_supports_v16 core_supports_v17 core_supports_v18 \
		core_supports_v19 core_supports_v20 core_supports_v21 core_supports_v23; do
		ok_true "$fn" "$v"
	done
done
# A v1.5 core must satisfy no v2 gate.
for fn in core_supports_v20 core_supports_v21 core_supports_v23; do
	ok_false "$fn" "1.5.0"
done

# --- aether-ctl: core_version normalization ---------------------------------
# core_version() turns whatever `aether --version` prints into the bare x.y.z
# form every core_supports_vNN gate consumes.
PROG=""
make_fake_core() {
	printf '#!/bin/sh\necho "%s"\n' "$1" >"$TMP/fake-aether"
	chmod 755 "$TMP/fake-aether"
	PROG="$TMP/fake-aether"
}

make_fake_core "aether 2.3.0"
ok_eq "core_version reads 'aether 2.3.0'" "2.3.0" "$(core_version)"
make_fake_core "aether version v2.3.0 (linux musl)"
ok_eq "core_version strips the v prefix" "2.3.0" "$(core_version)"
make_fake_core "v1.5.9"
ok_eq "core_version reads a bare 'v1.5.9'" "1.5.9" "$(core_version)"
make_fake_core "2.0.0"
ok_eq "core_version reads a bare '2.0.0'" "2.0.0" "$(core_version)"
make_fake_core "2.0.0-rc1"
ok_eq "core_version keeps a suffix on the first x.y.z field" "2.0.0-rc1" "$(core_version)"
make_fake_core "no version here"
ok_eq "core_version yields nothing for unparseable output" "" "$(core_version)"
make_fake_core ""
ok_eq "core_version yields nothing for empty output" "" "$(core_version)"

# A normalized version must feed the gates correctly end to end.
make_fake_core "aether version v2.3.0 (linux musl)"
_v="$(core_version)"
ok_true core_supports_v23 "$_v"
ok_true core_supports_v16 "$_v"
make_fake_core "aether version v1.5.9 (linux musl)"
_v="$(core_version)"
ok_false core_supports_v16 "$_v"
ok_false core_supports_v23 "$_v"

# --- aether-watchdog: local_socks_address -----------------------------------
MOCK_SOCKS="0.0.0.0:1819"
ok_eq "wildcard listen probes loopback" "127.0.0.1:1819" "$(local_socks_address)"
MOCK_SOCKS=""
ok_eq "empty listen falls back to the default" "127.0.0.1:1819" "$(local_socks_address)"
MOCK_SOCKS="192.168.1.1:1819"
ok_eq "explicit LAN listen is preserved" "192.168.1.1:1819" "$(local_socks_address)"
MOCK_SOCKS=":::1819"
ok_eq "IPv6 wildcard probes ::1" "[::1]:1819" "$(local_socks_address)"
MOCK_SOCKS="[::]:1819"
ok_eq "bracketed IPv6 wildcard probes ::1" "[::1]:1819" "$(local_socks_address)"
MOCK_SOCKS="127.0.0.1:9050"
ok_eq "custom loopback port is preserved" "127.0.0.1:9050" "$(local_socks_address)"

echo "----"
echo "assertions passed: $PASS_COUNT   failures: $FAILURES"
if [ "$FAILURES" -eq 0 ]; then
	echo "all helper unit tests passed"
else
	echo "$FAILURES helper assertion(s) FAILED"
	exit 1
fi
