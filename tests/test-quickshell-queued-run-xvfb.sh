#!/bin/sh
set -eu

# A refresh that arrives while a read is running is queued, the queued read starts
# once the first ends, and the "queued" flag clears only after that read has
# started (never before, and never on the process's running change). Driven
# through the real AutostartModel with its helper replaced by a slow stub.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_QUEUED_RUN_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_QUEUED_RUN_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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

mkdir -p "$work/qml" "$work/home/.config/lyona" \
	"$work/data/lyona/scripts" "$work/runtime" "$work/state/lyona"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
cp "$repo/tests/fixtures/queued-run-stub.sh" "$work/data/lyona/scripts/dwm-xdg-autostart"
chmod +x "$work/data/lyona/scripts/dwm-xdg-autostart"
python3 "$repo/tests/fixtures/queued-run.py" "$work/qml" "$repo/tests/qml/QueuedRun.inc"

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
timeout --foreground --kill-after=2s 60s env DISPLAY=":$display_number" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/data" \
	XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
	QUEUED_RUN_LOG="$work/reads.log" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Queued run: PASS' "$work/ui.log" ||
	grep -Eq 'Queued run FAILED:|ReferenceError:|TypeError:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Queued run: PASS\n'
