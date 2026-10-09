#!/bin/sh
# Test shim for wget: serves canned GitHub API/release content and maps
# raw.githubusercontent.com URLs to the local repository checkout.
# Failure simulation:
#   /tmp/shim-fail-sha-once   -> first .sha256 request fails (retry test)
#   /tmp/shim-fail-sha-always -> every .sha256 request fails (fallback test)
LOG=/tmp/wget-shim.log
REPO=/home/user/aether-openwrt-test-with-arena.ai

outfile=""
url=""
prev_o=0
for a in "$@"; do
	case "$a" in
		-O|-qO) prev_o=1 ;;
		-O-|-qO-|-q|-4|-T|--) : ;;
		''|*[!0-9]*)
			if [ "$prev_o" = 1 ]; then outfile="$a"; prev_o=0; else url="$a"; fi ;;
		*) [ "$prev_o" = 1 ] && { outfile="$a"; prev_o=0; } ;;
	esac
done

echo "GET $url" >>"$LOG"

case "$url" in
	*api.github.com/repos/CluvexStudio/Aether/releases*)
		cat /tmp/fakeapi/releases.json
		exit 0 ;;
	*api.github.com/repos/CluvexStudio/Aether/releases/tags/*)
		echo '{"tag_name":"v2.3.0","draft":false,"prerelease":false}'
		exit 0 ;;
	*releases/download/v2.3.0/SHA256SUMS.txt)
		cp /tmp/fakerelease/SHA256SUMS.txt "$outfile"
		exit 0 ;;
	*releases/download/v2.3.0/aether-linux-x86_64-musl.tar.gz.sha256)
		if [ -f /tmp/shim-fail-sha-always ]; then
			echo "shim: simulated timeout" >&2
			exit 1
		fi
		if [ -f /tmp/shim-fail-sha-once ] && [ "$(cat /tmp/shim-fail-sha-once 2>/dev/null)" = "0" ]; then
			echo 1 > /tmp/shim-fail-sha-once
			echo "shim: simulated timeout (first attempt)" >&2
			exit 1
		fi
		cp /tmp/fakerelease/aether-linux-x86_64-musl.tar.gz.sha256 "$outfile"
		exit 0 ;;
	*releases/download/v2.3.0/aether-linux-x86_64-musl.tar.gz)
		cp /tmp/fakerelease/aether-linux-x86_64-musl.tar.gz "$outfile"
		exit 0 ;;
	*raw.githubusercontent.com/Rezayavarzade123/aether-openwrt-test-with-arena.ai/*)
		rel="${url#*aether-openwrt-test-with-arena.ai/}"
		rel="${rel#main/}"
		src="$REPO/${rel}"
		if [ -f "$src" ] && [ -s "$src" ]; then
			cp "$src" "$outfile"
			exit 0
		fi
		echo "shim: no local source for $url" >&2
		exit 1 ;;
	"")
		echo "shim: no URL parsed from: $*" >&2
		exit 1 ;;
	*)
		echo "shim: unexpected URL $url" >&2
		exit 1 ;;
esac
