#!/usr/bin/env bash
set -euo pipefail

# #275: scripts/dwm-desktop-entry.sh, the one desktop-entry reader and Exec=
# writer. The reader refuses a file with control characters, a NUL, a repeated
# group or a duplicate key; the writer quotes and escapes one Exec argument.
# And a contract: no script grows a hand-written reader of its own.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
# shellcheck source=scripts/dwm-desktop-entry.sh
. "$repo/scripts/dwm-desktop-entry.sh"

entry=$work/entry.desktop
get() { # KEY [GROUP]: prints the value, then the status
	local status=0 value
	value=$(desktop_entry_get "$entry" "$@") || status=$?
	printf '%s|%s\n' "$value" "$status"
}

# ── the reader ──────────────────────────────────────────────────────────────
printf '%s\n' '# a comment' '[Desktop Entry]' 'Type=Application' 'Name = Spaced Name' \
	'Name[de]=Deutsch' 'Exec="/opt/my app/run" %U' '' '[Desktop Action new]' 'Name=Action name' >"$entry"
[[ $(get Type) == 'Application|0' ]] || fail "a plain key: $(get Type)"
[[ $(get Name) == 'Spaced Name|0' ]] || fail "spaces around = are not part of the key or value: $(get Name)"
[[ $(get 'Name[de]') == 'Deutsch|0' ]] || fail "a localized key: $(get 'Name[de]')"
[[ $(get Exec) == '"/opt/my app/run" %U|0' ]] || fail "a value is not given as written: $(get Exec)"
[[ $(get Missing) == '|1' ]] || fail "a missing key is not status 1: $(get Missing)"
[[ $(get Name 'Desktop Action new') == 'Action name|0' ]] || fail 'another group is not read when asked for'
[[ $(desktop_entry_get "$work/none.desktop" Name || echo "status $?") == 'status 1' ]] || fail 'a missing file is not status 1'

printf '[Desktop Entry]\r\nName=Windows lines\r\n' >"$entry"
[[ $(get Name) == 'Windows lines|0' ]] || fail "CRLF line ends: $(get Name)"

refused() { # DESCRIPTION: the entry in $entry is refused whole
	[[ $(get Name) == '|2' ]] || fail "$1 was not refused: $(get Name)"
}
printf '[Desktop Entry]\nName=Tab\there\n' >"$entry"
refused 'a control character'
printf '[Desktop Entry]\nName=Escape\033[31m\n' >"$entry"
refused 'an escape sequence'
printf '[Desktop Entry]\nName=Nul\000hidden\nExec=evil\n' >"$entry"
refused 'a NUL byte'
printf '[Desktop Entry]\nName=First\nName=Second\n' >"$entry"
refused 'a duplicate key'
printf '[Desktop Entry]\nName=First\n[Desktop Entry]\nExec=evil\n' >"$entry"
refused 'a repeated group'
{
	printf '[Desktop Entry]\nName=Big\n'
	head -c 70000 /dev/zero | tr '\0' x
	printf '\n'
} >"$entry"
refused 'a file over the size limit'

# ── the Exec= writer ────────────────────────────────────────────────────────
exec_case() { # VALUE EXPECTED
	local actual
	actual=$(desktop_exec_arg "$1")
	[[ $actual == "$2" ]] || fail "desktop_exec_arg '$1' gave '$actual', want '$2'"
}
exec_case /usr/bin/app /usr/bin/app
exec_case '/opt/my app' '"/opt/my app"'
exec_case '100%' '100%%'
exec_case 'say "hi"' '"say \\"hi\\""'
exec_case 'a\b' '"a\\\\b"'
# shellcheck disable=SC2016 # a literal $ and backticks, which the writer escapes
exec_case 'cost $5' '"cost \\$5"'
# shellcheck disable=SC2016
exec_case 'run `x`' '"run \\`x\\`"'

# ── the contract ────────────────────────────────────────────────────────────
# Desktop entries are read through dwm-desktop-entry.sh. These readers came
# before it and move in #308; anything else that compares a line with
# its group header, or reads an Exec= line itself, is a new hand-written parser.
allowed='dwm-default-apps dwm-xdg-autostart dwm-quickshell-launcher webapp-launch seed-autostart-overrides.sh dwm-packages.sh'
while IFS= read -r file; do
	name=${file##*/}
	[[ $name == dwm-desktop-entry.sh || " $allowed " == *" $name "* ]] ||
		fail "$name reads desktop entries by hand; use scripts/dwm-desktop-entry.sh"
done < <(grep -lE "== *[\"']\[Desktop Entry\][\"']|== Exec=\*" "$repo"/scripts/* 2>/dev/null || true)

printf 'Desktop entry reader and Exec writer: PASS\n'
