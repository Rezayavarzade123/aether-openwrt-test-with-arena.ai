#!/bin/sh
# End-to-end harness for install.sh.
#
# Runs the REAL installer inside a synthetic OpenWrt rootfs — a BusyBox chroot
# in an unprivileged user namespace — with tests/fixtures/wget-shim.sh standing
# in for the network and tests/fixtures/mock-uci + mock-rc-common standing in
# for uci and /etc/rc.common. Nothing outside the temporary rootfs is touched,
# and no real network access is possible (the rootfs has no wget binary other
# than the shim).
#
# Skips cleanly when BusyBox or user namespaces are unavailable.

set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
WORK="${TMPDIR:-/tmp}/aether-install-test.$$"
BASE="$WORK/base"

FAILURES=0
CASES=0
PASS_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAILURES=$((FAILURES + 1)); echo "FAIL: $1"; }

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
BUSYBOX="$(command -v busybox 2>/dev/null || true)"
UNSHARE="$(command -v unshare 2>/dev/null || true)"

chroot_works() {
	[ -n "$BUSYBOX" ] && [ -n "$UNSHARE" ] || return 1
	probe="$WORK/.probe"
	mkdir -p "$probe/bin" 2>/dev/null || return 1
	cp "$BUSYBOX" "$probe/bin/busybox" 2>/dev/null || return 1
	ln -sf busybox "$probe/bin/sh" 2>/dev/null || return 1
	"$UNSHARE" -rm "$BUSYBOX" chroot "$probe" /bin/sh -c 'echo ok' 2>/dev/null |
		grep -q ok
}

mkdir -p "$WORK"
if ! chroot_works; then
	echo "SKIP: BusyBox chroot in a user namespace is unavailable;"
	echo "      install.sh end-to-end scenarios were not exercised."
	exit 0
fi

# ---------------------------------------------------------------------------
# Synthetic release payload
# ---------------------------------------------------------------------------
ARCHIVE="aether-linux-x86_64-musl.tar.gz"

make_release() {
	stage="$WORK/release-stage"
	rm -rf "$stage"
	mkdir -p "$stage/pt"
	cat >"$stage/aether" <<'EOS'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
	echo "aether 2.3.0 (mock core)"
	exit 0
fi
if [ "${1:-}" = "--print-auth-env" ]; then
	printf 'TEAM=%s|ID=%s|SECRET=%s|TOKEN=%s|GATEWAY=%s\n' "${AETHER_TEAM:-}" "${AETHER_ACCESS_CLIENT_ID:-}" "${AETHER_ACCESS_CLIENT_SECRET:-}" "${AETHER_ACCESS_TOKEN:-}" "${AETHER_GATEWAY:-}"
	exit 0
fi
case " $* " in
	*" --psiphon-only "*)
		if [ ! -x /usr/bin/pt/psiphon-tunnel-core ]; then
			echo 'Error: Other("psiphon needs the psiphon-tunnel-core console client, and it was not in /usr/bin/pt or on PATH")' >&2
			exit 1
		fi
		echo "mock Psiphon helper loaded"
		;;
esac
echo "mock aether core: $*"
EOS
	chmod 755 "$stage/aether"
	printf '#!/bin/sh\necho mock lyrebird\n' >"$stage/pt/lyrebird"
	chmod 755 "$stage/pt/lyrebird"
	if [ "${1:-}" != "without-psiphon" ]; then
		printf '#!/bin/sh\necho mock psiphon-tunnel-core\n' >"$stage/pt/psiphon-tunnel-core"
		chmod 755 "$stage/pt/psiphon-tunnel-core"
	fi
	tar czf "$BASE/tmp/fakerelease/$ARCHIVE" -C "$stage" aether pt
	sum="$(sha256sum "$BASE/tmp/fakerelease/$ARCHIVE" | awk '{print $1}')"
	printf '%s  %s\n' "$sum" "$ARCHIVE" >"$BASE/tmp/fakerelease/$ARCHIVE.sha256"
	{
		printf '%s  %s\n' "$sum" "$ARCHIVE"
		printf '%s  aether-linux-aarch64-musl.tar.gz\n' "$sum"
		printf '%s  aether-linux-armv7-musl.tar.gz\n' "$sum"
	} >"$BASE/tmp/fakerelease/SHA256SUMS.txt"
	echo "$sum" >"$WORK/good-sum"
}

