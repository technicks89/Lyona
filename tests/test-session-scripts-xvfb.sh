#!/bin/sh

set -eu

# Sync Sprint 12 S12-13 step 3: one runtime source for the session scripts.
# dwm runs autostart.sh at startup and autostop.sh when it quits:
#   - from PREFIX/lib/lyona beside the installed dwm, with no per-user copy;
#   - from LYONA_DEV_SCRIPTS when that holds the script, and from the install
#     when it does not (saying so);
#   - never from the override as root (in a user namespace, when unshare can
#     make one).
# Each case runs a copy of dwm from an installed layout on an isolated Xvfb.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

for cmd in Xvfb xprop; do
	command -v "$cmd" >/dev/null 2>&1 || {
		printf 'SKIP: %s is unavailable\n' "$cmd"
		exit 77
	}
done
[ -x "$repo/dwm" ] || {
	printf 'SKIP: dwm is not built (run make all)\n'
	exit 77
}

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/session-scripts.XXXXXX")
dwm_pid=
xvfb_pid=
cleanup() {
	[ -z "$dwm_pid" ] || kill "$dwm_pid" 2>/dev/null || :
	[ -z "$xvfb_pid" ] || kill "$xvfb_pid" 2>/dev/null || :
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	[ ! -f "$work/dwm.log" ] || tail -20 "$work/dwm.log" >&2
	exit 1
}

display=":$((($$ % 500) + 1200))"
Xvfb "$display" -screen 0 800x600x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
until DISPLAY=$display xprop -root >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'Xvfb did not start'
	sleep 0.05
done

# The installed layout, and a user who never ran install-user: no
# ~/.local/share/lyona at all.
prefix=$work/prefix
home=$work/home
dev=$work/checkout-scripts
mkdir -p "$prefix/bin" "$prefix/lib/lyona" "$home" "$dev"
cp "$repo/dwm" "$prefix/bin/dwm"
# Each stub records which copy ran: SOURCE:SCRIPT.
stub() { # PATH SOURCE
	# shellcheck disable=SC2016 # ${0##*/} expands when the stub runs
	printf '#!/bin/sh\nprintf "%%s\\n" "%s:${0##*/}" >>"%s"\n' "$2" "$work/ran.log" >"$1"
	chmod 755 "$1"
}
stub "$prefix/lib/lyona/autostart.sh" installed
stub "$prefix/lib/lyona/autostop.sh" installed
stub "$dev/autostart.sh" override

run_session() { # LABEL [env assignments...]: start dwm, then quit it
	label=$1
	shift
	: >"$work/ran.log"
	env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$home/.config" \
		XDG_DATA_HOME="$home/.local/share" "$@" "$prefix/bin/dwm" >"$work/dwm.log" 2>&1 &
	dwm_pid=$!
	i=0
	until grep -q 'autostart.sh' "$work/ran.log"; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail "no autostart.sh ran ($label)"
		kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited at startup ($label)"
		sleep 0.05
	done
	kill -USR2 "$dwm_pid"
	i=0
	while kill -0 "$dwm_pid" 2>/dev/null; do
		i=$((i + 1))
		[ "$i" -lt 100 ] || fail "dwm did not quit ($label)"
		sleep 0.05
	done
	wait "$dwm_pid" 2>/dev/null || :
	dwm_pid=
}

expect_ran() { # LABEL EXPECTED-LINES
	[ "$(cat "$work/ran.log")" = "$2" ] ||
		fail "$1: expected $(printf '%s' "$2" | tr '\n' ' '), ran $(tr '\n' ' ' <"$work/ran.log")"
}

run_session installed
expect_ran installed "$(printf 'installed:autostart.sh\ninstalled:autostop.sh')"
[ ! -e "$home/.local/share/lyona" ] || fail 'dwm created a per-user copy'

# The override runs its own autostart.sh; it has no autostop.sh, so that one
# comes from the install, and dwm says so.
run_session override LYONA_DEV_SCRIPTS="$dev"
expect_ran override "$(printf 'override:autostart.sh\ninstalled:autostop.sh')"
grep -Fqx "dwm: LYONA_DEV_SCRIPTS=$dev has no executable autostop.sh; using the installed one" \
	"$work/dwm.log" || fail 'dwm did not report the missing override script'

# An override that is not a directory of scripts at all falls back entirely.
run_session bad-override LYONA_DEV_SCRIPTS="$work/missing"
expect_ran bad-override "$(printf 'installed:autostart.sh\ninstalled:autostop.sh')"

# As root the override is ignored: a user-writable copy never runs with root's
# rights. unshare -r maps this user to root in a new user namespace.
root_checked=no
if command -v unshare >/dev/null 2>&1 && unshare -r true 2>/dev/null; then
	run_session root unshare -r env LYONA_DEV_SCRIPTS="$dev"
	expect_ran root "$(printf 'installed:autostart.sh\ninstalled:autostop.sh')"
	grep -Fqx 'dwm: ignoring LYONA_DEV_SCRIPTS as root' "$work/dwm.log" ||
		fail 'dwm did not say it ignored the override as root'
	root_checked=yes
fi

printf 'Session scripts (installed, override, partial override, bad override, root: %s): PASS\n' \
	"$root_checked"
