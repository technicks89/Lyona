#!/bin/sh
set -eu

# Settings > Appearance > Layout (#479): dwm's tile gap and per-monitor,
# per-tag master size and count, saved in layout.toml by dwm-layout-settings
# and published as _DWM_LAYOUT_SETTINGS. A real dwm on Xvfb, one screen split
# into two RandR monitors (which Xinerama reports as two heads), and the real
# helper.

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
watch_pid=
cleanup() {
	set +e
	for pid in $client_pids $watch_pid $dwm_pid $xvfb_pid; do
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
	printf 'layout settings: %s\n' "$*" >&2
	[ ! -f "$work/dwm.log" ] || tail -20 "$work/dwm.log" >&2
	exit 1
}

home=$work/home
mkdir -p "$home/.config/lyona" "$work/bin" "$work/no-hooks"
cp "$repo/config/hotkeys.toml" "$repo/config/themes.toml" "$repo/config/window-rules.toml" \
	"$repo/config/layout.toml" "$home/.config/lyona/"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/notify-send"
chmod +x "$work/bin/notify-send"

cat >"$work/client.c" <<'EOF'
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* With no argument, a window that waits; with "frame WIN", that window's
 * frame (X Y W H, border included) as dwm placed it. */
int
main(int argc, char **argv)
{
	Display *dpy = XOpenDisplay(NULL);
	XClassHint hint = { "dwm-layout-test", "DwmLayoutTest" };
	Window win, root;
	int x, y;
	unsigned int w, h, b, depth;

	if (!dpy)
		return 1;
	if (argc == 3 && strcmp(argv[1], "frame") == 0) {
		if (!XGetGeometry(dpy, strtoul(argv[2], NULL, 0), &root, &x, &y, &w, &h, &b, &depth))
			return 1;
		printf("%d %d %u %u\n", x, y, w + 2 * b, h + 2 * b);
		return 0;
	}
	win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, 200, 150, 0, 0,
		WhitePixel(dpy, DefaultScreen(dpy)));
	XSetClassHint(dpy, win, &hint);
	XStoreName(dpy, win, "dwm-layout-test");
	XMapWindow(dpy, win);
	XSync(dpy, False);
	printf("0x%lx\n", win);
	fflush(stdout);
	for (;;)
		pause();
}
EOF
# shellcheck disable=SC2046 # pkg-config prints separate flags
cc -o "$work/client" "$work/client.c" $(pkg-config --cflags --libs x11)

Xvfb -displayfd 3 -noreset -screen 0 2048x768x24 \
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
xrandr --setmonitor LEFT 1024/270x768/200+0+0 screen >/dev/null
xrandr --setmonitor RIGHT 1024/270x768/200+1024+0 none >/dev/null

# No session hook: the developer override names an empty directory.
env HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
	LYONA_DEV_SCRIPTS="$work/no-hooks" PATH="$work/bin:$PATH" \
	"$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

