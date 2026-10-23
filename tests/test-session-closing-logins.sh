#!/bin/sh
# #448: at login, autostart ends this user's other X11 logins that logind
# reports closing, as one whose X server died, and only those. It does so only
# from this user's X11 login on its own display: a test's private X server in a
# desktop login must not end that desktop's sessions (#368).

set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

user=$(id -un)
# logind: self is c1, an X11 login on :0 (TEST_SELF_*), and the user has
# sessions c1 to c6. c2 is closing, the dead login; c3 is an active X11 login;
# c4 is another user's closing one; c5 a closing TTY login; c6 a closing
# greeter. Ends are logged.
cat >"$work/bin/loginctl" <<'STUB'
#!/bin/sh
case $* in
"show-user "*" -p Sessions --value") printf 'c1 c2 c3 c4 c5 c6\n' ;;
"show-session c1 -p Name -p Type -p Class -p Display")
	printf 'Name=%s\nType=%s\nClass=user\nDisplay=:0\n' "${TEST_SELF_OWNER:?}" "${TEST_SELF_TYPE:-x11}"
	;;
"show-session "*" -p Name -p Type -p Class -p State")
	case $2 in
	c2) printf 'Name=%s\nType=x11\nClass=user\nState=closing\n' "$TEST_USER" ;;
	c3) printf 'Name=%s\nType=x11\nClass=user\nState=active\n' "$TEST_USER" ;;
	c4) printf 'Name=someone-else\nType=x11\nClass=user\nState=closing\n' ;;
	c5) printf 'Name=%s\nType=tty\nClass=user\nState=closing\n' "$TEST_USER" ;;
	c6) printf 'Name=%s\nType=x11\nClass=greeter\nState=closing\n' "$TEST_USER" ;;
	*) exit 1 ;;
	esac
	;;
"kill-session "*) printf '%s\n' "$*" >>"${TEST_LOG:?}" ;;
*) exit 1 ;;
esac
STUB
chmod +x "$work/bin/loginctl"

ends() { # DISPLAY [VAR=value...]
	display=$1
	shift
	: >"$work/log"
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/bin:$PATH" DISPLAY="$display" TEST_USER="$user" TEST_SELF_OWNER="$user" \
		TEST_LOG="$work/log" "$@" lyona_lib="$repo/scripts" sh -c '
		. "$lyona_lib/dwm-session.sh"
		lyona_end_closing_x11_sessions c1
	'
	cat "$work/log"
}

[ "$(ends :0)" = 'kill-session c2' ] ||
	fail "the closing X11 login alone was not ended: $(ends :0)"
[ "$(ends :0.0)" = 'kill-session c2' ] ||
	fail "a screen of this login's display was not taken for it: $(ends :0.0)"
[ -z "$(ends :5)" ] || fail "a private X server in the login ended its sessions: $(ends :5)"
[ -z "$(ends '')" ] || fail "no display ended sessions: $(ends '')"
[ -z "$(ends :0 TEST_SELF_TYPE=tty)" ] || fail 'a TTY login ended sessions'
[ -z "$(ends :0 TEST_SELF_OWNER=someone-else)" ] || fail "another user's login ended sessions"

printf 'Closing X11 logins are ended at login, only from the X11 login: PASS\n'
