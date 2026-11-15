#!/bin/sh
set -eu

# Clipboard history (#469) in the shell: off by default with no source
# running; on, copies from the source come in newest first, a repeat moves up,
# search filters; saving writes through the helper; copy back, delete and clear;
# a malformed record stops capture until it is turned on again; off empties it.
# Every helper is `true` but dwm-clipboard-history, a stub;
# tests/test-clipboard-history.sh and check-clipboard-observer check the real
# ones.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_CLIPBOARD_HISTORY_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_CLIPBOARD_HISTORY_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
python3 "$repo/tests/fixtures/clipboard-history.py" "$work/qml" "$repo/tests/qml/ClipboardHistory.inc"
# The stub: settings in files, a log of calls, saves to a file, and an
# observer that follows a feed file of JSON records.
mkdir -p "$work/clipboard"
printf '%s\n' '{"event":"ready","protocol":1}' >"$work/clipboard/feed"
: >"$work/clipboard/log"
cat >"$work/clipboard-stub" <<'EOF'
#!/bin/sh
d=$CLIPBOARD_DIR
case $1 in
status)
	printf 'clipboard-history-protocol\t1\nstate\tavailable\tok\ncapture\t%s\npersist\t%s\ncomplete\tstatus\n' \
		"$(cat "$d/capture" 2>/dev/null || echo off)" "$(cat "$d/persist" 2>/dev/null || echo off)"
	;;
set)
	printf '%s\n' "$3" >"$d/$2"
	if [ "$2 $3" = "capture off" ] || [ "$2 $3" = "persist off" ]; then echo off >"$d/persist"; rm -f "$d/saved"; fi
	printf 'set %s %s\n' "$2" "$3" >>"$d/log"
	;;
load) cat "$d/saved" 2>/dev/null || : ;;
save) cat >"$d/saved.new" && mv "$d/saved.new" "$d/saved" && echo save >>"$d/log" ;;
clear) rm -f "$d/saved"; echo clear >>"$d/log" ;;
observe)
	echo observe >>"$d/log"
	exec tail -n +1 -f "$d/feed"
	;;
esac
EOF
chmod +x "$work/clipboard-stub"

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
	CLIPBOARD_STUB="$work/clipboard-stub" CLIPBOARD_DIR="$work/clipboard" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -F 'Clipboard history: PASS' "$work/ui.log" ||
	grep -Eq 'Clipboard history FAILED|ReferenceError:|TypeError:' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Clipboard history: PASS\n'
