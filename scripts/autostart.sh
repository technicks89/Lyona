#!/bin/sh

start_once() {
	process_name=$1
	shift

	command -v "$1" >/dev/null 2>&1 || return 0
	pgrep -u "$(id -u)" -x "$process_name" >/dev/null 2>&1 && return 0
	"$@" >/dev/null 2>&1 &
}

start_detached_once() {
	process_name=$1
	shift

	command -v "$1" >/dev/null 2>&1 || return 0
	pgrep -u "$(id -u)" -x "$process_name" >/dev/null 2>&1 && return 0
	if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] &&
		command -v setsid >/dev/null 2>&1; then
		setsid -f "$@" >/dev/null 2>&1
	else
		"$@" >/dev/null 2>&1 &
	fi
}

display_command_running() {
	display_command=$1
	display_command_path=$(command -v "$display_command" 2>/dev/null) || return 1
	display_command_path=$(readlink -f "$display_command_path" 2>/dev/null) || return 1
	display_command_uid=$(id -u)
	display_command_display=${DISPLAY:-}
	[ -n "$display_command_display" ] || return 1

	# One stat for every process, rather than one stat per process. Paths
	# under /proc are digits only, so word splitting them back apart is safe.
	display_command_owned=$(stat -c '%u %n' /proc/[0-9]* 2>/dev/null |
		awk -v uid="$display_command_uid" '$1 == uid { print $2 }')

	# One awk over every candidate's environ, rather than a tr and an awk per
	# candidate. Same rule as before: exactly one DISPLAY= entry, and it must
	# match ours.
	display_command_environs=
	for display_command_proc in $display_command_owned; do
		display_command_environs="$display_command_environs $display_command_proc/environ"
	done
	[ -n "$display_command_environs" ] || return 1
	# shellcheck disable=SC2086 # /proc paths are digits only; splitting is intended
	display_command_owned=$(awk -v want="$display_command_display" '
		BEGIN {
			RS = "\0"
			# read each environ explicitly: an unreadable one must be
			# skipped, and naming them as operands makes awk fatal instead
			for (i = 1; i < ARGC; i++) {
				path = ARGV[i]
				matches = 0
				value = ""
				while ((getline entry < path) > 0) {
					if (index(entry, "DISPLAY=") == 1) {
						matches++
						value = substr(entry, 9)
					}
				}
				close(path)
				if (matches == 1 && value == want) {
					sub(/\/environ$/, "", path)
					print path
				}
			}
			exit 0
		}
	' $display_command_environs 2>/dev/null)

	for display_command_proc in $display_command_owned; do
		{ IFS= read -r display_command_stat <"$display_command_proc/stat"; } 2>/dev/null ||
			continue
		# strip through the last ") " exactly as sub(/^.*\) /, "") did, so a
		# comm containing ") " is handled the same way
		display_command_state=${display_command_stat##*') '}
		display_command_state=${display_command_state%% *}
		[ "$display_command_state" != Z ] || continue

		display_process_command=$({
			tr '\0' '\n' <"$display_command_proc/cmdline"
		} 2>/dev/null) ||
			continue
		display_process_arg0=
		display_process_arg1=
		display_process_arg2=
		{
			IFS= read -r display_process_arg0 || true
			IFS= read -r display_process_arg1 || true
			IFS= read -r display_process_arg2 || true
		} <<COMMAND_LINE
$display_process_command
COMMAND_LINE
		[ -z "$display_process_arg2" ] || continue
		display_process_executable=$(readlink -f "$display_command_proc/exe" 2>/dev/null || true)
		if [ "$display_process_executable" = "$display_command_path" ] &&
			[ -z "$display_process_arg1" ]; then
			return 0
		fi
		[ -n "$display_process_arg0" ] && [ -n "$display_process_arg1" ] || continue
		[ "${display_process_arg0##*/}" = "${display_process_executable##*/}" ] || continue
		[ "${display_process_executable##*/}" = bash ] || continue
		display_process_script=$(readlink -f "$display_process_arg1" 2>/dev/null || true)
		[ "$display_process_script" = "$display_command_path" ] && return 0
	done

	return 1
}

start_detached_display_command_once() {
	display_command=$1
	shift
	display_lock_fd=

	command -v "$display_command" >/dev/null 2>&1 || return 0
	[ -n "${DISPLAY:-}" ] || return 0
	if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] &&
		[ ! -L "$XDG_RUNTIME_DIR" ] && command -v flock >/dev/null 2>&1 &&
		command -v sha256sum >/dev/null 2>&1 &&
		[ "$(stat -c %u -- "$XDG_RUNTIME_DIR" 2>/dev/null)" = "$(id -u)" ]; then
		display_lock_dir=$XDG_RUNTIME_DIR/lyona
		display_lock_key=$(printf '%s\n%s\n' "${DISPLAY:-}" "$display_command" |
			sha256sum | awk '{ print $1 }')
		if [ -n "$display_lock_key" ] &&
			(umask 077 && mkdir -p -- "$display_lock_dir") &&
			[ -d "$display_lock_dir" ] && [ ! -L "$display_lock_dir" ]; then
			if chmod 700 -- "$display_lock_dir" 2>/dev/null; then
				exec 9>"$display_lock_dir/dwm-status.$display_lock_key.lock"
				if flock -w 5 -x 9; then
					display_lock_fd=9
				else
					exec 9>&-
				fi
			fi
		fi
	fi
	if display_command_running "$display_command"; then
		if [ -n "$display_lock_fd" ]; then
			flock -u 9
			exec 9>&-
		fi
		return 0
	fi
	if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] &&
		command -v setsid >/dev/null 2>&1; then
		setsid -f "$display_command" "$@" >/dev/null 2>&1 9>&-
	else
		"$display_command" "$@" >/dev/null 2>&1 9>&- &
	fi
	if [ -n "$display_lock_fd" ]; then
		display_wait_attempt=0
		while [ "$display_wait_attempt" -lt 50 ]; do
			display_command_running "$display_command" && break
			display_wait_attempt=$((display_wait_attempt + 1))
			sleep 0.02
		done
		flock -u 9
		exec 9>&-
	fi
}

