#!/bin/sh
# #394: a managed Quickshell that is running on this display but does not
# answer its IPC yet (still loading, or too busy to answer within the probe's
# second on a loaded login) is waited for, never stopped. Autostart restarted
# it, and so did a shell key pressed early (lyona-shell), killing a shell that
# was nearly up; under load the restart could be killed again in turn, and the
# key did nothing. An instance of another display is still replaced, and so
# is one of another logind session on this display (#448): a display manager
# gives the next login the display of a dead one, whose shell hung. With
# none running one is started, never restarted (a key's restart stopped the
# shell autostart had just started). A key whose call came just before the
# shell answered is asked again.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}

state=$work/state
mkdir -p "$state" "$work/qs" "$work/config/quickshell"
config=$work/config/quickshell/shell.qml
: >"$config"
# The instance: a real process named quickshell, owned by this user, as the
# lifecycle checks its identity.
cp "$(command -v sleep)" "$work/qs/quickshell"

# quickshell: lists the instance in $state/pid, if any; answers IPC only once
# $state/up exists, and the tray probe brings it up on the probe numbered
# $state/up-after; logs kills and starts.
cat >"$work/bin/quickshell" <<'STUB'
#!/bin/sh
case $1 in
list)
	if [ -s "$STUB_STATE/pid" ]; then
		printf '[{"pid": %s}]\n' "$(cat "$STUB_STATE/pid")"
	else
		printf '[]\n'
	fi
	;;
ipc)
	case $* in
	*' call tray count')
		count=$(($(cat "$STUB_STATE/probes" 2>/dev/null || printf 0) + 1))
		printf '%s\n' "$count" >"$STUB_STATE/probes"
		[ "$count" -lt "$(cat "$STUB_STATE/up-after" 2>/dev/null || printf 999)" ] ||
			: >"$STUB_STATE/up"
		;;
	*)
		call=$*
		[ ! -e "$STUB_STATE/up" ] || printf 'call %s\n' "${call##* call }" >>"$STUB_STATE/log"
		;;
	esac
	[ -e "$STUB_STATE/up" ]
	;;
kill)
	printf 'kill %s\n' "$3" >>"$STUB_STATE/log"
	kill "$3"
	;;
*) printf 'start %s\n' "$*" >>"$STUB_STATE/log" ;;
esac
STUB
cat >"$work/bin/dwm-quickshell-controlcenter" <<'STUB'
#!/bin/sh
printf 'restart %s\n' "$*" >>"$STUB_STATE/log"
STUB
cat >"$work/bin/xmessage" <<'STUB'
#!/bin/sh
STUB
chmod +x "$work/bin/quickshell" "$work/bin/dwm-quickshell-controlcenter" "$work/bin/xmessage"

