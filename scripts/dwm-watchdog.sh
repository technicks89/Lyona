# shellcheck shell=sh
#
# Bounded and parent-bound execution, shared by the Quickshell backend
# scripts. POSIX shell: all three callers are #!/bin/sh.
#
# Source it with the directory the caller lives in, which is scripts/ in the
# repo and PREFIX/bin once installed:
#
#     script_dir=${0%/*}
#     [ "$script_dir" != "$0" ] || script_dir=.
#     . "$script_dir/dwm-watchdog.sh"
#
# Defines run_bounded, run_parent_bound and bound_to_this_shell; sets nothing
# else.
#
# run_bounded honors a caller-set $bounded_foreground=1 (unset/0 otherwise,
# preserving every existing caller's behavior) to keep a nested timeout in
# the same process group as an encompassing one, rather than backgrounding
# its own.

run_bounded() {
	duration=$1
	shift
	status=0
	# Sync Sprint 2 S2-03: a caller that is itself already running under a
	# bounded, timeout-owned process group (dwm-system-management's
	# read_information_process()) sets bounded_foreground=1 first, so this
	# nested timeout stays inside that group instead of moving the X11/
	# GSettings probe outside its cleanup boundary.
	if [ "${bounded_foreground:-0}" = 1 ]; then
		timeout --foreground --signal=TERM --kill-after=2 "$duration" "$@" || status=$?
	else
		timeout --signal=TERM --kill-after=2 "$duration" "$@" || status=$?
	fi
	if [ "$status" -eq 124 ]; then
		printf 'operation timed out after %s seconds\n' "$duration" >&2
	fi
	return "$status"
}

