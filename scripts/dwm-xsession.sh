# shellcheck shell=bash
#
# Which X session a Settings helper is talking to, in one place (#369). The
# wallpaper and display previews both tie their recovery state to the X server
# it was made on: after the server restarts (a crash, a logout), state from the
# old one must not be applied to the new one. Bash, for the helpers that source
# it:
#
#     . "$lyona_lib/dwm-xsession.sh"
#
#   valid_display DISPLAY        DISPLAY is one line, 255 characters or fewer.
#   normalize_x11_display VALUE  ":0.0", "unix:0" and ":0" all name ":0".
#   x11_session_identity DISPLAY The server running DISPLAY, printed: a local
#                                display by its socket (device, inode and
#                                owner: the server creates it when it starts),
#                                any other by its XAUTHORITY file. Fails when
#                                neither can be found, or the socket is not a
#                                socket or is a symbolic link.
#
# LYONA_X11_SOCKET_DIR moves /tmp/.X11-unix for the tests.

valid_display() {
	local value=${1:-}
	[[ -n $value && ${#value} -le 255 && $value != *$'\t'* &&
		$value != *$'\r'* && $value != *$'\n'* ]]
}

normalize_x11_display() {
	local value=$1
	if [[ $value =~ ^(.*:[0-9]+)[.]0+$ ]]; then
		value=${BASH_REMATCH[1]}
	fi
	[[ $value != unix:* ]] || value=:${value#unix:}
	printf '%s\n' "$value"
}

x11_session_identity() {
	local display socket_path identity
	display=$(normalize_x11_display "${1:-}")
	valid_display "$display" || return 1
	if [[ $display =~ ^:([0-9]+)$ ]]; then
		socket_path=${LYONA_X11_SOCKET_DIR:-/tmp/.X11-unix}/X${BASH_REMATCH[1]}
		[[ -S $socket_path && ! -L $socket_path ]] || return 1
		identity=$(stat -Lc '%d:%i:%u' -- "$socket_path") || return 1
		printf 'socket:%s:%s\n' "$display" "$identity"
		return
	fi
	if [[ -n ${XAUTHORITY:-} && -f $XAUTHORITY && ! -L $XAUTHORITY ]]; then
		identity=$(stat -Lc '%d:%i:%u' -- "$XAUTHORITY") || return 1
		printf 'xauthority:%s:%s\n' "$display" "$identity"
		return
	fi
	return 1
}
