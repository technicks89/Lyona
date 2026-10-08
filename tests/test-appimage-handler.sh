#!/usr/bin/env bash
set -euo pipefail

# #260: install.sh makes lyona-appimage the AppImage handler unless another is
# set. The user's own choice is read from mimeapps.list itself, so a Gear
# Lever xdg-mime query cannot see (no Flatpak exports in XDG_DATA_DIRS) is
# still kept. appimage_user_choice and configure_appimage_handler are extracted
# from install.sh and run against an xdg-mime stub: query answers STUB_QUERY,
# and default only logs.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

{
	sed -n '/^appimage_user_choice() {$/,/^}$/p' "$repo/install.sh"
	sed -n '/^configure_appimage_handler() {$/,/^}$/p' "$repo/install.sh"
} >"$work/handler.sh"
grep -q '^appimage_user_choice() {$' "$work/handler.sh" || fail 'appimage_user_choice not found in install.sh'
grep -q '^configure_appimage_handler() {$' "$work/handler.sh" || fail 'configure_appimage_handler not found in install.sh'

mkdir -p "$work/bin" "$work/config"
cat >"$work/bin/xdg-mime" <<'STUB'
#!/bin/sh
case $1 in
query) printf '%s\n' "${STUB_QUERY:-}" ;;
default) printf '%s\n' "$2" >>"$TEST_DIR/default.log" ;;
esac
STUB
chmod +x "$work/bin/xdg-mime"

# run_case MIMEAPPS_LINE: mimeapps.list with that line (none when empty).
# The variables are read, and the stubs called, by the extracted functions.
# shellcheck disable=SC2034,SC2329
run_case() {
	: >"$work/out.log"
	: >"$work/default.log"
	rm -f "$work/config/mimeapps.list"
	[[ -z $1 ]] || printf '[Default Applications]\n%s\n' "$1" >"$work/config/mimeapps.list"
	(
		ok() { printf 'ok %s\n' "$1" >>"$work/out.log"; }
		warn() { printf 'warn %s\n' "$1" >>"$work/out.log"; }
		REPO_DIR=$repo
		export PATH="$work/bin:$PATH" TEST_DIR="$work" XDG_CONFIG_HOME="$work/config"
		# shellcheck source=/dev/null
		. "$work/handler.sh"
		configure_appimage_handler
	)
}

# Nothing set: lyona-appimage becomes the handler.
run_case ''
grep -Fxq lyona-appimage.desktop "$work/default.log" || fail 'with no handler, lyona-appimage was not set'

# Already lyona-appimage: set again, harmlessly.
STUB_QUERY=lyona-appimage.desktop run_case 'application/vnd.appimage=lyona-appimage.desktop;'
grep -Fxq lyona-appimage.desktop "$work/default.log" || fail 'an existing lyona-appimage default was not kept'

# Gear Lever in mimeapps.list, invisible to xdg-mime query: kept.
STUB_QUERY='' run_case 'application/vnd.appimage=it.mijorus.gearlever.desktop;'
[[ ! -s $work/default.log ]] || fail "a Gear Lever xdg-mime query cannot see was replaced: $(cat "$work/default.log")"
grep -Fq 'keep opening with it.mijorus.gearlever.desktop' "$work/out.log" || fail 'keeping Gear Lever was not said'

# Another handler only xdg-mime knows about (a system default): kept.
STUB_QUERY=other.desktop run_case ''
[[ ! -s $work/default.log ]] || fail 'a handler xdg-mime reports was replaced'

# A mimeapps.list with other types only: lyona-appimage is set.
run_case 'text/plain=org.gnome.TextEditor.desktop;'
grep -Fxq lyona-appimage.desktop "$work/default.log" || fail 'an unrelated default stopped lyona-appimage being set'

printf 'AppImage handler (none, ours, Gear Lever unseen by xdg-mime, other, unrelated): PASS\n'
