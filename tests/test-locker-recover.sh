#!/usr/bin/env bash
# shellcheck disable=SC2016 # the stand-ins' bodies expand when they run
set -euo pipefail

# light-locker's leftover blanking windows (#416): dwm-settings-power
# recover-locker restarts light-locker only when it runs for this display, says
# it is inactive and still shows its windows; never while it is blanking or
# locked. The autorandr hook 60-lyona-locker runs it after a layout change.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
helper=$repo/scripts/dwm-settings-power
hook=$repo/config/autorandr/60-lyona-locker
bin=$work/bin
mkdir -p "$bin" "$work/run" "$work/home"

# Stand-ins. "running" says light-locker runs, "active" that it is blanking or
# locked, "windows" that its windows are shown. Every call is logged.
stub() { # NAME BODY
	printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >>"$STUB_DIR/calls"\n%s\n' "$1" "$2" >"$bin/$1"
	chmod +x "$bin/$1"
}
stub pgrep '[ "$*" = "-u $(id -u) -x light-locker --env DISPLAY=:77" ] && [ -e "$STUB_DIR/running" ]'
# "interrupt": recover-locker is asked to stop (TERM) while it stops
# light-locker; timeout's parent is recover-locker.
stub pkill '[ -e "$STUB_DIR/stopfails" ] || rm -f "$STUB_DIR/running" "$STUB_DIR/windows"
if [ -e "$STUB_DIR/interrupt" ]; then
	read -r _ _ _ helper_pid _ <"/proc/$PPID/stat"
	kill -TERM "$helper_pid"
fi'
stub setsid '[ "$*" = "-f light-locker" ] && [ ! -e "$STUB_DIR/startfails" ] && : >"$STUB_DIR/running"'
stub light-locker ':'
# "activates": inactive at the first query, active from the second on.
# "failsecond": the second query still prints inactive, but fails.
stub light-locker-command 'if [ -e "$STUB_DIR/noquery" ]; then exit 1; fi
if [ -e "$STUB_DIR/failsecond" ]; then
	if [ -e "$STUB_DIR/queried" ]; then echo "The screensaver is inactive"; exit 1; fi
	: >"$STUB_DIR/queried"
fi
if [ -e "$STUB_DIR/activates" ]; then
	[ -e "$STUB_DIR/queried" ] && : >"$STUB_DIR/active"
	: >"$STUB_DIR/queried"
fi
if [ -e "$STUB_DIR/active" ]; then echo "The screensaver is active"; else echo "The screensaver is inactive"; fi'
stub xdotool '[ -e "$STUB_DIR/windows" ] && printf "4194305\n6291457\n"; :'

sys_path=/usr/bin:/bin
run() {
	env -i PATH="$bin:$sys_path" HOME="$work/home" STUB_DIR="$work" DISPLAY=:77 \
		XDG_RUNTIME_DIR="$work/run" XDG_CONFIG_HOME="$work/config" "$helper" recover-locker
}
setup() { # FLAGS...
	rm -f "$work"/{running,active,activates,failsecond,queried,windows,noquery,stopfails,startfails,interrupt,calls}
	: >"$work/calls"
	local flag
	for flag in "$@"; do : >"$work/$flag"; done
}
expect() { # RESULT DETAIL-FRAGMENT
	local out status=0
	out=$(run) || status=$?
	[[ $out == "locker-recover"$'\t'"$1"$'\t'*"$2"* ]] || fail "expected $1 ($2), got: $out (exit $status)"
	[[ $1 == failed ]] || ((status == 0)) || fail "$1 exited $status"
	[[ $1 != failed ]] || ((status != 0)) || fail 'a failed recovery exited 0'
}
not_restarted() {
	! grep -Eq '^(pkill|setsid) ' "$work/calls" || fail "light-locker was touched: $(cat "$work/calls")"
}

# The bug: inactive, with its windows still up. Restarted, detached.
setup running windows
expect restarted 'inactive with its blanking windows'
grep -Fxq 'setsid -f light-locker' "$work/calls" || fail "not restarted detached: $(cat "$work/calls")"
[[ -e $work/running ]] || fail 'light-locker is not running again'

# Asked to stop while it stops light-locker: light-locker is started again all
# the same, and then it stops (143), not before.
setup running windows interrupt
status=0
out=$(run) || status=$?
[[ $out == $'locker-recover\trestarted\t'* ]] || fail "interrupted: $out"
((status == 143)) || fail "an interrupted recovery exited $status"
[[ -e $work/running ]] || fail 'an interrupted recovery left light-locker stopped'
grep -Fxq 'setsid -f light-locker' "$work/calls" || fail "not restarted: $(cat "$work/calls")"

# Blanking or locked: active, and left alone, windows or not.
setup running windows active
expect none 'active'
not_restarted
# Turning active between the first query and the stop: left alone.
setup running windows activates
expect none 'became active'
not_restarted
# A second query that fails, whatever it printed: left alone.
setup running windows failsecond
expect none 'stopped answering'
not_restarted
# Inactive with no windows: the normal state.
setup running
expect none 'no light-locker windows'
not_restarted
# Not running for this display.
setup windows
expect none 'not running'
not_restarted
# A query that fails is no evidence.
setup running windows noquery
expect none 'did not say'
not_restarted
# A restart that fails says so, with the manual command.
setup running windows startfails
expect failed 'setsid -f light-locker'
setup running windows stopfails
expect failed 'could not be restarted'

