#!/bin/sh
# #460: lyona-update's runtime check (runtime_verify in lyona-install-verify.sh)
# checks the restarted Quickshell, not the one being stopped. The Control
# Center's restart-quickshell returns before its detached copy has stopped the
# old shell (#394), which still answered the check's IPC probe; and the check
# counted `pgrep -xc quickshell`, which also counts the quickshell command-line
# tool that copy runs to stop it, so a good rollback reported "found 2". The
# check now waits for the old shell to exit, and counts this session's managed
# instances by identity.

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

command -v jq >/dev/null 2>&1 || {
	printf 'SKIP: jq is unavailable\n'
	exit 77
}
command -v setsid >/dev/null 2>&1 || {
	printf 'SKIP: setsid is unavailable\n'
	exit 77
}

state=$work/state
prefix=$work/prefix
config_dir=$work/config/quickshell
output=$work/output
mkdir -p "$state" "$work/qs" "$work/stub-bin" "$config_dir"
: >"$config_dir/shell.qml"
# The verifier and, in lib/lyona, the lifecycle library it runs.
stage_helpers prefix "$prefix" lyona-install-verify.sh
# Instances: real processes named quickshell, owned by this user, as the
# lifecycle checks identity.
cp "$(command -v sleep)" "$work/qs/quickshell"
: >"$state/pids"
: >"$state/old"
: >"$state/asked"
# shellcheck disable=SC2016 # expanded when the cleanup runs
cleanup_add 'for p in $(cat "$state/all" 2>/dev/null); do kill "$p" 2>/dev/null || :; done'

# quickshell: lists the live pids of $state/pids, of every session; the tray
# probe of --pid answers with that pid, so the output names the shell that
# answered, and is logged; one by --path answers from the newest.
cat >"$work/stub-bin/quickshell" <<'STUB'
#!/bin/sh
live() {
	while read -r p; do
		kill -0 "$p" 2>/dev/null && printf '%s\n' "$p"
	done <"$STUB_STATE/pids"
}
case $1 in
list) live | jq -Rsc '[split("\n")[] | select(. != "") | {pid: tonumber}]' ;;
ipc)
	if [ "$2" = --pid ]; then
		printf '%s\n' "$3" >>"$STUB_STATE/asked"
		kill -0 "$3" 2>/dev/null || exit 1
		printf '%s\n' "$3"
	else
		newest=$(live | tail -n 1)
		[ -n "$newest" ] || exit 1
		printf '%s\n' "$newest"
	fi
	;;
kill) kill "$3" ;;
*) exit 2 ;;
esac
STUB
# Only dwm is asked for, and none runs: the restart is never deferred.
cat >"$work/stub-bin/pgrep" <<'STUB'
#!/bin/sh
case $* in
'-xo dwm') exit 1 ;;
*) exit 2 ;;
esac
STUB
# The Control Center's restart-quickshell: returns at once, and a detached copy
# runs the quickshell tool for a moment, stops the shells in $state/old and
# starts $STUB_STARTS new ones. With STUB_STARTS=keep it stops nothing.
cat >"$prefix/bin/dwm-quickshell-controlcenter" <<'STUB'
#!/bin/sh
[ "$*" = 'action restart-quickshell' ] || exit 2
setsid -f sh -c '
	old=$(cat "$STUB_STATE/old")
	[ "$STUB_STARTS" != keep ] || exit 0
	sleep 0.3
	"$STUB_QS" 1 &
	printf "%s\n" "$!" >>"$STUB_STATE/all"
	for p in $old; do quickshell kill --pid "$p"; done
	sleep 0.3
	i=0
	while [ "$i" -lt "$STUB_STARTS" ]; do
		"$STUB_QS" 60 &
		printf "%s\n" "$!" | tee -a "$STUB_STATE/all" >>"$STUB_STATE/pids"
		i=$((i + 1))
	done
