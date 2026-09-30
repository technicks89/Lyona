# shellcheck shell=bash
# shellcheck disable=SC2154,SC2034 # paths and state are shared with the caller
#
# The preview, keep, revert and rollback machinery shared by dwm-settings-font
# and dwm-settings-toolkit (Sync Sprint 12 S12-14). It is safety logic -- the
# mutation lock, preview tokens, the rollback watchdog, expiry, and the atomic
# config exchange -- so it lives once: a fix here reaches both helpers.
# dwm-settings-display, -input, -wallpaper and -theme have different state
# machines and keep their own.
#
# The caller sets, before sourcing:
#   preview_program       its name in messages: dwm-settings-font
#   preview_label         the word in messages and state names: font
#   preview_config_name   the config's file name, for temporary names: font.conf
#   preview_env           the test-hook prefix: DWM_SETTINGS_FONT, read as
#                         ${preview_env}_NOW and ${preview_env}_BOOT_ID
# and the paths these functions use: home_dir, config_home, config_dir,
# config_file, state_home, state_base, appearance_state_dir, state_dir,
# lock_file, preview_file, preview_meta, preview_baseline and preview_failed.
# It also defines die, and the domain functions these call back: read_config,
# write_config, apply_selection, emit_status and the rest of its own model.

capture_baseline() {
	local temp
	temp=$(mktemp --tmpdir="$state_dir" .preview.baseline.XXXXXX)
	trap 'unlink -- "${temp:-}" 2>/dev/null || true' RETURN
	cp -- "$config_file" "$temp"
	chmod 600 -- "$temp"
	mv -fT -- "$temp" "$preview_baseline"
	trap - RETURN
}

