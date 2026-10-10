#!/bin/sh

# A checkout keeps the shared shell code beside the scripts; an install keeps it
# in PREFIX/lib/lyona (Sync Sprint 12 S12-13).
lyona_lib=${0%/*}
[ "$lyona_lib" != "$0" ] || lyona_lib=.
[ -f "$lyona_lib/dwm-xdg.sh" ] || lyona_lib=${lyona_lib%bin}lib/lyona
# shellcheck source=scripts/dwm-proc.sh
. "$lyona_lib/dwm-proc.sh"
# shellcheck source=scripts/dwm-xdg.sh
. "$lyona_lib/dwm-xdg.sh"
# shellcheck source=scripts/dwm-quickshell-lifecycle.sh
. "$lyona_lib/dwm-quickshell-lifecycle.sh"
# Lenient: a session must still start without HOME; what needs it is skipped.
lyona_xdg_dirs lenient

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

start_detached() {
	command -v "$1" >/dev/null 2>&1 || return 0
	if [ "${DWM_AUTOSTART_NO_SETSID:-0}" != 1 ] &&
		command -v setsid >/dev/null 2>&1; then
		setsid -f "$@" >/dev/null 2>&1
	else
		"$@" >/dev/null 2>&1 &
	fi
}

# Until the tray is up, so tray apps started next find it; at most 5 seconds.
# The tray owns org.kde.StatusNotifierWatcher: gdbus waits for that name, one
# process and no polling (#288). Without gdbus, or with no session bus, ask
# Quickshell over IPC every 0.1 s.
wait_for_quickshell_tray() {
	config=$1

	if command -v gdbus >/dev/null 2>&1 &&
		{ [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || [ -S "${XDG_RUNTIME_DIR:-/nonexistent}/bus" ]; }; then
		timeout 6 gdbus wait --session --timeout 5 org.kde.StatusNotifierWatcher >/dev/null 2>&1
		return
	fi
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
	*/*) helper=${0%/*}/dwm-settings-power ;;
	esac

	if [ -n "$helper" ] && [ -x "$helper" ]; then
		"$helper" power-apply >/dev/null 2>&1 || true
		return 0
	fi

	if command -v dwm-settings-power >/dev/null 2>&1; then
		dwm-settings-power power-apply >/dev/null 2>&1 || true
		return 0
	fi

	# Only reached when no power helper exists. It honours a saved
	# power.conf the way the helper's read_power_config does (same keys, same
	# boolean words, timeouts kept within 60-86400 s), and otherwise the D-13
	# defaults: blank at 10 minutes. Locking needs light-locker, which only the
	# helper starts.
	command -v xset >/dev/null 2>&1 || return 0
	power_dpms_enabled=1
	power_dpms_timeout=600
	power_lock_enabled=1
	power_lock_timeout=600
	power_config=$config_home/lyona/power.conf
	if [ -r "$power_config" ]; then
		while IFS='=' read -r power_key power_value || [ -n "$power_key" ]; do
			power_key=$(printf '%s' "$power_key" | tr -d '[:space:]')
			power_value=${power_value%%#*}
			power_value=$(printf '%s' "$power_value" | tr -d '[:space:]')
			case $power_key in
			dpms_enabled | lock_enabled)
				case $(printf '%s' "$power_value" | tr '[:upper:]' '[:lower:]') in
				1 | true | yes | on | enabled) power_value=1 ;;
				*) power_value=0 ;;
				esac
				;;
			dpms_timeout | lock_timeout)
				case $power_value in
				'' | *[!0123456789]*) continue ;;
				esac
				[ "$power_value" -ge 60 ] || power_value=60
				[ "$power_value" -le 86400 ] || power_value=86400
				;;
			*) continue ;;
			esac
			case $power_key in
			dpms_enabled) power_dpms_enabled=$power_value ;;
			dpms_timeout) power_dpms_timeout=$power_value ;;
			lock_enabled) power_lock_enabled=$power_value ;;
			lock_timeout) power_lock_timeout=$power_value ;;
			esac
		done <"$power_config"
	fi
	if [ "$power_lock_enabled" = 1 ]; then
		xset s "$power_lock_timeout"
	else
		xset s off
		xset s noblank
	fi
	if [ "$power_dpms_enabled" = 1 ]; then
		xset +dpms
		xset dpms "$power_dpms_timeout" "$power_dpms_timeout" "$power_dpms_timeout"
	else
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
		if [ -z "$input_session_start" ]; then
			input_session_start=$(proc_starttime "$input_session_pid" || true)
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
		setsid -f xsettingsd -c "$config_home/lyona/xsettingsd.conf" \
			>/dev/null 2>&1 || true
	else
		xsettingsd -c "$config_home/lyona/xsettingsd.conf" \
			>/dev/null 2>&1 &
	fi
fi

if [ -n "$display_helper" ]; then
	# The layout last kept in Settings, when the same monitors are connected.
	"$display_helper" apply-kept >/dev/null 2>&1 || true
	"$display_helper" dpi-apply-saved >/dev/null 2>&1 || true
fi

THEME_ENV="$config_home/lyona/theme-env.sh"
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

QUICKSHELL_CONFIG=$config_home/quickshell/shell.qml
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
		# Theme.uiScale (config/quickshell/core/Theme.qml) is the shell's own
		# DPI scaling, driven by dwm-settings-display's dpi.current -- not
		# Qt's. Qt6 scales automatically from the X server's DPI by default,
		# and the two would otherwise compound (a 1.5x DPI setting rendering
		# at 1.5 * 1.5 = 2.25x). Scoped to Quickshell's own launch rather than
		# exported session-wide, so other Qt apps keep their native scaling;
		# any later self-relaunch (dwm-quickshell-controlcenter's restart
		# action) still inherits it as a descendant of this process.
		QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1 \
			start_managed_quickshell "$QUICKSHELL_CONFIG" start_detached
	else
		printf '%s\n' 'lyona: compatible Quickshell 0.3.0 or newer is required' >&2
	fi
	if [ "$quickshell_compatible" -eq 1 ]; then
		wait_for_quickshell_tray "$QUICKSHELL_CONFIG" || true
	fi
fi

xdg_autostart_started=0

# Refresh generated entries first: an installer may have seeded user exclusions
# after this user manager started, even when the wm shim already exists.
if command -v systemctl >/dev/null 2>&1; then
	if systemctl --user daemon-reload 2>/dev/null &&
		systemctl --user start "$WM_GRAPHICAL_SESSION" 2>/dev/null; then
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

# One notification about the session, once. Quickshell shows notifications and
# may not be up yet, so it is tried for up to DWM_AUTOSTART_NOTIFY_TRIES (15)
# times DWM_AUTOSTART_NOTIFY_INTERVAL (2) seconds, then given up: never a loop.
notify_retry() { # URGENCY TITLE BODY: 0 once shown, 1 if it never was
	command -v notify-send >/dev/null 2>&1 || return 1
	tries=${DWM_AUTOSTART_NOTIFY_TRIES:-15}
	while [ "$tries" -gt 0 ]; do
		notify-send -a lyona -u "$1" -- "$2" "$3" >/dev/null 2>&1 && return 0
		tries=$((tries - 1))
		[ "$tries" -eq 0 ] || sleep "${DWM_AUTOSTART_NOTIFY_INTERVAL:-2}"
	done
	return 1
}

notify_session_problem() {
	notify_retry critical "$1" "$2" || :
}

# Picom is part of the lyona desktop: the overview's window previews need it
# (#244). dwm never depends on it. If it is missing or cannot start, the session
# goes on, the overview keeps its icon-and-title cards, and the user is told
# once. dwm-settings-picom picks the backend for this GPU and honours
# PICOM_BACKEND as an override; it starts nothing if this display already has a
# compositor.
start_compositor() {
	if ! command -v picom >/dev/null 2>&1; then
		command -v quickshell >/dev/null 2>&1 || return 0
		notify_session_problem "Picom is not installed" \
			"Window previews in the overview are off. Install it with: sudo pacman -S picom"
		return 0
	fi
	picom_helper=$(command -v dwm-settings-picom 2>/dev/null || printf '%s' "${0%/*}/dwm-settings-picom")
	if ! picom_error=$("$picom_helper" start 2>&1 >/dev/null); then
		notify_session_problem "Picom could not start" \
			"Window previews in the overview are off. Try the XRender backend in Settings > Appearance > Compositor. $picom_error"
	fi
	return 0
}
start_compositor &

# dwm-status is no longer started: dwm draws no bar, and the panel takes the
# battery from UPower, so nothing read the root name it wrote (#284).

# Gear Lever, when the image installer could not set it up (it ran in a chroot):
# once per login, in the background, until it succeeds (Sync Sprint 16).
if [ -n "${state_home:-}" ] && [ -f "$state_home/lyona/pending-gearlever" ] &&
	command -v install-gearlever >/dev/null 2>&1; then
	# shellcheck disable=SC2016 # expanded by the inner shell
	start_detached sh -c 'install-gearlever && rm -f -- "$1"' sh "$state_home/lyona/pending-gearlever"
fi

# The first keys, once, after an image install (#295): its postinstall leaves
# this marker. Removed once shown, so a login without notifications tries again.
if [ -n "${state_home:-}" ] && [ -f "$state_home/lyona/first-login-keys" ]; then
	(
		notify_retry normal "Welcome to lyona" \
			"Super+/ shows every key. Super+R opens the app launcher, Super+F1 the Control Center." &&
			rm -f -- "$state_home/lyona/first-login-keys"
	) &
fi

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
