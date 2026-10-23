# shellcheck shell=sh
#
# The user's graphical logins, as logind reports them, shared by autostop.sh
# (which ends the shared user targets at logout) and autostart.sh (which ends
# targets and closing logins a crashed login left behind). POSIX, as both
# callers are:
#
#     . "$lyona_lib/dwm-session.sh"
#     lyona_other_graphical_session "$session_id" || stop_the_targets
#
# The user's systemd manager outlives a login, so graphical-session.target and
# the XDG autostart target are shared by every graphical login of the user.

# True when this user has an active X11 or Wayland login other than SESSION_ID,
# and also when logind cannot say: a shared target is kept unless it is known
# that no other login uses it.
lyona_other_graphical_session() {
	_lyona_session=$1
	_lyona_user=$(id -un)
	_lyona_sessions=$(loginctl show-user "$(id -u)" -p Sessions --value 2>/dev/null) || return 0
	for _lyona_other in $_lyona_sessions; do
		[ "$_lyona_other" != "$_lyona_session" ] || continue
		_lyona_details=$(loginctl show-session "$_lyona_other" \
			-p Name -p Type -p Class -p Active 2>/dev/null) || return 0
		_lyona_owner=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Name=//p')
		_lyona_type=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Type=//p')
		_lyona_class=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Class=//p')
		_lyona_active=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Active=//p')
		case "$_lyona_type:$_lyona_class:$_lyona_active" in
		x11:user:yes | wayland:user:yes)
			[ "$_lyona_owner" != "$_lyona_user" ] || return 0
			;;
		esac
	done
	return 1
}

# lyona_end_closing_x11_sessions SESSION_ID: end this user's other X11 logins
# that logind reports closing: their leader is gone, as when the X server died,
# and what they left running stays until a reboot under logind's default
# KillUserProcesses=no. A Quickshell that hung as its X server died kept its
# old login's helpers with it (#448). What is left is sent SIGTERM: logind has
# stopped such a session once already, and terminate-session does nothing
# more, while kill-session signals it again; one's own session needs no
# authorization, and failures are ignored. A hung Quickshell ignores the
# signal, and the lifecycle's stop sequence replaces it. Only from the X11
# login SESSION_ID on its own display, as autostop.sh checks too: a test's
# private X server inside a desktop login must not end that desktop's
# sessions (#368).
lyona_end_closing_x11_sessions() {
	_lyona_session=$1
	[ -n "$_lyona_session" ] || return 0
	_lyona_user=$(id -un)
	_lyona_details=$(loginctl show-session "$_lyona_session" \
		-p Name -p Type -p Class -p Display 2>/dev/null) || return 0
	_lyona_owner=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Name=//p')
	_lyona_type=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Type=//p')
	_lyona_class=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Class=//p')
	_lyona_display=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Display=//p')
	[ "$_lyona_owner:$_lyona_type:$_lyona_class" = "$_lyona_user:x11:user" ] || return 0
	case "${DISPLAY:-}" in
	'') return 0 ;;
	"$_lyona_display" | "$_lyona_display".[0-9]*) ;;
	*) return 0 ;;
	esac
	_lyona_sessions=$(loginctl show-user "$(id -u)" -p Sessions --value 2>/dev/null) || return 0
	for _lyona_other in $_lyona_sessions; do
		[ "$_lyona_other" != "$_lyona_session" ] || continue
		_lyona_details=$(loginctl show-session "$_lyona_other" \
			-p Name -p Type -p Class -p State 2>/dev/null) || continue
		_lyona_owner=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Name=//p')
		_lyona_type=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Type=//p')
		_lyona_class=$(printf '%s\n' "$_lyona_details" | sed -n 's/^Class=//p')
		_lyona_state=$(printf '%s\n' "$_lyona_details" | sed -n 's/^State=//p')
		[ "$_lyona_owner:$_lyona_type:$_lyona_class:$_lyona_state" = "$_lyona_user:x11:user:closing" ] ||
			continue
		loginctl kill-session "$_lyona_other" >/dev/null 2>&1 || true
	done
}
