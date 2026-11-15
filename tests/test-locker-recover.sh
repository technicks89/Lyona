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
stub pkill '[ -e "$STUB_DIR/stopfails" ] || rm -f "$STUB_DIR/running" "$STUB_DIR/windows"'
stub setsid '[ "$*" = "-f light-locker" ] && [ ! -e "$STUB_DIR/startfails" ] && : >"$STUB_DIR/running"'
stub light-locker ':'
stub light-locker-command 'if [ -e "$STUB_DIR/noquery" ]; then exit 1; fi
if [ -e "$STUB_DIR/active" ]; then echo "The screensaver is active"; else echo "The screensaver is inactive"; fi'
stub xdotool '[ -e "$STUB_DIR/windows" ] && printf "4194305\n6291457\n"; :'

sys_path=/usr/bin:/bin
run() {
	env -i PATH="$bin:$sys_path" HOME="$work/home" STUB_DIR="$work" DISPLAY=:77 \
		XDG_RUNTIME_DIR="$work/run" XDG_CONFIG_HOME="$work/config" "$helper" recover-locker
}
setup() { # FLAGS...
	rm -f "$work"/{running,active,windows,noquery,stopfails,startfails,calls}
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

# Blanking or locked: active, and left alone, windows or not.
setup running windows active
expect none 'active'
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

# The hook: runs the recovery after the settle delay, in the background, from
# either phase, and always exits 0.
cat >"$work/fake-power" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/hook-calls"
sleep "${FAKE_POWER_SLEEP:-0}"
exit 1
STUB
chmod +x "$work/fake-power"
for phase in preswitch postswitch; do
	mkdir -p "$work/$phase.d"
	cp "$hook" "$work/$phase.d/60-lyona-locker"
	rm -f "$work/hook-calls"
	env -i PATH=/usr/bin:/bin STUB_DIR="$work" XDG_RUNTIME_DIR="$work/run" LYONA_AUTORANDR_LOCKER_HELPER="$work/fake-power" \
		LYONA_AUTORANDR_LOCKER_SETTLE=0.2 "$work/$phase.d/60-lyona-locker" || fail "the $phase hook failed"
	[[ ! -e $work/hook-calls ]] || fail "the $phase hook did not wait before recovering"
	for _ in $(seq 50); do
		[[ -e $work/hook-calls ]] && break
		sleep 0.1
	done
	[[ $(cat "$work/hook-calls" 2>/dev/null) == recover-locker ]] || fail "the $phase hook did not run recover-locker"
done
# Both phases at once: one recovery runs, the other skips.
rm -f "$work/hook-calls"
for phase in preswitch postswitch; do
	env -i PATH=/usr/bin:/bin STUB_DIR="$work" XDG_RUNTIME_DIR="$work/run" FAKE_POWER_SLEEP=1 \
		LYONA_AUTORANDR_LOCKER_HELPER="$work/fake-power" LYONA_AUTORANDR_LOCKER_SETTLE=0.2 \
		"$work/$phase.d/60-lyona-locker" || fail "the $phase hook failed"
done
sleep 2
[[ $(wc -l <"$work/hook-calls") == 1 ]] || fail "two overlapping hooks ran $(wc -l <"$work/hook-calls") recoveries"
# Without the helper it does nothing, successfully.
env -i PATH=/nonexistent LYONA_AUTORANDR_LOCKER_HELPER="$work/missing" /bin/sh "$hook" || fail 'the hook failed without its helper'

printf 'Locker recovery (#416): PASS\n'
