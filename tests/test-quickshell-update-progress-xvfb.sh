#!/bin/sh
set -eu

# The update progress popup, the panel indicator and the bounded log view,
# driven through the same status and log files lyona-update writes. The shell
# starts with an update already in flight, as it does after the Quickshell
# restart that an apply causes.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3 tail; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_UPDATE_PROGRESS_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_UPDATE_PROGRESS_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
python3 "$repo/tests/fixtures/update-progress.py" "$work/qml" "$repo/tests/qml/UpdateProgress.inc"

# An update in flight (written just now, so it counts as running) and the log
# it has produced so far.
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf 'lyona-update-status-protocol\t1\t0\nphase\tinstalling\tInstalling 2026.10.0\ntarget\t2026.10.0\noutcome\tpending\t\ntimestamp\t%s\ncomplete\tstatus\n' \
	"$now" >"$work/state/lyona/update.status"
printf '%s apply started\nfixture log line one\nfixture log line two\n' "$now" >"$work/state/lyona/update.log"

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
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Update progress: PASS' "$work/ui.log" ||
	grep -Eq 'Update progress FAILED:|ReferenceError:|TypeError:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Update progress surfaces: PASS\n'