# GitHub's /releases payload, in the real field order. Deliberately includes
# nested objects (author) and multi-element arrays (assets) because install.sh
# splits release objects on "},{" — assets after draft/prerelease is what keeps
# that heuristic correct, so the fixture must reproduce it.
rel() {
	tag="$1" draft="$2" pre="$3" nassets="$4" id="$5"
	assets="" i=0
	while [ "$i" -lt "$nassets" ]; do
		[ -n "$assets" ] && assets="$assets,"
		assets="$assets{\"url\":\"https://api.github.com/asset/$id/$i\",\"id\":$((1000 + i)),\"node_id\":\"A$i\",\"name\":\"asset-$i\",\"label\":null,\"state\":\"uploaded\",\"size\":$((i + 1))}"
		i=$((i + 1))
	done
	printf '{"url":"https://api.github.com/repos/CluvexStudio/Aether/releases/%s","assets_url":"https://api.github.com/uploads","upload_url":"https://uploads.github.com/x","html_url":"https://github.com/x","id":%s,"author":{"login":"dev","id":7,"node_id":"MDQ6","avatar_url":"https://avatars.githubusercontent.com/u/7","gravatar_id":"","url":"https://api.github.com/users/dev","html_url":"https://github.com/dev","type":"User","site_admin":false},"node_id":"RE_%s","tag_name":"%s","target_commitish":"main","name":"Aether %s","draft":%s,"prerelease":%s,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-02T00:00:00Z","published_at":"2026-01-02T00:00:00Z","assets":[%s],"tarball_url":"https://api.github.com/t","zipball_url":"https://api.github.com/z","body":"Release notes for %s."}' \
		"$id" "$id" "$id" "$tag" "$tag" "$draft" "$pre" "$assets" "$tag"
}

make_releases_json() {
	{
		printf '['
		rel v2.4.0 false true 2 40; printf ','   # prerelease -> filtered
		rel v2.3.0 false false 2 30; printf ','  # newest stable
		rel v2.2.0 true false 1 20; printf ','   # draft -> filtered
		rel v2.1.0 false false 2 10; printf ','
		rel v2.0.0 false false 0 9; printf ','   # zero assets
		rel v1.9.0 false false 2 8; printf ','
		rel v1.4.0 false false 2 7; printf ','   # too old -> filtered
		rel v1.5.0 false false 2 6; printf ','   # oldest supported
		rel nightly false false 1 5              # invalid tag -> filtered
		printf ']\n'
	} >"$BASE/tmp/fakeapi/releases.json"
}

