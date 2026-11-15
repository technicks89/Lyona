#!/bin/sh
set -eu

# What the panel shows from dwm, through the real state bridge, on Xvfb with a
# real dwm:
# - occupied= (#474): the tags with windows, as windows open, move and close.
# - The keyboard layout (#470): dwm's _DWM_KEYBOARD_GROUP and
#   _DWM_KEYBOARD_SYMBOLS, the labels the bridge makes of them, and
#   `dwm-quickshell-state keyboard`, which steps, wraps and clamps, publishes
#   nothing for an unchanged group, and gives up on a dwm that does not answer
#   without leaving a watcher behind.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb xprop xdotool setxkbmap cc pkg-config timeout; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
[ -x "$repo/dwm" ] || {
	printf 'dwm is not built: %s\n' "$repo/dwm" >&2
	exit 1
}

work=$(mktemp -d)
xvfb_pid=
dwm_pid=
client_pids=
cleanup() {
	set +e
	[ -z "$dwm_pid" ] || kill -CONT "$dwm_pid" 2>/dev/null
	for pid in $client_pids $dwm_pid $xvfb_pid; do
		kill "$pid" 2>/dev/null
	done
	wait 2>/dev/null
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
	printf 'panel state: %s\n' "$*" >&2
	[ ! -f "$work/dwm.log" ] || tail -20 "$work/dwm.log" >&2
	exit 1
}

home=$work/home
mkdir -p "$home/.config/lyona" "$work/bin" "$work/no-hooks"
cp "$repo/config/hotkeys.toml" "$repo/config/themes.toml" "$repo/config/window-rules.toml" \
	"$repo/config/layout.toml" "$home/.config/lyona/"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/notify-send"
chmod +x "$work/bin/notify-send"

# A window that waits, printing its id.
cat >"$work/client.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <unistd.h>

int
main(void)
{
	Display *dpy = XOpenDisplay(NULL);
	XClassHint hint = { "panel-state-test", "PanelStateTest" };
	Window win;

	if (!dpy)
		return 1;
	win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, 200, 150, 0, 0,
		WhitePixel(dpy, DefaultScreen(dpy)));
	XSetClassHint(dpy, win, &hint);
	XStoreName(dpy, win, "panel-state-test");
	XMapWindow(dpy, win);
	XSync(dpy, False);
	printf("0x%lx\n", win);
	fflush(stdout);
	for (;;)
		pause();
}
EOF
# Latches XKB group N (relative), as a group-latch key would; it holds until
# the next key event, of which Xvfb has none.
cat >"$work/latch.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/XKBlib.h>
#include <stdlib.h>

int
main(int argc, char **argv)
{
	Display *dpy = XOpenDisplay(NULL);

	if (!dpy || argc != 2 || !XkbLatchGroup(dpy, XkbUseCoreKbd, (unsigned int)atoi(argv[1])))
		return 1;
	XSync(dpy, False);
	return 0;
}
EOF
# shellcheck disable=SC2046 # pkg-config prints separate flags
cc -o "$work/client" "$work/client.c" $(pkg-config --cflags --libs x11)
# shellcheck disable=SC2046
cc -o "$work/latch" "$work/latch.c" $(pkg-config --cflags --libs x11)

Xvfb -displayfd 3 -noreset -screen 0 1024x768x24 \
	-nolisten tcp 3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ ! -s "$work/display" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	sleep 0.05
done
display=:$(sed -n '1p' "$work/display")
case $display in :[0-9]*) ;; *) fail "Xvfb reported no display" ;; esac
export DISPLAY="$display"
i=0
while [ "$i" -lt 100 ] && ! xprop -root >/dev/null 2>&1; do
	i=$((i + 1))
	sleep 0.05
done
setxkbmap -layout us

# No session hook: the developer override names an empty directory.
env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
	LYONA_DEV_SCRIPTS="$work/no-hooks" PATH="$work/bin:$PATH" \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

bridge() {
	"$repo/scripts/dwm-quickshell-state" "$@"
}
# Waits until the bridge's state has the line LINE.
wait_state() {
	i=0
	while [ "$i" -lt 100 ]; do
		bridge state 2>/dev/null | grep -Fqx -- "$1" && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "expected '$1' in the state, got: $(bridge state 2>&1 | grep -E '^(occupied|keyboard_)')"
}
start_client() {
	"$work/client" >"$work/client-id" &
	client_pids="$client_pids $!"
	last_client_pid=$!
	i=0
	while [ ! -s "$work/client-id" ] && [ "$i" -lt 100 ]; do
		i=$((i + 1))
		sleep 0.05
	done
	[ -s "$work/client-id" ] || fail "the test client did not start"
	client_id=$(cat "$work/client-id")
	: >"$work/client-id"
}

i=0
while [ "$i" -lt 100 ] && ! xprop -root _DWM_KEYBOARD_GROUP 2>/dev/null | grep -q '= '; do
	i=$((i + 1))
	sleep 0.05
done

