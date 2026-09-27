#!/usr/bin/env bash
# theme-apply.sh must leave qt5ct/qt6ct configured so Qt applications actually get
# the palette (Sync Sprint 11 S11-06). qt6ct ignores color_scheme_path unless
# custom_palette=true (checked with qt6ct 0.11, tests/test-qt-palette-xvfb.sh
# proves it), and the old block wrote only the path, and only when the user had
# already opened qt6ct once, so installing the tool left Qt on its default light
# palette on a dark desktop.
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

home=$work/home
runtime=$work/run
bin=$work/bin
mkdir -p "$home/.config/lyona" "$home/.local/share" "$home/.local/state" \
	"$runtime" "$bin"
chmod 700 "$runtime"

# Everything that could touch the developer's real session is a stub. qt6ct and
# qt5ct are stubs too: theme-apply.sh only asks whether the tool exists.
for name in gsettings xfconf-query systemctl dbus-update-activation-environment \
	xsetroot dwm-cursor-reload qt6ct qt5ct; do
	printf '#!/bin/sh\nexit 0\n' >"$bin/$name"
done
chmod +x "$bin"/*

use_preset() {
	cp "$repo/config/themes.toml" "$home/.config/lyona/themes.toml"
	sed -i "s/^theme = \".*\"/theme = \"$1\"/" "$home/.config/lyona/themes.toml"
}

run_apply() {
	HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
		XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$runtime \
		PATH=$bin:/usr/bin:/bin \
		"$repo/scripts/theme-apply.sh" >"$work/apply.out" 2>&1 || {
		cat "$work/apply.out" >&2
		fail 'theme-apply.sh failed'
	}
}

conf_value() {
	sed -n "s/^$2=//p" "$1" | head -n 1
}

# 1. A dark preset, qt6ct installed, and no qt6ct.conf yet: the config is created
# and points at the palette's own generated scheme with the custom palette on.
use_preset tokyonight
conf=$home/.config/qt6ct/qt6ct.conf
[[ ! -e $conf ]] || fail 'qt6ct.conf exists before the run; the test setup is wrong'
run_apply
assert_file "$conf"
assert_equals true "$(conf_value "$conf" custom_palette)" 'qt6ct custom_palette'
scheme=$(conf_value "$conf" color_scheme_path)
assert_equals "$home/.local/share/themes/Lyona-tokyonight/qt/colors.conf" "$scheme" 'qt6ct color_scheme_path'
assert_file "$scheme"
grep -Fq '[ColorScheme]' "$scheme" || fail 'the generated scheme is not a qt6ct colour scheme'
grep -Fq 'QT_QPA_PLATFORMTHEME=qt6ct' "$home/.config/lyona/theme-env.sh" ||
	fail 'theme-env.sh does not select qt6ct'
printf 'qt6ct is pointed at the generated palette with the custom palette on: PASS\n'

# 2. A light preset switches the scheme, and everything else in an existing
# config survives (other keys in [Appearance], and other sections).
printf '[Appearance]\nstyle=Fusion\ncustom_palette=false\ncolor_scheme_path=/old/scheme.conf\nicon_theme=breeze\n\n[Fonts]\ngeneral="Sans,10"\n' >"$conf"
use_preset catppuccin-latte
run_apply
assert_equals true "$(conf_value "$conf" custom_palette)" 'custom_palette after a light preset'
assert_equals "$home/.local/share/themes/Lyona-catppuccin-latte/qt/colors.conf" \
	"$(conf_value "$conf" color_scheme_path)" 'color_scheme_path after a light preset'
assert_equals Fusion "$(conf_value "$conf" style)" 'an unrelated qt6ct key was kept'
assert_equals breeze "$(conf_value "$conf" icon_theme)" 'an unrelated qt6ct key was kept'
grep -Fqx '[Fonts]' "$conf" || fail 'an unrelated qt6ct section was lost'
grep -Fqx 'general="Sans,10"' "$conf" || fail 'an unrelated qt6ct setting was lost'
[[ $(grep -c '^color_scheme_path=' "$conf") == 1 ]] || fail 'color_scheme_path was duplicated'
[[ $(grep -c '^custom_palette=' "$conf") == 1 ]] || fail 'custom_palette was duplicated'
printf 'a light preset switches the scheme and keeps the rest of the config: PASS\n'

# 3. qt5ct chosen explicitly gets its own config the same way.
printf 'toolkit-protocol\t1\t0\nqt\tqt5ct\n' >"$home/.config/lyona/personalization.conf"
use_preset tokyonight
run_apply
qt5conf=$home/.config/qt5ct/qt5ct.conf
assert_file "$qt5conf"
assert_equals true "$(conf_value "$qt5conf" custom_palette)" 'qt5ct custom_palette'
assert_equals "$home/.local/share/themes/Lyona-tokyonight/qt/colors.conf" \
	"$(conf_value "$qt5conf" color_scheme_path)" 'qt5ct color_scheme_path'
printf 'qt5ct is configured the same way: PASS\n'

# 4. A runtime-only apply changes nothing on disk.
rm -f "$qt5conf" "$conf"
rm -f "$home/.config/lyona/personalization.conf"
HOME=$home XDG_CONFIG_HOME=$home/.config XDG_DATA_HOME=$home/.local/share \
	XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$runtime \
	DWM_APPEARANCE_RUNTIME_ONLY=1 PATH=$bin:/usr/bin:/bin \
	"$repo/scripts/theme-apply.sh" >"$work/apply.out" 2>&1 || {
	cat "$work/apply.out" >&2
	fail 'a runtime-only theme-apply.sh failed'
}
[[ ! -e $conf && ! -e $qt5conf ]] || fail 'a runtime-only apply wrote a qt5ct/qt6ct config'
printf 'a runtime-only apply leaves the Qt configuration alone: PASS\n'

printf 'theme-apply.sh Qt palette: PASS\n'