# ---------------------------------------------------------------------------
# Rootfs construction
# ---------------------------------------------------------------------------
build_base() {
	rm -rf "$BASE"
	mkdir -p "$BASE/bin" "$BASE/sbin" "$BASE/usr/bin" "$BASE/usr/sbin" \
		"$BASE/etc/config" "$BASE/etc/init.d" "$BASE/tmp/fakeapi" \
		"$BASE/tmp/fakerelease" "$BASE/mockbin" "$BASE/proc" "$BASE/repo" \
		"$BASE/pkg" "$BASE/root" "$BASE/dev" "$BASE/www" \
		"$BASE/usr/libexec/rpcd" "$BASE/usr/share/rpcd/acl.d" \
		"$BASE/usr/share/luci/menu.d"

	cp "$BUSYBOX" "$BASE/bin/busybox"
	for a in $("$BUSYBOX" --list); do
		ln -sf busybox "$BASE/bin/$a" 2>/dev/null
	done
	# No real wget in the rootfs: the only resolver is the shim in /mockbin.
	rm -f "$BASE/bin/wget"

	cp "$FIX/mock-uci" "$BASE/sbin/uci"
	chmod 755 "$BASE/sbin/uci"
	cp "$FIX/mock-rc-common" "$BASE/etc/rc.common"
	chmod 755 "$BASE/etc/rc.common"
	cp "$FIX/wget-shim.sh" "$BASE/mockbin/wget"
	chmod 755 "$BASE/mockbin/wget"

	# Runs INSIDE the chroot: sets the environment, then execs the installer
	# and records its exit status for the assertions on the host side.
	cat >"$BASE/mockbin/drive.sh" <<'EOS'
#!/bin/sh
PATH=/mockbin:/bin:/sbin:/usr/bin:/usr/sbin
AETHER_REPO_ROOT=/repo
HOME=/root
export PATH AETHER_REPO_ROOT HOME
envs="$1"
script="$2"
shift 2
[ "$envs" = "-" ] || eval "export $envs"
/bin/sh "$script" "$@" >/tmp/install.log 2>&1
echo $? >/tmp/install.rc
EOS
	chmod 755 "$BASE/mockbin/drive.sh"

	cp -a "$ROOT/files" "$BASE/repo/files"
	cp "$ROOT/install.sh" "$BASE/repo/install.sh"
	cp "$ROOT/install.sh" "$BASE/pkg/install.sh"
	cp "$ROOT/update.sh" "$BASE/pkg/update.sh"
	cp "$ROOT/uninstall.sh" "$BASE/pkg/uninstall.sh"
	cp -a "$ROOT/files" "$BASE/pkg/files"

	printf 'MemTotal:        1048576 kB\nMemFree:          524288 kB\n' \
		>"$BASE/proc/meminfo"

	# Runs OUTSIDE the chroot but INSIDE the user+mount namespace: the rootfs
	# needs a real /dev/null for the installer's `2>/dev/null` redirections.
	cat >"$WORK/enter.sh" <<EOS
#!/bin/sh
C="\$1"; envs="\$2"; script="\$3"; shift 3
mkdir -p "\$C/dev"
mount --bind /dev "\$C/dev" 2>/dev/null || : > "\$C/dev/null" 2>/dev/null
exec "$BUSYBOX" chroot "\$C" /bin/sh /mockbin/drive.sh "\$envs" "\$script" "\$@"
EOS
	chmod 755 "$WORK/enter.sh"

	make_release
	make_releases_json
}

# new_case <name> — start from a pristine copy of the base rootfs.
new_case() {
	CASE="$1"
	C="$WORK/case-$CASE"
	rm -rf "$C"
	cp -a "$BASE" "$C"
	rm -f "$C/tmp/shim-fail-sha-once" "$C/tmp/shim-fail-sha-always" \
		"$C/tmp/wget-shim.log" "$C/tmp/mock-rcd.log" "$C/tmp/mock-uci-store" \
		"$C/tmp/install.log" "$C/tmp/install.rc"
	CASES=$((CASES + 1))
	echo "--- case: $CASE"
}

set_mem_kb() { printf 'MemTotal:         %s kB\n' "$1" >"$C/proc/meminfo"; }
set_arch() {
	rm -f "$C/bin/uname"
	printf '#!/bin/sh\ncase "${1:-}" in\n-m) echo %s ;;\n*) echo Linux ;;\nesac\n' "$1" >"$C/bin/uname"
	chmod 755 "$C/bin/uname"
}

# run_install <env|- > <script-in-chroot> [args...]
run_install() {
	envs="$1"; script="$2"; shift 2
	"$UNSHARE" -rm /bin/sh "$WORK/enter.sh" "$C" "$envs" "$script" "$@"
}

# The same chroot driver also runs update.sh and uninstall.sh.
run_script() { run_install "$@"; }