# Without xdotool it does nothing and says why: the system's commands, less
# xdotool, and no stand-in for it.
mkdir -p "$work/sysbin"
for tool in /usr/bin/*; do
	[[ ${tool##*/} == xdotool ]] || ln -sf "$tool" "$work/sysbin/"
done
mv "$bin/xdotool" "$work/xdotool.off"
sys_path=$work/sysbin
setup running windows
expect unavailable 'xdotool'
not_restarted
sys_path=/usr/bin:/bin
mv "$work/xdotool.off" "$bin/xdotool"

# The hook. The stand-in recovery notes when it starts, waits for the test's
# gate, then notes that it ran; each hook is run with fd 8 on a FIFO, which its
# background work inherits, so the FIFO's reader ends when all of it has ended.
cat >"$work/fake-power" <<'STUB'
#!/bin/sh
printf '%s %s\n' "$(date +%s%N)" "${DISPLAY:-none}" >>"$STUB_DIR/hook-entered"
[ ! -e "/proc/$$/fd/9" ] || echo 'fd 9 open' >>"$STUB_DIR/hook-fd"
i=0
while [ ! -e "$STUB_DIR/gate" ] && [ "$i" -lt 200 ]; do
	i=$((i + 1))
	sleep 0.05
done
printf '%s\n' "$*" >>"$STUB_DIR/hook-calls"
exit 1
STUB
chmod +x "$work/fake-power"
for phase in preswitch postswitch; do
	mkdir -p "$work/$phase.d"
	cp "$hook" "$work/$phase.d/60-lyona-locker"
done
wait_until() { # COMMAND...: up to 10 seconds
	local _
	for _ in $(seq 200); do
		"$@" && return 0
		sleep 0.05
	done
	return 1
}
lines() { [[ -e $1 ]] && wc -l <"$1" || echo 0; }
has_lines() { [[ $(lines "$1") == "$2" ]]; } # FILE N, checked each time it is called
hook_reset() {
	rm -f "$work"/{gate,hook-entered,hook-calls,hook-fd} "$work"/done.*
}
start_hook() { # NAME PHASE SETTLE [VAR=VALUE...]: runs it; its background work ends the reader done.NAME
	local name=$1 phase=$2 settle=$3
	shift 3
	mkfifo "$work/done.$name"
	timeout 15 cat "$work/done.$name" >/dev/null &
	eval "reader_$name=$!"
	env -i PATH=/usr/bin:/bin STUB_DIR="$work" XDG_RUNTIME_DIR="$work/run" "$@" \
		LYONA_AUTORANDR_LOCKER_HELPER="$work/fake-power" LYONA_AUTORANDR_LOCKER_SETTLE="$settle" \
		"$work/$phase.d/60-lyona-locker" 8>"$work/done.$name" || fail "the $phase hook failed"
}
hook_ended() { # NAME: its background work has ended, in time
	local pid
	eval "pid=\$reader_$1"
	wait "$pid" || fail "the $1 hook's recovery did not end"
}
reader_running() { # NAME
	local pid
	eval "pid=\$reader_$1"
	kill -0 "$pid" 2>/dev/null
}

# From either phase: the hook returns at once, and the recovery runs after the
# settle delay, without the lock's descriptor.
for phase in preswitch postswitch; do
	hook_reset
	started=$(date +%s%N)
	start_hook one "$phase" 0.3
	[[ ! -e $work/hook-calls ]] || fail "the $phase hook waited for the recovery"
	wait_until test -e "$work/hook-entered" || fail "the $phase hook did not start the recovery"
	entered=$(cut -d' ' -f1 "$work/hook-entered")
	((entered - started >= 300000000)) || fail "the $phase hook did not wait before recovering"
	: >"$work/gate"
	hook_ended one
	[[ $(cat "$work/hook-calls") == recover-locker ]] || fail "the $phase hook did not run recover-locker"
	[[ ! -e $work/hook-fd ]] || fail 'the recovery inherited the lock'
done

# Both phases at once on one display: one recovery runs, the other skips.
hook_reset
start_hook a preswitch 0 DISPLAY=:5
start_hook b postswitch 0 DISPLAY=:5
wait_until has_lines "$work/hook-entered" 1 || fail 'no overlapping hook started a recovery'
# The one that lost the lock ends while the other waits at the gate.
wait_until eval '! reader_running a || ! reader_running b' || fail 'the second overlapping hook did not skip'
: >"$work/gate"
hook_ended a
hook_ended b
[[ $(lines "$work/hook-calls") == 1 ]] || fail "two overlapping hooks ran $(lines "$work/hook-calls") recoveries"

# Two displays: each has its own lock, so both recover.
hook_reset
start_hook a preswitch 0 DISPLAY=:5
start_hook b preswitch 0 DISPLAY=:6
wait_until has_lines "$work/hook-entered" 2 || fail "a second display's recovery was locked out: $(cat "$work/hook-entered" 2>/dev/null)"
: >"$work/gate"
hook_ended a
hook_ended b
[[ $(lines "$work/hook-calls") == 2 ]] || fail 'both displays did not recover'

# Without the helper it does nothing, successfully.
env -i PATH=/nonexistent LYONA_AUTORANDR_LOCKER_HELPER="$work/missing" /bin/sh "$hook" || fail 'the hook failed without its helper'

printf 'Locker recovery (#416): PASS\n'
