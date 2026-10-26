# shellcheck shell=sh
#
# The managed Quickshell's lifecycle, shared by autostart.sh and the Control
# Center's restart-quickshell (Sync Sprint 16 R16-49), which used to
# `pkill -x quickshell` (every user's instance named quickshell, the managed
# one or not) and start it again without --path. POSIX, as both callers are.
# An instance is the managed one when Quickshell lists it for the managed
# config's path; it is stopped by identity (pid and start time, and owned by
# this user), politely first. Needs dwm-proc.sh, beside it: the caller's
# $lyona_lib names that directory.

# shellcheck source=scripts/dwm-proc.sh disable=SC2154 # lyona_lib is the caller's
. "$lyona_lib/dwm-proc.sh"

quickshell_instance_pids() {
	config=$1

	command -v jq >/dev/null 2>&1 || return 1
	# A UTF-8 locale for Quickshell alone: under a C locale (a TTY, ssh, a
	# service) Qt prints its locale warning to stdout, the JSON no longer
	# parsed, no instance was found, and a restart silently did nothing (#280 VM).
	instances=$(LC_ALL=C.UTF-8 timeout 1 quickshell list --path "$config" --json 2>/dev/null) || return 1
	printf '%s\n' "$instances" |
		jq -r '.[]? | .pid | select(type == "number" and . >= 2 and floor == .)'
}

quickshell_pid_is_owned() {
	pid=$1
	case $pid in
	'' | *[!0-9]*) return 1 ;;
	esac

	[ "$(stat -c %u "/proc/$pid" 2>/dev/null)" = "$(id -u)" ] || return 1
	executable=$(readlink "/proc/$pid/exe" 2>/dev/null) || return 1
	case $executable in
	*' (deleted)') executable=${executable%' (deleted)'} ;;
	esac
	[ "${executable##*/}" = quickshell ]
}

quickshell_instance_identities() {
	config=$1
	pids=$(quickshell_instance_pids "$config") || return 1
	for pid in $pids; do
		quickshell_pid_is_owned "$pid" || continue
		starttime=$(proc_starttime "$pid") || continue
		printf '%s:%s\n' "$pid" "$starttime"
	done
}

