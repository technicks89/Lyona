#!/bin/sh
# #461: install-user replaces ~/.config/quickshell through
# replace-quickshell-config.sh. The new tree is swapped in whole, and this
# session's shell is stopped first and started again after only when it still
# watches its config files (a release older than #461): Quickshell 0.3.2
# crashes when a shell that has hot-reloaded is stopped, as the restart after
# an update does. A shell that does not watch them, another session's, or one
# with no display to start it again on, is left running.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

state=$work/state
scripts=$work/scripts
mkdir -p "$state" "$work/qs" "$work/stub-bin" "$work/src/core"
stage_helpers checkout "$scripts" replace-quickshell-config.sh
printf '%s\n' 'import Quickshell' 'ShellRoot {' \
	'    Component.onCompleted: Quickshell.watchFiles = false' '}' >"$work/src/shell.qml"
printf 'new theme\n' >"$work/src/core/Theme.qml"
# The instance: a real process named quickshell, owned by this user, as the
# lifecycle checks identity.
cp "$(command -v sleep)" "$work/qs/quickshell"

# quickshell: lists the instance in $state/pid, if any; logs kills.
cat >"$work/stub-bin/quickshell" <<'STUB'
#!/bin/sh
case $1 in
list)
	if [ -s "$STUB_STATE/pid" ]; then
		printf '[{"pid": %s}]\n' "$(cat "$STUB_STATE/pid")"
	else
		printf '[]\n'
	fi
	;;
kill)
	printf 'kill %s\n' "$3" >>"$STUB_STATE/log"
	kill "$3"
	;;
*) exit 2 ;;
esac
STUB
# The Control Center beside the script: logs what it is asked.
cat >"$scripts/dwm-quickshell-controlcenter" <<'STUB'
#!/bin/sh
printf 'controlcenter %s\n' "$*" >>"$STUB_STATE/log"
STUB
chmod +x "$work/stub-bin/quickshell" "$scripts/dwm-quickshell-controlcenter"

instance_pid=
start_instance() { # DISPLAY
	env -u XDG_SESSION_ID DISPLAY="$1" "$work/qs/quickshell" 60 &
	instance_pid=$!
	printf '%s\n' "$instance_pid" >"$state/pid"
	cleanup_add "kill $instance_pid 2>/dev/null || :"
	i=0
	while [ "$(readlink "/proc/$instance_pid/exe" 2>/dev/null)" != "$work/qs/quickshell" ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail 'the stand-in instance did not start'
		sleep 0.05
	done
}
# live_tree WATCHES: the live config, from an older release (yes) or not (no).
live_tree() {
	rm -rf "$work/config"
	mkdir -p "$work/config/quickshell/core"
	if [ "$1" = yes ]; then
		printf '%s\n' 'import Quickshell' 'ShellRoot {}' >"$work/config/quickshell/shell.qml"
	else
		cp "$work/src/shell.qml" "$work/config/quickshell/shell.qml"
	fi
	printf 'old theme\n' >"$work/config/quickshell/core/Theme.qml"
	printf 'stale\n' >"$work/config/quickshell/stale.qml"
}
reset_state() { rm -f "$state/log" "$state/pid"; }
log() { cat "$state/log" 2>/dev/null || :; }
replace() { # [DISPLAY]
	env -u XDG_SESSION_ID ${1:+DISPLAY="$1"} PATH="$work/stub-bin:$PATH" STUB_STATE="$state" \
		"$scripts/replace-quickshell-config.sh" "$work/src" "$work/config/quickshell" >"$work/out" 2>&1 ||
		fail "replace-quickshell-config.sh failed: $(cat "$work/out")"
}
assert_replaced() {
	assert_equals 'new theme' "$(cat "$work/config/quickshell/core/Theme.qml")" 'the new tree is in place'
	assert_no_file "$work/config/quickshell/stale.qml" 'a file of the old tree is gone'
	[ "$(find "$work/config" -mindepth 1 -maxdepth 1)" = "$work/config/quickshell" ] ||
		fail "the swap left something behind: $(ls -a "$work/config")"
}

# An older shell of this session, which watches its files: stopped before the
# swap and started again after.
reset_state
live_tree yes
start_instance :7
replace :7
assert_replaced
log | grep -Fqx "kill $instance_pid" || fail "the watching shell was not stopped: $(log)"
[ "$(log | tail -n 1)" = 'controlcenter action start-quickshell' ] ||
	fail "the stopped shell was not started again after the swap: $(log)"
wait "$instance_pid" 2>/dev/null || :

# A shell of #461 or later does not watch its files: left running.
reset_state
live_tree no
start_instance :7
replace :7
assert_replaced
[ -z "$(log)" ] || fail "a shell that does not watch its files was stopped or started: $(log)"
kill -0 "$instance_pid" 2>/dev/null || fail 'a shell that does not watch its files was stopped'
kill "$instance_pid"
wait "$instance_pid" 2>/dev/null || :

# Another session's shell, or no display to start one again on: left running.
for display in :7 ''; do
	reset_state
	live_tree yes
	start_instance :8
	replace "$display"
	assert_replaced
	[ -z "$(log)" ] || fail "display '$display': a shell this install could not restart was stopped: $(log)"
	kill "$instance_pid"
	wait "$instance_pid" 2>/dev/null || :
done

# The swap fails where the filesystem cannot exchange: the old tree is put
# back, the script fails, and the shell it stopped is started again.
reset_state
live_tree yes
start_instance :7
mkdir -p "$work/no-swap"
cat >"$work/no-swap/mv" <<'STUB'
#!/bin/sh
[ "$1" != --exchange ] || exit 1
case $2 in */.quickshell.new) exit 1 ;; esac
exec /usr/bin/mv "$@"
STUB
chmod +x "$work/no-swap/mv"
if env -u XDG_SESSION_ID DISPLAY=:7 PATH="$work/no-swap:$work/stub-bin:$PATH" STUB_STATE="$state" \
	"$scripts/replace-quickshell-config.sh" "$work/src" "$work/config/quickshell" >"$work/out" 2>&1; then
	fail 'a swap that failed was reported as done'
fi
assert_equals 'old theme' "$(cat "$work/config/quickshell/core/Theme.qml")" 'a failed swap puts the old tree back'
[ "$(log | tail -n 1)" = 'controlcenter action start-quickshell' ] ||
	fail "the shell stopped for a failed swap was not started again: $(log)"
wait "$instance_pid" 2>/dev/null || :

# No live tree yet: moved into place.
reset_state
rm -rf "$work/config"
mkdir -p "$work/config"
replace :7
assert_equals 'new theme' "$(cat "$work/config/quickshell/core/Theme.qml")" 'a first install puts the tree in place'
[ -z "$(log)" ] || fail "a first install stopped or started a shell: $(log)"

printf 'The managed Quickshell config is swapped in whole, an older shell stopped first: PASS\n'
