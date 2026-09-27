#!/bin/sh
set -eu

# Sync Sprint 11 S11-06 (docs/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md):
# a palette the generator writes for qt5ct/qt6ct really becomes the palette Qt
# apps get, and qt6ct ignores color_scheme_path unless custom_palette=true (the
# reason theme-apply.sh must set both). Quickshell's SystemPalette reports the
# palette Qt took from the platform theme.
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ ! -e /usr/lib/qt6/plugins/platformthemes/libqt6ct.so ]; then
	printf 'SKIP: qt6ct is not installed\n'
	exit 77
fi
if [ "${DWM_QT_PALETTE_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_QT_PALETTE_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
xvfb_pid=
cleanup() {
	if [ -n "$xvfb_pid" ]; then
		kill "$xvfb_pid" 2>/dev/null || true
		wait "$xvfb_pid" 2>/dev/null || true
	fi
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$work/themes" "$work/qml" "$work/runtime"
chmod 700 "$work/runtime"
"$repo/scripts/lyona-gtk-theme" generate-all "$repo/config/themes.toml" "$work/themes"

cat >"$work/qml/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
    SystemPalette { id: p; colorGroup: SystemPalette.Active }
    Timer {
        interval: 300
        running: true
        onTriggered: {
            console.info("PALETTE window=" + p.window + " base=" + p.base + " text=" + p.text + " highlight=" + p.highlight);
            Qt.quit();
        }
    }
}
QML

Xvfb -displayfd 3 -screen 0 800x600x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ ! -s "$work/display" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	sleep 0.05
done
display_number=$(sed -n '1p' "$work/display")
case $display_number in
'' | *[!0-9]*)
	cat "$work/xvfb.log" >&2
	exit 1
	;;
esac

# The palette Qt reports for a qt6ct configuration, as "window base text highlight".
palette_with() {
	home=$work/home-$1
	mkdir -p "$home/.config/qt6ct"
	printf '[Appearance]\ncolor_scheme_path=%s\n' "$2" >"$home/.config/qt6ct/qt6ct.conf"
	[ -z "${3:-}" ] || printf 'custom_palette=%s\n' "$3" >>"$home/.config/qt6ct/qt6ct.conf"
	env HOME="$home" XDG_CONFIG_HOME="$home/.config" DISPLAY=":$display_number" \
		XDG_RUNTIME_DIR="$work/runtime" QT_QPA_PLATFORMTHEME=qt6ct \
		timeout 30 quickshell --no-duplicate --path "$work/qml/shell.qml" 2>&1 |
		sed 's/\x1b\[[0-9;]*m//g' |
		sed -n 's/.*PALETTE window=\(#[0-9a-f]*\) base=\(#[0-9a-f]*\) text=\(#[0-9a-f]*\) highlight=\(#[0-9a-f]*\).*/\1 \2 \3 \4/p' |
		head -n 1
}

# Roles 11, 10, 1 and 13 of active_colors (1-based) are Window, Base, Text, Highlight;
# see ROLES in tests/test-app-palettes.py.
expected_from() {
	awk -F'[=,]' '/^active_colors=/ {
		for (i = 2; i <= NF; i++) { gsub(/^[ \t]*#ff/, "", $i); $i = tolower($i) }
		printf "#%s #%s #%s #%s\n", $12, $11, $2, $14
	}' "$1"
}

for preset in dracula catppuccin-latte; do
	scheme=$work/themes/Lyona-$preset/qt/colors.conf
	expected=$(expected_from "$scheme")

	applied=$(palette_with "$preset-on" "$scheme" true)
	if [ "$applied" != "$expected" ]; then
		printf '%s: qt6ct with custom_palette=true gave "%s", expected "%s"\n' "$preset" "$applied" "$expected" >&2
		exit 1
	fi

	for flag in '' false; do
		ignored=$(palette_with "$preset-off-$flag" "$scheme" "$flag")
		if [ -z "$ignored" ] || [ "$ignored" = "$expected" ]; then
			printf '%s: qt6ct applied color_scheme_path without custom_palette=true ("%s"); theme-apply.sh may no longer need to set it\n' "$preset" "$ignored" >&2
			exit 1
		fi
	done
done

printf 'Qt palette under qt6ct: PASS\n'
