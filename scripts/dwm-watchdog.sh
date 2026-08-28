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
# Defines run_bounded and run_parent_bound; sets nothing else.

run_bounded() {
	duration=$1
	shift
	status=0
	timeout --signal=TERM --kill-after=2 "$duration" "$@" || status=$?
	if [ "$status" -eq 124 ]; then
		printf 'operation timed out after %s seconds\n' "$duration" >&2
	fi
	return "$status"
}

# Runs "$@" in the background and kills it if the parent goes away. The
# identity is the parent's starttime from /proc/pid/stat field 20, kept
# separate from the state letter in field 1: comparing the two concatenated
# meant a live parent merely scheduling from S to R changed the string and
# the watchdog killed a healthy child.
run_parent_bound() {
	parent_pid=$PPID
	parent_record=$(sed 's/^.*) //' "/proc/$parent_pid/stat" 2>/dev/null |
		awk '{ print $1 " " $20 }') || return 1
	parent_state=${parent_record%% *}
	parent_identity=${parent_record#* }
	[ -n "$parent_identity" ] || return 1
	case $parent_state in
	Z) return 1 ;;
	esac
	"$@" &
	child_pid=$!

	# shellcheck disable=SC2329 # invoked through the trap immediately below
	cleanup_parent_bound() {
		kill -TERM "$child_pid" 2>/dev/null || :
		kill -TERM "${watchdog_pid:-}" 2>/dev/null || :
	}
	trap cleanup_parent_bound EXIT HUP INT TERM
	(
		while :; do
			current_record=$(sed 's/^.*) //' "/proc/$parent_pid/stat" 2>/dev/null |
				awk '{ print $1 " " $20 }' || true)
			current_state=${current_record%% *}
			current_identity=${current_record#* }
			[ "$current_state" != Z ] && [ "$current_identity" = "$parent_identity" ] || {
				kill -TERM "$child_pid" 2>/dev/null || :
				exit 0
			}
			sleep 0.25
		done
	) &
	watchdog_pid=$!

	status=0
	wait "$child_pid" || status=$?
	kill -TERM "$watchdog_pid" 2>/dev/null || :
	wait "$watchdog_pid" 2>/dev/null || :
	trap - EXIT HUP INT TERM
	return "$status"
}
