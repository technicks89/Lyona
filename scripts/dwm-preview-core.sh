# shellcheck shell=bash
# shellcheck disable=SC2034 # the clock and exchange results are set for the caller
#
# The safety primitives every Settings preview helper uses (#277): the token, the
# mutation lock, the clock, the atomic-exchange check and the watchdog's
# identity. They were copied into dwm-preview.sh (font and toolkit),
# dwm-settings-wallpaper, -theme, -display and -input, each a little
# differently, so a fix to one copy never reached the others. Each helper keeps
# its own state machine on top of these; dwm-preview.sh is the font and toolkit
# one.
#
#   preview_valid_token TOKEN [MAX]   A token: a letter or digit, then letters,
#                                     digits, ".", "_" or "-", MAX in all
#                                     (64 unless given).
#   preview_lock FILE FD [WAIT]       FILE, a private regular file of this user's
#                                     (created if missing), open on FD and
#                                     locked: waiting WAIT seconds, or for as
#                                     long as it takes. 0 locked, 1 not within
#                                     WAIT, 2 unsafe (a symbolic link, another
#                                     owner, a second hard link, or swapped
#                                     while it was being opened).
#   preview_clock_read [BOOT] [UPTIME]
#                                     The boot and the monotonic clock, from the
#                                     files given (the kernel's by default):
#                                     preview_clock_boot_id, and the time since
#                                     boot as preview_clock_ms and
#                                     preview_clock_s. A deadline that names its
#                                     boot is never carried into another one.
#   preview_exchange_supported DIR PREFIX [CACHE]
#                                     GNU mv can exchange two files in DIR
#                                     atomically (coreutils 9.5 or newer, on a
#                                     filesystem that supports it), probed with
#                                     two PREFIX files. With CACHE, the answer is
#                                     kept per filesystem. When not, the reason
#                                     is in preview_exchange_detail.
#   preview_mv_exchange_options       This mv has --exchange and --no-copy.
#   preview_exchange_cached DIR CACHE The kept answer only, for a read-only
#                                     status: no probe, no write.
#   preview_process_owned PID START   PID is this user's, running, and started at
#                                     START (dwm-proc.sh): the watchdog it names
#                                     is still that process.
#   preview_stop_process PID START [group]
#                                     Stops that process, or with "group" its
#                                     process group when it leads one, and
#                                     never this shell.
#
# Commands: flock, mktemp, mv, stat, unlink and chmod; a helper's tests run it
# with no others on PATH. Needs dwm-proc.sh, beside it: the caller's $lyona_lib names that directory.

# shellcheck source=scripts/dwm-proc.sh disable=SC2154 # lyona_lib is the caller's
. "$lyona_lib/dwm-proc.sh"

