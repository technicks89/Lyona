# shellcheck shell=bash
#
# A udev-backed change watcher: prints "changed" on every matching event and
# exits when either its owner or its own monitor goes away.
#
# Shared by dwm-settings-display and dwm-settings-input, which carried
# byte-identical copies of the four helpers and a watch loop differing only in
# the udev subsystem and the noun in its messages -- the largest single
# duplicate in the repo. Sourced with the directory the caller lives in:
#
#     script_dir=${BASH_SOURCE[0]%/*}
#     . "$script_dir/dwm-simple-watch.sh"
#
# Caller contract: reports through die, so a caller must define one.
#
# Identity throughout is "pid:starttime" from /proc/pid/stat field 22, which is
# what makes a recycled pid detectable; the state letter in field 3 is checked
# separately so a process merely being rescheduled never reads as gone.

declare -a simple_watch_children=()
simple_watch_fifo_dir=
simple_watch_monitor_pid=

simple_watch_process_starttime() {
	local pid=$1 stat rest
	local -a fields=()
	[[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
	{ IFS= read -r stat <"/proc/$pid/stat"; } 2>/dev/null || return 1
	rest=${stat##*) }
	read -r -a fields <<<"$rest"
	[[ ${#fields[@]} -ge 20 && ${fields[0]} != Z && ${fields[19]} =~ ^[0-9]+$ ]] || return 1
	printf '%s\n' "${fields[19]}"
}

simple_watch_identity_is_live() {
	local identity=$1 expected_parent=${2:-} pid=${1%%:*} starttime=${1#*:} stat rest
	local -a fields=()
	[[ $pid =~ ^[1-9][0-9]*$ && $starttime =~ ^[0-9]+$ ]] || return 1
	{ IFS= read -r stat <"/proc/$pid/stat"; } 2>/dev/null || return 1
	rest=${stat##*) }
	read -r -a fields <<<"$rest"
	[[ ${#fields[@]} -ge 20 && ${fields[0]} != Z && ${fields[19]} == "$starttime" ]] || return 1
	[[ -z $expected_parent || ${fields[1]} == "$expected_parent" ]]
}

simple_watch_capture_child() {
	local pid=$1 starttime attempt
	for ((attempt = 0; attempt < 20; attempt++)); do
		starttime=$(simple_watch_process_starttime "$pid" 2>/dev/null || true)
		if [[ $starttime =~ ^[0-9]+$ ]] &&
			simple_watch_identity_is_live "$pid:$starttime" "$$"; then
			printf '%s:%s\n' "$pid" "$starttime"
			return 0
		fi
		sleep 0.01
	done
	return 1
}

simple_watch_cleanup() {
	local identity pid attempt live
	trap - EXIT HUP INT TERM
	for identity in "${simple_watch_children[@]}"; do
		simple_watch_identity_is_live "$identity" "$$" || continue
		kill -TERM "${identity%%:*}" 2>/dev/null || true
	done
	for ((attempt = 0; attempt < 20; attempt++)); do
		live=0
		for identity in "${simple_watch_children[@]}"; do
			simple_watch_identity_is_live "$identity" "$$" || continue
			live=1
		done
		((live == 0)) && break
		sleep 0.05
	done
	for identity in "${simple_watch_children[@]}"; do
		simple_watch_identity_is_live "$identity" "$$" || continue
		kill -KILL "${identity%%:*}" 2>/dev/null || true
	done
	for identity in "${simple_watch_children[@]}"; do
		pid=${identity%%:*}
		wait "$pid" 2>/dev/null || true
	done
	simple_watch_children=()
	if [[ -n $simple_watch_fifo_dir ]]; then
		rm -f -- "$simple_watch_fifo_dir/events"
		rmdir -- "$simple_watch_fifo_dir" 2>/dev/null || true
		simple_watch_fifo_dir=
	fi
}

# Streams change events for one udev subsystem until the owner exits.
#
#     simple_watch_events SUBSYSTEM NOUN OWNER_PID OWNER_STARTTIME
#
# NOUN appears in the diagnostics and in the temporary directory name.
simple_watch_events() {
	local subsystem=$1 noun=$2 owner_pid=$3 owner_starttime=$4
	local identity line read_status simple_watch_signal=0
	command -v udevadm >/dev/null 2>&1 || die "udevadm is unavailable"
	[[ $owner_pid =~ ^[1-9][0-9]*$ && $owner_starttime =~ ^[1-9][0-9]*$ ]] ||
		die "invalid $noun watch owner identity"
	simple_watch_identity_is_live "$owner_pid:$owner_starttime" ||
		die "$noun watch owner is unavailable"
	simple_watch_fifo_dir=$(mktemp -d "${TMPDIR:-/tmp}/dwm-settings-$noun-watch.XXXXXX")
	trap simple_watch_cleanup EXIT
	trap 'simple_watch_signal=129' HUP
	trap 'simple_watch_signal=130' INT
	trap 'simple_watch_signal=143' TERM
	mkfifo -m 600 "$simple_watch_fifo_dir/events"

	udevadm monitor --udev --subsystem-match="$subsystem" --property \
		>"$simple_watch_fifo_dir/events" 2>/dev/null &
	simple_watch_monitor_pid=$!
	identity=$(simple_watch_capture_child "$simple_watch_monitor_pid") ||
		die "cannot identify the $noun event monitor"
	simple_watch_children+=("$identity")
	((simple_watch_signal == 0)) || return "$simple_watch_signal"

	exec {simple_watch_fd}<"$simple_watch_fifo_dir/events"
	while ((simple_watch_signal == 0)) &&
		simple_watch_identity_is_live "$owner_pid:$owner_starttime" &&
		simple_watch_identity_is_live "$identity" "$$"; do
		if IFS= read -r -t 0.1 line <&"$simple_watch_fd"; then
			case $line in ACTION=*) printf 'changed\n' ;; esac
		else
			read_status=$?
			((read_status > 128)) || break
		fi
	done
	((simple_watch_signal == 0)) || return "$simple_watch_signal"
	simple_watch_identity_is_live "$owner_pid:$owner_starttime" || return 0
	if ! simple_watch_identity_is_live "$identity" "$$"; then
		if wait "${identity%%:*}"; then
			return 1
		else
			read_status=$?
			return "$read_status"
		fi
	fi
	return 1
}