' </dev/null >/dev/null 2>&1
printf 'action\trestart-quickshell\n'
STUB
chmod +x "$work/stub-bin/quickshell" "$work/stub-bin/pgrep" "$prefix/bin/dwm-quickshell-controlcenter"

# start_instance DISPLAY XDG_SESSION_ID [old]: old marks the one the restart stops.
start_instance() {
	env DISPLAY="$1" XDG_SESSION_ID="$2" "$work/qs/quickshell" 60 &
	instance_pid=$!
	printf '%s\n' "$instance_pid" >>"$state/pids"
	printf '%s\n' "$instance_pid" >>"$state/all"
	[ "${3:-}" != old ] || printf '%s\n' "$instance_pid" >>"$state/old"
	i=0
	while [ "$(readlink "/proc/$instance_pid/exe" 2>/dev/null)" != "$work/qs/quickshell" ]; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail 'the stand-in instance did not start'
		sleep 0.05
	done
}
stop_all() {
	while read -r p; do kill "$p" 2>/dev/null || :; done <"$state/all"
	: >"$state/pids"
	: >"$state/all"
	: >"$state/old"
	: >"$state/asked"
}

probe=$work/runtime-probe
sed -n -e '/^runtime_quickshell() {$/,/^}$/p' -e '/^runtime_verify() {$/,/^}$/p' \
	"$prefix/bin/lyona-install-verify.sh" >"$probe"
grep -q '^runtime_verify() {$' "$probe" || fail 'runtime_verify was not found'

# The new shells start as the instance the check runs in: display :7, session c1.
runtime_check() { # STARTS
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/stub-bin:$PATH" DISPLAY=:7 XDG_SESSION_ID=c1 STUB_STATE="$state" \
		STUB_QS="$work/qs/quickshell" STUB_STARTS="$1" DWM_DEV_SYNC_SKIP_RUNTIME=0 sh -c '
		set -eu
		. "$1"
		prefix=$2
		binary_target=$prefix/bin/dwm
		quickshell_dir=$3
		runtime_verify 1
	' sh "$probe" "$prefix" "$config_dir"
}

# A restart: the check sees the new shell, not the old one that still answers.
start_instance :7 c1 old
old_pid=$instance_pid
runtime_check 1 >"$output" 2>&1 || fail "a good restart failed the runtime check: $(cat "$output")"
new_pid=$(tail -n 1 "$state/pids")
[ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] || fail 'the stand-in restart started no new shell'
grep -Fqx "Quickshell IPC ready; tray items: $new_pid." "$output" ||
	fail "the check did not probe the restarted shell ($new_pid, old $old_pid): $(cat "$output")"
! grep -Fqx "$old_pid" "$state/asked" || fail 'the check probed the shell being stopped'
stop_all

# Another session's shells, on another display or of another login on this
# one, are not this session's to count or to probe, though they answer for
# the same config.
start_instance :8 c9
other_display=$instance_pid
start_instance :7 c2
other_login=$instance_pid
start_instance :7 c1 old
runtime_check 1 >"$output" 2>&1 || fail "another session's shell failed the check: $(cat "$output")"
! grep -Eqx "$other_display|$other_login" "$state/asked" || fail "the check probed another session's shell"
stop_all

# Two shells of this session after the restart: reported.
start_instance :7 c1 old
if runtime_check 2 >"$output" 2>&1; then
	fail 'two managed shells in this session passed the check'
fi
grep -Fq 'expected one managed Quickshell in this session, found 2' "$output" ||
	fail "two managed shells were not reported: $(cat "$output")"
stop_all

# An old shell that never stops: reported, not checked as if restarted.
start_instance :7 c1 old
if runtime_check keep >"$output" 2>&1; then
	fail 'a shell the restart did not stop passed the check'
fi
grep -Fq 'the previous Quickshell did not stop on restart' "$output" ||
	fail "the shell that did not stop was not reported: $(cat "$output")"
stop_all

printf 'The runtime check waits for the restarted Quickshell: PASS\n'
