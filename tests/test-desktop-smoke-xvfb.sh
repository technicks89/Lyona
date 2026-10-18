#!/bin/sh
set -eu

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

# A fast, minimal end-to-end check for hosted CI: build dwm, start the real
# managed Quickshell shell against it, and confirm the panel and launcher
# actually work. This intentionally does not exercise individual Settings
# panes or providers -- that's tests/test-quickshell-settings-xvfb.sh and the
# rest of the Xvfb suite, which stay local-only in CI for speed. See
# CONTRIBUTING.md.
for command_name in Xvfb dbus-run-session quickshell xdotool xprop; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done

test_tmp_root=${DWM_TEST_TMP_ROOT:-${HOME}/tmp}
mkdir -p -- "$test_tmp_root"

if [ "${DWM_SMOKE_XVFB_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_SMOKE_XVFB_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d "$test_tmp_root/dwm-smoke-xvfb.XXXXXX")
dwm_bin=${DWM_SMOKE_TEST_DWM_BIN:-$repo/dwm}
[ -x "$dwm_bin" ] || {
	printf 'dwm binary is not built: %s\n' "$dwm_bin" >&2
	exit 1
}
test_stage='initializing fixture'

capture_process_identity() (
	identity_pid=$1
	[ -r "/proc/$identity_pid/stat" ] || return 1
	IFS= read -r identity_stat 2>/dev/null <"/proc/$identity_pid/stat" || return 1
	identity_fields=${identity_stat##*) }
	# shellcheck disable=SC2086
	set -- $identity_fields
	[ "$1" != Z ] || return 1
	[ -n "${20:-}" ] || return 1
	printf '%s:%s\n' "$identity_pid" "${20}"
)

process_identity_alive() (
	identity=$1
	identity_pid=${identity%%:*}
	identity_start=${identity#*:}
	[ -n "$identity_pid" ] && [ "$identity_start" != "$identity" ] || return 1
	current_identity=$(capture_process_identity "$identity_pid") || return 1
	[ "$current_identity" = "$identity" ]
)

terminate_process_identity() {
	terminate_identity=$1
	[ -n "$terminate_identity" ] || return 0
	terminate_pid=${terminate_identity%%:*}
	if process_identity_alive "$terminate_identity"; then
		kill -TERM "$terminate_pid" 2>/dev/null || true
	fi
	terminate_attempt=0
	while [ "$terminate_attempt" -lt 20 ] && process_identity_alive "$terminate_identity"; do
		terminate_attempt=$((terminate_attempt + 1))
		sleep 0.05
	done
	if process_identity_alive "$terminate_identity"; then
		kill -KILL "$terminate_pid" 2>/dev/null || true
	fi
	terminate_attempt=0
	while [ "$terminate_attempt" -lt 20 ] && process_identity_alive "$terminate_identity"; do
		terminate_attempt=$((terminate_attempt + 1))
		sleep 0.05
	done
	wait "$terminate_pid" 2>/dev/null || true
}

cleanup() {
	cleanup_status=$?
	set +e
	if [ "$cleanup_status" -ne 0 ]; then
		printf 'Desktop smoke Xvfb failed while %s (status %s)\n' \
			"${test_stage:-stage unknown}" "$cleanup_status" >&2
		[ -f "${work:-}/dwm.log" ] && tail -40 "$work/dwm.log" >&2
		[ -f "${work:-}/quickshell.log" ] && tail -80 "$work/quickshell.log" >&2
	fi
	terminate_process_identity "${quickshell_identity:-}"
	terminate_process_identity "${dwm_identity:-}"
	terminate_process_identity "${xvfb_identity:-}"
	# What the session detached or orphaned (autostart, helpers, D-Bus services).
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
state_home=$home/.local/state
runtime=$work/runtime
mkdir -p "$config_home/autostart" "$config_home/lyona" "$data_home/applications" \
	"$data_home/checkout" "$state_home/lyona" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell" "$config_home/quickshell"
rm -f "$config_home/quickshell/assets/lyona-icon.png"
cp "$repo/assets/logo/lyona-icon.png" "$config_home/quickshell/assets/lyona-icon.png"
cp "$repo"/config/*.toml "$config_home/lyona/"
mkdir -p "$data_home/lyona/assets"
cp -a "$repo/assets/logo" "$data_home/lyona/assets/logo"
ln -s "$repo/scripts" "$data_home/checkout/scripts"
# Helpers are no longer looked up in a per-user copy; the developer override
# names the directory holding this test's helpers (Sync Sprint 12 S12-13).
export LYONA_DEV_SCRIPTS="$data_home/checkout/scripts"

smoke_marker=$work/launched
cat >"$data_home/applications/dwm-smoke.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=DwmSmokeApp
Exec=touch $smoke_marker
Terminal=false
Categories=Utility;
EOF

test_stage='starting Xvfb'
# Xvfb picks a free display, so this never lands on another test's server, and
# -noreset keeps the readiness xprop's exit from resetting it, and dropping
# dwm's connection, as dwm starts (#393).
Xvfb -displayfd 3 -noreset -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
xvfb_identity=$(capture_process_identity "$xvfb_pid")

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

i=0
while [ "$i" -lt 100 ]; do
	if DISPLAY=$display xprop -root >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
DISPLAY=$display xprop -root >/dev/null

test_stage='starting dwm'
# dwm runs its bindings through this lyona-shell first (#411): each call is
# recorded, so a launcher that did not open tells a key dwm never handled from
# a call that reached the shell. It runs the checkout's, which the held-index
# stages below swap.
mkdir -p "$work/binding-bin"
cat >"$work/binding-bin/lyona-shell" <<EOF
#!/bin/sh
printf '%s %s\\n' "\$(date +%s.%N)" "\$*" >>"$work/lyona-shell.calls"
exec "$data_home/checkout/scripts/lyona-shell" "\$@"
EOF
chmod +x "$work/binding-bin/lyona-shell"
DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
	XDG_RUNTIME_DIR=$runtime DWM_AUTOSTART_NO_INPUT_WATCH=1 \
	PATH="$work/binding-bin:$data_home/checkout/scripts:$PATH" \
	"$dwm_bin" >"$work/dwm.log" 2>&1 &
dwm_pid=$!
dwm_identity=$(capture_process_identity "$dwm_pid")

test_stage='starting Quickshell'
env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" XDG_DATA_DIRS="$data_home" XDG_RUNTIME_DIR="$runtime" \
	QT_QPA_PLATFORM=xcb QT_QUICK_BACKEND=software \
	QT_QPA_PLATFORMTHEME= QT_ENABLE_HIGHDPI_SCALING=0 QT_SCALE_FACTOR=1 \
	PATH="$data_home/checkout/scripts:$PATH" \
	quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
quickshell_pid=$!
quickshell_identity=$(capture_process_identity "$quickshell_pid")

config=$config_home/quickshell/shell.qml
launcher_ipc() {
	DISPLAY=$display HOME=$home XDG_CONFIG_HOME=$config_home XDG_DATA_HOME=$data_home \
		XDG_RUNTIME_DIR=$runtime quickshell ipc --path "$config" call launcher "$@"
}

test_stage='waiting for Quickshell IPC'
i=0
while [ "$i" -lt 200 ]; do
	if launcher_ipc indexCount >/dev/null 2>&1; then
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
launcher_ipc indexCount >/dev/null

test_stage='validating the managed panel is visible'
panel_visible() {
	# Quickshell's PanelWindow ends up owned by a forked child, not the PID
	# captured from launching `quickshell` itself, so match on the panel's
	# known geometry (full screen width, Theme.panelHeight) instead of PID.
	for window_id in $(DISPLAY=$display xdotool search --onlyvisible '' 2>/dev/null || true); do
		geometry=$(DISPLAY=$display xdotool getwindowgeometry --shell "$window_id" 2>/dev/null || true)
		case $geometry in
		*'WIDTH=1024'*'HEIGHT=30'*) return 0 ;;
		esac
	done
	return 1
}
i=0
while [ "$i" -lt 100 ]; do
	panel_visible && break
	i=$((i + 1))
	sleep 0.05
done
panel_visible || {
	printf 'Quickshell panel window did not appear\n' >&2
	exit 1
}

test_stage='opening the launcher with Super+R'
launcher_visible() {
	DISPLAY=$display xdotool search --onlyvisible --name '^dwm launcher$' >/dev/null 2>&1
}
# press_super_r: press Super+R, first noting how many binding calls dwm has
# made, so a failure is judged by this keypress's calls alone.
press_super_r() {
	calls_before=0
	if [ -f "$work/lyona-shell.calls" ]; then
		calls_before=$(wc -l <"$work/lyona-shell.calls")
	fi
	DISPLAY=$display xdotool key --clearmodifiers super+r
}
# launcher_not_shown WHAT: say where a Super+R that showed no launcher was lost
# (#411): whether dwm ran the binding for it, whether the shell holds the
# launcher open, and whether its window exists at all, and which window has the
# focus. Calls from earlier keypresses do not count.
launcher_not_shown() {
	printf '%s\n' "$1" >&2
	new_calls=
	if [ -f "$work/lyona-shell.calls" ]; then
		new_calls=$(tail -n +"$((calls_before + 1))" "$work/lyona-shell.calls")
	fi
	if [ -n "$new_calls" ]; then
		printf 'lyona-shell calls from dwm since this Super+R (time, arguments):\n%s\n' "$new_calls" >&2
	else
		printf 'dwm ran no lyona-shell binding for this Super+R: the key did not reach it as Super+R\n' >&2
	fi
	printf 'launcher open in the shell: %s\n' "$(launcher_ipc isOpen 2>&1)" >&2
	printf 'launcher windows (any state): %s\n' \
		"$(DISPLAY=$display xdotool search --name '^dwm launcher$' 2>/dev/null | tr '\n' ' ')" >&2
	printf 'focused window: %s\n' \
		"$(DISPLAY=$display xdotool getwindowfocus getwindowname 2>&1)" >&2
	exit 1
}
press_super_r
i=0
while [ "$i" -lt 100 ]; do
	launcher_visible && break
	i=$((i + 1))
	sleep 0.05
done
launcher_visible || {
	launcher_not_shown 'Launcher window did not open on Super+R'
}
i=0
while [ "$i" -lt 100 ]; do
	index_count=$(launcher_ipc indexCount 2>/dev/null || printf 0)
	[ "$index_count" -gt 0 ] 2>/dev/null && break
	i=$((i + 1))
	sleep 0.05
done
[ "${index_count:-0}" -gt 0 ] || {
	printf 'Launcher application index is empty\n' >&2
	exit 1
}

test_stage='dismissing the launcher with Escape'
DISPLAY=$display xdotool key Escape
i=0
while [ "$i" -lt 100 ]; do
	launcher_visible || break
	i=$((i + 1))
	sleep 0.05
done
! launcher_visible || {
	printf 'Launcher window did not close on Escape\n' >&2
	exit 1
}

test_stage='launching an application from the launcher'
press_super_r
i=0
while [ "$i" -lt 100 ]; do
	launcher_visible && break
	i=$((i + 1))
	sleep 0.05
done
launcher_visible || {
	launcher_not_shown 'Launcher window did not reopen on Super+R'
}
DISPLAY=$display xdotool type --clearmodifiers --delay 1 DwmSmokeApp
DISPLAY=$display xdotool key Return
i=0
while [ "$i" -lt 100 ]; do
	[ -f "$smoke_marker" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ -f "$smoke_marker" ] || {
	printf 'Test application did not launch from the launcher\n' >&2
	exit 1
}

# Each open reloads the application index, so Enter can come before it: a
# quick Super+R, query and Enter. That Enter must launch once the index
# arrives, not be dropped with the launcher left open. For this stage the
# launcher's helper waits on a FIFO before listing, so Enter is always first.
test_stage='launching before the application index has loaded'
index_hold=$work/index-hold
held_scripts=$work/held-scripts
mkfifo "$index_hold"
mkdir "$held_scripts"
for script in "$repo"/scripts/* "$repo"/scripts/.[!.]*; do
	[ ! -e "$script" ] || ln -s "$script" "$held_scripts/"
done
rm "$held_scripts/dwm-quickshell-launcher"
cat >"$held_scripts/dwm-quickshell-launcher" <<EOF
#!/bin/sh
[ "\${1:-}" != list ] || cat "$index_hold" >/dev/null
exec "$repo/scripts/dwm-quickshell-launcher" "\$@"
EOF
chmod +x "$held_scripts/dwm-quickshell-launcher"
ln -sfn "$held_scripts" "$data_home/checkout/scripts"
rm -f "$smoke_marker"
press_super_r
i=0
while [ "$i" -lt 100 ]; do
	launcher_visible && break
	i=$((i + 1))
	sleep 0.05
done
launcher_visible || {
	launcher_not_shown 'Launcher window did not open on Super+R with the index held'
}
DISPLAY=$display xdotool type --clearmodifiers --delay 1 DwmSmokeApp
DISPLAY=$display xdotool key Return
[ "$(launcher_ipc indexCount 2>/dev/null || printf x)" = 0 ] || {
	printf 'The application index was not held back\n' >&2
	exit 1
}
# shellcheck disable=SC2016 # $1 is the inner shell's argument
timeout 5 sh -c ': >"$1"' sh "$index_hold" || {
	printf 'The launcher never asked for the held application index\n' >&2
	exit 1
}
ln -sfn "$repo/scripts" "$data_home/checkout/scripts"
i=0
while [ "$i" -lt 100 ]; do
	[ -f "$smoke_marker" ] && break
	i=$((i + 1))
	sleep 0.05
done
[ -f "$smoke_marker" ] || {
	printf 'Enter before the application index loaded launched nothing\n' >&2
	exit 1
}

# Opening the launcher again while it is open (IPC open, the Control Center's
# openOnScreen) starts a new session with an empty query: an Enter still
# pending from the last one must not launch whatever tops that. The launch
# would happen as the index is parsed, closing the launcher, so a launcher
# still open with its index loaded means nothing was launched.
test_stage='opening the launcher again with an Enter pending'
ln -sfn "$held_scripts" "$data_home/checkout/scripts"
rm -f "$smoke_marker"
press_super_r
i=0
while [ "$i" -lt 100 ]; do
	launcher_visible && break
	i=$((i + 1))
	sleep 0.05
done
launcher_visible || {
	launcher_not_shown 'Launcher window did not open on Super+R with the index held'
}
DISPLAY=$display xdotool type --clearmodifiers --delay 1 DwmSmokeApp
DISPLAY=$display xdotool key Return
launcher_ipc open >/dev/null
# shellcheck disable=SC2016 # $1 is the inner shell's argument
timeout 5 sh -c ': >"$1"' sh "$index_hold" || {
	printf 'The launcher never asked for the held application index\n' >&2
	exit 1
}
ln -sfn "$repo/scripts" "$data_home/checkout/scripts"
# Until the index loads, or the launcher closes: a launch closes it, and
# closing clears the index again.
i=0
while [ "$i" -lt 100 ]; do
	launcher_visible || break
	[ "$(launcher_ipc indexCount 2>/dev/null || printf 0)" -gt 0 ] && break
	i=$((i + 1))
	sleep 0.05
done
if ! launcher_visible || [ -f "$smoke_marker" ]; then
	printf 'An Enter from before the launcher was opened again launched an application\n' >&2
	exit 1
fi
[ "$(launcher_ipc indexCount 2>/dev/null || printf 0)" -gt 0 ] || {
	printf 'The application index did not load after it was released\n' >&2
	exit 1
}
launcher_ipc close >/dev/null

printf 'Desktop smoke: dwm build, Quickshell panel, launcher hotkey, application launch, Enter before the index loads, and no stale Enter after reopening: PASS\n'