rc() { cat "$C/tmp/install.rc" 2>/dev/null || echo "norc"; }
log() { cat "$C/tmp/install.log" 2>/dev/null; }
shimlog() { cat "$C/tmp/wget-shim.log" 2>/dev/null; }
rcdlog() { cat "$C/tmp/mock-rcd.log" 2>/dev/null; }
ucistore() { cat "$C/tmp/mock-uci-store" 2>/dev/null; }

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
assert_rc() {
	if [ "$(rc)" = "$1" ]; then pass "[$CASE] exit code $1"; else
		fail "[$CASE] exit code (want $1, got $(rc))"
		echo "  log tail: $(log | tail -n 5 | tr '\n' '|')"
	fi
}
assert_rc_nonzero() {
	if [ "$(rc)" != "0" ] && [ "$(rc)" != "norc" ]; then pass "[$CASE] exits non-zero"; else
		fail "[$CASE] expected non-zero exit, got $(rc)"
	fi
}
assert_log() {
	if log | grep -Fq -- "$1"; then pass "[$CASE] log has '$1'"; else
		fail "[$CASE] log missing '$1'"
	fi
}
assert_log_absent() {
	if log | grep -Fq -- "$1"; then fail "[$CASE] log must not have '$1'"; else
		pass "[$CASE] log omits '$1'"
	fi
}
assert_mode() {
	got="$(stat -c %a "$C$1" 2>/dev/null || echo missing)"
	if [ "$got" = "$2" ]; then pass "[$CASE] $1 mode $2"; else
		fail "[$CASE] $1 mode (want $2, got $got)"
	fi
}
assert_exists() {
	if [ -e "$C$1" ]; then pass "[$CASE] $1 exists"; else fail "[$CASE] $1 missing"; fi
}
assert_absent() {
	if [ -e "$C$1" ]; then fail "[$CASE] $1 should not exist"; else pass "[$CASE] $1 absent"; fi
}
assert_file_contains() {
	if grep -Fq -- "$2" "$C$1" 2>/dev/null; then pass "[$CASE] $1 contains '$2'"; else
		fail "[$CASE] $1 does not contain '$2'"
	fi
}
assert_file_absent_text() {
	if grep -Fq -- "$2" "$C$1" 2>/dev/null; then fail "[$CASE] $1 must not contain '$2'"; else
		pass "[$CASE] $1 omits '$2'"
	fi
}
assert_uci() {
	if ucistore | grep -Fxq "$1=$2"; then pass "[$CASE] uci $1=$2"; else
		fail "[$CASE] uci $1 (want $2, store: $(ucistore | tr '\n' ' '))"
	fi
}
assert_rcd() {
	if rcdlog | grep -Fq -- "$1"; then pass "[$CASE] service action '$1'"; else
		fail "[$CASE] missing service action '$1' (rcd log: $(rcdlog | tr '\n' '|'))"
	fi
}
assert_fetch() {
	if shimlog | grep -Fq -- "$1"; then pass "[$CASE] fetched '$1'"; else
		fail "[$CASE] never fetched '$1'"
	fi
}

# Asserts every single shim request carried the mirror prefix.
assert_all_mirrored() {
	total="$(shimlog | grep -c '^GET ' || true)"
	mirrored="$(shimlog | grep -c "^GET $1" || true)"
	if [ "$total" -gt 0 ] && [ "$total" = "$mirrored" ]; then
		pass "[$CASE] all $total requests went through $1"
	else
		fail "[$CASE] $mirrored/$total requests used $1"
		echo "  $(shimlog | grep '^GET ' | grep -v "^GET $1" | head -n 3 | tr '\n' '|')"
	fi
}

# Asserts the support files and release-bundled helper binaries were installed.
assert_full_install() {
	assert_mode /usr/bin/aether 755
	assert_mode /usr/bin/pt/lyrebird 755
	assert_mode /usr/bin/pt/psiphon-tunnel-core 755
	assert_file_contains /usr/bin/pt/psiphon-tunnel-core "mock psiphon-tunnel-core"
	assert_mode /etc/config/aether 600
	assert_mode /etc/init.d/aether 755
	assert_mode /usr/bin/aether-ctl 755
	assert_mode /usr/bin/aether-run 755
	assert_mode /usr/bin/aether-watchdog 755
	assert_mode /usr/libexec/rpcd/luci-app-aether 755
	assert_mode /usr/share/rpcd/acl.d/luci-app-aether.json 644
	assert_mode /usr/share/luci/menu.d/luci-app-aether.json 644
	assert_mode /www/luci-static/resources/view/aether.js 644
	assert_mode /etc/aether 700
}

echo "=========================================================="
echo " install.sh end-to-end scenarios (BusyBox chroot)"
echo "=========================================================="

