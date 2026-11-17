#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

# The panel from the keyboard (#534), with the real dwm, the real managed
# shell and the real hotkeys.toml, a client window open and focused, and real
# key events only: Ctrl+Alt+Tab puts the X keyboard focus on the panel, Tab
# and Shift+Tab move between its items, Escape gives the keyboard back to the
# window, a popup opened with Enter gives it back to the panel when Escape
# closes it, a click on the window ends it all, a popup opened without the
# keyboard path still gives the keyboard to the window, and a panel under a
# fullscreen window is refused the keyboard.
for command_name in Xvfb dbus-run-session quickshell xdotool xprop xmessage; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

test_tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
mkdir -p -- "$test_tmp_root"

if [ "${DWM_PANEL_KEYBOARD_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_PANEL_KEYBOARD_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d "$test_tmp_root/dwm-panel-keyboard.XXXXXX")
dwm_bin=$repo/dwm
[ -x "$dwm_bin" ] || {
	printf 'dwm binary is not built: %s\n' "$dwm_bin" >&2
	exit 1
}
test_stage='initializing fixture'
pids=''

cleanup() {
	cleanup_status=$?
	set +e
	if [ "$cleanup_status" -ne 0 ]; then
		printf 'Panel keyboard Xvfb failed while %s (status %s)\n' \
			"${test_stage:-stage unknown}" "$cleanup_status" >&2
		[ -f "$work/dwm.log" ] && tail -40 "$work/dwm.log" >&2
		[ -f "$work/quickshell.log" ] && tail -80 "$work/quickshell.log" >&2
	fi
	for pid in $pids; do
		kill "$pid" 2>/dev/null
	done
	kill_session_tree "${home:-}"
	rm -rf "$work"
	trap - EXIT HUP INT TERM
	exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

home=$work/home
config_home=$home/.config
data_home=$home/.local/share
runtime=$work/runtime
mkdir -p "$config_home/lyona" "$data_home/checkout" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell" "$config_home/quickshell"
rm -f "$config_home/quickshell/assets/lyona-icon.png"
cp "$repo/assets/logo/lyona-icon.png" "$config_home/quickshell/assets/lyona-icon.png"
cp "$repo"/config/*.toml "$config_home/lyona/"
# The helpers, one link each, without the session hooks (#502): dwm must not
# run the real autostart.sh in this Xvfb.
helpers=$work/helpers
mkdir -p "$helpers"
for script in "$repo"/scripts/*; do
	case ${script##*/} in
	autostart.sh | autostop.sh) continue ;;
	esac
	ln -s "$script" "$helpers/"
done
ln -s "$helpers" "$data_home/checkout/scripts"
export LYONA_DEV_SCRIPTS="$data_home/checkout/scripts"
xdg_config_dirs=$work/xdg
mkdir -p "$xdg_config_dirs"

test_stage='starting Xvfb'
Xvfb -displayfd 3 -noreset -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
pids="$pids $!"
i=0
while [ ! -s "$work/display" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	sleep 0.05
done
display_number=$(sed -n '1p' "$work/display")
case $display_number in
'' | *[!0-9]*) fail "Xvfb did not report a display: $(cat "$work/xvfb.log")" ;;
esac
display=:$display_number
export DISPLAY="$display"
i=0
until xprop -root >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'Xvfb did not answer'
	sleep 0.05
done

session_env() {
	env HOME="$home" XDG_CONFIG_HOME="$config_home" XDG_DATA_HOME="$data_home" \
		XDG_DATA_DIRS="$data_home" XDG_CONFIG_DIRS="$xdg_config_dirs" \
		XDG_RUNTIME_DIR="$runtime" PATH="$data_home/checkout/scripts:$PATH" "$@"
}

test_stage='starting dwm'
session_env DWM_AUTOSTART_NO_INPUT_WATCH=1 "$dwm_bin" >"$work/dwm.log" 2>&1 &
pids="$pids $!"

test_stage='starting Quickshell'
session_env QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME= \
	QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1 \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
