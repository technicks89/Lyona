#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

for command_name in Xvfb dbus-run-session quickshell xdotool xprop pgrep; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

if [ "${DWM_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
display=":$((($$ % 400) + 300))"
cleanup() {
	set +e
	[ -n "${quickshell_pid:-}" ] && kill "$quickshell_pid" 2>/dev/null
	[ -n "${dwm_pid:-}" ] && kill "$dwm_pid" 2>/dev/null
	[ -n "${xvfb_pid:-}" ] && kill "$xvfb_pid" 2>/dev/null
	rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

home=$work/home
runtime=$work/runtime
config_home=$home/.config
data_home=$home/.local/share
mkdir -p "$config_home/quickshell" "$config_home/lyona" "$data_home/checkout/scripts" "$runtime"
# Helpers are no longer looked up in a per-user copy; the developer override
# names the directory holding this test's helpers (Sync Sprint 12 S12-13).
export LYONA_DEV_SCRIPTS="$data_home/checkout/scripts"
# The checkout layout: the built TOML reader sits beside scripts/ (S12-14).
cp "$repo/lyona-toml" "$data_home/checkout/scripts/.."
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$config_home/quickshell/"
cp "$repo/config/"*.toml "$config_home/lyona/"
sed -i '/title="dwm control center utility"/d' "$config_home/lyona/window-rules.toml"
sed -i '/title="dwm network password"/a\
  { title="dwm control center",         isfloating=1, alwaysontop=1 },' \
	"$config_home/lyona/window-rules.toml"
grep -Fqx '  { title="dwm control center",         isfloating=1, alwaysontop=1 },' \
	"$config_home/lyona/window-rules.toml"
# The helpers this test runs, and every library they source (S12-21).
stage_helpers checkout "$data_home/checkout/scripts" dwm-system-health dwm-diagnostics \
	dwm-quickshell-controlcenter dwm-quickshell-controls dwm-quickshell-launcher \
	dwm-quickshell-network dwm-quickshell-pointer

# The staged Health backend reports the login keyring (Sync Sprint 15 S15-01):
# dwm-diagnostics found the package map beside it. ok or warn, by this host.
HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	"$data_home/checkout/scripts/dwm-diagnostics" --format health-tsv >"$work/dependencies.tsv" || true
grep -E "$(printf '\t(ok|warn)\tdependency-package-gnome-keyring\t')" "$work/dependencies.tsv" >/dev/null ||
	fail "the staged diagnostics report no gnome-keyring row"

Xvfb "$display" -screen 0 1024x768x24 -nolisten tcp -extension GLX >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!

i=0
while [ "$i" -lt 100 ]; do
	if DISPLAY=$display xprop -root >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
DISPLAY=$display xprop -root >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime "$repo/dwm" >"$work/dwm.log" 2>&1 &
dwm_pid=$!

env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_RUNTIME_DIR="$runtime" \
	QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1 \
	PATH="$data_home/checkout/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!

config=$config_home/quickshell/shell.qml
i=0
while [ "$i" -lt 200 ]; do
	if DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call systemhealth open >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done

window=
i=0
while [ "$i" -lt 200 ]; do
	window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' 2>/dev/null | head -1 || true)
	[ -n "$window" ] && break
	i=$((i + 1))
	sleep 0.05
done

if [ -z "$window" ]; then
	printf 'System Health window did not open\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi

# Below the panel, which stays visible (#231): not fullscreen, the screen's
# width, the height the 30-pixel panel leaves, and right below it.
if DISPLAY=$display xprop -id "$window" _NET_WM_STATE | grep -q '_NET_WM_STATE_FULLSCREEN'; then
	printf 'System Health is fullscreen, over the panel\n' >&2
	exit 1
fi
i=0
while [ "$i" -lt 100 ]; do
	geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window")
	width=$(printf '%s\n' "$geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
	height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
	top=$(printf '%s\n' "$geometry" | awk -F= '$1 == "Y" { print $2 }')
	[ "$width/$height/$top" = 1024/738/30 ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$width/$height/$top" = 1024/738/30 ] || {
	printf 'System Health is %sx%s at y=%s, not 1024x738 below the panel\n' "$width" "$height" "$top" >&2
	exit 1
}

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call systemhealth close >/dev/null

i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' >/dev/null 2>&1; then
	printf 'System Health window did not close\n' >&2
	exit 1
fi

i=0
while [ "$i" -lt 200 ]; do
	scan_processes=$(pgrep -af '[d]wm-system-health (scan-user|scan-system)' || true)
	if ! printf '%s\n' "$scan_processes" | grep -F "$data_home/checkout/scripts/dwm-system-health" >/dev/null; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
scan_processes=$(pgrep -af '[d]wm-system-health (scan-user|scan-system)' || true)
if printf '%s\n' "$scan_processes" | grep -F "$data_home/checkout/scripts/dwm-system-health" >/dev/null; then
	printf 'System Health scan remained active after close\n' >&2
	exit 1
fi

# The open popup's window: Quickshell's click-away surface, below the panel
# (y > 0) and far taller than it. Found by what it is, not as "a window that was
# not visible before": a popup reuses its window, so a reopen during the
# previous close's fade was never "new", and the test failed now and then
# ("Control Center popup did not open").
popup_surface() {
	for candidate in $(DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null || true); do
		geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$candidate" 2>/dev/null || true)
		surface_y=$(printf '%s\n' "$geometry" | sed -n 's/^Y=//p')
		surface_height=$(printf '%s\n' "$geometry" | sed -n 's/^HEIGHT=//p')
		if [ "${surface_y:-0}" -gt 0 ] && [ "${surface_height:-0}" -gt 300 ]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	return 1
}

# Sets popup_window to the open popup's surface; fails after 10 s.
wait_popup() {
	popup_window=
	i=0
	while [ "$i" -lt 200 ]; do
		popup_window=$(popup_surface) && return 0
		i=$((i + 1))
		sleep 0.05
	done
	return 1
}

visible_windows=$(DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null || true)
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call controlcenter open >/dev/null

window=
if wait_popup; then
	window=$popup_window
fi

if [ -z "$window" ]; then
	printf 'Control Center popup did not open\n' >&2
	# This has failed now and then in full runs and never alone: say what was
	# on screen, so the next failure shows whether the popup never mapped or
	# reused a window already counted as visible.
	describe_windows() {
		for id in $1; do
			printf '  %s %s %s\n' "$id" "$(DISPLAY=$display xdotool getwindowname "$id" 2>/dev/null || printf '?')" \
				"$(DISPLAY=$display xdotool getwindowgeometry --shell "$id" 2>/dev/null | tr '\n' ' ')" >&2
		done
	}
	printf 'Quickshell windows visible before the open:\n' >&2
	describe_windows "$visible_windows"
	printf 'Quickshell windows visible now:\n' >&2
	describe_windows "$(DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null || true)"
	printf 'Every visible window now:\n' >&2
	describe_windows "$(DISPLAY=$display xdotool search --onlyvisible --name '' 2>/dev/null || true)"
	printf 'controlcenter isOpen answers: %s\n' "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home \
		XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call controlcenter isOpen 2>&1)" >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi
DISPLAY=$display xdotool mousemove 700 700 click 1
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
	printf 'Control Center popup did not close on outside click\n' >&2
	exit 1
fi

visible_windows=$(DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null || true)
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call controlcenter open >/dev/null

window=
if wait_popup; then
	window=$popup_window
fi
[ -n "$window" ]

DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
	printf 'Control Center popup did not close on Escape\n' >&2
	exit 1
fi

exercise_panel_popup() {
	target=$1
	label=$2
	visible_windows=$(DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null || true)
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call "$target" open >/dev/null

	wait_popup || popup_window=

	if [ -z "$popup_window" ]; then
		printf '%s popup did not open\n' "$label" >&2
		tail -40 "$work/quickshell.log" >&2
		exit 1
	fi

	DISPLAY=$display xdotool windowfocus --sync "$popup_window"
	DISPLAY=$display xdotool key Escape
	i=0
	while [ "$i" -lt 100 ]; do
		if ! DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$popup_window"; then
			break
		fi
		i=$((i + 1))
		sleep 0.05
	done
	if DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$popup_window"; then
		printf '%s popup did not close on Escape\n' "$label" >&2
		exit 1
	fi
}

exercise_panel_popup controls Audio
exercise_panel_popup network Network
exercise_panel_popup power Power

visible_windows=$(DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null || true)
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call controlcenter open >/dev/null

window=
if wait_popup; then
	window=$popup_window
fi
[ -n "$window" ]

DISPLAY=$display xdotool mousemove 120 141 click 1
sleep 0.1
DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
	printf 'Control Center in-place page did not close on Escape\n' >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call controlcenter open >/dev/null
sleep 0.1
DISPLAY=$display xdotool mousemove 120 74 click 1

launcher_window=
i=0
while [ "$i" -lt 200 ]; do
	launcher_window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm launcher$' 2>/dev/null | head -1 || true)
	[ -n "$launcher_window" ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ -z "$launcher_window" ]; then
	printf 'Applications menu item did not open the launcher\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi
if DISPLAY=$display xdotool search --onlyvisible --pid "$quickshell_pid" 2>/dev/null | grep -Fqx "$window"; then
	printf 'Control Center remained open behind the launcher\n' >&2
	exit 1
fi
DISPLAY=$display xdotool windowactivate --sync "$launcher_window"
DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm launcher$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm launcher$' >/dev/null 2>&1; then
	printf 'Launcher did not close on Escape\n' >&2
	exit 1
fi

DISPLAY=$display xdotool mousemove 5 5
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call menu summon >/dev/null

menu_window=
i=0
while [ "$i" -lt 200 ]; do
	menu_window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm menu$' 2>/dev/null | head -1 || true)
	[ -n "$menu_window" ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ -z "$menu_window" ]; then
	printf 'Command menu did not open\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi

[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call menu resultCount)" = 10 ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call menu selectedLabel)" = Apps ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call launcher applicationConsumers)" = 1 ]

geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$menu_window")
width=$(printf '%s\n' "$geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
[ "$width" = 720 ]
[ "$height" = 600 ]

pointer_window=
i=0
while [ "$i" -lt 100 ]; do
	pointer_window=$(DISPLAY=$display xdotool getmouselocation --shell |
		awk -F= '$1 == "WINDOW" { print $2 }')
	[ "$pointer_window" = "$menu_window" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$pointer_window" = "$menu_window" ]
[ "$(DISPLAY=$display xdotool getwindowfocus)" = "$menu_window" ]

DISPLAY=$display xdotool key Return
i=0
while [ "$i" -lt 100 ]; do
	active_menu=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call menu activeMenu)
	[ "$active_menu" = apps ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$active_menu" = apps ]

DISPLAY=$display xdotool key BackSpace
i=0
while [ "$i" -lt 100 ]; do
	active_menu=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call menu activeMenu)
	[ "$active_menu" = root ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$active_menu" = root ]

DISPLAY=$display xdotool type --delay 10 'system health'
i=0
while [ "$i" -lt 100 ]; do
	selected_label=$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
		quickshell ipc --path "$config" call menu selectedLabel)
	[ "$selected_label" = 'System Health' ] && break
	i=$((i + 1))
	sleep 0.05
done
[ "$selected_label" = 'System Health' ]
DISPLAY=$display xdotool key Return

health_window=
i=0
while [ "$i" -lt 200 ]; do
	health_window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm system health$' 2>/dev/null | head -1 || true)
	[ -n "$health_window" ] && break
	i=$((i + 1))
	sleep 0.05
done
if [ -z "$health_window" ]; then
	printf 'Command menu did not dispatch the System Health IPC action\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm menu$' >/dev/null 2>&1; then
	printf 'Command menu remained visible after dispatch\n' >&2
	exit 1
fi
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call launcher applicationConsumers)" = 0 ]
[ "$(DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call launcher indexCount)" = 0 ]
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call systemhealth close >/dev/null

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call menu toggle >/dev/null
i=0
while [ "$i" -lt 200 ]; do
	menu_window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm menu$' 2>/dev/null | head -1 || true)
	[ -n "$menu_window" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ -n "$menu_window" ]
DISPLAY=$display xdotool windowactivate --sync "$menu_window"
DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm menu$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm menu$' >/dev/null 2>&1; then
	printf 'Command menu did not close on Escape\n' >&2
	exit 1
fi

DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home XDG_RUNTIME_DIR=$runtime \
	quickshell ipc --path "$config" call controlcenter openKeybinds >/dev/null

window=
i=0
while [ "$i" -lt 200 ]; do
	window=$(DISPLAY=$display xdotool search --onlyvisible --name '^dwm control center utility$' 2>/dev/null | head -1 || true)
	[ -n "$window" ] && break
	i=$((i + 1))
	sleep 0.05
done

if [ -z "$window" ]; then
	printf 'Control-center utility window did not open\n' >&2
	tail -40 "$work/quickshell.log" >&2
	exit 1
fi

geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window")
width=$(printf '%s\n' "$geometry" | awk -F= '$1 == "WIDTH" { print $2 }')
height=$(printf '%s\n' "$geometry" | awk -F= '$1 == "HEIGHT" { print $2 }')
[ "$width" = 680 ]
[ "$height" = 500 ]

DISPLAY=$display xdotool windowactivate --sync "$window"
DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	if ! DISPLAY=$display xdotool search --onlyvisible --name '^dwm control center utility$' >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
if DISPLAY=$display xdotool search --onlyvisible --name '^dwm control center utility$' >/dev/null 2>&1; then
	printf 'Control-center utility window did not close\n' >&2
	exit 1
fi
kill -0 "$quickshell_pid"

ticks_before=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
ticks_per_second=$(getconf CLK_TCK)
sleep 2
ticks_after=$(awk '{ print $14 + $15 }' "/proc/$quickshell_pid/stat")
if ! awk -v delta="$((ticks_after - ticks_before))" -v hz="$ticks_per_second" \
	'BEGIN { exit !((delta * 100 / (hz * 2)) <= 5) }'; then
	printf 'Quickshell exceeded 5%% CPU while the dashboard was closed\n' >&2
	exit 1
fi

printf 'Quickshell System Health Xvfb: PASS\n'
