#!/bin/sh
set -eu

# Sync Sprint 11 S11-01 (docs/sprints/SYNC-SPRINT-11-SHELL-CONTRAST-AND-SURVEY-GAPS.md):
# every text role of the real Theme singleton reads on its surface at 4.5:1 for
# every palette in config/themes.toml. Against the original Theme.qml this fails
# 105 of 174 assertions across 14 of the 15 presets: the hover surface came from
# the terminal's bright-black colour (all 5 light presets and 6 dark ones fell
# below 4.5:1 on hover), and selected and action text were unchecked too.
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_THEME_CONTRAST_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_THEME_CONTRAST_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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

mkdir -p "$work/qml" "$work/home/.config/lyona" "$work/runtime"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/core" "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"

# One colour map per preset, from themes.toml, using the key mapping in
# scripts/dwm-settings-appearance's emit_color_records() (read from that script,
# so this cannot drift from what the shell really receives).
python3 - "$repo" "$work/qml/shell.qml" <<'PYGEN'
import json
import re
import sys
import tomllib
from pathlib import Path

repo = Path(sys.argv[1])
source = (repo / "scripts/dwm-settings-appearance").read_text()
block = re.search(r"local -a mappings=\((.*?)\n\t\)", source, re.S).group(1)
mappings = [m.split("|") for m in re.findall(r"'([^']+)'", block)]
assert len(mappings) >= 18, mappings

themes = tomllib.loads((repo / "config/themes.toml").read_text())["theme"]
valid = re.compile(r"^#[0-9A-Fa-f]{6}$")
presets = []
for name, theme in themes.items():
    colors = {}
    for key, *candidates in mappings:
        candidates = [c for c in candidates if c]
        value = next((theme[c] for c in candidates if valid.match(str(theme.get(c, "")))), None)
        assert value, f"{name}: no usable colour for {key} from {candidates}"
        colors[key] = value
    presets.append({"name": name, "dark": theme.get("dark_mode", True), "colors": colors})
assert len(presets) >= 10, len(presets)

qml = (repo / "tests/qml/ThemeContrast.qml").read_text()
assert "__PRESETS__" in qml
Path(sys.argv[2]).write_text(qml.replace("__PRESETS__", json.dumps(presets)))
PYGEN

Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp -extension GLX \
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

status=0
timeout --foreground --kill-after=2s 30s env DISPLAY=":$display_number" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_RUNTIME_DIR="$work/runtime" QT_QPA_PLATFORMTHEME= \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/contrast.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Theme contrast tests: PASS' "$work/contrast.log" ||
	grep -Eq 'Theme contrast FAILED|ReferenceError:|TypeError:|Binding loop' "$work/contrast.log"; then
	cat "$work/contrast.log" >&2
	exit 1
fi

printf 'Quickshell Theme contrast: PASS\n'
