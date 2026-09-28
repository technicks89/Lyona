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
	local identity line read_status interval
	command -v udevadm >/dev/null 2>&1 || die "udevadm is unavailable"
	[[ $owner_pid =~ ^[1-9][0-9]*$ && $owner_starttime =~ ^[1-9][0-9]*$ ]] ||
		die "invalid $noun watch owner identity"
	simple_watch_identity_is_live "$owner_pid:$owner_starttime" ||
		die "$noun watch owner is unavailable"
	# In the session's runtime directory, like dwm-status: cleared at logout, so a
	# watcher killed before it can clean up leaves nothing in /tmp.
	simple_watch_fifo_dir=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/dwm-settings-$noun-watch.XXXXXX")
	trap simple_watch_cleanup EXIT
	# Exit, not just note the signal: a trap that returns leaves a blocked read
	# waiting for its timeout, and SIGTERM is how the watcher is stopped (its
	# parent-death signal included, Commands.watchCommand).
	trap 'exit 129' HUP
	trap 'exit 130' INT
	trap 'exit 143' TERM
	mkfifo -m 600 "$simple_watch_fifo_dir/events"

	# The monitor ends with this watcher however the watcher ends: Quickshell stops
	# a watcher it no longer needs (a Settings section left) without waiting for
	# its cleanup. The guard is Commands.watchCommand's; the signal is KILL, as the
	# monitor has nothing to clean up and must not be able to ignore it.
	if command -v setpriv >/dev/null 2>&1; then
		# shellcheck disable=SC2016 # expanded by the guard's own shell
		setpriv --pdeathsig KILL -- sh -c '[ "$PPID" = "$1" ] || exit 0; shift; exec "$@"' sh "$$" \
			udevadm monitor --udev --subsystem-match="$subsystem" --property \
			>"$simple_watch_fifo_dir/events" 2>/dev/null &
	else
		udevadm monitor --udev --subsystem-match="$subsystem" --property \
			>"$simple_watch_fifo_dir/events" 2>/dev/null &
	fi
	simple_watch_monitor_pid=$!
	identity=$(simple_watch_capture_child "$simple_watch_monitor_pid") ||
		die "cannot identify the $noun event monitor"
	simple_watch_children+=("$identity")

	# A backstop only: the watcher is bound to its owner by a parent-death signal
	# and is woken by every event; this catches an owner that died unseen (no
	# setpriv). Same setting and default as dwm-watchdog.sh's run_parent_bound.
	interval=${LYONA_PARENT_BOUND_INTERVAL:-5}
	[[ $interval =~ ^[0-9]+([.][0-9]+)?$ && $interval =~ [1-9] ]] || interval=5
	exec {simple_watch_fd}<"$simple_watch_fifo_dir/events"
	# Opening a fifo to read waits for its writer, so both ends are open now and
	# the name is no longer needed: a watcher that is killed outright (SIGKILL,
	# which runs no trap) then leaves nothing behind in the temporary directory.
	rm -f -- "$simple_watch_fifo_dir/events"
	rmdir -- "$simple_watch_fifo_dir" 2>/dev/null || true
	simple_watch_fifo_dir=
	while simple_watch_identity_is_live "$owner_pid:$owner_starttime" &&
		simple_watch_identity_is_live "$identity" "$$"; do
		if IFS= read -r -t "$interval" line <&"$simple_watch_fd"; then
			case $line in ACTION=*) printf 'changed\n' ;; esac
		else
			read_status=$?
			((read_status > 128)) || break
		fi
	done
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