# parent_bound_record PID: print "STATE STARTTIME" for PID from /proc/PID/stat
# (fields 3 and 22, counted after the ") " that ends the command name), using only
# shell builtins. The start time is the identity: comparing it, not the state,
# means a live parent merely scheduling from S to R is never taken for a new one.
parent_bound_record() {
	parent_bound_line=
	IFS= read -r parent_bound_line 2>/dev/null <"/proc/$1/stat" || return 1
	# shellcheck disable=SC2086 # splitting the fields is the point
	set -- ${parent_bound_line##*) }
	[ "$#" -ge 20 ] || return 1
	printf '%s %s\n' "$1" "${20}"
}

# Runs "$@" in the background and ends it when this script's parent (Quickshell)
# goes away. Sync Sprint 12 S12-07: this used to poll the parent every 0.25 s
# with sed, awk and sleep, about 12 process starts and 4 wake-ups a second per
# always-on watcher. Now:
#
# - When setpriv is available, a program child runs under
#   `setpriv --pdeathsig TERM` (util-linux), so the kernel sends it SIGTERM the
#   moment this shell exits, however it exits. A shell function child
#   (power_watch_sources) runs as before and cleans up its own children on SIGTERM.
# - A backstop loop covers the parent dying without taking this shell with it (a
#   crash): it reads /proc with builtins every $LYONA_PARENT_BOUND_INTERVAL
#   seconds (default 5), one `sleep` and nothing else. When setpriv is available,
#   it too is bound to this shell by pdeathsig.
#
# Without setpriv both run as a plain child and a plain loop, relying on cleanup;
# they may outlive this shell if cleanup does not run.
#
# setpriv arms the signal and then execs, so a parent that dies before the signal
# is armed would never send it. When setpriv is used, each bound process therefore
# starts through parent_bound_guard, which, with the signal armed, checks its
# parent is still the process that started it and exits if not, then execs the
# real command.
# shellcheck disable=SC2016 # expanded by the guard's own shell
parent_bound_guard='[ "$PPID" = "$1" ] || exit 0; shift; exec "$@"'

# bound_to_this_shell PROGRAM ARGS...: always started in the background, with
# `&`, it becomes PROGRAM. When setpriv is available, it is bound to this shell
# by the kernel: the moment this shell exits, however it exits, PROGRAM gets
# SIGTERM (Sync Sprint 13 S13-01).
# A watcher's EXIT trap stops its children too, but under load a watcher was
# seen to die without its trap reaching them, leaving an `xprop -spy` or an
# `inotifywait` to the init process. $! is PROGRAM's pid, as with a plain `&`,
# so a caller's own cleanup still works. In the background subshell, $$ is this
# shell, which the guard checks is still the parent once setpriv arms the signal.
# Without setpriv it is a plain background child and may outlive this shell if
# cleanup does not run. Never call it without `&`:
# it would replace this shell.
bound_to_this_shell() {
	if command -v setpriv >/dev/null 2>&1; then
		exec setpriv --pdeathsig TERM -- sh -c "$parent_bound_guard" sh "$$" "$@"
	fi
	exec "$@"
}

run_parent_bound() {
	parent_pid=$PPID
	parent_record=$(parent_bound_record "$parent_pid") || return 1
	parent_state=${parent_record%% *}
	parent_identity=${parent_record#* }
	[ -n "$parent_identity" ] || return 1
	case $parent_state in
	Z) return 1 ;;
	esac
	# A positive number of seconds (digits, at most one "." with digits on both
	# sides); anything else, zero included, would make the backstop loop spin.
	parent_bound_interval=${LYONA_PARENT_BOUND_INTERVAL:-5}
	case $parent_bound_interval in
	'' | *[!0-9.]* | .* | *. | *.*.*) parent_bound_interval=5 ;;
	esac
	case $parent_bound_interval in
	*[1-9]*) ;;
	*) parent_bound_interval=5 ;;
	esac
	parent_bound_wrap=
	command -v setpriv >/dev/null 2>&1 && parent_bound_wrap=setpriv
	# This shell's own pid, which is what its children see as their parent even
	# when run_parent_bound runs in a subshell ($$ would be the main shell's): the
	# read builtin opens /proc/self in this very process.
	parent_bound_self=
	IFS=' ' read -r parent_bound_self _ 2>/dev/null </proc/self/stat || parent_bound_self=

	# A function cannot be exec'd by setpriv; it runs as a plain child.
	case $(command -v "$1" 2>/dev/null) in
	/*)
		if [ -n "$parent_bound_wrap" ] && [ -n "$parent_bound_self" ]; then
			setpriv --pdeathsig TERM -- sh -c "$parent_bound_guard" sh "$parent_bound_self" "$@" &
		else
			"$@" &
		fi
		;;
	*) "$@" & ;;
	esac
	child_pid=$!

	# shellcheck disable=SC2329 # invoked through the trap immediately below
	cleanup_parent_bound() {
		kill -TERM "$child_pid" 2>/dev/null || :
		kill -TERM "${watchdog_pid:-}" 2>/dev/null || :
	}
	trap cleanup_parent_bound EXIT HUP INT TERM
	# shellcheck disable=SC2016 # expanded by the loop's own shell
	parent_bound_loop='
		parent_pid=$1 parent_identity=$2 child_pid=$3 interval=$4 guard=$5 bound=$6
		self=
		IFS=" " read -r self _ </proc/self/stat
		while :; do
			line=
			IFS= read -r line 2>/dev/null <"/proc/$parent_pid/stat" || line=
			set -- ${line##*) }
			state=${1:-} identity=${20:-}
			[ "$state" != Z ] && [ -n "$identity" ] && [ "$identity" = "$parent_identity" ] || {
				kill -TERM "$child_pid" 2>/dev/null || :
				exit 0
			}
			# When setpriv is used, the sleep is bound to this loop too, through the same guard.
			if [ "$bound" = bound ] && [ -n "$self" ]; then
				setpriv --pdeathsig TERM -- sh -c "$guard" sh "$self" sleep "$interval"
			else
				sleep "$interval"
			fi
		done'
	# When setpriv is used, the loop's sleep is bound to the loop the same way,
	# so a stopped loop never leaves a sleep behind for the rest of its interval.
	if [ -n "$parent_bound_wrap" ] && [ -n "$parent_bound_self" ]; then
		setpriv --pdeathsig TERM -- sh -c "$parent_bound_guard" sh "$parent_bound_self" \
			sh -c "$parent_bound_loop" sh \
			"$parent_pid" "$parent_identity" "$child_pid" "$parent_bound_interval" \
			"$parent_bound_guard" bound &
	else
		sh -c "$parent_bound_loop" sh \
			"$parent_pid" "$parent_identity" "$child_pid" "$parent_bound_interval" \
			"$parent_bound_guard" sleep &
	fi
	watchdog_pid=$!

	status=0
	wait "$child_pid" || status=$?
	kill -TERM "$watchdog_pid" 2>/dev/null || :
	wait "$watchdog_pid" 2>/dev/null || :
	trap - EXIT HUP INT TERM
	return "$status"
}