# ── occupied= (#474) ────────────────────────────────────────────────────
wait_state 'occupied='
start_client
first_pid=$last_client_pid
first_id=$client_id
wait_state 'occupied=0'
# A second window, sent to tag 3, then the first to tag 5 (by _NET_WM_DESKTOP,
# which dwm takes as a move).
start_client
second_pid=$last_client_pid
second_id=$client_id
wait_state 'occupied=0'
xdotool set_desktop_for_window "$second_id" 2
wait_state 'occupied=0|2'
xdotool set_desktop_for_window "$first_id" 4
wait_state 'occupied=2|4'
# The last window on a tag closing empties it.
kill "$first_pid"
wait_state 'occupied=2'
kill "$second_pid"
wait_state 'occupied='

# ── the keyboard layout (#470) ──────────────────────────────────────────
wait_state 'keyboard_group=0|1'
wait_state 'keyboard_layouts=US'
setxkbmap -layout us,de
wait_state 'keyboard_group=0|2'
wait_state 'keyboard_layouts=US|DE'
bridge keyboard next || fail "keyboard next failed"
wait_state 'keyboard_group=1|2'
# Wraps both ways.
bridge keyboard next
wait_state 'keyboard_group=0|2'
bridge keyboard prev
wait_state 'keyboard_group=1|2'

# Three layouts, a variant and an explicit group: steps one group per request,
# however quickly they come.
setxkbmap -layout us,de,fr -variant ,nodeadkeys,
wait_state 'keyboard_layouts=US|DE|FR'
bridge keyboard 0
wait_state 'keyboard_group=0|3'
for step in 1 2 3 4; do
	bridge keyboard next || fail "keyboard next $step failed"
done
wait_state 'keyboard_group=1|3'
# A group past the last is the last; an unknown request is refused.
bridge keyboard 3
wait_state 'keyboard_group=2|3'
if bridge keyboard 4 2>/dev/null; then fail "keyboard 4 was accepted"; fi
if bridge keyboard sideways 2>/dev/null; then fail "keyboard sideways was accepted"; fi

# The group already active: dwm writes nothing.
xprop -root -spy _DWM_KEYBOARD_GROUP >"$work/spy.out" 2>/dev/null &
spy_pid=$!
sleep 0.3
bridge keyboard 2
sleep 0.3
kill "$spy_pid"
wait "$spy_pid" 2>/dev/null || :
[ "$(wc -l <"$work/spy.out")" -eq 1 ] || fail "an unchanged group was published again: $(cat "$work/spy.out")"

# With a group latched the effective group is locked + latched: a request
# still ends on the group asked for, and next steps from the effective one.
"$work/latch" 1 || fail "could not latch a group"
wait_state 'keyboard_group=0|3'
bridge keyboard 2
wait_state 'keyboard_group=2|3'
bridge keyboard next
wait_state 'keyboard_group=0|3'
bridge keyboard prev
wait_state 'keyboard_group=2|3'
"$work/latch" 0

# Labels: an explicit ":1", options after the layouts, and an odd name.
xprop -root -f _DWM_KEYBOARD_SYMBOLS 8u -set _DWM_KEYBOARD_SYMBOLS 'pc+gb:1+ru:2+inet(evdev)+ctrl(nocaps)'
xprop -root -f _DWM_KEYBOARD_GROUP 32c -set _DWM_KEYBOARD_GROUP '0, 2'
wait_state 'keyboard_layouts=GB|RU'
xprop -root -f _DWM_KEYBOARD_SYMBOLS 8u -set _DWM_KEYBOARD_SYMBOLS 'pc+us+Odd Name:2'
wait_state 'keyboard_layouts=US|2'
setxkbmap -layout us,de
wait_state 'keyboard_layouts=US|DE'

# A dwm that does not answer: the request fails within its bound, and its
# watcher goes with it.
kill -STOP "$dwm_pid"
started=$(date +%s)
if bridge keyboard next 2>"$work/stopped.err"; then
	kill -CONT "$dwm_pid"
	fail "a request to a stopped dwm succeeded"
fi
[ $(($(date +%s) - started)) -le 4 ] || fail "the request to a stopped dwm took too long"
grep -Fq 'dwm did not take the keyboard layout request' "$work/stopped.err" ||
	fail "no error for a stopped dwm: $(cat "$work/stopped.err")"
sleep 0.2
if pgrep -f 'xprop -root -spy _DWM_SET_KEYBOARD_GROUP' >/dev/null; then
	kill -CONT "$dwm_pid"
	fail "a request left its watcher running"
fi
# TERM while it waits ends the watcher too.
"$repo/scripts/dwm-quickshell-state" keyboard next 2>/dev/null &
request_pid=$!
sleep 0.5
kill -TERM "$request_pid"
wait "$request_pid" 2>/dev/null || :
sleep 0.2
if pgrep -f 'xprop -root -spy _DWM_SET_KEYBOARD_GROUP' >/dev/null; then
	kill -CONT "$dwm_pid"
	fail "TERM left the request's watcher running"
fi
kill -CONT "$dwm_pid"
# The request left behind is taken once dwm runs again.
i=0
while [ "$i" -lt 100 ] && xprop -root _DWM_SET_KEYBOARD_GROUP 2>/dev/null | grep -q '= '; do
	i=$((i + 1))
	sleep 0.05
done

# Back to one layout: one group, no switching.
setxkbmap -layout us
wait_state 'keyboard_group=0|1'
wait_state 'keyboard_layouts=US'

printf 'Panel state (occupied tags, keyboard layout): PASS\n'