clean_field() {
	local value=$1
	value=${value//$'\t'/ }
	value=${value//$'\r'/ }
	value=${value//$'\n'/ }
	printf '%.512s' "$value"
}

cleanup_preview_exchange() {
	local token=$1 path baseline_hash captured_hash baseline_mode captured_mode
	path=$(preview_exchange_path "$token") || return 1
	[[ -e $path || -L $path ]] || return 0
	[[ -f $preview_baseline && ! -L $preview_baseline ]] || return 1
	baseline_hash=$(config_path_hash "$preview_baseline" 2>/dev/null || true)
	captured_hash=$(config_path_hash "$path" 2>/dev/null || true)
	baseline_mode=$(meta_value baseline-mode 2>/dev/null || true)
	captured_mode=$(stat -c %a -- "$path" 2>/dev/null || true)
	[[ -n $baseline_hash && $captured_hash == "$baseline_hash" &&
		$baseline_mode == "$captured_mode" ]] || return 1
	unlink -- "$path"
}

clear_preview() {
	local token
	token=$(preview_token 2>/dev/null || true)
	stop_watchdog
	if [[ -n $token ]]; then
		cleanup_preview_exchange "$token" || true
	fi
	for path in "$preview_file" "$preview_meta" "$preview_baseline" "$preview_failed"; do
		if [[ -e $path || -L $path ]]; then
			unlink -- "$path"
		fi
	done
}

config_path_hash() {
	local path=$1
	[[ -f $path && ! -L $path && $(stat -c %u -- "$path") == "$(id -u)" &&
	$(stat -c %h -- "$path") == 1 && $(stat -c %s -- "$path") -le 4096 ]] || return 1
	sha256sum -- "$path" | awk '{ print $1 }'
}

file_hash() {
	if [[ -e $config_file ]]; then
		sha256sum -- "$config_file" | awk '{ print $1 }'
	else
		printf '%s\n' absent
	fi
}

file_mode() {
	if [[ -e $config_file ]]; then
		stat -c %a -- "$config_file"
	else
		printf '%s\n' absent
	fi
}

mark_failed() {
	local token=$1 detail=$2 temp
	temp=$(mktemp --tmpdir="$state_dir" .preview.failed.XXXXXX)
	trap 'unlink -- "${temp:-}" 2>/dev/null || true' RETURN
	chmod 600 -- "$temp"
	printf '%s\t%s\n' "$token" "$(clean_field "$detail")" >"$temp"
	mv -fT -- "$temp" "$preview_failed"
	trap - RETURN
}

meta_value() {
	local key=$1
	awk -F '\t' -v key="$key" '$1 == key && NF == 2 { print $2; found = 1; exit } END { exit(found ? 0 : 1) }' "$preview_meta"
}

mv_exchange_options_supported() {
	local help
	help=$(LC_ALL=C mv --help 2>/dev/null) || return 1
	[[ $help == *'--exchange'* && $help == *'--no-copy'* ]]
}

preview_token() {
	[[ -f $preview_file ]] || return 1
	local token extra
	IFS=$'\t' read -r token extra <"$preview_file" || true
	valid_token "$token" && [[ -z ${extra:-} ]] || return 1
	printf '%s\n' "$token"
}

process_group_id() {
	local pid=$1
	awk '{ line=$0; sub(/^.*\) /, "", line); split(line, field, " "); if (field[1] != "Z") print field[3] }' \
		"/proc/$pid/stat" 2>/dev/null
}

process_start_time() {
	local pid=$1
	awk '{ line=$0; sub(/^.*\) /, "", line); split(line, field, " "); if (field[1] != "Z") print field[20] }' \
		"/proc/$pid/stat" 2>/dev/null
}

require_paths() {
	[[ -n $home_dir ]] || die 'HOME is unavailable'
	valid_absolute_path "$home_dir" || die 'HOME must be an absolute path'
	valid_absolute_path "$config_home" || die 'XDG_CONFIG_HOME must be an absolute path'
	valid_absolute_path "$state_home" || die 'XDG_STATE_HOME must be an absolute path'
}

restore_interrupted_exchange() {
	local token=$1 expected_hash=$2 expected_mode=$3 path path_hash path_mode current_hash current_mode
	local baseline_present baseline_hash
	path=$(preview_exchange_path "$token") || return 1
	[[ -e $path || -L $path ]] || return 2
	path_hash=$(config_path_hash "$path" 2>/dev/null || true)
	path_mode=$(stat -c %a -- "$path" 2>/dev/null || true)
	[[ -n $path_hash ]] || return 1
	baseline_present=$(meta_value baseline-present 2>/dev/null || true)
	current_hash=$(file_hash)
	current_mode=$(file_mode)
	if [[ $path_hash == "$expected_hash" && $path_mode == "$expected_mode" ]]; then
		case $baseline_present in
		yes)
			baseline_hash=$(config_path_hash "$preview_baseline" 2>/dev/null || true)
			if [[ -n $baseline_hash && $current_hash == "$baseline_hash" &&
				$current_mode == "$expected_mode" ]]; then
				unlink -- "$path"
				return 0
			fi
			;;
		no)
			if [[ $current_hash == absent && $current_mode == absent ]]; then
				unlink -- "$path"
				return 0
			fi
			;;
		esac
	fi
	publish_config_if_hash "$path" "$expected_hash" "$expected_mode"
}

stop_watchdog() {
	[[ -f $preview_meta ]] || return 0
	local pid start boot_id current_boot current
	pid=$(meta_value watchdog-pid 2>/dev/null || true)
	start=$(meta_value watchdog-start 2>/dev/null || true)
	boot_id=$(meta_value boot-id 2>/dev/null || true)
	[[ $pid =~ ^[0-9]+$ && $pid -ge 2 && -n $start && $pid -ne $$ ]] || return 0
	current_boot=$(read_boot_id)
	[[ $current_boot == "$boot_id" ]] || return 0
	current=$(process_start_time "$pid" || true)
	[[ $current == "$start" ]] || return 0
	terminate_watchdog_group "$pid"
}

terminate_watchdog_group() {
	local pid=$1 pgrp
	[[ $pid =~ ^[0-9]+$ && $pid -ge 2 && $pid -ne $$ ]] || return 0
	pgrp=$(process_group_id "$pid" || true)
	[[ $pgrp == "$pid" ]] || return 0
	kill -TERM -- "-$pid" 2>/dev/null || true
}

validate_file() {
	local path=$1 label=$2 uid
	[[ ! -e $path && ! -L $path ]] && return 0
	uid=$(id -u)
	[[ -f $path && ! -L $path ]] || die "$label must be a regular file: $path"
	[[ $(stat -c %u -- "$path" 2>/dev/null) == "$uid" ]] ||
		die "$label is not owned by the current user: $path"
	[[ $(stat -c %h -- "$path" 2>/dev/null) == 1 ]] ||
		die "$label must not have multiple hard links: $path"
}

valid_seconds() {
	[[ $1 =~ ^[0-9]+$ ]] && ((10#$1 >= 5 && 10#$1 <= 120))
}

valid_token() {
	[[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$ ]]
}

watchdog() {
	local token=$1 deadline=$2 boot_id now next attempts=0
	valid_token "$token" || exit 1
	[[ $deadline =~ ^[0-9]+$ ]] || exit 1
	boot_id=$(read_boot_id)
	while :; do
		[[ $(read_boot_id) == "$boot_id" ]] || exit 0
		now=$(read_now)
		((now >= deadline)) && break
		sleep $((deadline - now))
		next=$(read_now)
		((next > now)) || exit 1
	done
	prepare_state
	exec 9>"$lock_file"
	until flock -w 5 -x 9; do
		((attempts += 1))
		((attempts < 24)) || exit 1
	done
	expire_preview_locked "$token" || true
}

watchdog_alive() {
	[[ -f $preview_meta ]] || return 1
	local pid start boot_id current_boot current
	pid=$(meta_value watchdog-pid 2>/dev/null || true)
	start=$(meta_value watchdog-start 2>/dev/null || true)
	boot_id=$(meta_value boot-id 2>/dev/null || true)
	[[ $pid =~ ^[0-9]+$ && $pid -ge 2 && -n $start ]] || return 1
	current_boot=$(read_boot_id)
	[[ $current_boot == "$boot_id" ]] || return 1
	current=$(process_start_time "$pid" || true)
	[[ $current == "$start" ]]
}

write_preview_token() {
	local token=$1 temp
	temp=$(mktemp --tmpdir="$state_dir" .preview.current.XXXXXX)
	trap 'unlink -- "${temp:-}" 2>/dev/null || true' RETURN
	chmod 600 -- "$temp"
	printf '%s\n' "$token" >"$temp"
	mv -fT -- "$temp" "$preview_file"
	trap - RETURN
}

acquire_lock() {
	prepare_state
	exec 9>"$lock_file"
	flock -w 5 -x 9 || die "another $preview_label settings operation is already running"
}

exchange_supported() {
	local probe_a probe_b status=1
	exchange_failure_detail='Atomic file exchange readiness could not be verified'
	if ! mv_exchange_options_supported; then
		exchange_failure_detail='GNU mv with --exchange and --no-copy is required (coreutils 9.5 or newer)'
		return 1
	fi
	prepare_config
	probe_a=$(mktemp --tmpdir="$config_dir" ".$preview_label-exchange-a.XXXXXX") || return 1
	probe_b=$(mktemp --tmpdir="$config_dir" ".$preview_label-exchange-b.XXXXXX") || {
		unlink -- "$probe_a"
		return 1
	}
	if mv --exchange --no-copy -- "$probe_a" "$probe_b" 2>/dev/null; then
		status=0
	else
		exchange_failure_detail="Atomic file exchange is unavailable on the $preview_label configuration filesystem"
	fi
	unlink -- "$probe_a"
	unlink -- "$probe_b"
	return "$status"
}

expire_preview_locked() {
	local expected_token=${1:-} token deadline boot_id current_boot now expected_hash current_hash
	local expected_mode current_mode interrupted_status published baseline_present baseline_hash
	token=$(preview_token 2>/dev/null || true)
	if [[ -z $token ]]; then
		if [[ -e $preview_file || -L $preview_file || -e $preview_meta || -L $preview_meta ||
			-e $preview_baseline || -L $preview_baseline || -e $preview_failed || -L $preview_failed ]]; then
			clear_preview
		fi
		return 0
	fi
	[[ -z $expected_token || $token == "$expected_token" ]] || return 0
	[[ -f $preview_meta ]] || {
		mark_failed "$token" 'Preview metadata is missing'
		return 1
	}
	deadline=$(meta_value deadline 2>/dev/null || true)
	boot_id=$(meta_value boot-id 2>/dev/null || true)
	current_boot=$(read_boot_id)
	if [[ ! $deadline =~ ^[0-9]+$ || ! $boot_id =~ ^[0-9A-Fa-f-]{36}$ ]]; then
		mark_failed "$token" 'Preview timing metadata is invalid'
		return 1
	fi
	if [[ $current_boot == "$boot_id" ]]; then
		now=$(read_now)
	fi
	expected_hash=$(meta_value hash 2>/dev/null || true)
	expected_mode=$(meta_value baseline-mode 2>/dev/null || true)
	if restore_interrupted_exchange "$token" "$expected_hash" "$expected_mode"; then
		clear_preview
		return 0
	else
		interrupted_status=$?
		if ((interrupted_status != 2)); then
			mark_failed "$token" "Interrupted $preview_label preview could not restore the captured configuration"
			return 1
		fi
	fi
	current_hash=$(file_hash)
	current_mode=$(file_mode)
	if [[ -z $expected_hash || $current_hash != "$expected_hash" ||
		! $expected_mode =~ ^[0-7]{3,4}$ || $current_mode != "$expected_mode" ]]; then
		published=$(meta_value published 2>/dev/null || true)
		if [[ $published == no ]]; then
			baseline_present=$(meta_value baseline-present 2>/dev/null || true)
			case $baseline_present in
			yes)
				baseline_hash=$(config_path_hash "$preview_baseline" 2>/dev/null || true)
				if [[ -n $baseline_hash && $current_hash == "$baseline_hash" &&
					$current_mode == "$expected_mode" ]]; then
					clear_preview
					return 0
				fi
				;;
			no)
				if [[ $current_hash == absent && $current_mode == absent ]]; then
					clear_preview
					return 0
				fi
				;;
			esac
		fi
		mark_failed "$token" 'Font configuration changed outside Settings; automatic rollback was not applied'
		return 1
	fi
	if [[ $current_boot == "$boot_id" ]]; then
		((now >= deadline)) || return 0
	fi
	if ! restore_baseline "$expected_hash"; then
		mark_failed "$token" "Automatic $preview_label rollback could not restore the previous configuration"
		return 1
	fi
	clear_preview
}

prepare_config() {
	local allow_oversized=${1:-no}
	require_paths
	existing_path_chain_is_safe "$config_file" || die "unsafe $preview_label configuration path: $config_file"
	ensure_owned_directory "$config_home" 'configuration home'
	ensure_owned_directory "$config_dir" 'lyona configuration'
	validate_file "$config_file" "$preview_label configuration"
	if [[ $allow_oversized != yes && -e $config_file && $(stat -c %s -- "$config_file") -gt 4096 ]]; then
		die "$preview_label configuration is too large: $config_file"
	fi
}

prepare_state() {
	require_paths
	existing_path_chain_is_safe "$state_dir/.$preview_label-ready" || die "unsafe $preview_label state path: $state_dir"
	ensure_owned_directory "$state_home" 'state home'
	ensure_owned_directory "$state_base" 'lyona state'
	ensure_owned_directory "$appearance_state_dir" 'appearance state'
	ensure_owned_directory "$state_dir" "$preview_label state"
	chmod 700 -- "$state_base" "$appearance_state_dir" "$state_dir"
	validate_file "$lock_file" "$preview_label mutation lock"
}

preview_exchange_path() {
	local token=$1
	valid_token "$token" || return 1
	printf '%s/.%s.preview-exchange.%s\n' "$config_dir" "$preview_config_name" "$token"
}

preview_setup_cleanup() {
	local status=$1 current_hash='' current_mode='' token='' interrupted_status=2
	local recovery_complete=false
	trap - EXIT HUP INT TERM
	[[ $preview_setup_active == true ]] || exit "$status"
	set +e
	if [[ -n $preview_setup_pid ]]; then
		terminate_watchdog_group "$preview_setup_pid"
	fi
	token=$(preview_token 2>/dev/null || true)
	if [[ -n $token && -n $preview_setup_hash ]]; then
		if restore_interrupted_exchange "$token" "$preview_setup_hash" \
			"$preview_setup_mode" >/dev/null 2>&1; then
			recovery_complete=true
		else
			interrupted_status=$?
			if ((interrupted_status == 2)); then
				current_hash=$(file_hash 2>/dev/null)
				current_mode=$(file_mode 2>/dev/null)
				if [[ $current_hash != "$preview_setup_hash" ]]; then
					recovery_complete=true
				elif [[ $current_mode == "$preview_setup_mode" ]] &&
					restore_captured_baseline "$preview_setup_present" "$preview_setup_mode" \
						"$preview_setup_hash" >/dev/null 2>&1; then
					recovery_complete=true
				else
					mark_failed "$token" \
						"Interrupted $preview_label preview could not restore the captured configuration"
				fi
			else
				mark_failed "$token" \
					"Interrupted $preview_label preview could not restore the captured configuration"
			fi
		fi
	else
		recovery_complete=true
	fi
	if [[ $recovery_complete == true ]]; then
		if [[ -n $token ]]; then
			cleanup_preview_exchange "$token" >/dev/null 2>&1 || true
		fi
		for path in "$preview_file" "$preview_meta" "$preview_baseline" "$preview_failed"; do
			if [[ -e $path || -L $path ]]; then
				unlink -- "$path" 2>/dev/null
			fi
		done
	fi
	exit "$status"
}

publish_config_if_hash() {
	local staged=$1 expected_hash=$2 expected_mode=${3:-} published_hash captured_hash captured_mode rollback_hash
	published_config_retained=false
	published_hash=$(config_path_hash "$staged") || return 1
	if [[ $expected_hash == absent ]]; then
		mv --no-clobber --no-target-directory -- "$staged" "$config_file" || return 1
		[[ ! -e $staged && ! -L $staged ]] || return 1
		[[ $(config_path_hash "$config_file" 2>/dev/null || true) == "$published_hash" ]]
		return
	fi
	if ! mv_exchange_options_supported; then
		printf '%s: GNU mv with --exchange and --no-copy is required (coreutils 9.5 or newer)\n' "$preview_program" >&2
		return 1
	fi
	if ! mv --exchange --no-copy -- "$staged" "$config_file"; then
		printf '%s: atomic file exchange is unavailable on the %s configuration filesystem\n' "$preview_program" "$preview_label" >&2
		return 1
	fi
	captured_hash=$(config_path_hash "$staged" 2>/dev/null || true)
	captured_mode=$(stat -c %a -- "$staged" 2>/dev/null || true)
	if [[ $captured_hash == "$expected_hash" &&
		(-z $expected_mode || $captured_mode == "$expected_mode") ]]; then
		unlink -- "$staged"
		return 0
	fi
	if [[ $(config_path_hash "$config_file" 2>/dev/null || true) != "$published_hash" ]]; then
		retain_external_config "$staged"
		published_config_retained=true
		return 1
	fi
	if mv --exchange --no-copy -- "$staged" "$config_file"; then
		rollback_hash=$(config_path_hash "$staged" 2>/dev/null || true)
		if [[ $rollback_hash == "$published_hash" ]]; then
			unlink -- "$staged"
		else
			retain_external_config "$staged"
			published_config_retained=true
		fi
	else
		retain_external_config "$staged"
		published_config_retained=true
	fi
	return 1
}

read_boot_id() {
	local boot_id
	local boot_id_var=${preview_env}_BOOT_ID
	if [[ -n ${!boot_id_var:-} ]]; then
		boot_id=${!boot_id_var}
	else
		IFS= read -r boot_id </proc/sys/kernel/random/boot_id || die 'boot identity is unavailable'
	fi
	[[ $boot_id =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] ||
		die 'boot identity is invalid'
	printf '%s\n' "$boot_id"
}

read_now() {
	local now_var=${preview_env}_NOW
	if [[ -n ${!now_var:-} ]]; then
		[[ ${!now_var} =~ ^[0-9]+$ ]] || die "$now_var must be a monotonic timestamp"
		printf '%s\n' "${!now_var}"
	else
		local uptime
		IFS=' ' read -r uptime _ </proc/uptime || die 'monotonic clock is unavailable'
		[[ $uptime =~ ^[0-9]+([.][0-9]+)?$ ]] || die 'monotonic clock is invalid'
		printf '%s\n' "${uptime%%.*}"
	fi
}

remove_config() {
	local expected_hash=$1 expected_mode=${2:-} captured captured_hash captured_mode
	prepare_config
	[[ $expected_hash != absent ]] || {
		[[ ! -e $config_file && ! -L $config_file ]]
		return
	}
	captured=$(mktemp --tmpdir="$config_dir" ".$preview_config_name.removed.XXXXXX") || return 1
	unlink -- "$captured" || return 1
	trap 'if [[ -e ${captured:-} || -L ${captured:-} ]]; then unlink -- "$captured" 2>/dev/null || true; fi' RETURN
	mv --no-clobber --no-target-directory -- "$config_file" "$captured" || return 1
	[[ ! -e $config_file && ! -L $config_file && -e $captured ]] || return 1
	captured_hash=$(config_path_hash "$captured" 2>/dev/null || true)
	captured_mode=$(stat -c %a -- "$captured" 2>/dev/null || true)
	if [[ $captured_hash == "$expected_hash" &&
		(-z $expected_mode || $captured_mode == "$expected_mode") ]]; then
		unlink -- "$captured"
		captured=
		trap - RETURN
		return 0
	fi
	if mv --no-clobber --no-target-directory -- "$captured" "$config_file" &&
		[[ ! -e $captured && ! -L $captured ]]; then
		captured=
	else
		retain_external_config "$captured"
		captured=
	fi
	return 1
}

restore_baseline() {
	local expected_hash=$1 present mode temp
	present=$(meta_value baseline-present)
	mode=$(meta_value baseline-mode)
	prepare_config
	case $present in
	yes)
		[[ -f $preview_baseline && ! -L $preview_baseline && $mode =~ ^[0-7]{3,4}$ ]] || return 1
		temp=$(mktemp --tmpdir="$config_dir" ".$preview_config_name.restore.XXXXXX") || return 1
		trap 'unlink -- "${temp:-}" 2>/dev/null || true' RETURN
		cp -- "$preview_baseline" "$temp" || return 1
		chmod "$mode" -- "$temp" || return 1
		if ! publish_config_if_hash "$temp" "$expected_hash" "$mode"; then
			[[ $published_config_retained == false ]] || temp=
			return 1
		fi
		temp=
		trap - RETURN
		;;
	no)
		if [[ ! -e $config_file && ! -L $config_file ]]; then
			return 0
		fi
		remove_config "$expected_hash" 600
		;;
	*) return 1 ;;
	esac
}

restore_captured_baseline() {
	local present=$1 mode=$2 expected_hash=$3 temp
	prepare_config
	case $present in
	yes)
		[[ -f $preview_baseline && ! -L $preview_baseline && $mode =~ ^[0-7]{3,4}$ ]] || return 1
		temp=$(mktemp --tmpdir="$config_dir" ".$preview_config_name.restore.XXXXXX") || return 1
		trap 'unlink -- "${temp:-}" 2>/dev/null || true' RETURN
		cp -- "$preview_baseline" "$temp" || return 1
		chmod "$mode" -- "$temp" || return 1
		if ! publish_config_if_hash "$temp" "$expected_hash" "$mode"; then
			[[ $published_config_retained == false ]] || temp=
			return 1
		fi
		temp=
		trap - RETURN
		;;
	no)
		if [[ ! -e $config_file && ! -L $config_file ]]; then
			return 0
		fi
		remove_config "$expected_hash" 600
		;;
	*) return 1 ;;
	esac
}

retain_external_config() {
	local path=$1
	printf '%s: concurrent %s configuration retained at %s\n' "$preview_program" "$preview_label" "$path" >&2
}