instance_pid=
start_instance() { # DISPLAY [XDG_SESSION_ID]
	env -u XDG_SESSION_ID DISPLAY="$1" ${2:+XDG_SESSION_ID="$2"} "$work/qs/quickshell" 60 &
	instance_pid=$!
	printf '%s\n' "$instance_pid" >"$state/pid"
	cleanup_add "kill $instance_pid 2>/dev/null || :"
	# Until it is the copy named quickshell, not the shell that forks it.
	i=0
	while [ "$(readlink "/proc/$instance_pid/exe" 2>/dev/null)" != "$work/qs/quickshell" ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail 'the stand-in instance did not start'
		sleep 0.05
	done
}
reset_state() {
	rm -f "$state/log" "$state/probes" "$state/up" "$state/up-after" "$state/pid"
}
log() { cat "$state/log" 2>/dev/null || :; }

# start_managed_quickshell, as autostart runs it at login.
autostart_start() { # DISPLAY [XDG_SESSION_ID]
	# shellcheck disable=SC2016 # expanded by the inner shell
	env -u XDG_SESSION_ID PATH="$work/bin:$PATH" DISPLAY="$1" ${2:+XDG_SESSION_ID="$2"} \
		STUB_STATE="$state" lyona_lib="$repo/scripts" sh -c '
		. "$lyona_lib/dwm-quickshell-lifecycle.sh"
		launch() { "$@"; }
		start_managed_quickshell "$1" launch
	' sh "$config"
}

# This display's instance, not answering yet: kept, and no second one started.
reset_state
start_instance :7
autostart_start :7 || fail 'start_managed_quickshell failed'
[ -z "$(log)" ] || fail "autostart stopped or restarted a starting shell: $(log)"
kill -0 "$instance_pid" 2>/dev/null || fail 'the starting shell was stopped'
kill "$instance_pid"
wait "$instance_pid" 2>/dev/null || :

# Another display's instance: replaced, as before.
reset_state
start_instance :8
autostart_start :7 || fail 'start_managed_quickshell failed'
log | grep -Fqx "kill $instance_pid" || fail "another display's instance was not stopped: $(log)"
log | grep -Fqx "start --path $config --no-duplicate" || fail "no shell was started: $(log)"
wait "$instance_pid" 2>/dev/null || :

# This display's instance of this logind session: kept. So is one when either
# side names no session, as only the display can tell then.
for sessions in 'c1 c1' 'c1 -' '- c1'; do
	reset_state
	instance_session=${sessions% *}
	login_session=${sessions#* }
	start_instance :7 "${instance_session#-}"
	autostart_start :7 "${login_session#-}" || fail 'start_managed_quickshell failed'
	[ -z "$(log)" ] || fail "sessions $sessions: autostart stopped this session's shell: $(log)"
	kill "$instance_pid"
	wait "$instance_pid" 2>/dev/null || :
done

# This display's instance of another logind session, a dead login's: replaced.
reset_state
start_instance :7 c1
autostart_start :7 c2 || fail 'start_managed_quickshell failed'
log | grep -Fqx "kill $instance_pid" || fail "a dead login's shell on this display was not stopped: $(log)"
log | grep -Fqx "start --path $config --no-duplicate" || fail "no shell was started past a dead login's: $(log)"
wait "$instance_pid" 2>/dev/null || :

# None running: started.
reset_state
autostart_start :7 || fail 'start_managed_quickshell failed'
[ "$(log)" = "start --path $config --no-duplicate" ] || fail "with no shell, autostart ran: $(log)"

# A shell key pressed while this display's shell is starting: lyona-shell waits
# for it and then does what the key asks, with no restart.
reset_state
start_instance :7
printf '3\n' >"$state/up-after"
env PATH="$work/bin:$PATH" DISPLAY=:7 XDG_CONFIG_HOME="$work/config" STUB_STATE="$state" \
	LYONA_SHELL_RESTART_WAIT=5 "$repo/scripts/lyona-shell" launcher toggle 2>"$work/err" ||
	fail "the key failed while the shell was starting: $(cat "$work/err")"
[ "$(log)" = 'call launcher toggle' ] || fail "lyona-shell did not wait for the starting shell: $(log)"
grep -Fq 'still starting; waiting for it' "$work/err" || fail "the wait was not announced: $(cat "$work/err")"
kill -0 "$instance_pid" 2>/dev/null || fail 'lyona-shell stopped the starting shell'
kill "$instance_pid"
wait "$instance_pid" 2>/dev/null || :

# A key pressed as the shell finished starting: the call found no shell, the
# probe right after it did. The key is asked again, not dropped.
reset_state
printf '1\n' >"$state/up-after"
env PATH="$work/bin:$PATH" DISPLAY=:7 XDG_CONFIG_HOME="$work/config" STUB_STATE="$state" \
	LYONA_SHELL_RESTART_WAIT=5 "$repo/scripts/lyona-shell" launcher toggle 2>"$work/err" ||
	fail "the key failed as the shell came up: $(cat "$work/err")"
[ "$(log)" = 'call launcher toggle' ] || fail "the key was dropped as the shell came up: $(log)"

# The same key with no shell running still starts one.
reset_state
env PATH="$work/bin:$PATH" DISPLAY=:7 XDG_CONFIG_HOME="$work/config" STUB_STATE="$state" \
	LYONA_SHELL_RESTART_WAIT=1 "$repo/scripts/lyona-shell" launcher toggle 2>/dev/null || :
log | grep -Fqx 'restart action start-quickshell' || fail "with no shell, lyona-shell did not start one: $(log)"

printf 'A starting Quickshell is waited for, not restarted: PASS\n'
