#!/bin/sh

set -eu

# Sync Sprint 12 S12-20: the clock's month calendar. Runs dwm and the full
# managed Quickshell on an isolated Xvfb and D-Bus session, opens the calendar
# through its IPC target, and drives it with real key presses and a real click:
# it opens on today, Page Down and Home move a month and back, an arrow moves a
# day, and Escape and a click outside the card both close it. Then the weather
# (decision D-19): with its switch off, as it starts, the shell never asks for
# the weather; turned on, it asks once.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

for cmd in Xvfb xprop xdotool quickshell dbus-run-session python3; do
	command -v "$cmd" >/dev/null 2>&1 || {
		printf 'SKIP: %s is unavailable\n' "$cmd"
		exit 77
	}
done
[ -x "$repo/dwm" ] || {
	printf 'SKIP: dwm is not built (run make all)\n'
	exit 77
}
if [ "${DWM_CALENDAR_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_CALENDAR_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/calendar.XXXXXX")
pids=
cleanup() {
	status=$?
	set +e
	if [ "$status" -ne 0 ] && [ -f "$work/quickshell.log" ]; then
		tail -40 "$work/quickshell.log" >&2
	fi
	for pid in $pids; do kill "$pid" 2>/dev/null; done
	rm -rf "$work"
	exit "$status"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

home=$work/home
runtime=$work/runtime
mkdir -p "$home/.config/quickshell" "$home/.config/lyona" "$home/.cache" "$home/.local/share/checkout" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$home/.config/quickshell/"
cp "$repo/config/"*.toml "$home/.config/lyona/"
cp -a "$repo/scripts" "$home/.local/share/checkout/scripts"
export LYONA_DEV_SCRIPTS="$home/.local/share/checkout/scripts"
cp "$repo/lyona-toml" "$home/.local/share/checkout/scripts/.."
# The shell's weather helper is a stub that logs what it is asked, and answers
# as the real one does with no location set.
weather_log=$work/weather.log
: >"$weather_log"
cat >"$LYONA_DEV_SCRIPTS/lyona-weather" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >>"$weather_log"
case \$1 in
current) printf 'weather-protocol\t1\t0\nstate\tunconfigured\tSet a location\ncomplete\tcurrent\n' ;;
status) printf 'weather-settings-protocol\t1\t0\ncomplete\tstatus\n' ;;
esac
STUB
chmod +x "$LYONA_DEV_SCRIPTS/lyona-weather"

display=":$((($$ % 400) + 1100))"
Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
pids="$pids $!"
i=0
until DISPLAY=$display xprop -root >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'Xvfb did not start'
	sleep 0.05
done

run_env() {
	env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
		XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$runtime" \
		QSG_RHI_BACKEND=software QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME= \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 PATH="$repo/scripts:$PATH" "$@"
}
run_env "$repo/dwm" >"$work/dwm.log" 2>&1 &
pids="$pids $!"
run_env quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
pids="$pids $!"

calendar() {
	run_env quickshell ipc --path "$home/.config/quickshell/shell.qml" call calendar "$@" 2>/dev/null
}
# Wait until the shell answers, then for the calendar to reach the expected state.
wait_status() { # EXPECTED WHAT
	i=0
	until [ "$(calendar status || true)" = "$1" ]; do
		i=$((i + 1))
		[ "$i" -lt 200 ] || fail "$2: the calendar reports '$(calendar status || true)', expected '$1'"
		sleep 0.05
	done
}
# The date DELTA days or months from today, as status prints it, with the
# day kept where the month has it, as the calendar does.
expected() { # days|months DELTA
	python3 - "$1" "$2" <<'PY'
import calendar, datetime, sys
today = datetime.date.today()
kind, delta = sys.argv[1], int(sys.argv[2])
if kind == "days":
    d = today + datetime.timedelta(days=delta)
else:
    month = today.month - 1 + delta
    year, month = today.year + month // 12, month % 12 + 1
    d = datetime.date(year, month, min(today.day, calendar.monthrange(year, month)[1]))
print(f"open\t{d.year}-{d.month:02d}\t{d.day}")
PY
}

wait_status closed 'before it is opened'
calendar open >/dev/null
wait_status "$(expected days 0)" 'opened'

# Real key presses reach the popup, which takes the keyboard while it is open.
DISPLAY=$display xdotool key Next
wait_status "$(expected months 1)" 'Page Down'
DISPLAY=$display xdotool key Home
wait_status "$(expected days 0)" 'Home'
DISPLAY=$display xdotool key Right
wait_status "$(expected days 1)" 'Right'
DISPLAY=$display xdotool key Escape
wait_status closed 'Escape'

# A click outside the card, in the bottom-right corner of the screen, closes it.
calendar open >/dev/null
wait_status "$(expected days 0)" 'reopened'
DISPLAY=$display xdotool mousemove 1270 790 click 1
wait_status closed 'a click outside'

# The weather starts off: in all of the above, the shell never asked for it.
! grep -qx current "$weather_log" || fail 'the shell asked for the weather while its switch was off'
# Turned on, through the real helper, it asks once.
run_env "$LYONA_DEV_SCRIPTS/dwm-panel-settings" set weather enabled >/dev/null
i=0
until grep -qx current "$weather_log"; do
	i=$((i + 1))
	[ "$i" -lt 200 ] || fail 'the shell did not ask for the weather once its switch was on'
	sleep 0.05
done
sleep 1
[ "$(grep -cx current "$weather_log")" = 1 ] ||
	fail "the shell asked for the weather $(grep -cx current "$weather_log") times, not once"

grep -Eq 'ReferenceError|TypeError|Binding loop' "$work/quickshell.log" &&
	fail "the shell logged a QML error: $(grep -Em1 'ReferenceError|TypeError|Binding loop' "$work/quickshell.log")"

printf 'Quickshell calendar and weather: the calendar opens on today, keys move it, Escape and a click outside close it; the weather is not asked for until it is on: PASS\n'
