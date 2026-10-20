#!/usr/bin/env bash
set -euo pipefail

# #426: install.sh's closing line offers `startx` only when ~/.xinitrc starts
# dwm. `make install-user` keeps an existing one, so a kept file that runs
# something else gets a line that says so instead.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

sed -n '/^startx_hint() {$/,/^}$/p' "$repo/install.sh" >"$work/hint.sh"
grep -q '^startx_hint() {$' "$work/hint.sh" || fail 'startx_hint not found in install.sh'
grep -qx 'startx_hint' "$repo/install.sh" || fail 'the closing banner does not use startx_hint'

# hint XINITRC_TEXT: the line for a home with that ~/.xinitrc ("-" for none).
hint() {
	rm -rf "${work:?}/home"
	mkdir -p "$work/home"
	[[ $1 == - ]] || printf '%s\n' "$1" >"$work/home/.xinitrc"
	(
		# shellcheck disable=SC2034 # read by the sourced function
		HOME=$work/home REPO_DIR=$repo
		# shellcheck source=/dev/null
		. "$work/hint.sh"
		startx_hint
	)
}
offers() { [[ $(hint "$1") == *'or start with: startx'* ]] || fail "startx was not offered for: $1"; }
warns() {
	local line
	line=$(hint "$1")
	[[ $line != *'or start with: startx'* && $line == *'does not start dwm'* && $line == *"$repo/scripts/.xinitrc"* ]] ||
		fail "a .xinitrc that does not start dwm was not explained: $1"$'\n'"$line"
}

offers "$(cat "$repo/scripts/.xinitrc")"
offers -
offers $'#!/bin/sh\nxset s off\nexec dbus-run-session dwm'
offers $'#!/bin/sh\nexec /usr/local/bin/dwm'
warns $'#!/bin/sh\nexec xterm'
warns $'#!/bin/sh\n# exec dwm\nexec i3'
warns $'#!/bin/sh\nexec dwm-like-wm'
# dwm named where it is not run: an argument, or a comment after the command.
warns $'#!/bin/sh\necho dwm\nexec xterm'
warns $'#!/bin/sh\npkill dwm\nexec i3'
warns $'#!/bin/sh\nexec i3 # dwm'
offers $'#!/bin/sh\nxset s off; exec dwm'
offers $'#!/bin/sh\ndwm &\nwait'

printf 'install.sh startx hint (lyona .xinitrc, none, dwm run, kept other, dwm named but not run): PASS\n'