build_base

# --- release resolution -----------------------------------------------------
new_case release-parsing
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Selected release: v2.3.0"
assert_log "Checksum verified"
assert_log "Installation complete!"
assert_log "Binary: aether 2.3.0 (mock core)"
assert_fetch "api.github.com/repos/CluvexStudio/Aether/releases?per_page=30"
assert_fetch "releases/download/v2.3.0/$ARCHIVE"
assert_fetch "releases/download/v2.3.0/$ARCHIVE.sha256"
# Drafts, prereleases, invalid and pre-1.5 tags must never be selected.
assert_log_absent "v2.4.0"
assert_log_absent "v2.2.0"
assert_log_absent "v1.4.0"
assert_full_install
assert_uci main.perf_profile high
assert_rcd "disable aether"
run_script - /usr/bin/aether --psiphon-only
assert_rc 0
assert_log "mock Psiphon helper loaded"

# Emulate a previously installed core whose Psiphon helper has gone missing.
# It must fail with the same diagnostic the LuCI status classifier recognizes.
new_case psiphon-only-helper-missing-at-runtime
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
rm -f "$C/usr/bin/pt/psiphon-tunnel-core"
run_script - /usr/bin/aether --psiphon-only
assert_rc_nonzero
assert_log "psiphon needs the psiphon-tunnel-core console client"

# Psiphon-capable releases must contain the console helper before replacing
# an existing core; fail safely rather than installing a guaranteed crash loop.
make_release without-psiphon
new_case psiphon-helper-required
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "Aether v2.3.0 archive is missing pt/psiphon-tunnel-core"
assert_absent /usr/bin/aether
make_release

# --- performance profile from RAM ------------------------------------------
new_case perf-medium
set_mem_kb 524288
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_uci main.perf_profile medium
assert_log "perf_profile = medium"

new_case perf-low
set_mem_kb 131072
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_uci main.perf_profile low

new_case perf-low-boundary
set_mem_kb 262144
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_uci main.perf_profile medium

new_case perf-unknown-meminfo
rm -f "$C/proc/meminfo"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_uci main.perf_profile low

# --- support-file staging ---------------------------------------------------
new_case stage-from-github-raw
# Standalone installer with no local files/ directory: every support file must
# come from raw.githubusercontent.com (the real router code path).
cp "$ROOT/install.sh" "$C/tmp/install.sh"
run_install - /tmp/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Installation complete!"
for rel in etc/config/aether etc/init.d/aether usr/bin/aether-ctl \
	usr/bin/aether-run usr/bin/aether-watchdog \
	usr/libexec/rpcd/luci-app-aether \
	usr/share/rpcd/acl.d/luci-app-aether.json \
	usr/share/luci/menu.d/luci-app-aether.json \
	www/luci-static/resources/view/aether.js; do
	assert_fetch "raw.githubusercontent.com/Rezayavarzade123/aether-openwrt-test-with-arena.ai/main/files/$rel"
done
assert_full_install
# Staged content must match the repository byte for byte.
if cmp -s "$C/www/luci-static/resources/view/aether.js" \
	"$ROOT/files/www/luci-static/resources/view/aether.js"; then
	pass "[$CASE] installed aether.js matches the repository"
else
	fail "[$CASE] installed aether.js differs from the repository"
fi

new_case stage-from-local-dir
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
if shimlog | grep -q 'raw.githubusercontent.com'; then
	fail "[$CASE] must not hit raw.githubusercontent when files/ is present"
else
	pass "[$CASE] used the local files/ directory (no raw fetches)"
fi

# Installer preflight accepts either standard UCI path, so runtime tools must
# continue working when the only UCI binary is under /usr/sbin.
new_case uci-in-usr-sbin
mv "$C/sbin/uci" "$C/usr/sbin/uci"
printf 'main.team=team.example\nmain.access_id=client-id\nmain.access_secret=client-secret\nmain.access_token=access-token\nmain.gateway=1\n' \
	>"$C/tmp/mock-uci-store"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
