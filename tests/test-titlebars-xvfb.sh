#!/bin/sh
set -eu

# Title bars on floating windows (#496): a real dwm on Xvfb, one screen split
# into two RandR monitors. Off by default with no extra windows; turned on by
# saving themes.toml; on floating windows of the allowed tags only, never on a
# tiled or fullscreen one; dragging moves the window and the x closes it
# (WM_DELETE_WINDOW); following the window to the other monitor; an invalid
# value keeps the last valid one; off again removes them.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb xprop xdotool xrandr cc pkg-config; do
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
	printf 'titlebars: %s\n' "$*" >&2
	[ ! -f "$work/dwm.log" ] || tail -20 "$work/dwm.log" >&2
	exit 1
}

home=$work/home
config=$home/.config/lyona
mkdir -p "$config" "$work/bin" "$work/no-hooks"
cp "$repo/config/hotkeys.toml" "$repo/config/themes.toml" "$repo/config/layout.toml" "$config/"
cp "$repo/config/window-rules.toml" "$config/window-rules.toml"
# The test's floating windows, by class.
printf '\nrules = [\n  { class="DwmTitleFloat", isfloating=1 },\n  { class="DwmTitleOnTop", isfloating=1, alwaysontop=1 },\n]\n' >"$work/float-rule"
awk 'BEGIN { skip = 0 } /^rules = \[/ { skip = 1 } skip && /^\]/ { skip = 0; next } !skip' \
	"$repo/config/window-rules.toml" >"$config/window-rules.toml"
cat "$work/float-rule" >>"$config/window-rules.toml"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s/notify.log"\n' "$work" >"$work/bin/notify-send"
chmod +x "$work/bin/notify-send"
: >"$work/notify.log"

cat >"$work/client.c" <<'EOF'
#include <X11/Xatom.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* open CLASS: a window that prints its id, then "deleted" when asked to close.
 * strip WIN: its title strip's "X Y W H" (mapped), or "none".
 * frame WIN: the window's frame, border included, as "X Y W H".
 * fullscreen WIN 0|1: asks for _NET_WM_STATE_FULLSCREEN. */
static Window
strip_for(Display *dpy, Window target)
{
	Atom prop = XInternAtom(dpy, "_DWM_TITLEBAR_FOR", False), type;
	Window root_return, parent, *children = NULL, found = None;
	unsigned int n, i;
	int format;
	unsigned long items, after;
	unsigned char *data;
	XWindowAttributes wa;

	if (!XQueryTree(dpy, DefaultRootWindow(dpy), &root_return, &parent, &children, &n))
		return None;
	for (i = 0; i < n && !found; i++) {
		data = NULL;
		if (XGetWindowProperty(dpy, children[i], prop, 0, 1, False, XA_WINDOW, &type, &format,
		    &items, &after, &data) == Success && data && items == 1
		    && (target == None || *(Window *)data == target)
		    && XGetWindowAttributes(dpy, children[i], &wa) && wa.map_state == IsViewable)
			found = children[i];
		if (data)
			XFree(data);
	}
	if (children)
		XFree(children);
	return found;
}

