#!/bin/sh

set -eu

# A checkout keeps the shared shell code beside the scripts; an install keeps it
# in PREFIX/lib/lyona.
lyona_lib=${0%/*}
[ "$lyona_lib" != "$0" ] || lyona_lib=.
[ -f "$lyona_lib/dwm-session.sh" ] || lyona_lib=${lyona_lib%bin}lib/lyona
# shellcheck source=scripts/dwm-session.sh
. "$lyona_lib/dwm-session.sh"

command -v loginctl >/dev/null 2>&1 || exit 0
self_session_id=$(loginctl show-session self -p Id --value 2>/dev/null) || exit 0
[ -n "$self_session_id" ] || exit 0
case "${XDG_SESSION_ID:-$self_session_id}" in
"$self_session_id") session_id=$self_session_id ;;
*) exit 0 ;;
esac

session_details=$(loginctl show-session "$session_id" \
	-p Name -p Type -p Class -p Active -p Display 2>/dev/null) || exit 0
session_owner=$(printf '%s\n' "$session_details" | sed -n 's/^Name=//p')
session_type=$(printf '%s\n' "$session_details" | sed -n 's/^Type=//p')
session_class=$(printf '%s\n' "$session_details" | sed -n 's/^Class=//p')
session_display=$(printf '%s\n' "$session_details" | sed -n 's/^Display=//p')
user_name=$(id -un)
[ "$session_owner" = "$user_name" ] || exit 0

case "$session_type:$session_class:$session_display" in
x11:user:?*)
	case "${DISPLAY:-}" in
	"$session_display" | "$session_display".[0-9]*) ;;
	*) exit 0 ;;
	esac
	;;
esac

stop_targets=1
! lyona_other_graphical_session "$session_id" || stop_targets=0

if [ "$stop_targets" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
	systemctl --user stop \
		xdg-desktop-autostart.target \
		wm-graphical-session.service \
		graphical-session.target \
		>/dev/null 2>&1 || true
fi

case "$session_type:$session_class:$session_display" in
x11:user:?*) loginctl terminate-session "$session_id" >/dev/null 2>&1 || true ;;
esac