quickshell_identity_matches() {
	identity=$1
	pid=${identity%%:*}
	starttime=${identity#*:}

	quickshell_pid_is_owned "$pid" || return 1
	proc_identity_live "$pid" "$starttime"
}

wait_for_quickshell_exit() {
	cohort=$1
	max_attempts=${2:-40}
	attempt=0

	while [ "$attempt" -lt "$max_attempts" ]; do
		cohort_live=0
		for identity in $cohort; do
			if quickshell_identity_matches "$identity"; then
				cohort_live=1
				break
			fi
		done
		[ "$cohort_live" -eq 1 ] || return 0
		attempt=$((attempt + 1))
		sleep 0.05
	done
	return 1
}

# stop_quickshell_identities IDENTITIES: stop those instances, each one only
# while it is still the process its identity names, politely first.
stop_quickshell_identities() {
	identities=$1
	[ -n "$identities" ] || return 0

	for identity in $identities; do
		quickshell_identity_matches "$identity" || continue
		pid=${identity%%:*}
		timeout 1 quickshell kill --pid "$pid" >/dev/null 2>&1 || true
	done
	wait_for_quickshell_exit "$identities" 10 >/dev/null 2>&1 && return 0
	for identity in $identities; do
		quickshell_identity_matches "$identity" || continue
		pid=${identity%%:*}
		kill -TERM "$pid" 2>/dev/null || true
	done
	wait_for_quickshell_exit "$identities" >/dev/null 2>&1 && return 0

	for identity in $identities; do
		quickshell_identity_matches "$identity" || continue
		pid=${identity%%:*}
		kill -KILL "$pid" 2>/dev/null || true
	done
	wait_for_quickshell_exit "$identities" >/dev/null 2>&1
}

stop_managed_quickshell() {
	config=$1
	identities=$(quickshell_instance_identities "$config") || return 1
	stop_quickshell_identities "$identities"
}

# Whether the managed instance answers: its tray, which tray apps need first.
quickshell_tray_ready() {
	config=$1

	command -v timeout >/dev/null 2>&1 || return 1
	timeout 1 quickshell ipc --path "$config" call tray count >/dev/null 2>&1
}

# restart_managed_quickshell CONFIG LAUNCHER...: stop the managed instance, by
# identity, and start it again with --path, the instance the keys address,
# through the caller's LAUNCHER (which detaches it). The one start sequence of
# autostart.sh and the Control Center (#320).
restart_managed_quickshell() {
	config=$1
	shift
	stop_managed_quickshell "$config" >/dev/null 2>&1 || true
	"$@" quickshell --path "$config" --no-duplicate
}

# A variable of a process's environment, NAME=value, which is fixed at exec and
# readable by its owner. Empty when it has none.
quickshell_pid_env() {
	tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | sed -n "/^$2=/{s///p;q;}"
}

# quickshell_session_identity_in IDENTITIES: whether one of those instances is
# this session's: started on this X display, and in this logind session when
# both sides name one. Such an instance that does not answer yet is still
# loading, or too busy to answer within the probe's second (a loaded login): it
# is waited for, never stopped, as stopping it killed a shell that was nearly
# up and started the wait again from nothing (#394). One on another display is
# another session's, or a dead one's. So is one of another logind session on
# this display: a display manager gives the next login the same display
# number, and a shell that hung as its X server died (#448) was waited for at
# every later login, which then had no panel.
quickshell_session_identity_in() {
	[ -n "${DISPLAY:-}" ] || return 1
	for session_identity in $1; do
		session_pid=${session_identity%%:*}
		[ "$(quickshell_pid_env "$session_pid" DISPLAY)" = "$DISPLAY" ] || continue
		[ -n "${XDG_SESSION_ID:-}" ] || return 0
		session_of_pid=$(quickshell_pid_env "$session_pid" XDG_SESSION_ID)
		[ -n "$session_of_pid" ] && [ "$session_of_pid" != "$XDG_SESSION_ID" ] || return 0
	done
	return 1
}

# quickshell_stop_watching CONFIG: stop this session's managed shells when they
# still watch their config files, started from a shell.qml older than #461,
# and print their identities, for the caller to start one again once the new
# config is in place. Such a shell hot-reloads a config replaced under it, and
# Quickshell 0.3.2 crashes when a shell that has reloaded is stopped, as the
# restart after an install or rollback does. A shell that does not watch them,
# another session's, or any with no display to start one again on, is left.
quickshell_stop_watching() {
	config=$1
	[ -n "${DISPLAY:-}" ] && [ -f "$config" ] || return 0
	! grep -Fq 'Quickshell.watchFiles = false' "$config" || return 0
	watching=
	for watching_identity in $(quickshell_instance_identities "$config" 2>/dev/null || true); do
		! quickshell_session_identity_in "$watching_identity" ||
			watching="$watching $watching_identity"
	done
	[ -n "$watching" ] || return 0
	stop_quickshell_identities "$watching" >/dev/null 2>&1 || true
	# shellcheck disable=SC2086 # one identity a line
	printf '%s\n' $watching
}

# Whether this session's managed instance is running, answering or not.
quickshell_session_instance_running() {
	session_identities=$(quickshell_instance_identities "$1") || return 1
	quickshell_session_identity_in "$session_identities"
}

# start_managed_quickshell CONFIG LAUNCHER...: as restart_managed_quickshell,
# only when this session's managed instance is neither answering nor running,
# as at login. An instance that is not this session's is replaced. The
# instances are listed once: the one listing decides, and names what is stopped.
start_managed_quickshell() {
	config=$1
	shift
	quickshell_tray_ready "$config" && return 0
	if start_identities=$(quickshell_instance_identities "$config"); then
		quickshell_session_identity_in "$start_identities" && return 0
		stop_quickshell_identities "$start_identities" >/dev/null 2>&1 || true
	fi
	"$@" quickshell --path "$config" --no-duplicate
}
