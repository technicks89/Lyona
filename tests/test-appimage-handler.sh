#!/usr/bin/env bash
set -euo pipefail

# #260: install.sh makes lyona-appimage the AppImage handler unless another is
# set. The user's own choice is read from mimeapps.list itself, so a Gear
# Lever xdg-mime query cannot see (no Flatpak exports in XDG_DATA_DIRS) is
# still kept. appimage_user_choice and configure_appimage_handler are extracted
# from scripts/lyona-reconcile-user (#273), which install.sh and make
# install-user both run, and run against an xdg-mime stub: query answers STUB_QUERY,
# and default only logs.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

{
	sed -n '/^appimage_user_choice() {$/,/^}$/p' "$repo/scripts/lyona-reconcile-user"
	sed -n '/^appimage_entry_installed() {$/,/^}$/p' "$repo/scripts/lyona-reconcile-user"
	sed -n '/^configure_appimage_handler() {$/,/^}$/p' "$repo/scripts/lyona-reconcile-user"
} >"$work/handler.sh"
grep -q '^appimage_user_choice() {$' "$work/handler.sh" || fail 'appimage_user_choice not found in lyona-reconcile-user'
grep -q '^configure_appimage_handler() {$' "$work/handler.sh" ||
	fail 'configure_appimage_handler not found in lyona-reconcile-user'

mkdir -p "$work/bin" "$work/config" "$work/data/applications"
# lyona-appimage's entry, installed (#276); a case below removes it.
: >"$work/data/applications/lyona-appimage.desktop"
cat >"$work/bin/xdg-mime" <<'STUB'
#!/bin/sh
case $1 in
query) printf '%s\n' "${STUB_QUERY:-}" ;;
default) printf '%s\n' "$2" >>"$TEST_DIR/default.log" ;;
esac
STUB
chmod +x "$work/bin/xdg-mime"
# The handler is set through dwm-default-apps set-mime (#276); logged here in
# the same place as xdg-mime default, by desktop id.
cat >"$work/bin/dwm-default-apps" <<'STUB'
#!/bin/sh
[ "$1" = set-mime ] && [ "$2" = application/vnd.appimage ] && printf '%s\n' "$3" >>"$TEST_DIR/default.log"
STUB
chmod +x "$work/bin/dwm-default-apps"

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
		info() { printf 'info %s\n' "$1" >>"$work/out.log"; }
		warn() { printf 'warn %s\n' "$1" >>"$work/out.log"; }
		config_home=$work/config
		data_home=$work/data
		XDG_DATA_DIRS=$work/no-system-data
		script_dir=$work/bin
		export PATH="$work/bin:$PATH" TEST_DIR="$work"
		# shellcheck source=/dev/null
		. "$work/handler.sh"
		configure_appimage_handler
	)
}

# Nothing set: lyona-appimage becomes the handler.
run_case ''
grep -Fxq lyona-appimage.desktop "$work/default.log" || fail 'with no handler, lyona-appimage was not set'

# Already set to lyona-appimage by an earlier run: detected, nothing changed.
STUB_QUERY=lyona-appimage.desktop run_case 'application/vnd.appimage=lyona-appimage.desktop;'
[[ ! -s $work/default.log ]] || fail 'an existing lyona-appimage default was set again'
grep -Fq 'ok AppImages already open with lyona-appimage.' "$work/out.log" ||
	fail "an existing lyona-appimage default was not reported: $(cat "$work/out.log")"

# lyona-appimage only by xdg-mime's own choice (no explicit default): set.
STUB_QUERY=lyona-appimage.desktop run_case ''
grep -Fxq lyona-appimage.desktop "$work/default.log" || fail 'an implicit lyona-appimage default was not made explicit'
grep -Fq 'ok AppImages open with lyona-appimage, which adds them to the launcher.' "$work/out.log" ||
	fail "setting lyona-appimage was not reported: $(cat "$work/out.log")"

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

# Before make install-system put lyona-appimage's entry in place (install.sh's
# first pass): nothing is set and nothing is a warning; the later pass sets it.
rm -f "$work/data/applications/lyona-appimage.desktop"
run_case ''
[[ ! -s $work/default.log ]] || fail "a handler was set before its entry was installed: $(cat "$work/default.log")"
grep -q '^info .*once lyona.s files are installed' "$work/out.log" || fail "a missing entry was not explained: $(cat "$work/out.log")"
grep -q '^warn ' "$work/out.log" && fail "a missing entry was a warning: $(cat "$work/out.log")"

printf 'AppImage handler (none, ours, implicit, Gear Lever unseen by xdg-mime, other, unrelated, not yet installed): PASS\n'