int
main(int argc, char **argv)
{
	Display *dpy = XOpenDisplay(NULL);
	Window win, root;
	int x, y;
	unsigned int w, h, b, depth;

	if (!dpy || argc < 2)
		return 1;
	if (!strcmp(argv[1], "strip") && argc == 3) {
		Window s = strip_for(dpy, strtoul(argv[2], NULL, 0));
		if (!s || !XGetGeometry(dpy, s, &root, &x, &y, &w, &h, &b, &depth)) {
			puts("none");
			return 0;
		}
		printf("%d %d %u %u\n", x, y, w, h);
		return 0;
	}
	if (!strcmp(argv[1], "frame") && argc == 3) {
		if (!XGetGeometry(dpy, strtoul(argv[2], NULL, 0), &root, &x, &y, &w, &h, &b, &depth))
			return 1;
		printf("%d %d %u %u\n", x, y, w + 2 * b, h + 2 * b);
		return 0;
	}
	if (!strcmp(argv[1], "fullscreen") && argc == 4) {
		XEvent ev = { 0 };
		ev.xclient.type = ClientMessage;
		ev.xclient.window = strtoul(argv[2], NULL, 0);
		ev.xclient.message_type = XInternAtom(dpy, "_NET_WM_STATE", False);
		ev.xclient.format = 32;
		ev.xclient.data.l[0] = atoi(argv[3]);
		ev.xclient.data.l[1] = XInternAtom(dpy, "_NET_WM_STATE_FULLSCREEN", False);
		XSendEvent(dpy, DefaultRootWindow(dpy), False,
			SubstructureRedirectMask | SubstructureNotifyMask, &ev);
		XSync(dpy, False);
		return 0;
	}
	if (!strcmp(argv[1], "open") && argc == 3) {
		XClassHint hint = { argv[2], argv[2] };
		Atom del = XInternAtom(dpy, "WM_DELETE_WINDOW", False);
		XEvent ev;

		win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 300, 300, 300, 200, 0, 0,
			WhitePixel(dpy, DefaultScreen(dpy)));
		XSetClassHint(dpy, win, &hint);
		XStoreName(dpy, win, "Titlebar test window");
		XSetWMProtocols(dpy, win, &del, 1);
		XMapWindow(dpy, win);
		XSync(dpy, False);
		printf("0x%lx\n", win);
		fflush(stdout);
		for (;;) {
			XNextEvent(dpy, &ev);
			if (ev.type == ClientMessage && (Atom)ev.xclient.data.l[0] == del) {
				puts("deleted");
				fflush(stdout);
				return 0;
			}
		}
	}
	return 1;
}
EOF
# shellcheck disable=SC2046 # pkg-config prints separate flags
cc -o "$work/client" "$work/client.c" $(pkg-config --cflags --libs x11)

Xvfb -displayfd 3 -noreset -screen 0 2048x768x24 -nolisten tcp 3>"$work/display" >"$work/xvfb.log" 2>&1 &
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
xrandr --setmonitor LEFT 1024/270x768/200+0+0 screen >/dev/null
xrandr --setmonitor RIGHT 1024/270x768/200+1024+0 none >/dev/null
xdotool mousemove 500 400

env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
	LYONA_DEV_SCRIPTS="$work/no-hooks" PATH="$work/bin:$PATH" \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!
i=0
while [ "$i" -lt 100 ] && ! xprop -root _DWM_MONITOR_DESKTOPS 2>/dev/null | grep -q '1024, 0, 1024, 768'; do
	i=$((i + 1))
	sleep 0.05
done

# open CLASS: starts a client; its id in client_id, its output file in client_out.
open_client() {
	client_count=$((${client_count:-0} + 1))
	n=$client_count
	client_out=$work/client-$n.out
	"$work/client" open "$1" >"$client_out" &
	client_pids="$client_pids $!"
	last_client_pid=$!
	i=0
	while [ ! -s "$client_out" ] && [ "$i" -lt 100 ]; do
		i=$((i + 1))
		sleep 0.05
	done
	client_id=$(sed -n 1p "$client_out")
	[ -n "$client_id" ] || fail "a client did not start"
	sleep 0.3
}
strip() { "$work/client" strip "$1"; }
frame() { "$work/client" frame "$1"; }
wait_strip() { # WINDOW none|some
	i=0
	while [ "$i" -lt 100 ]; do
		s=$(strip "$1")
		if [ "$2" = none ] && [ "$s" = none ]; then return 0; fi
		if [ "$2" = some ] && [ "$s" != none ]; then return 0; fi
		i=$((i + 1))
		sleep 0.05
	done
	fail "window $1: expected $2 strip, got $(strip "$1")"
}
set_theme() { # KEY VALUE
	sed -i "s/^$1 = .*/$1 = $2/" "$config/themes.toml"
}
# The strip sits on the window: same x and width, its bottom at the frame's top.
check_on_top() {
	read -r fx fy fw fh <<EOF
$(frame "$1")
EOF
	read -r sx sy sw sh <<EOF
$(strip "$1")
EOF
	[ "$sx" = "$fx" ] && [ "$sw" = "$fw" ] && [ $((sy + sh)) = "$fy" ] && [ "$sh" -gt 0 ] ||
		fail "strip $sx $sy $sw $sh does not sit on frame $fx $fy $fw $fh"
}

# Off by default: no strip anywhere.
open_client DwmTitleFloat
floating=$client_id
floating_out=$client_out
[ "$(strip 0)" = none ] || fail "a strip exists with title bars off"

# On by saving themes.toml: the floating window gets one, on top of it.
set_theme titlebars 1
wait_strip "$floating" some
check_on_top "$floating"
read -r sx sy sw sh <<EOF
$(strip "$floating")
EOF
[ "$sy" -ge 0 ] || fail "the strip is above the screen: $sy"

