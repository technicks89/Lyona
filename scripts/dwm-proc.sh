# shellcheck shell=sh
# shellcheck disable=SC2034 # the fields are set for the caller
#
# Process identity from /proc/PID/stat, in one place (#277). A PID can be
# reused once its process is reaped, so a process is named by its PID and its
# start time (field 22, clock ticks since boot): the pair names one process for
# as long as the machine is up. POSIX and builtins only, so the sh and the Bash
# scripts source it, and a loop that checks a process every few seconds all
# session starts no process to do it:
#
#     . "$lyona_lib/dwm-proc.sh"
#
#   proc_stat PID                 Reads PID's record into proc_pid, proc_state,
#                                 proc_ppid, proc_pgrp and proc_start. PID
#                                 "self" is the shell that calls it. Fails when
#                                 there is no such process or the record does
#                                 not parse.
#   proc_alive PID                proc_stat, for a process that is running:
#                                 not a zombie (exited, not yet reaped) or dead.
#   proc_starttime PID            A running PID's start time, printed.
#   proc_identity_live PID START  PID is running and started at START.
#
# The fields are counted after the last ") ": the command name in parentheses
# may hold spaces, and ")" too, so splitting the whole line would shift them.

proc_stat() {
	proc_pid='' proc_state='' proc_ppid='' proc_pgrp='' proc_start=''
	case ${1:-} in
	self) ;;
	'' | *[!0-9]*) return 1 ;;
	esac
	{ IFS= read -r proc_line <"/proc/$1/stat"; } 2>/dev/null || return 1
	case $proc_line in *') '*) ;; *) return 1 ;; esac
	proc_pid=${proc_line%% *}
	# Field 3 on: state, ppid, pgrp, then 17 more to the start time.
	proc_rest=${proc_line##*) }
	proc_state=${proc_rest%% *}
	proc_rest=${proc_rest#* }
	proc_ppid=${proc_rest%% *}
	proc_rest=${proc_rest#* }
	proc_pgrp=${proc_rest%% *}
	proc_field=0
	while [ "$proc_field" -lt 17 ]; do
		proc_rest=${proc_rest#* }
		proc_field=$((proc_field + 1))
	done
	proc_start=${proc_rest%% *}
	case $proc_pid$proc_ppid$proc_pgrp in '' | *[!0-9]*) proc_start= ;; esac
	case $proc_start in
	'' | *[!0-9]*)
		proc_pid='' proc_state='' proc_ppid='' proc_pgrp='' proc_start=''
		return 1
		;;
	esac
}

proc_alive() {
	proc_stat "$1" || return 1
	case $proc_state in Z | X | x) return 1 ;; esac
}

proc_starttime() {
	proc_alive "$1" || return 1
	printf '%s\n' "$proc_start"
}

proc_identity_live() {
	case ${2:-} in '' | *[!0-9]*) return 1 ;; esac
	proc_alive "$1" && [ "$proc_start" = "$2" ]
}