run_script - /usr/bin/aether-ctl set protocol wg
assert_rc 0
assert_uci main.protocol wg
run_script - /usr/bin/aether-run --print-auth-env
assert_rc 0
assert_log "TEAM=team.example|ID=client-id|SECRET=client-secret|TOKEN=access-token|GATEWAY=1"

# --- mirror support ---------------------------------------------------------
new_case mirror-flag
run_install - /pkg/install.sh --non-interactive --no-curl --mirror https://ghproxy.net
assert_rc 0
assert_all_mirrored "https://ghproxy.net/"

new_case mirror-flag-equals
run_install - /pkg/install.sh --non-interactive --no-curl --mirror=https://ghproxy.net/
assert_rc 0
assert_all_mirrored "https://ghproxy.net/"

new_case mirror-env
run_install "AETHER_GH_MIRROR=https://ghproxy.example.org" /pkg/install.sh \
	--non-interactive --no-curl
assert_rc 0
assert_all_mirrored "https://ghproxy.example.org/"

new_case mirror-flag-beats-env
run_install "AETHER_GH_MIRROR=https://env.example.org" /pkg/install.sh \
	--non-interactive --no-curl --mirror https://flag.example.org
assert_rc 0
assert_all_mirrored "https://flag.example.org/"

# --- checksum handling ------------------------------------------------------
new_case checksum-fallback-to-sha256sums
echo always >"$C/tmp/shim-fail-sha-always"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Could not download the per-file checksum; trying SHA256SUMS.txt..."
assert_fetch "releases/download/v2.3.0/SHA256SUMS.txt"
assert_log "Checksum verified"
assert_exists /usr/bin/aether

new_case checksum-retry-then-succeed
echo 0 >"$C/tmp/shim-fail-sha-once"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Download attempt 1 failed; retrying..."
assert_log "Checksum verified"

new_case checksum-mismatch-aborts
printf '%s  %s\n' \
	"0000000000000000000000000000000000000000000000000000000000000000" \
	"$ARCHIVE" >"$C/tmp/fakerelease/$ARCHIVE.sha256"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "Checksum verification failed. Aborting."
assert_absent /usr/bin/aether
assert_absent /etc/init.d/aether

new_case checksum-unavailable
echo always >"$C/tmp/shim-fail-sha-always"
rm -f "$C/tmp/fakerelease/SHA256SUMS.txt"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "Could not download the release checksum."
assert_absent /usr/bin/aether

new_case checksum-html-error-page
# A captive portal / proxy that returns HTML instead of a digest must be
# rejected rather than fed to sha256sum -c.
echo always >"$C/tmp/shim-fail-sha-always"
printf '<html><body>404: Not Found</body></html>\n' \
	>"$C/tmp/fakerelease/SHA256SUMS.txt"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "Could not download the release checksum."
assert_absent /usr/bin/aether

new_case archive-corrupt
printf 'not a gzip archive at all\n' >"$C/tmp/fakerelease/$ARCHIVE"
sum="$(sha256sum "$C/tmp/fakerelease/$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$sum" "$ARCHIVE" >"$C/tmp/fakerelease/$ARCHIVE.sha256"
printf '%s  %s\n' "$sum" "$ARCHIVE" >"$C/tmp/fakerelease/SHA256SUMS.txt"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "could not be extracted"
assert_absent /usr/bin/aether

# --- architecture detection -------------------------------------------------
new_case arch-arm64
set_arch aarch64
run_install - /pkg/install.sh --non-interactive --no-curl
assert_log "Arch: aarch64 -> aether-linux-aarch64-musl.tar.gz"

new_case arch-armv7
set_arch armv7l
run_install - /pkg/install.sh --non-interactive --no-curl
assert_log "Arch: armv7l -> aether-linux-armv7-musl.tar.gz"

new_case arch-unsupported
set_arch mips
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "Unsupported architecture: mips"

# --- version selection ------------------------------------------------------
new_case version-too-old
run_install - /pkg/install.sh --non-interactive --no-curl --version v1.4.0
assert_rc_nonzero
assert_log "v1.5.0 or newer is required"

