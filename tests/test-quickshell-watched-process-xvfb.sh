#!/bin/sh
set -eu

# Sync Sprint 12 S12-14 step 7: core/WatchedProcess.qml, which the resident
# watchers now share, run in a real Quickshell (tests/qml/WatchedProcessLines.qml).

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb quickshell timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/watched-process.XXXXXX")
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

mkdir -p "$work/qml" "$work/home/.config" "$work/runtime"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/core" "$work/qml/"
cp "$repo/tests/qml/WatchedProcessLines.qml" "$work/qml/shell.qml"

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

status=0
timeout --foreground --kill-after=2s 20s env DISPLAY=":$display_number" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_RUNTIME_DIR="$work/runtime" QT_QPA_PLATFORMTHEME= \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/watched.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'WatchedProcess tests: PASS' "$work/watched.log" ||
	grep -Eq 'WatchedProcess FAILED:|ReferenceError:|TypeError:|Binding loop' "$work/watched.log"; then
	cat "$work/watched.log" >&2
	exit 1
fi

printf 'WatchedProcess lines, settle and restart: PASS\n'
