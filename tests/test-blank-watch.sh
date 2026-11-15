#!/usr/bin/env bash
# shellcheck disable=SC2016 # the stand-ins' bodies expand when they run
set -euo pipefail

# dwm-blank-watch (#416): when light-locker stops blanking (ActiveChanged
# false on the session bus), it runs recover-locker once, after a moment, under
# the per-display lock the autorandr hook also takes, without passing that lock
# on; blanking starting (true) does nothing; it ends with its X display.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
watch=$repo/scripts/dwm-blank-watch
bin=$work/bin
mkdir -p "$bin" "$work/run"

# dbus-monitor follows a feed file the test appends to; xprop stays until the
# test removes "x-alive" (the X display going away); logger keeps its lines.
cat >"$bin/dbus-monitor" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_DIR/monitor-args"
exec tail -n +1 -f "$STUB_DIR/feed"
STUB
cat >"$bin/xprop" <<'STUB'
#!/bin/sh
while [ -e "$STUB_DIR/x-alive" ]; do sleep 0.05; done
STUB
cat >"$bin/logger" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/logged"
STUB
# The recovery: notes its call and whether it got the lock's descriptor, then
# waits for the gate, so a second one can be seen to skip.
cat >"$work/fake-power" <<'STUB'
#!/bin/sh
printf '%s %s\n' "$*" "$DISPLAY" >>"$STUB_DIR/calls"
[ ! -e "/proc/$$/fd/9" ] || echo 'fd 9 open' >>"$STUB_DIR/fd"
i=0
while [ ! -e "$STUB_DIR/gate" ] && [ "$i" -lt 200 ]; do
	i=$((i + 1))
	sleep 0.05
done
printf 'locker-recover\tnone\tstub\n'
STUB
chmod +x "$bin"/* "$work/fake-power"

wait_until() { # COMMAND...: up to 10 seconds
	local _
	for _ in $(seq 200); do
		"$@" && return 0
		sleep 0.05
	done
	return 1
}
lines() { [[ -e $1 ]] && wc -l <"$1" || echo 0; }
has_lines() { [[ $(lines "$1") == "$2" ]]; }
signal() { # INTERFACE true|false
	printf 'signal time=1 sender=:1.9 -> destination=(null destination) serial=7 path=/x; interface=%s; member=ActiveChanged\n   boolean %s\n' \
		"$1" "$2" >>"$work/feed"
}

: >"$work/feed"
: >"$work/x-alive"
env -i PATH="$bin:/usr/bin:/bin" STUB_DIR="$work" DISPLAY=:7 XDG_RUNTIME_DIR="$work/run" \
	DWM_BLANK_WATCH_HELPER="$work/fake-power" DWM_BLANK_WATCH_SETTLE=0.3 "$watch" &
watch_pid=$!
wait_until test -e "$work/monitor-args" || fail 'the watcher did not start dbus-monitor'
grep -Fq "member='ActiveChanged',interface='org.freedesktop.ScreenSaver'" "$work/monitor-args" ||
	fail "it does not follow ActiveChanged: $(cat "$work/monitor-args")"

# Blanking starts: nothing.
signal org.freedesktop.ScreenSaver true
sleep 0.6
[[ ! -e $work/calls ]] || fail "blanking starting ran a recovery: $(cat "$work/calls")"

# Blanking ends: one recovery on this display, after the settle delay.
started=$(date +%s%N)
signal org.freedesktop.ScreenSaver false
wait_until test -e "$work/calls" || fail 'the end of blanking ran no recovery'
((($(date +%s%N) - started) >= 300000000)) || fail 'it did not wait before recovering'
[[ $(cat "$work/calls") == 'recover-locker :7' ]] || fail "the recovery: $(cat "$work/calls")"
[[ ! -e $work/fd ]] || fail 'the recovery inherited the lock'
: >"$work/gate"
wait_until test -e "$work/logged" || fail 'the result was not logged'
grep -Fq 'after an idle blank: locker-recover' "$work/logged" || fail "logged: $(cat "$work/logged")"

# With the hook's lock held on this display, the next one skips.
rm -f "$work/calls" "$work/gate" "$work/logged"
exec 7>>"$work/run/lyona-locker-recover._7.lock"
flock -n 7 || fail 'could not take the lock'
signal org.gnome.ScreenSaver false
sleep 1
[[ ! -e $work/calls ]] || fail 'a recovery ran while the hook held the lock'
exec 7>&-
# Released, and from the other interface: it runs again.
signal org.gnome.ScreenSaver false
wait_until has_lines "$work/calls" 1 || fail 'no recovery once the lock was free'
: >"$work/gate"

# The X display goes away: the watcher ends, and takes dbus-monitor with it.
rm -f "$work/x-alive"
wait_until eval '! kill -0 '"$watch_pid"' 2>/dev/null' || fail 'the watcher outlived its display'
wait "$watch_pid" || fail 'the watcher exited non-zero'
wait_until eval '! pgrep -f "tail -n \+1 -f $work/feed" >/dev/null' || fail 'dbus-monitor outlived the watcher'

# No DISPLAY: it does nothing, successfully.
env -i PATH="$bin:/usr/bin:/bin" STUB_DIR="$work" "$watch" || fail 'it failed without a display'

printf 'Blank watch (#416): PASS\n'