pids="$pids $!"
config=$config_home/quickshell/shell.qml
panel_ipc() {
	session_env quickshell ipc --path "$config" call panel "$@"
}
i=0
until panel_ipc keyboardState >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 200 ] || fail 'the shell did not answer its panel IPC'
	sleep 0.1
done

# The panel's X window: the dock dwm took as its bar.
panel_window=''
i=0
while [ -z "$panel_window" ]; do
	for window in $(xdotool search --name '' 2>/dev/null); do
		xprop -id "$window" _NET_WM_WINDOW_TYPE 2>/dev/null | grep -q _NET_WM_WINDOW_TYPE_DOCK || continue
		xprop -id "$window" _NET_WM_STRUT_PARTIAL 2>/dev/null | grep -q '=' || continue
		panel_window=$window
	done
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'no panel dock window appeared'
	[ -n "$panel_window" ] || sleep 0.1
done

test_stage='opening a client window'
xmessage -name lyona-panel-keyboard-client 'client window' &
pids="$pids $!"
client=''
i=0
while [ -z "$client" ]; do
	client=$(xdotool search --classname lyona-panel-keyboard-client 2>/dev/null | head -n 1 || :)
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'the client window did not map'
	[ -n "$client" ] || sleep 0.1
done

# The X keyboard focus, as a decimal window id.
focus_window() {
	xdotool getwindowfocus 2>/dev/null || printf 0
}
# wait_for DESCRIPTION COMMAND...: up to 5 s for COMMAND to succeed.
wait_for() {
	wait_what=$1
	shift
	i=0
	until "$@"; do
		i=$((i + 1))
		if [ "$i" -ge 50 ]; then
			printf 'panel state: %s\nX focus: %s (panel %s, client %s)\n' \
				"$(panel_ipc keyboardState 2>&1)" "$(focus_window)" "$panel_window" "$client" >&2
			fail "timed out waiting for $wait_what"
		fi
		sleep 0.1
	done
}
focus_is() { [ "$(focus_window)" = "$1" ]; }
state_has() { panel_ipc keyboardState 2>/dev/null | grep -Fq "$1"; }
# The keyboard on another item of the panel than the logo.
state_moved_off_logo() {
	moved_state=$(panel_ipc keyboardState 2>/dev/null) || return 1
	case $moved_state in
	*'"hasKeyboard":true'*'"item":"logoButton"'*) return 1 ;;
	*'"hasKeyboard":true'*) return 0 ;;
	esac
	return 1
}
input_hint_is() { xprop -id "$panel_window" WM_HINTS 2>/dev/null | grep -q "input focus: $1"; }
key() {
	xdotool key --clearmodifiers "$@"
}

wait_for 'the client window to have the keyboard' focus_is "$client"
wait_for 'the panel to say it takes no input' input_hint_is False

test_stage='Ctrl+Alt+Tab onto the panel'
key ctrl+alt+Tab
wait_for 'the panel to have the X keyboard focus' focus_is "$panel_window"
wait_for 'the panel to report the keyboard on its logo' state_has '"hasKeyboard":true,"popupOpen":false,"item":"logoButton"'
input_hint_is True || fail 'the panel has the keyboard without saying it takes input'

test_stage='Tab and Shift+Tab between the items'
key Tab
wait_for 'Tab to move off the logo' state_moved_off_logo
state_has '"item":"workspaceButton"' || fail "Tab from the logo did not reach the first tag: $(panel_ipc keyboardState)"
key shift+Tab
wait_for 'Shift+Tab to come back to the logo' state_has '"item":"logoButton"'
key shift+Tab
wait_for 'Shift+Tab from the logo to wrap to the power pill' state_has '"item":"powerPill"'
key Right
wait_for 'Right from the power pill to wrap to the logo' state_has '"item":"logoButton"'
key Left
wait_for 'Left from the logo to wrap to the power pill' state_has '"item":"powerPill"'
focus_is "$panel_window" || fail 'moving between items took the keyboard off the panel'

