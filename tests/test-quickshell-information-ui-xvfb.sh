#!/bin/sh
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_INFORMATION_UI_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_INFORMATION_UI_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
cp -a "$repo/config/quickshell/core" "$repo/config/quickshell/settings" "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
cp "$repo/tests/qml/SystemInformationUi.qml" "$work/qml/shell.qml"

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

# Sync Sprint 2 S2-06 (docs/SYNC-SPRINT-2-SYSTEM-INFORMATION.md, upstream
# cc96efd/#287): a pure information-view fixture (bounded 256-row mount
# inventory, unknown-value rendering, keyboard-focus reveal, health
# navigation availability) at three viewport sizes, matching upstream's own
# evidence captures.
for size in 640x480 780x580 1000x740; do
	width=${size%x*}
	height=${size#*x}
	status=0
	timeout --foreground --kill-after=2s 15s env DISPLAY=":$display_number" HOME="$work/home" \
		XDG_CONFIG_HOME="$work/home/.config" XDG_RUNTIME_DIR="$work/runtime" QT_QPA_PLATFORMTHEME= \
		DWM_INFORMATION_UI_WIDTH="$width" DWM_INFORMATION_UI_HEIGHT="$height" \
		quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/information-ui-$size.log" 2>&1 || status=$?
	if [ "$status" -ne 0 ] || ! grep -F 'Information UI tests: PASS' "$work/information-ui-$size.log" ||
		grep -Eq 'Information UI FAILED:|ReferenceError:|TypeError:|Binding loop' "$work/information-ui-$size.log"; then
		cat "$work/information-ui-$size.log" >&2
		exit 1
	fi
done

printf 'Quickshell system information view: PASS\n'
