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

printf 'Legacy ChatGPT web-app compatibility: PASS\n'
