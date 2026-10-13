# shellcheck shell=sh
#
# The user's graphical logins, as logind reports them, shared by autostop.sh
# (which ends the shared user targets at logout) and autostart.sh (which ends
# targets a crashed login left behind). POSIX, as both callers are:
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
