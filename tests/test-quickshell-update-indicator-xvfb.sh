#!/bin/sh

set -eu

# Sync Sprint 15 S15-02 (decision D-25): the panel's updates-available
# indicator in the full managed shell, on an isolated Xvfb and D-Bus session.
# Its helper is a stub that logs each check and replays what the test asks, and
# whose network watch is a FIFO the test writes NetworkManager events into.
#
# - A connection event starts a check, and pending updates show the pill with
#   their count.
# - A real click on the pill opens Settings on System.
# - A check by hand (from Settings) finding nothing hides it.
# - A second connection event soon after does not check again.
# - "Show when current", set through the real helper, shows it with nothing to
#   install.
# - "Update packages" runs the real lyona-update-terminal, in a stub terminal
#   with a stub yay; the result reaches the shell, and the counts are read again
#   (S15-04).
# - The shell stays near idle while nothing happens.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

for cmd in Xvfb xprop xdotool quickshell dbus-run-session; do
	command -v "$cmd" >/dev/null 2>&1 || {
		printf 'SKIP: %s is unavailable\n' "$cmd"
		exit 77
	}
done
[ -x "$repo/dwm" ] || {
	printf 'SKIP: dwm is not built (run make all)\n'
	exit 77
}
if [ "${DWM_UPDATE_INDICATOR_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_UPDATE_INDICATOR_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/update-indicator.XXXXXX")
pids=
cleanup() {
	status=$?
	set +e
	if [ "$status" -ne 0 ] && [ -f "$work/quickshell.log" ]; then
		tail -40 "$work/quickshell.log" >&2
	fi
	exec 3>&- 2>/dev/null
	for pid in $pids; do kill "$pid" 2>/dev/null; done
	# Gone before the workspace is removed, so none of them writes into it again.
	for pid in $pids; do wait "$pid" 2>/dev/null; done
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
scripts=$home/.local/share/checkout/scripts
mkdir -p "$home/.config/quickshell" "$home/.config/lyona" "$home/.cache" "$home/.local/state" "${scripts%/*}" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$home/.config/quickshell/"
cp "$repo/config/"*.toml "$home/.config/lyona/"
cp -a "$repo/scripts" "$scripts"
cp "$repo/lyona-toml" "$scripts/.."
export LYONA_DEV_SCRIPTS="$scripts"

# The indicator's helper: check is the test's; the settings are the real
# helper's. The network helper is the test's: its snapshot reports the state in
# $net_state, and its monitor prints what the test writes to the FIFO, which
# makes the shell's NetworkModel read the snapshot again (Sync Sprint 16 R16-34:
# the indicator follows NetworkModel, not a watcher of its own).
mv "$scripts/lyona-update-indicator" "$scripts/lyona-update-indicator.real"
log=$work/checks.log
mode=$work/mode
fifo=$work/network.fifo
net_state=$work/network.state
# Connected from the start: the state found at login is not a connection
# coming up, so it does not check before the start delay.
printf 'connected\n' >"$net_state"
: >"$log"
printf 'updates\n' >"$mode"
mkfifo "$fifo"
cat >"$scripts/lyona-update-indicator" <<STUB
#!/bin/sh
case \$1 in
check)
	printf 'check\n' >>"$log"
	printf 'update-indicator-protocol\t1\t0\n'
	case \$(cat "$mode") in
	updates) printf 'provider\tsystem\tavailable\t3\t3 package updates\n' ;;
	*) printf 'provider\tsystem\tcurrent\t0\tPackages are up to date\n' ;;
	esac
	printf 'complete\tcheck\n'
	;;
*) exec "$scripts/lyona-update-indicator.real" "\$@" ;;
esac
STUB
chmod +x "$scripts/lyona-update-indicator"
cat >"$scripts/dwm-quickshell-network" <<STUB
#!/bin/sh
case \$1 in
snapshot)
	printf 'connectivity-protocol\t1\t0\n'
	printf 'provider\tnetwork\tavailable\tdelegated\ttest\n'
	printf 'network-state\t%s\n' "\$(cat "$net_state")"
	;;
monitor) exec cat "$fifo" ;;
status) printf 'NET test\n' ;;
esac
STUB
chmod +x "$scripts/dwm-quickshell-network"
# connect|disconnect: the state NetworkManager would report, and a monitor line.
network() {
	if [ "$1" = connect ]; then printf 'connected\n'; else printf 'disconnected\n'; fi >"$net_state"
	printf 'state changed\n' >&3
}
# A terminal and yay for "Update packages": the terminal runs the command it is
# given, and yay logs its arguments.
mkdir -p "$work/bin"
cat >"$work/bin/alacritty" <<'STUB'
#!/bin/bash
while (($# > 0)) && [[ $1 != -e ]]; do shift; done
shift
"$@" </dev/null
STUB
cat >"$work/bin/yay" <<STUB
#!/bin/sh
printf 'yay %s\n' "\$*" >>"$work/yay.log"
STUB
chmod +x "$work/bin/alacritty" "$work/bin/yay"
# The release check: current, so the count is the packages alone.
cat >"$scripts/lyona-update" <<'STUB'
#!/bin/sh
case $1 in
check) printf 'lyona-update-protocol\t1\t0\nstate\tcurrent\tUp to date\ncomplete\tcheck\n' ;;
esac
STUB
chmod +x "$scripts/lyona-update"

display=":$((($$ % 400) + 1500))"
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
		DWM_AUTOSTART_NO_INPUT_WATCH=1 LYONA_SHELL_TEST_IPC=1 DWM_TERMINAL=alacritty \
		PATH="$work/bin:$repo/scripts:$PATH" "$@"
}
run_env "$repo/dwm" >"$work/dwm.log" 2>&1 &
pids="$pids $!"
run_env quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
shell_pid=$!
pids="$pids $shell_pid"

