#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

helper="$repo/scripts/dwm-quickshell-state"
bin="$work/bin"
mkdir -p "$bin"

fail() {
	printf 'dwm-quickshell-state: %s\n' "$1" >&2
	[[ -n ${2:-} ]] && cat "$2" >&2
	exit 1
}

# A root-owned pid is skipped; a pid this test owns is kept. Using real
# processes keeps the /proc uid lookup honest instead of stubbing it.
root_pid=1
own_pid=$$
[[ $(awk '/^Uid:/ { print $2; exit }' "/proc/$root_pid/status") == 0 ]] ||
	fail "expected pid $root_pid to be root-owned; cannot exercise the uid skip"
[[ $(awk '/^Uid:/ { print $2; exit }' "/proc/$own_pid/status") != 0 ]] ||
	fail 'this test must not run as root'

cat >"$bin/xprop" <<EOF
#!/bin/sh
# -root <props...>  |  -id <window> <props...>
printf '%s\n' "\$*" >>"$work/xprop.log"
if [ "\$1" = "-root" ]; then
	cat <<'ROOT'
_NET_CURRENT_DESKTOP(CARDINAL) = 2
_NET_NUMBER_OF_DESKTOPS(CARDINAL) = 9
_NET_DESKTOP_NAMES(UTF8_STRING) = "one", "two", "three"
_NET_CLIENT_LIST(WINDOW): window id # 0xaa, 0xbb, 0xcc, 0xdd
_DWM_FULLSCREEN_MONITORS(STRING) = "1, 0, 1"
_DWM_MONITOR_DESKTOPS(STRING) = "0, 1, 2"
_DWM_SELECTED_MONITOR(CARDINAL) = 1
WM_NAME(STRING) = "AC  |   VOL 15%"
ROOT
	exit 0
fi

window=\$2
shift 2
case "\$window:\$*" in
0xaa:*WM_CLASS*)
	printf '_NET_WM_DESKTOP(CARDINAL) = 3\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf 'WM_CLASS(STRING) = "alacritty", "Alacritty"\n'
	;;
0xbb:*WM_CLASS*)
	printf '_NET_WM_DESKTOP(CARDINAL) = 1\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf 'WM_CLASS(STRING) = "firefox", "firefox"\n'
	;;
0xcc:*WM_CLASS*)
	# duplicate class, and a desktop that must sort before the others
	printf '_NET_WM_DESKTOP(CARDINAL) = 0\n'
	printf '_NET_WM_PID(CARDINAL) = $own_pid\n'
	printf 'WM_CLASS(STRING) = "alacritty", "Alacritty"\n'
	;;
0xdd:*WM_CLASS*)
	# root-owned: must be skipped, but its desktop still counts as occupied
	printf '_NET_WM_DESKTOP(CARDINAL) = 7\n'
	printf '_NET_WM_PID(CARDINAL) = $root_pid\n'
	printf 'WM_CLASS(STRING) = "rootapp", "RootApp"\n'
	;;
*_NET_WM_NAME*)
	printf '_NET_WM_NAME(UTF8_STRING) = "a  title\twith   spaces"\n'
	;;
*WM_CLASS*)
	printf 'WM_CLASS(STRING) = "alacritty", "Alacritty"\n'
	;;
esac
exit 0
EOF

cat >"$bin/xdotool" <<'EOF'
#!/bin/sh
[ "$1" = "getactivewindow" ] && { printf '0xaa\n'; exit 0; }
exit 1
EOF
chmod +x "$bin/xprop" "$bin/xdotool"

PATH="$bin:$PATH" "$helper" state >"$work/out" 2>"$work/err" ||
	fail 'state exited non-zero' "$work/err"

expect() {
	grep -Fqx "$1" "$work/out" ||
		fail "expected line: $1" "$work/out"
}

expect 'current=2'
expect 'count=9'
expect 'names=one|two|three'
expect 'focused_monitor=1'
expect 'monitor_desktops=0,1,2'
expect 'status=AC | VOL 15%'

# occupied is numerically sorted and de-duplicated, and includes the desktop
# of the root-owned window even though that window is not a running app
expect 'occupied=0|1|3|7'

# apps keeps first-seen order, de-duplicates by class, and drops root-owned
expect 'apps=0xaa:alacritty|0xbb:firefox'

# fullscreen monitors are de-duplicated and sorted
expect 'fullscreen_monitors=0|1'

# the active window's title has its whitespace collapsed
expect 'title=a title with spaces'
expect 'class=alacritty'

# One xprop for every root property, then exactly one per client window,
# plus the active window's title and class. Anything more is a regression.
root_calls=$(grep -c '^-root' "$work/xprop.log" || true)
[[ $root_calls -eq 1 ]] ||
	fail "expected exactly 1 batched root xprop call, got $root_calls" "$work/xprop.log"
per_window=$(grep -c '^-id .* _NET_WM_DESKTOP _NET_WM_PID WM_CLASS$' "$work/xprop.log" || true)
[[ $per_window -eq 4 ]] ||
	fail "expected 1 batched xprop per client window (4), got $per_window" "$work/xprop.log"
total=$(wc -l <"$work/xprop.log")
[[ $total -le 7 ]] ||
	fail "expected at most 7 xprop calls for 4 windows, got $total" "$work/xprop.log"

printf 'Quickshell state bridge: PASS\n'