new_case version-invalid-format
run_install - /pkg/install.sh --non-interactive --no-curl --version 2.3.0
assert_rc_nonzero
assert_log "Invalid release tag: 2.3.0"

new_case version-oldest-supported
run_install - /pkg/install.sh --non-interactive --no-curl --version v1.5.0
assert_log "Selected release: v1.5.0"

# --- existing config handling ----------------------------------------------
new_case keep-existing-config
printf "config aether 'main'\n\n\toption marker 'KEEPME'\n" \
	>"$C/etc/config/aether"
chmod 600 "$C/etc/config/aether"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Keeping existing /etc/config/aether"
assert_file_contains /etc/config/aether "KEEPME"
assert_file_absent_text /etc/config/aether "option protocol 'masque'"
assert_log "Initialized perf_profile = high"
assert_mode /etc/config/aether 600

new_case force-config-overwrites
printf "config aether 'main'\n\n\toption marker 'KEEPME'\n" \
	>"$C/etc/config/aether"
run_install - /pkg/install.sh --non-interactive --no-curl --force-config
assert_rc 0
assert_file_absent_text /etc/config/aether "KEEPME"
assert_file_contains /etc/config/aether "option protocol 'masque'"
assert_mode /etc/config/aether 600

new_case boot-enabled-syncs-service
printf 'main.enabled=1\n' >"$C/tmp/mock-uci-store"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_rcd "enable aether"

# --- identity migration -----------------------------------------------------
new_case migrate-legacy-identity
printf 'device_id = "abc123"\n' >"$C/root/aether.toml"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Migrating identity /root/aether.toml"
assert_file_contains /etc/aether/aether.toml "abc123"
assert_absent /root/aether.toml
assert_mode /etc/aether/aether.toml 600

new_case remove-invalid-identity-stub
mkdir -p "$C/etc/aether"
: >"$C/etc/aether/aether.toml"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_log "Removing invalid identity stub"
assert_absent /etc/aether/aether.toml

new_case keep-valid-identity
mkdir -p "$C/etc/aether"
printf 'device_id = "keepme99"\n' >"$C/etc/aether/aether.toml"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_file_contains /etc/aether/aether.toml "keepme99"
assert_log_absent "Removing invalid identity stub"

# --- preflight --------------------------------------------------------------
new_case not-openwrt
rm -f "$C/sbin/uci"
run_install - /pkg/install.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "This does not look like OpenWrt"
assert_absent /usr/bin/aether

# --- update.sh --------------------------------------------------------------
new_case update-happy-path
run_script - /pkg/update.sh --non-interactive --no-curl
assert_rc 0
assert_fetch "raw.githubusercontent.com/Rezayavarzade123/aether-openwrt-test-with-arena.ai/main/install.sh"
assert_log "Installation complete!"
assert_mode /usr/bin/aether 755
assert_mode /usr/bin/aether-ctl 755
assert_mode /usr/bin/pt/psiphon-tunnel-core 755
assert_file_contains /usr/bin/pt/psiphon-tunnel-core "mock psiphon-tunnel-core"

new_case update-forwards-mirror
run_script - /pkg/update.sh --non-interactive --no-curl --mirror https://ghproxy.net
assert_rc 0
assert_all_mirrored "https://ghproxy.net/"

new_case update-rejects-unknown-option
run_script - /pkg/update.sh --bogus
assert_rc_nonzero
assert_log "unsupported installer option: --bogus"
assert_absent /usr/bin/aether

new_case update-download-failure-prints-hint
# Regression: this branch calls warn(), which update.sh used to leave
# undefined, so the actionable mirror hint was replaced by "warn: not found".
rm -f "$C/repo/install.sh"
run_script - /pkg/update.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "failed to download the current installer"
assert_log "retry with a mirror: aether-ctl update --mirror https://ghproxy.net/"
assert_log_absent "not found"

new_case update-rejects-empty-installer
# A captive portal that returns junk instead of the installer must be refused.
printf '<html>sign in to continue</html>\n' >"$C/repo/install.sh"
run_script - /pkg/update.sh --non-interactive --no-curl
assert_rc_nonzero
assert_log "downloaded installer is empty or invalid"
assert_absent /usr/bin/aether

