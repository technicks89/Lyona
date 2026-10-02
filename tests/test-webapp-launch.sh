#!/bin/sh
# Covers scripts/webapp-launch: the general web-app dispatcher, and its
# special-cased ChatGPT hotkey compatibility path (Super+A prefers an
# installed native desktop app; scripts/dwm-quickshell-launcher launches
# this script only as the fallback, with DWM_CHATGPT_WEB_FALLBACK=1 set so
# the fallback doesn't call back into the launcher and recurse).

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

home=$work/home
apps=$home/.local/share/applications
mkdir -p "$apps"

native_log=$work/native.log
browser_log=$work/browser.log

stub_command xdg-settings <<'SH'
#!/bin/sh
[ "${DWM_TEST_XDG_FAIL:-0}" != 1 ] || exit 1
printf '%s\n' "${DWM_TEST_BROWSER_DESKTOP:-helium.desktop}"
SH

cat >"$work/bin/dwm-quickshell-launcher" <<SH
#!/bin/sh
printf '%s\n' "\$*" >>"$native_log"
SH
chmod +x "$work/bin/dwm-quickshell-launcher"

cat >"$work/bin/test-browser" <<SH
#!/bin/sh
printf '%s\n' "\$*" >>"$browser_log"
SH
chmod +x "$work/bin/test-browser"
# A browser at a path containing a space -- the case an unquoted `$(...)`
# in the original one-liner would have word-split.
ln -s "$work/bin/test-browser" "$work/bin/test browser"

cat >"$apps/helium.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Test Browser
Exec=$work/bin/test-browser %U
DESKTOP

cat >"$apps/brave-quoted.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Quoted Test Browser
Exec="$work/bin/test browser" %U
DESKTOP

cat >"$apps/brave-escaped.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Escaped Test Browser
Exec=$work/bin/test\\ browser %U
DESKTOP

cat >"$apps/brave-wrapper.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Wrapped Test Browser
Exec=flatpak run com.example.Browser %U
DESKTOP

run_webapp() {
	HOME="$home" PATH="$work/bin:/usr/bin:/bin" \
		"$repo/scripts/webapp-launch" "$@"
}

# ── the ChatGPT hotkey path: native-first, web only as an explicit fallback ──

run_webapp https://chatgpt.com
assert_line "$native_log" 'launch-chatgpt'
assert_no_file "$browser_log" 'a bare chatgpt.com launch must prefer the native helper'

run_webapp https://chatgpt.com/
assert_equals 2 "$(grep -Fxc 'launch-chatgpt' "$native_log")" \
	'the trailing-slash form must also route natively'
assert_no_file "$browser_log"

# Extra arguments mean this isn't the plain hotkey invocation -- go straight
# to the browser, since the native desktop app takes no arguments.
run_webapp https://chatgpt.com --incognito
assert_line "$browser_log" '--app=https://chatgpt.com --incognito'
assert_equals 2 "$(grep -Fxc 'launch-chatgpt' "$native_log")" \
	'an argument-bearing call must not also touch the native helper'

# The fallback env guard: what dwm-quickshell-launcher itself sets when the
# native app isn't installed. Must not recurse back into the launcher.
DWM_CHATGPT_WEB_FALLBACK=1 run_webapp https://chatgpt.com --new-window
assert_line "$browser_log" '--app=https://chatgpt.com --new-window'
assert_equals 2 "$(grep -Fxc 'launch-chatgpt' "$native_log")" \
	'the fallback guard must skip the native helper entirely'

# A partial installation without the native-first helper still opens the web app.
mv "$work/bin/dwm-quickshell-launcher" "$work/dwm-quickshell-launcher.disabled"
run_webapp https://chatgpt.com/
assert_line "$browser_log" '--app=https://chatgpt.com/'
mv "$work/dwm-quickshell-launcher.disabled" "$work/bin/dwm-quickshell-launcher"

# ── ordinary web apps: always the browser, never the ChatGPT special case ──

run_webapp https://example.com --incognito
assert_line "$browser_log" '--app=https://example.com --incognito'

DWM_TEST_XDG_FAIL=1 run_webapp https://example.net
assert_line "$browser_log" '--app=https://example.net'

# ── Exec= line parsing: quoted and backslash-escaped paths ──

DWM_TEST_BROWSER_DESKTOP=brave-quoted.desktop run_webapp https://quoted.example
assert_line "$browser_log" '--app=https://quoted.example'