start_detached() {
	command -v "$1" >/dev/null 2>&1 || return 0
	if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] &&
		command -v setsid >/dev/null 2>&1; then
		setsid -f "$@" >/dev/null 2>&1
	else
		"$@" >/dev/null 2>&1 &
	fi
}

quickshell_tray_ready() {
	config=$1

	command -v timeout >/dev/null 2>&1 || return 1
	timeout 1 quickshell ipc --path "$config" call tray count >/dev/null 2>&1
}

quickshell_instance_pids() {
	config=$1

	command -v jq >/dev/null 2>&1 || return 1
	instances=$(timeout 1 quickshell list --path "$config" --json 2>/dev/null) || return 1
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

quickshell_pid_starttime() {
	pid=$1
	awk '
		{
			line = $0
			sub(/^.*\) /, "", line)
			split(line, fields, " ")
			if (fields[1] != "Z" && fields[20] ~ /^[0-9]+$/) {
				print fields[20]
			}
		}
	' "/proc/$pid/stat" 2>/dev/null
}

quickshell_instance_identities() {
	config=$1
	pids=$(quickshell_instance_pids "$config") || return 1
	for pid in $pids; do
		quickshell_pid_is_owned "$pid" || continue
		starttime=$(quickshell_pid_starttime "$pid")
		[ -n "$starttime" ] || continue
		printf '%s:%s\n' "$pid" "$starttime"
	done
}

