#!/bin/sh
# #280 VM: install-system removes the shared data an earlier update left under
# PREFIX/share (the old DATADIR default), which XDG_DATA_DIRS would find before
# DATADIR's, and only what is lyona's.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

stage=$work/stage
legacy=$stage/usr/local/share
put() { install -D -m 0644 /dev/null "$legacy/$1"; }

# What an earlier update put there, lyona's own license directory included.
put themes/Lyona-tokyonight/index.theme
put applications/lyona-appimage.desktop
put icons/Capitaine-Cursors/index.theme
put icons/Capitaine-Cursors-White/index.theme
put grub/themes/CyberRe/theme.txt
put licenses/lyona/capitaine-cursors/COPYING
put licenses/lyona/grub-themes/LICENSE
# What is not lyona's.
put themes/Adwaita-custom/index.theme
put icons/hicolor/index.theme
put applications/firefox.desktop

make -s -C "$repo" remove-legacy-shared-data DESTDIR="$stage" PREFIX=/usr/local DATADIR=/usr/share \
	>"$work/out" 2>&1 || {
	cat "$work/out" >&2
	fail 'remove-legacy-shared-data failed'
}
for gone in themes/Lyona-tokyonight applications/lyona-appimage.desktop icons/Capitaine-Cursors \
	icons/Capitaine-Cursors-White grub/themes/CyberRe licenses/lyona; do
	assert_no_file "$legacy/$gone" 'an earlier update left it; install-system removes it'
	grep -Fq "Removing an earlier update's copy: $legacy/$gone" "$work/out" ||
		fail "the removal of $gone was not reported"
done
for kept in themes/Adwaita-custom/index.theme icons/hicolor/index.theme applications/firefox.desktop; do
	assert_file "$legacy/$kept" 'not lyona'"'"'s; kept'
done

# Without lyona's license directory there, nothing there is lyona's: not even a
# theme named like lyona's, nor the cursor and GRUB themes.
command rm -rf "$stage"
put icons/Capitaine-Cursors/index.theme
put grub/themes/CyberRe/theme.txt
put themes/Lyona-mine/index.theme
put applications/lyona-appimage.desktop
make -s -C "$repo" remove-legacy-shared-data DESTDIR="$stage" PREFIX=/usr/local DATADIR=/usr/share \
	>"$work/out" 2>&1
assert_file "$legacy/icons/Capitaine-Cursors/index.theme" 'no lyona license there: kept'
assert_file "$legacy/grub/themes/CyberRe/theme.txt" 'no lyona license there: kept'
assert_file "$legacy/themes/Lyona-mine/index.theme" 'no lyona license there: a theme named Lyona-* is kept'
assert_file "$legacy/applications/lyona-appimage.desktop" 'no lyona license there: kept'

# When DATADIR is PREFIX/share, those are the live copies: nothing is removed.
put themes/Lyona-tokyonight/index.theme
make -s -C "$repo" remove-legacy-shared-data DESTDIR="$stage" PREFIX=/usr/local DATADIR=/usr/local/share \
	>"$work/out" 2>&1
assert_file "$legacy/themes/Lyona-tokyonight/index.theme" 'DATADIR is PREFIX/share: kept'

# install-system runs it before installing the shared data.
awk '/^install-system:/ { inside = 1 } inside && /remove-legacy-shared-data/ { found = 1 }
	inside && /install-gtk-themes/ { exit !found }' "$repo/Makefile" ||
	fail 'install-system does not remove the legacy copies before installing the shared data'

printf 'Legacy shared data from earlier updates: PASS\n'
