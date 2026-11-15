#!/bin/sh
set -eu

# Joining a hidden Wi-Fi network (#471): the prompt waits for a snapshot,
# survives a failed one and adapter changes, checks the name and password, and
# keeps the name with the reason after a failed join. Driven through the real
# NetworkModel and prompt in the production shell; every helper is `true` but
# the hidden join, a stub. tests/test-quickshell-network.sh checks the helper.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_HIDDEN_WIFI_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_HIDDEN_WIFI_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
python3 "$repo/tests/fixtures/hidden-wifi.py" "$work/qml" "$repo/tests/qml/HiddenWifi.inc"
# The hidden join's stub: it logs its arguments and the line on its stdin, and
# fails as the helper does on a wrong password while hidden.log.fail exists.
cat >"$work/hidden-stub" <<'EOF'
#!/bin/sh
printf 'args %s\n' "$*" >>"$HIDDEN_WIFI_LOG"
IFS= read -r line || line=
printf 'stdin %s\n' "$line" >>"$HIDDEN_WIFI_LOG"
sleep 0.1
if [ -e "$HIDDEN_WIFI_LOG.fail" ]; then
	printf 'wrong password, or the network asked for one it did not get\nError: Secrets were required\n' >&2
	exit 4
fi
EOF
chmod +x "$work/hidden-stub"
: >"$work/hidden.log"

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
	HIDDEN_WIFI_STUB="$work/hidden-stub" HIDDEN_WIFI_LOG="$work/hidden.log" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Hidden Wi-Fi: PASS' "$work/ui.log" ||
	grep -Eq 'Hidden Wi-Fi FAILED|ReferenceError:|TypeError:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Hidden Wi-Fi: PASS\n'