quickshell_identity_matches() {
	identity=$1
	pid=${identity%%:*}
	starttime=${identity#*:}

	quickshell_pid_is_owned "$pid" || return 1
	[ "$(quickshell_pid_starttime "$pid")" = "$starttime" ]
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

start_managed_quickshell() {
	config=$1

	if ! quickshell_tray_ready "$config"; then
		stop_managed_quickshell "$config" >/dev/null 2>&1 || true
		start_detached quickshell --path "$config" --no-duplicate
	fi
}

wait_for_quickshell_tray() {
	config=$1

	# shellcheck disable=SC2016 # The script runs in the child shell below.
	timeout 5 sh -c '
		config=$1
		while ! timeout 1 quickshell ipc --path "$config" call tray count \
			>/dev/null 2>&1; do
			sleep 0.1
		done
	' sh "$config"
}

apply_power_settings() {
	helper=
	case $0 in
	*/*) helper=${0%/*}/dwm-quickshell-controlcenter ;;
	esac

	if [ -n "$helper" ] && [ -x "$helper" ]; then
		"$helper" power-apply >/dev/null 2>&1 || true
		return 0
	fi

	if command -v dwm-quickshell-controlcenter >/dev/null 2>&1; then
		dwm-quickshell-controlcenter power-apply >/dev/null 2>&1 || true
		return 0
	fi

	if command -v xset >/dev/null 2>&1; then
		xset s off
		xset s noblank
		xset -dpms
	fi
}

resume_theme_preview() {
	theme_helper=
	case $0 in
	*/*)
		theme_candidate=${0%/*}/dwm-settings-theme
		[ ! -x "$theme_candidate" ] || theme_helper=$theme_candidate
		;;
	esac
	if [ -z "$theme_helper" ] && command -v dwm-settings-theme >/dev/null 2>&1; then
		theme_helper=dwm-settings-theme
	fi
	if [ -n "$theme_helper" ] && command -v timeout >/dev/null 2>&1; then
		if ! timeout --signal=TERM --kill-after=2 5 \
			"$theme_helper" _resume-preview >/dev/null 2>&1; then
			if command -v setsid >/dev/null 2>&1; then
				setsid -f "$theme_helper" _resume-preview >/dev/null 2>&1
			else
				"$theme_helper" _resume-preview </dev/null >/dev/null 2>&1 &
			fi
		fi
	fi
}

PICOM_BACKEND=${PICOM_BACKEND:-xrender}
WM_GRAPHICAL_SESSION=wm-graphical-session.service

resume_theme_preview

apply_power_settings

input_helper=
case $0 in
*/*)
	candidate=${0%/*}/dwm-settings-input
	[ ! -x "$candidate" ] || input_helper=$candidate
	;;
esac
if [ -z "$input_helper" ] && command -v dwm-settings-input >/dev/null 2>&1; then
	input_helper=dwm-settings-input
fi
if [ -n "$input_helper" ]; then
	"$input_helper" apply-saved >/dev/null 2>&1 || true
	if [ "${DWM_AUTOSTART_NO_INPUT_WATCH:-0}" != 1 ]; then
		input_session_pid=${DWM_INPUT_SESSION_PID:-$PPID}
		input_session_start=${DWM_INPUT_SESSION_START:-}
		if [ -z "$input_session_start" ] && [ -r "/proc/$input_session_pid/stat" ]; then
			input_session_start=$(awk '{ print $22 }' "/proc/$input_session_pid/stat" 2>/dev/null || true)
		fi
		if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] && command -v setsid >/dev/null 2>&1; then
			DWM_INPUT_SESSION_PID=$input_session_pid \
				DWM_INPUT_SESSION_START=$input_session_start \
				setsid -f "$input_helper" watch-apply >/dev/null 2>&1
		else
			DWM_INPUT_SESSION_PID=$input_session_pid \
				DWM_INPUT_SESSION_START=$input_session_start \
				"$input_helper" watch-apply >/dev/null 2>&1 &
		fi
	fi
fi

display_helper=
case $0 in
*/*)
	candidate=${0%/*}/dwm-settings-display
	[ ! -x "$candidate" ] || display_helper=$candidate
	;;
esac
if [ -z "$display_helper" ] && command -v dwm-settings-display >/dev/null 2>&1; then
	display_helper=dwm-settings-display
fi

if command -v xsettingsd >/dev/null 2>&1 &&
	! pgrep -u "$(id -u)" -x xsettingsd >/dev/null 2>&1; then
	if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] && command -v setsid >/dev/null 2>&1; then
		setsid -f xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/lyona/xsettingsd.conf" \
			>/dev/null 2>&1 || true
	else
		xsettingsd -c "${XDG_CONFIG_HOME:-$HOME/.config}/lyona/xsettingsd.conf" \
			>/dev/null 2>&1 &
	fi
fi

if [ -n "$display_helper" ]; then
	"$display_helper" dpi-apply-saved >/dev/null 2>&1 || true
fi

THEME_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/lyona/theme-env.sh"
# shellcheck disable=SC1090
[ -f "$THEME_ENV" ] && . "$THEME_ENV"

desktop_tokens=${XDG_CURRENT_DESKTOP:-}
case :$desktop_tokens: in
*:dwm:*) ;;
*) desktop_tokens="${desktop_tokens:+$desktop_tokens:}dwm" ;;
esac
case :$desktop_tokens: in
*:X-DWM:*) ;;
*) desktop_tokens="X-DWM:$desktop_tokens" ;;
esac
XDG_CURRENT_DESKTOP=$desktop_tokens
export XDG_CURRENT_DESKTOP
export DESKTOP_SESSION="${DESKTOP_SESSION:-dwm}"
export XDG_SESSION_TYPE=x11
export QT_QPA_PLATFORM=xcb
unset WAYLAND_DISPLAY

systemctl_import_pid=
dbus_import_pid=
if command -v systemctl >/dev/null 2>&1; then
	{
		systemctl --user unset-environment WAYLAND_DISPLAY
		systemctl --user import-environment \
			DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP DESKTOP_SESSION \
			XDG_SESSION_TYPE QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME \
			XCURSOR_THEME XCURSOR_SIZE
	} &
	systemctl_import_pid=$!
fi
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
	{
		dbus-update-activation-environment WAYLAND_DISPLAY=
		dbus-update-activation-environment --systemd \
			DISPLAY XAUTHORITY XDG_CURRENT_DESKTOP DESKTOP_SESSION \
			XDG_SESSION_TYPE QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME \
			XCURSOR_THEME XCURSOR_SIZE
	} 2>/dev/null &
	dbus_import_pid=$!
fi
[ -z "$systemctl_import_pid" ] || wait "$systemctl_import_pid"
[ -z "$dbus_import_pid" ] || wait "$dbus_import_pid"

QUICKSHELL_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml"
if [ -f "$QUICKSHELL_CONFIG" ]; then
	quickshell_check=
	quickshell_compatible=0
	case $0 in
	*/*)
		[ ! -x "${0%/*}/dwm-quickshell-version-check" ] ||
			quickshell_check=${0%/*}/dwm-quickshell-version-check
		;;
	esac
	if [ -z "$quickshell_check" ] && command -v dwm-quickshell-version-check >/dev/null 2>&1; then
		quickshell_check=dwm-quickshell-version-check
	fi
	if [ -n "$quickshell_check" ] && "$quickshell_check"; then
		quickshell_compatible=1
		start_managed_quickshell "$QUICKSHELL_CONFIG"
	else
		printf '%s\n' 'lyona: compatible Quickshell 0.3.0 or newer is required' >&2
	fi
	if [ "$quickshell_compatible" -eq 1 ]; then
		wait_for_quickshell_tray "$QUICKSHELL_CONFIG" || true
	fi
fi

xdg_autostart_started=0

if command -v systemctl >/dev/null 2>&1; then
	if systemctl --user start "$WM_GRAPHICAL_SESSION" 2>/dev/null ||
		{
			systemctl --user daemon-reload 2>/dev/null &&
				systemctl --user start "$WM_GRAPHICAL_SESSION" 2>/dev/null
		}; then
		xdg_autostart_started=1
	fi
fi

if command -v feh >/dev/null 2>&1; then
	wallpaper_helper=dwm-settings-wallpaper
	if ! command -v "$wallpaper_helper" >/dev/null 2>&1; then
		case $0 in
		*/*) wallpaper_helper=${0%/*}/dwm-settings-wallpaper ;;
		esac
	fi
	if command -v "$wallpaper_helper" >/dev/null 2>&1 || [ -x "$wallpaper_helper" ]; then
		(
			"$wallpaper_helper" session-apply >/dev/null 2>&1 || {
				! pgrep -u "$(id -u)" -x feh >/dev/null 2>&1 &&
					feh --no-fehbg --randomize --bg-fill "$HOME/Pictures/backgrounds" >/dev/null 2>&1
			}
		) &
	elif ! pgrep -u "$(id -u)" -x feh >/dev/null 2>&1; then
		start_once feh feh --no-fehbg --randomize --bg-fill "$HOME/Pictures/backgrounds"
	fi
fi

start_detached_once picom picom --backend "$PICOM_BACKEND"

start_detached_display_command_once dwm-status

lock_watch=dwm-lock-watch
if ! command -v "$lock_watch" >/dev/null 2>&1; then
	case $0 in
	*/*)
		lock_watch=${0%/*}/dwm-lock-watch
		;;
	esac
fi
start_detached_once dwm-lock-watch "$lock_watch"

for agent in \
	/usr/lib/mate-polkit/polkit-mate-authentication-agent-1 \
	/usr/libexec/polkit-mate-authentication-agent-1 \
	/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 \
	/usr/libexec/polkit-gnome-authentication-agent-1 \
	/usr/lib/polkit-kde-authentication-agent-1 \
	/usr/libexec/polkit-kde-authentication-agent-1 \
	/usr/bin/lxpolkit \
	/usr/lib/lxpolkit/lxpolkit; do
	if [ -x "$agent" ]; then
		agent_name=$(basename "$agent")
		if ! pgrep -u "$(id -u)" -x "$agent_name" >/dev/null 2>&1; then
			"$agent" >/dev/null 2>&1 &
		fi
		break
	fi
done

if [ "$xdg_autostart_started" -eq 0 ]; then
	if command -v dex >/dev/null 2>&1; then
		dex -a 2>/dev/null
	elif command -v dex-autostart >/dev/null 2>&1; then
		dex-autostart -a 2>/dev/null
	fi
fi

apply_power_settings