test_stage='Escape back to the window'
key Escape
wait_for 'Escape to give the keyboard back to the client' focus_is "$client"
wait_for 'the panel to leave its keyboard path' state_has '"keyboardMode":false'
wait_for 'the panel to say it takes no input again' input_hint_is False

test_stage='a popup opened with Enter, closed with Escape'
key ctrl+alt+Tab
wait_for 'the panel to have the keyboard again' focus_is "$panel_window"
wait_for 'a new visit to start on the logo' state_has '"item":"logoButton"'
key shift+Tab
wait_for 'the power pill' state_has '"item":"powerPill"'
key Return
wait_for 'Enter to open the power menu' state_has '"popupOpen":true'
wait_for 'the power menu to take the keyboard' sh -c "[ \"\$(xdotool getwindowfocus 2>/dev/null)\" != $panel_window ] && [ \"\$(xdotool getwindowfocus 2>/dev/null)\" != $client ]"
key Escape
wait_for 'Escape to close the power menu' state_has '"popupOpen":false'
wait_for 'the keyboard to come back to the panel' focus_is "$panel_window"
wait_for 'the keyboard back on the power pill' state_has '"keyboardMode":true,"hasKeyboard":true,"popupOpen":false,"item":"powerPill"'

test_stage='Ctrl+Alt+Tab again, off the panel'
key ctrl+alt+Tab
wait_for 'the second Ctrl+Alt+Tab to give the keyboard back' focus_is "$client"
wait_for 'the panel to leave its keyboard path' state_has '"keyboardMode":false'

test_stage='a click on the window ends it'
key ctrl+alt+Tab
wait_for 'the panel to have the keyboard' focus_is "$panel_window"
eval "$(xdotool getwindowgeometry --shell "$client")"
xdotool mousemove "$((X + WIDTH / 2))" "$((Y + HEIGHT / 2))" click 1
wait_for 'the click to give the keyboard to the client' focus_is "$client"
wait_for 'the panel to leave its keyboard path after the click' state_has '"keyboardMode":false'

test_stage='a popup opened without the keyboard path'
session_env quickshell ipc --path "$config" call power open >/dev/null
wait_for 'the power menu to open' state_has '"popupOpen":true'
wait_for 'the power menu to take the keyboard' sh -c "[ \"\$(xdotool getwindowfocus 2>/dev/null)\" != $client ]"
key Escape
wait_for 'Escape to close the power menu' state_has '"popupOpen":false'
wait_for 'the keyboard to go back to the client, not the panel' focus_is "$client"
sleep 0.3
focus_is "$client" || fail 'a popup opened without the keyboard path gave the keyboard to the panel'
input_hint_is False || fail 'the panel says it takes input after a mouse-path popup'

test_stage='a bar that says it takes no input is not given the keyboard'
# A _NET_ACTIVE_WINDOW for the panel while it takes no input, as any client
# could send: dwm leaves the keyboard where it is.
xdotool windowactivate "$panel_window" >/dev/null 2>&1 || :
sleep 0.3
focus_is "$client" || fail 'dwm gave the keyboard to a bar that says it takes no input'

test_stage='a fullscreen window keeps the keyboard'
# The panel is hidden under a fullscreen window: dwm refuses it the keyboard,
# and the panel leaves its keyboard path instead of waiting with it on.
xdotool windowstate --add FULLSCREEN "$client"
wait_for 'the client to go fullscreen' sh -c "xprop -id $client _NET_WM_STATE | grep -q _NET_WM_STATE_FULLSCREEN"
wait_for 'the panel to see the fullscreen window' state_has '"covered":true'
key ctrl+alt+Tab
sleep 0.5
focus_is "$client" || fail 'dwm gave the keyboard to a panel under a fullscreen window'
wait_for 'the panel to leave its keyboard path when refused' state_has '"keyboardMode":false'
wait_for 'the panel to say it takes no input after the refusal' input_hint_is False
xdotool windowstate --remove FULLSCREEN "$client"

printf 'panel keyboard Xvfb: ok\n'
