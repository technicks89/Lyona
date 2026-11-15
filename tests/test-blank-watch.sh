#!/usr/bin/env bash
# shellcheck disable=SC2016 # the stand-ins' bodies expand when they run
set -euo pipefail

# dwm-blank-watch (#416): when light-locker stops blanking (ActiveChanged
# false on the session bus), it runs recover-locker once, after a moment, under
# the per-display lock the autorandr hook also takes, passing neither lock on;
# blanking starting (true) does nothing; one watcher runs per display; it ends
# with its X display, and so does a recovery it is running.

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
# The recovery: notes whether it got either lock's descriptor, then its call
# (so "calls" means the check is done), then waits for the gate.
cat >"$work/fake-power" <<'STUB'
#!/bin/sh
for fd in 8 9; do [ ! -e "/proc/$$/fd/$fd" ] || echo "fd $fd open" >>"$STUB_DIR/fd"; done
echo $$ >"$STUB_DIR/power-pid"
printf '%s %s\n' "$*" "$DISPLAY" >>"$STUB_DIR/calls"
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

# A second watcher on this display exits at once.
env -i PATH="$bin:/usr/bin:/bin" STUB_DIR="$work" DISPLAY=:7 XDG_RUNTIME_DIR="$work/run" \
	DWM_BLANK_WATCH_HELPER="$work/fake-power" timeout 5 "$watch" || fail 'a second watcher did not exit at once'

# Blanking starts, then ends: one recovery, on this display, after the settle
# delay. Events are handled in order, so once the second one's recovery is
# done the first was handled too, and ran nothing.
started=$(date +%s%N)
signal org.freedesktop.ScreenSaver true
signal org.freedesktop.ScreenSaver false
wait_until test -e "$work/calls" || fail 'the end of blanking ran no recovery'
((($(date +%s%N) - started) >= 300000000)) || fail 'it did not wait before recovering'
[[ ! -e $work/fd ]] || fail "the recovery inherited a lock: $(cat "$work/fd")"
: >"$work/gate"
wait_until test -e "$work/logged" || fail 'the result was not logged'
grep -Fq 'after an idle blank: locker-recover' "$work/logged" || fail "logged: $(cat "$work/logged")"
[[ $(cat "$work/calls") == 'recover-locker :7' ]] || fail "blanking starting ran a recovery too: $(cat "$work/calls")"

# With the hook's lock held on this display, the next one skips, and says so.
rm -f "$work/calls" "$work/gate" "$work/logged"
exec 7>>"$work/run/lyona-locker-recover._7.lock"
flock -n 7 || fail 'could not take the lock'
signal org.gnome.ScreenSaver false
wait_until test -e "$work/logged" || fail 'nothing was logged while the hook held the lock'
grep -Fq 'skipped; another recovery is running' "$work/logged" || fail "logged: $(cat "$work/logged")"
[[ ! -e $work/calls ]] || fail 'a recovery ran while the hook held the lock'
exec 7>&-
# Released, and from the other interface: it runs again.
rm -f "$work/logged"
signal org.gnome.ScreenSaver false
wait_until has_lines "$work/calls" 1 || fail 'no recovery once the lock was free'
: >"$work/gate"
wait_until test -e "$work/logged" || fail 'the second recovery did not finish'

# The X display goes away: the watcher ends, and takes dbus-monitor with it.
rm -f "$work/x-alive"
wait_until eval '! kill -0 '"$watch_pid"' 2>/dev/null' || fail 'the watcher outlived its display'
wait "$watch_pid" || fail 'the watcher exited non-zero'
wait_until eval '! pgrep -f "tail -n \+1 -f $work/feed" >/dev/null' || fail 'dbus-monitor outlived the watcher'

# Stopped while a recovery waits on its helper: the helper goes with it, and
# both locks are free again.
rm -f "$work/calls" "$work/gate" "$work/logged" "$work/power-pid"
: >"$work/x-alive"
env -i PATH="$bin:/usr/bin:/bin" STUB_DIR="$work" DISPLAY=:7 XDG_RUNTIME_DIR="$work/run" \
	DWM_BLANK_WATCH_HELPER="$work/fake-power" DWM_BLANK_WATCH_SETTLE=0 "$watch" &
watch_pid=$!
wait_until test -e "$work/monitor-args" || fail 'the watcher did not start again'
signal org.freedesktop.ScreenSaver false
wait_until test -e "$work/power-pid" || fail 'no recovery started'
power_pid=$(cat "$work/power-pid")
kill -TERM "$watch_pid"
wait "$watch_pid" || :
wait_until eval '! kill -0 '"$power_pid"' 2>/dev/null' || fail 'the recovery outlived the watcher'
flock -n "$work/run/lyona-locker-recover._7.lock" true || fail 'the recovery lock was not released'
flock -n "$work/run/lyona-blank-watch._7.lock" true || fail 'the watcher lock was not released'
rm -f "$work/x-alive"

# No DISPLAY: it does nothing, successfully.
env -i PATH="$bin:/usr/bin:/bin" STUB_DIR="$work" "$watch" || fail 'it failed without a display'

printf 'Blank watch (#416): PASS\n'
