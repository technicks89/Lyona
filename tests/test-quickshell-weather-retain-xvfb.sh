#!/bin/sh
set -eu

# A failed weather refresh keeps the last good report, marked stale, and
# "Unavailable" shows only when there is none; changing the location or turning
# the widget off drops the report (#480). Driven through the real WeatherModel
# with its helper replaced by a stub that answers a fixed sequence.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_WEATHER_RETAIN_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_WEATHER_RETAIN_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
	"$work/data/checkout/scripts" "$work/runtime" "$work/state/lyona" "$work/stub"
# Helpers are no longer looked up in a per-user copy; the developer override
# names the directory holding this test's helpers (Sync Sprint 12 S12-13).
export LYONA_DEV_SCRIPTS="$work/data/checkout/scripts"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
cp "$repo/tests/fixtures/weather-retain-stub.sh" "$work/data/checkout/scripts/lyona-weather"
chmod +x "$work/data/checkout/scripts/lyona-weather"
printf 'Berlin\n' >"$work/stub/location"
printf '%s\n' 'ok 21.5 Berlin' fail fail 'ok 10 Paris' fail >"$work/stub/script"
python3 "$repo/tests/fixtures/weather-retain.py" "$work/qml" "$repo/tests/qml/WeatherRetain.inc"

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
	WEATHER_STUB_DIR="$work/stub" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Weather retain: PASS' "$work/ui.log" ||
	grep -Eq 'Weather retain FAILED|ReferenceError:|TypeError:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	[ ! -f "$work/stub/current.log" ] || cat "$work/stub/current.log" >&2
	exit 1
fi
# Exactly the five scripted reads: no extra request, no retry loop.
[ "$(wc -l <"$work/stub/current.log")" -eq 5 ] || {
	printf 'expected 5 weather reads, got:\n' >&2
	cat "$work/stub/current.log" >&2
	exit 1
}
printf 'Weather retain: PASS\n'