preview_valid_token() {
	local max=${2:-64}
	[[ $max =~ ^[1-9][0-9]*$ ]] || return 1
	[[ ${1:-} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && ${#1} -le $max ]]
}

preview_lock() {
	local file=$1 fd=$2 wait=${3:-} path_identity fd_identity
	[[ $fd =~ ^[3-9]$ ]] || return 2
	if [[ ! -e $file && ! -L $file ]]; then
		(umask 077 && set -o noclobber && : >"$file") 2>/dev/null || :
	fi
	[[ -f $file && ! -L $file && $(stat -c %u -- "$file" 2>/dev/null) == "$UID" &&
	$(stat -c %h -- "$file" 2>/dev/null) == 1 ]] || return 2
	path_identity=$(stat -Lc '%d:%i' -- "$file" 2>/dev/null) || return 2
	eval "exec $fd>>\"\$file\""
	# The file opened is the one checked, not one swapped in between.
	fd_identity=$(stat -Lc '%d:%i:%u:%h' -- "/dev/fd/$fd" 2>/dev/null) || fd_identity=
	if [[ -L $file || $fd_identity != "$path_identity:$UID:1" ]]; then
		eval "exec $fd>&-"
		return 2
	fi
	chmod 600 -- "/dev/fd/$fd" 2>/dev/null || :
	if [[ -n $wait ]]; then
		flock -x -w "$wait" "$fd" || return 1
	else
		flock -x "$fd" || return 1
	fi
}

preview_clock_read() {
	local boot_file=${1:-/proc/sys/kernel/random/boot_id} uptime_file=${2:-/proc/uptime} uptime fraction
	preview_clock_boot_id=
	preview_clock_ms=0
	preview_clock_s=0
	{ IFS= read -r preview_clock_boot_id <"$boot_file"; } 2>/dev/null || return 1
	{ IFS=' ' read -r uptime _ <"$uptime_file"; } 2>/dev/null || return 1
	[[ $preview_clock_boot_id =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ &&
		$uptime =~ ^([0-9]{1,12})([.]([0-9]+))?$ ]] || {
		preview_clock_boot_id=
		return 1
	}
	fraction=${BASH_REMATCH[3]:-}000
	preview_clock_s=$((10#${BASH_REMATCH[1]}))
	preview_clock_ms=$((preview_clock_s * 1000 + 10#${fraction:0:3}))
}

preview_mv_exchange_options() {
	local help
	help=$(LC_ALL=C mv --help 2>/dev/null) || return 1
	[[ $help == *'--exchange'* && $help == *'--no-copy'* ]]
}

preview_exchange_supported() {
	local dir=$1 prefix=$2 cache=${3:-} device='' cached_device='' cached_result=''
	local probe_a probe_b result=restricted temporary
	preview_exchange_detail='Atomic file exchange readiness could not be verified'
	if ! preview_mv_exchange_options; then
		preview_exchange_detail='GNU mv with --exchange and --no-copy is required (coreutils 9.5 or newer)'
		return 1
	fi
	if [[ -n $cache ]]; then
		device=$(stat -c %d -- "$dir" 2>/dev/null) || return 1
		if [[ -f $cache && ! -L $cache && $(stat -c %u -- "$cache") == "$UID" &&
		$(stat -c %h -- "$cache") == 1 ]]; then
			IFS=: read -r cached_device cached_result <"$cache" || :
			if [[ $cached_device == "$device" ]]; then
				[[ $cached_result == available ]] && return 0
				preview_exchange_detail="Atomic file exchange is unavailable on the $prefix configuration filesystem"
				return 1
			fi
		fi
	fi
	probe_a=$(umask 077 && mktemp "$dir/.$prefix-exchange-a.XXXXXX") || return 1
	probe_b=$(umask 077 && mktemp "$dir/.$prefix-exchange-b.XXXXXX") || {
		unlink -- "$probe_a" 2>/dev/null || :
		return 1
	}
	if mv --exchange --no-copy -- "$probe_a" "$probe_b" 2>/dev/null; then
		result=available
	fi
	unlink -- "$probe_a" 2>/dev/null || :
	unlink -- "$probe_b" 2>/dev/null || :
	if [[ -n $cache ]]; then
		temporary=$(umask 077 && mktemp "${cache%/*}/.exchange-support.XXXXXX") || return 1
		if ! printf '%s:%s\n' "$device" "$result" >"$temporary" ||
			! mv -fT -- "$temporary" "$cache"; then
			unlink -- "$temporary" 2>/dev/null || :
			return 1
		fi
	fi
	[[ $result == available ]] && return 0
	preview_exchange_detail="Atomic file exchange is unavailable on the $prefix configuration filesystem"
	return 1
}

preview_exchange_cached() {
	local dir=$1 cache=$2 device cached_device='' cached_result=''
	[[ -d $dir && ! -L $dir ]] || return 1
	device=$(stat -c %d -- "$dir" 2>/dev/null) || return 1
	[[ -f $cache && ! -L $cache && $(stat -c %u -- "$cache") == "$UID" &&
	$(stat -c %h -- "$cache") == 1 ]] || return 1
	IFS=: read -r cached_device cached_result <"$cache" || return 1
	[[ $cached_device == "$device" && $cached_result == available ]]
}

preview_process_owned() {
	local pid=$1 start=$2
	[[ $pid =~ ^[1-9][0-9]*$ && $pid -ge 2 ]] || return 1
	proc_identity_live "$pid" "$start" || return 1
	[[ $(stat -c %u -- "/proc/$pid" 2>/dev/null) == "$UID" ]]
}

preview_stop_process() {
	local pid=$1 start=$2 mode=${3:-}
	[[ $pid != "$$" ]] || return 0
	preview_process_owned "$pid" "$start" || return 0
	if [[ $mode == group ]]; then
		[[ $proc_pgrp == "$pid" ]] || return 0
		kill -TERM -- "-$pid" 2>/dev/null || :
	else
		kill -TERM "$pid" 2>/dev/null || :
	fi
}
