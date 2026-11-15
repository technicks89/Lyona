#!/bin/sh
set -eu

# Settings' wallpaper status reads (#444): a status read queued behind an
# inventory read runs when that read ends, even while the inventory read's own
# retry waits for a watch that is restarting, so a wallpaper applied outside
# Settings shows up there without waiting for the watch. The real wallpaper and
# appearance helpers answer, through a wrapper that slows the inventory read
# and holds the watch short of ready; every other helper is `true`.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_APPEARANCE_QUEUE_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_APPEARANCE_QUEUE_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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

mkdir -p "$work/qml" "$work/home/.config/lyona" "$work/home/Pictures/backgrounds" \
	"$work/data/checkout/scripts" "$work/runtime" "$work/state/lyona"
export LYONA_DEV_SCRIPTS="$work/data/checkout/scripts"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
python3 "$repo/tests/fixtures/appearance-status-queue.py" "$work/qml" "$repo/tests/qml/AppearanceStatusQueue.inc"
# A 1x1 PNG to apply.
printf '\211PNG\r\n\032\n\0\0\0\rIHDR\0\0\0\001\0\0\0\001\010\002\0\0\0\220wS\336\0\0\0\014IDATx\234c\370\017\0\0\001\001\0\005\030\330N\0\0\0\0IEND\256B`\202' \
	>"$work/home/Pictures/backgrounds/b.png"
# The wrapper: the real helper, but a watch that never becomes ready (one still
# restarting) and an inventory read slowed by the delay the test writes.
cat >"$work/appearance-stub" <<STUB
#!/bin/sh
helper=\$1
shift
case "\$helper \$1" in
'dwm-settings-appearance watch-inventory') exec sleep 60 ;;
'dwm-settings-appearance inventory') sleep "\$(cat "\$APPEARANCE_DIR/inventory-delay" 2>/dev/null || echo 0)" ;;
esac
exec "$repo/scripts/\$helper" "\$@"
STUB
chmod +x "$work/appearance-stub"

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
	APPEARANCE_STUB="$work/appearance-stub" APPEARANCE_DIR="$work" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -Fq 'Appearance status queue: PASS' "$work/ui.log" ||
	grep -Eq 'Appearance status queue FAILED|ReferenceError:|TypeError:' "$work/ui.log"; then
	grep -E 'Appearance status queue|ReferenceError:|TypeError:' "$work/ui.log" >&2 || tail -40 "$work/ui.log" >&2
	exit 1
fi
printf 'Appearance status queue: PASS\n'
