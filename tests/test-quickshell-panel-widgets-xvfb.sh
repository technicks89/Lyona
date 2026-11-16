#!/bin/sh
set -eu

# The panel's occupied-tag marker (#474), the clock with and without seconds
# (#472) and the keyboard layout pill (#470), driven through the real panel,
# clock, DwmState and PanelSettingsModel in the production shell, with every
# helper replaced by `true`. tests/test-panel-state-xvfb.sh checks what the
# state bridge feeds them.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_PANEL_WIDGETS_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_PANEL_WIDGETS_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d)
xvfb_pid=
cleanup() {
	if [ -n "$xvfb_pid" ]; then
		kill "$xvfb_pid" 2>/dev/null || true
		wait "$xvfb_pid" 2>/dev/null || true
	fi
	rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$work/qml" "$work/home/.config/lyona" \
	"$work/data/checkout/scripts" "$work/runtime" "$work/state/lyona"
# Helpers are no longer looked up in a per-user copy; the developer override
# names the directory holding this test's helpers (Sync Sprint 12 S12-13).
export LYONA_DEV_SCRIPTS="$work/data/checkout/scripts"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
python3 "$repo/tests/fixtures/shell-stub.py" "$work/qml" "$repo/tests/qml/PanelWidgets.inc" dwm-quickshell-state@keyboard:PANEL_KEYBOARD_STUB:args
# The keyboard requests' stub: it logs each one, takes a moment as dwm would,
# and fails while keyboard.fail exists.
cat >"$work/keyboard-stub" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$PANEL_KEYBOARD_LOG"
sleep 0.1
[ ! -e "$PANEL_KEYBOARD_LOG.fail" ]
EOF
chmod +x "$work/keyboard-stub"
: >"$work/keyboard.log"

Xvfb -displayfd 3 -screen 0 1024x768x24 -nolisten tcp -extension GLX \
	3>"$work/display" >"$work/xvfb.log" 2>&1 &
xvfb_pid=$!
i=0
while [ ! -s "$work/display" ] && [ "$i" -lt 100 ]; do
	i=$((i + 1))
	sleep 0.05
done
display_number=$(sed -n '1p' "$work/display")
case $display_number in
'' | *[!0-9]*)
	cat "$work/xvfb.log" >&2
	exit 1
	;;
esac

status=0
timeout --foreground --kill-after=2s 60s env DISPLAY=":$display_number" HOME="$work/home" \
	XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/data" \
	XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
	PANEL_KEYBOARD_STUB="$work/keyboard-stub" PANEL_KEYBOARD_LOG="$work/keyboard.log" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Panel widgets: PASS' "$work/ui.log" ||
	grep -Eq 'Panel widgets FAILED|ReferenceError:|TypeError:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Panel widgets: PASS\n'