helper() {
	env HOME="$home" XDG_CONFIG_HOME="$home/.config" "$repo/scripts/dwm-layout-settings" "$@"
}
# Waits until _DWM_LAYOUT_SETTINGS is "MON, TAG, MFACT, NMASTER, GAP".
wait_settings() {
	i=0
	while [ "$i" -lt 100 ]; do
		[ "$(xprop -root _DWM_LAYOUT_SETTINGS 2>/dev/null | sed 's/.*= //')" = "$1" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "expected _DWM_LAYOUT_SETTINGS $1, got: $(xprop -root _DWM_LAYOUT_SETTINGS 2>&1)"
}
start_client() {
	"$work/client" >"$work/client-id" &
	client_pids="$client_pids $!"
	i=0
	while [ ! -s "$work/client-id" ] && [ "$i" -lt 100 ]; do
		i=$((i + 1))
		sleep 0.05
	done
	client_id=$(cat "$work/client-id")
	[ -n "$client_id" ] || fail "the test client did not start"
	: >"$work/client-id"
}
# The window's frame (outer) geometry as "X Y W H".
frame() {
	"$work/client" frame "$1" 2>/dev/null
}
wait_frame() { # WINDOW "X Y W H"
	i=0
	while [ "$i" -lt 100 ]; do
		[ "$(frame "$1")" = "$2" ] && return 0
		i=$((i + 1))
		sleep 0.05
	done
	fail "window $1: expected frame $2, got $(frame "$1")"
}

# Two heads; the shipped layout.toml has no entry, so the defaults hold.
i=0
while [ "$i" -lt 100 ] && ! xprop -root _DWM_MONITOR_DESKTOPS 2>/dev/null | grep -q '1024, 0, 1024, 768'; do
	i=$((i + 1))
	sleep 0.05
done
xprop -root _DWM_MONITOR_DESKTOPS | grep -q '1024, 0, 1024, 768' || fail "dwm did not see two monitors"
# dwm starts on the monitor under the pointer, the right one here.
xdotool key super+comma
wait_settings '0, 1, 55, 1, 0'

# Gap 0 is today's tiling, to the pixel: tile() splits the 1024 px width
# with mfact 0.55 into a 563 px master and a stack of (int)(1024 * 0.45) =
# 460 px beside it, as it always has. Recorded, to be compared after a gap
# comes and goes.
start_client
master=$client_id
start_client
stack=$client_id
sleep 0.3
frame_master=$(frame "$master")
frame_stack=$(frame "$stack")
[ "$frame_master" = '0 0 563 768' ] && [ "$frame_stack" = '563 0 460 768' ] ||
	fail "gap 0: master $frame_master, stack $frame_stack"

# A gap saved for monitor 0, tag 1 applies on reload: around and between.
[ "$(helper set 0 1 gap 10)" = "$(printf 'layout-settings-result\tok')" ] || fail "set gap"
wait_settings '0, 1, 55, 1, 10'
sleep 0.2
read -r mx my mw mh <<EOF
$(frame "$master")
EOF
read -r sx sy sw sh <<EOF
$(frame "$stack")
EOF
# The same rounding leaves the stack at most a pixel short of the margin.
[ "$mx" = 10 ] && [ "$my" = 10 ] && [ "$mh" = 748 ] &&
	[ "$sx" = $((mx + mw + 10)) ] && [ "$sy" = 10 ] && [ "$sh" = 748 ] &&
	[ $((sx + sw)) -ge 1013 ] && [ $((sx + sw)) -le 1014 ] ||
	fail "gap 10: master $(frame "$master"), stack $(frame "$stack")"

# Per tag: tag 2 has no gap, and tag 1 keeps its own.
xdotool key super+2
wait_settings '0, 2, 55, 1, 0'
xdotool key super+1
wait_settings '0, 1, 55, 1, 10'

# Master size and count, saved and applied.
helper set 0 1 mfact 70 >/dev/null
wait_settings '0, 1, 70, 1, 10'
helper set 0 1 nmaster 2 >/dev/null
wait_settings '0, 1, 70, 2, 10'

# Back to the defaults: the frames are exactly the gap 0 ones again.
helper set 0 1 gap default >/dev/null
helper set 0 1 mfact default >/dev/null
helper set 0 1 nmaster default >/dev/null
wait_settings '0, 1, 55, 1, 0'
wait_frame "$master" "$frame_master"
wait_frame "$stack" "$frame_stack"

# A live change through a hotkey is not saved and survives an edit of another
# runtime file; a layout.toml change applies the saved values again.
xdotool key super+i
wait_settings '0, 1, 55, 2, 0'
cp "$home/.config/lyona/hotkeys.toml" "$work/hotkeys.toml"
cp "$work/hotkeys.toml" "$home/.config/lyona/hotkeys.toml"
kill -USR1 "$dwm_pid"
sleep 0.3
wait_settings '0, 1, 55, 2, 0'
helper set 0 1 gap 4 >/dev/null
wait_settings '0, 1, 55, 1, 4'
helper set 0 1 gap default >/dev/null
wait_settings '0, 1, 55, 1, 0'

# The second monitor: its own entry, for its own tags.
helper set 1 6 gap 12 >/dev/null
helper set 1 6 mfact 40 >/dev/null
xdotool key super+period
xdotool key super+6
i=0
while [ "$i" -lt 100 ] && [ "$(xprop -root _DWM_LAYOUT_SETTINGS | sed 's/.*= //')" != '1, 6, 40, 1, 12' ]; do
	i=$((i + 1))
	sleep 0.05
done
[ "$(xprop -root _DWM_LAYOUT_SETTINGS | sed 's/.*= //')" = '1, 6, 40, 1, 12' ] ||
	fail "monitor 1 tag 6: $(xprop -root _DWM_LAYOUT_SETTINGS)"
xdotool key super+comma
xdotool key super+1
wait_settings '0, 1, 55, 1, 0'

# Out of range or malformed in layout.toml: that value is ignored, the rest apply.
printf 'layouts = [\n  { monitor=0, tag=1, mfact=99, nmaster=-1, gap=8 },\n  { monitor=0, tag=12, gap=30 },\n  { tag=1, gap=30 },\n]\n' \
	>"$home/.config/lyona/layout.toml"
wait_settings '0, 1, 55, 1, 8'

# The helper's watch reports each change while it runs.
helper watch >"$work/watch.out" &
watch_pid=$!
sleep 0.3
printf 'layouts = []\n' >"$home/.config/lyona/layout.toml"
wait_settings '0, 1, 55, 1, 0'
sleep 0.2
kill "$watch_pid"
wait "$watch_pid" 2>/dev/null || :
watch_pid=
grep -q "$(printf '^layout-settings\t0\t1\t55\t1\t8\t0$')" "$work/watch.out" || fail "watch missed the start: $(cat "$work/watch.out")"
grep -q "$(printf '^layout-settings\t0\t1\t55\t1\t0\t0$')" "$work/watch.out" || fail "watch missed the change: $(cat "$work/watch.out")"
[ "$(helper state)" = "$(printf 'layout-settings\t0\t1\t55\t1\t0\t0')" ] || fail "state: $(helper state)"

printf 'Layout settings (gaps, master size and count, per tag and monitor): PASS\n'
