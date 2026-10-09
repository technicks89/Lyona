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

stop_managed_quickshell() {
	config=$1
	identities=$(quickshell_instance_identities "$config") || return 1
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
