#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_HEALTH_NAVIGATION_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_HEALTH_NAVIGATION_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/systemmanagement" "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
cp "$repo/tests/qml/SystemHealthNavigation.qml" "$work/qml/shell.qml"

# Sync Sprint 2 S2-06 (docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md, upstream
# 0c9d07c/#287): the harness's SystemManagementModel exercises openHealth()
# for real, but targetScreen's actual fallback chain lives only in
# config/quickshell/shell.qml, which cannot be loaded standalone (it wires
# the whole desktop). Extract that one binding programmatically and inject
# it in place of the harness's placeholder, so this test is guaranteed to
# exercise the real production expression rather than a hand-copied one
# that could silently drift out of sync with it.
python3 - "$repo/config/quickshell/shell.qml" "$work/qml/shell.qml" <<'PY'
from pathlib import Path
import re
import sys
source = Path(sys.argv[1]).read_text()
block = source.split("    SystemManagementModel {", 1)[1].split("\n    }", 1)[0]
match = re.search(r"^        targetScreen: (.+)$", block, re.MULTILINE)
assert match is not None, "Missing production Health screen binding"
fixture = Path(sys.argv[2])
marker = "targetScreen: null // Inject the production shell binding before loading."
assert fixture.read_text().count(marker) == 1
fixture.write_text(fixture.read_text().replace(marker, "targetScreen: " + match.group(1)))
PY

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
timeout --foreground --kill-after=2s 20s env DISPLAY=":$display_number" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_RUNTIME_DIR="$work/runtime" QT_QPA_PLATFORMTHEME= \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/health-navigation.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Health navigation tests: PASS' "$work/health-navigation.log" ||
	grep -Eq 'Health navigation FAILED:|ReferenceError:|TypeError:|Binding loop' "$work/health-navigation.log"; then
	cat "$work/health-navigation.log" >&2
	exit 1
fi

printf 'Quickshell Health navigation screen routing: PASS\n'