ipc() {
	run_env quickshell ipc --path "$home/.config/quickshell/shell.qml" call "$@" 2>/dev/null
}
wait_for() { # EXPECTED WHAT COMMAND...
	expected=$1 what=$2
	shift 2
	i=0
	until [ "$("$@" || true)" = "$expected" ]; do
		i=$((i + 1))
		[ "$i" -lt 300 ] || fail "$what: got '$("$@" || true)', expected '$expected'"
		sleep 0.05
	done
}
checks() { grep -c . "$log" || true; }
tab=$(printf '\t')

wait_for "hidden${tab}0${tab}unknown${tab}6${tab}no" 'at start' ipc updateIndicatorTest status
[ "$(checks)" = 0 ] || fail 'the shell checked at once, before its start delay'
# The monitor holds the FIFO open for reading once it is running.
exec 3>"$fifo"

# Give NetworkModel time to read the login state before it changes.
sleep 1
[ "$(checks)" = 0 ] || fail 'the connection found at login ran a check'
network disconnect
sleep 1
network connect
wait_for "shown${tab}3${tab}available${tab}6${tab}no" 'after a connection event' ipc updateIndicatorTest status
[ "$(checks)" = 1 ] || fail "a connection event ran $(checks) checks, not one"

# A real click on the pill opens Settings on System.
center=$(ipc updateIndicatorTest pillCenter)
[ -n "$center" ] || fail 'the pill has no position'
# shellcheck disable=SC2086
DISPLAY=$display xdotool mousemove $center click 1
wait_for system 'the click on the pill' ipc settingsTest currentSection

# By hand: nothing left to install hides the pill.
printf 'none\n' >"$mode"
ipc updateIndicatorTest check >/dev/null
wait_for "hidden${tab}0${tab}current${tab}6${tab}no" 'a check by hand finding nothing' ipc updateIndicatorTest status
[ "$(checks)" = 2 ] || fail "expected two checks, saw $(checks)"

# Soon after a successful check, a connection coming back does not check again.
network disconnect
sleep 1
network connect
sleep 1
[ "$(checks)" = 2 ] || fail 'a second connection event checked again within the gap'

# "Show when current", through the real helper: the shell follows the file.
run_env "$scripts/lyona-update-indicator" set-show-when-current yes >/dev/null
wait_for "shown${tab}0${tab}current${tab}6${tab}yes" 'show when current' ipc updateIndicatorTest status
[ "$(stat -c %a "$home/.config/lyona/update-indicator.conf")" = 600 ] || fail 'the settings file is not private'

# "Update packages" in a terminal: the real helper, the tool's own command, the
# result in the shell, and a check once the terminal closes.
before_checks=$(checks)
ipc updateIndicatorTest updateInTerminal system >/dev/null
wait_for "idle${tab}system${tab}succeeded${tab}0${tab}tile${tab}rule" 'an update in a terminal' \
	ipc updateIndicatorTest terminalStatus
[ "$(cat "$work/yay.log")" = 'yay -Syu' ] || fail "yay was run as: $(cat "$work/yay.log" 2>/dev/null)"
i=0
until [ "$(checks)" -gt "$before_checks" ]; do
	i=$((i + 1))
	[ "$i" -lt 200 ] || fail 'the counts were not read again after the terminal closed'
	sleep 0.05
done

# Near idle with nothing happening: under 5% of one CPU over three seconds.
ticks() { awk '{ print $14 + $15 }' "/proc/$shell_pid/stat"; }
sleep 1
before=$(ticks)
sleep 3
after=$(ticks)
hz=$(getconf CLK_TCK)
[ $(((after - before) * 100)) -lt $((hz * 3 * 5)) ] ||
	fail "the shell used $((after - before)) ticks in 3 s at $hz Hz while idle"

grep -Eq 'ReferenceError|TypeError|Binding loop' "$work/quickshell.log" &&
	fail "the shell logged a QML error: $(grep -Em1 'ReferenceError|TypeError|Binding loop' "$work/quickshell.log")"

printf 'Quickshell update indicator: a connection checks, updates show a count, a click opens Settings > System, nothing to install hides it, a flapping connection does not re-check, show-when-current shows it, an update in a terminal reports its result, idle: PASS\n'