# --- uninstall.sh -----------------------------------------------------------
new_case uninstall-keeps-config-and-identity
run_script - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
assert_exists /usr/bin/aether
run_script - /pkg/uninstall.sh
assert_rc 0
assert_log "Aether OpenWrt Client removed."
assert_rcd "stop aether"
assert_rcd "disable aether"
for f in /usr/bin/aether /usr/bin/aether-ctl /usr/bin/aether-run \
	/usr/bin/aether-watchdog /usr/bin/pt /etc/init.d/aether \
	/usr/libexec/rpcd/luci-app-aether \
	/usr/share/rpcd/acl.d/luci-app-aether.json \
	/usr/share/luci/menu.d/luci-app-aether.json \
	/www/luci-static/resources/view/aether.js; do
	assert_absent "$f"
done
assert_exists /etc/config/aether
assert_exists /etc/aether

new_case uninstall-purge
run_script - /pkg/install.sh --non-interactive --no-curl
assert_rc 0
run_script - /pkg/uninstall.sh --purge
assert_rc 0
assert_log "Config and identity data purged."
assert_absent /etc/config/aether
assert_absent /etc/aether
assert_absent /usr/bin/aether

new_case uninstall-unknown-option
# Regression: error() used to be defined AFTER argument parsing, so an unknown
# option died with "error: not found" and exit 127 instead of a clean message.
run_script - /pkg/uninstall.sh --bogus
assert_rc 1
assert_log "Unknown option: --bogus"
assert_log_absent "not found"
assert_absent /usr/bin/aether

new_case uninstall-on-clean-system
run_script - /pkg/uninstall.sh
assert_rc 0
assert_log "Aether OpenWrt Client removed."

# --- argument parsing (exits before the root check, so run on the host) -----
echo "--- case: host-arg-parsing"
CASES=$((CASES + 1))
CASE=host-arg-parsing

host_expect() {
	label="$1"; needle="$2"; shift 2
	hout="$(sh "$ROOT/install.sh" "$@" 2>&1)"; hrc=$?
	if [ "$hrc" -ne 0 ] && printf '%s' "$hout" | grep -Fq -- "$needle"; then
		pass "[host] $label"
	else
		fail "[host] $label (rc=$hrc, want '$needle'; got: $(printf '%s' "$hout" | head -n 2 | tr '\n' '|'))"
	fi
}

hout="$(sh "$ROOT/install.sh" --help 2>&1)"; hrc=$?
if [ "$hrc" -eq 0 ] && printf '%s' "$hout" | grep -Fq -- "--mirror <url>"; then
	pass "[host] --help exits 0 and documents --mirror"
else
	fail "[host] --help (rc=$hrc)"
fi

host_expect "unknown option rejected" "Unknown option: --bogus" --bogus
host_expect "--version requires an argument" "--version requires a release tag" --version
host_expect "--mirror requires an argument" "--mirror requires a URL prefix" --mirror
if [ "$(id -u)" -ne 0 ]; then
	host_expect "non-root is refused" "Run as root on the OpenWrt device" --non-interactive
else
	echo "SKIP: [host] non-root refusal (this shell is root)"
fi

# uninstall.sh parses arguments before the root check, so this runs anywhere.
hout="$(sh "$ROOT/uninstall.sh" --bogus 2>&1)"; hrc=$?
if [ "$hrc" -eq 1 ] && printf '%s' "$hout" | grep -Fq -- "Unknown option: --bogus" &&
	! printf '%s' "$hout" | grep -Fq -- "not found"; then
	pass "[host] uninstall.sh reports unknown options cleanly (exit 1)"
else
	fail "[host] uninstall.sh unknown option (rc=$hrc; got: $(printf '%s' "$hout" | head -n 2 | tr '\n' '|'))"
fi

echo "----"
echo "cases: $CASES   assertions passed: $PASS_COUNT   failures: $FAILURES"
if [ "$FAILURES" -eq 0 ]; then
	echo "all install.sh end-to-end scenarios passed"
else
	echo "$FAILURES install scenario assertion(s) FAILED"
	exit 1
fi