DWM_TEST_BROWSER_DESKTOP=brave-escaped.desktop run_webapp https://escaped.example
assert_line "$browser_log" '--app=https://escaped.example'

# ── non-http(s) URL schemes ──

run_webapp file:///home/user/dashboard.html
assert_line "$browser_log" '--app=file:///home/user/dashboard.html'

run_webapp mailto:user@example.com
assert_line "$browser_log" '--app=mailto:user@example.com'

# ── rejections ──

if DWM_TEST_BROWSER_DESKTOP=brave-wrapper.desktop \
	run_webapp https://wrapped.example 2>"$work/wrapper.err"; then
	fail 'webapp-launch accepted a browser wrapper command'
fi
assert_contains "$work/wrapper.err" 'unsupported browser wrapper'

if run_webapp 2>"$work/missing.err"; then
	fail 'webapp-launch accepted a missing URL'
fi
assert_contains "$work/missing.err" 'usage: webapp-launch URL'

for invalid_url in '' chatgpt.com 'https://' 'https:///' 'https://chatgpt.com/bad path'; do
	if run_webapp "$invalid_url" 2>"$work/invalid.err"; then
		fail "webapp-launch accepted invalid URL: $invalid_url"
	fi
	assert_contains "$work/invalid.err" 'invalid web app URL'
done

# ── the launcher's own recursion guard ──

assert_contains "$repo/scripts/dwm-quickshell-launcher" \
	'DWM_CHATGPT_WEB_FALLBACK=1 webapp-launch https://chatgpt.com'

# ── webapp-create writes a spec-quoted Exec line (Sync Sprint 12 S12-18) ──
#
# The expected lines were checked against GLib: its key-file reader and shell
# parser give back exactly the URL as one argument.
create_home=$work/create-home
mkdir -p "$create_home"
check_exec() { # URL EXPECTED-EXEC
	HOME=$create_home "$repo/scripts/webapp-create" create 'Quote Test' "$1" '' launcher-x >/dev/null
	actual=$(sed -n 's/^Exec=//p' "$create_home/.local/share/applications/quote-test.desktop")
	[ "$actual" = "$2" ] || fail "webapp-create wrote Exec=$actual for $1, expected Exec=$2"
}
check_exec 'https://example.com/' 'launcher-x https://example.com/'
check_exec 'https://example.com/?a=1&b=2' 'launcher-x "https://example.com/?a=1&b=2"'
# shellcheck disable=SC2016 # literal $ and backquote, the characters under test
check_exec 'https://e.com/$x"y`z' 'launcher-x "https://e.com/\\$x\\"y\\`z"'
check_exec 'https://e.com/%20' 'launcher-x https://e.com/%%20'
check_exec 'https://e.com/back\slash' 'launcher-x "https://e.com/back\\\\slash"'
# The wget fallback, like curl's, fetches the icon over HTTPS only.
grep -Fq 'wget -q --https-only' "$repo/scripts/webapp-create" ||
	fail 'webapp-create fetches icons with wget without --https-only'

# Exercise both downloader branches without using the network or host curl.
for downloader in curl wget; do
	download_bin="$work/download-$downloader"
	mkdir -p "$download_bin"
	for utility in mkdir tr sed cat rm; do
		ln -s "$(command -v "$utility")" "$download_bin/$utility"
	done
	cat >"$download_bin/$downloader" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
	case "$1" in
	-o | -O)
		shift
		printf 'downloaded bytes' >"$1"
		;;
	esac
	shift
done
exit "${DOWNLOAD_STATUS:?}"
SH
	chmod +x "$download_bin/$downloader"
	for status in 0 1; do
		PATH="$download_bin" HOME="$create_home" DOWNLOAD_STATUS=$status \
			"$repo/scripts/webapp-create" create 'Icon Test' 'https://example.com' \
			'https://example.com/icon.png' launcher-x >"$work/icon.out" 2>&1 ||
			fail "webapp-create failed with $downloader status $status"
		icon_file="$create_home/.local/share/icons/icon-test.png"
		desktop_file="$create_home/.local/share/applications/icon-test.desktop"
		if [ "$status" = 0 ]; then
			[ -s "$icon_file" ] || fail "$downloader success lost the icon"
			assert_line "$desktop_file" "Icon=$icon_file"
		else
			[ ! -e "$icon_file" ] || fail "$downloader failure left a partial icon"
			assert_line "$desktop_file" 'Icon='
			assert_contains "$work/icon.out" 'continuing without an icon'
		fi
	done
done

printf 'Legacy ChatGPT web-app compatibility: PASS\n'