# A tiled window has none, nor does an always-on-top floating one (the shell's
# own windows are, by their rules).
open_client DwmTitleTiled
tiled=$client_id
[ "$(strip "$tiled")" = none ] || fail "a tiled window has a strip"
open_client DwmTitleOnTop
[ "$(strip "$client_id")" = none ] || fail "an always-on-top window has a strip"
# Closed again: it would sit above the floating window the next steps click.
kill "$last_client_pid"
sleep 0.3

# Dragging the title moves the window by the same distance.
read -r fx fy fw fh <<EOF
$(frame "$floating")
EOF
xdotool mousemove $((sx + 20)) $((sy + sh / 2))
sleep 0.2
xdotool mousedown 1
sleep 0.2
for _ in 1 2 3 4 5 6; do
	xdotool mousemove_relative -- 20 10
	sleep 0.05
done
xdotool mouseup 1
sleep 0.3
read -r nx ny _ _ <<EOF
$(frame "$floating")
EOF
[ "$nx" = $((fx + 120)) ] && [ "$ny" = $((fy + 60)) ] ||
	fail "a drag of 120,60 moved the window from $fx,$fy to $nx,$ny"
check_on_top "$floating"

# Fullscreen: none while fullscreen, back after.
"$work/client" fullscreen "$floating" 1
wait_strip "$floating" none
"$work/client" fullscreen "$floating" 0
wait_strip "$floating" some
check_on_top "$floating"

# The allowed tags: tag 2 only hides it on tag 1; all tags brings it back.
set_theme titlebar_tags 2
wait_strip "$floating" none
set_theme titlebar_tags 511
wait_strip "$floating" some

# An invalid value keeps the last valid one, and says so.
set_theme titlebars 2
sleep 0.5
[ "$(strip "$floating")" != none ] || fail "an invalid value turned them off"
grep -q 'titlebars must be 0 or 1' "$work/notify.log" || fail "no notice for an invalid value: $(cat "$work/notify.log")"
set_theme titlebars 1

# Dragged by its title to the other monitor: dwm hands it over on release, and
# the strip follows. (The send-to-monitor key does not move a floating window
# on screen in Lyona.)
read -r sx sy sw sh <<EOF
$(strip "$floating")
EOF
xdotool mousemove $((sx + 20)) $((sy + sh / 2))
sleep 0.2
xdotool mousedown 1
sleep 0.2
for _ in 1 2 3 4 5 6 7 8 9 10; do
	xdotool mousemove_relative -- 70 0
	sleep 0.05
done
xdotool mouseup 1
sleep 0.3
read -r fx fy fw fh <<EOF
$(frame "$floating")
EOF
[ "$fx" -ge 1024 ] || fail "the window was not dragged to the other monitor: $fx"
wait_strip "$floating" some
check_on_top "$floating"
# dwm moved it to that monitor: it is that monitor's selected window.
xprop -root _DWM_MONITOR_WINDOWS | grep -q "$floating" || fail "no monitor has it: $(xprop -root _DWM_MONITOR_WINDOWS)"
xprop -root _DWM_MONITOR_WINDOWS | grep -Eq "# 0x[0-9a-f]+, $floating" ||
	fail "it is not the right monitor's window: $(xprop -root _DWM_MONITOR_WINDOWS)"

# The x closes it: WM_DELETE_WINDOW, and the strip goes with the window.
read -r sx sy sw sh <<EOF
$(strip "$floating")
EOF
xdotool mousemove $((sx + sw - sh / 2)) $((sy + sh / 2))
sleep 0.2
xdotool click 1
i=0
while [ "$i" -lt 100 ] && ! grep -qx deleted "$floating_out"; do
	i=$((i + 1))
	sleep 0.05
done
grep -qx deleted "$floating_out" || fail "the close control did not send WM_DELETE_WINDOW"
i=0
while [ "$i" -lt 100 ] && [ "$(strip 0)" != none ]; do
	i=$((i + 1))
	sleep 0.05
done
[ "$(strip 0)" = none ] || fail "the strip outlived its window"

# Off again: a new floating window gets none.
set_theme titlebars 0
sleep 0.5
open_client DwmTitleFloat
[ "$(strip "$client_id")" = none ] || fail "title bars off, but the window got a strip"
kill -0 "$dwm_pid" 2>/dev/null || fail "dwm exited"

printf 'Floating title bars (off by default, drag, close, fullscreen, tags, monitors, reload): PASS\n'
