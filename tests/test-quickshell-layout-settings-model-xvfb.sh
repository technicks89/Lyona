#!/bin/sh
set -eu

# Settings > Appearance > Layout's model (#530, #534) in the shell: it reads
# only while Appearance shows, says it is reading until the first line, queues
# writes one at a time (the latest per field), keeps a slider on the value
# asked for until dwm reports it, resets a tag, sets title bars, and goes back
# to dwm's values when a write fails. Every helper is `true` but
# dwm-layout-settings and dwm-settings-theme, a stub; check-layout-settings and
# the theme test check the real ones.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_LAYOUT_MODEL_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_LAYOUT_MODEL_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
	"$work/data/checkout/scripts" "$work/runtime" "$work/state/lyona" "$work/layout"
export LYONA_DEV_SCRIPTS="$work/data/checkout/scripts"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
python3 "$repo/tests/fixtures/shell-stub.py" "$work/qml" "$repo/tests/qml/LayoutSettingsModel.inc" dwm-layout-settings,dwm-settings-theme:LAYOUT_STUB:helper
# The stub: the watch follows a feed file; a set is logged after 0.4 s (so
# the next ones queue), and fails while "fail" exists; title bars in a file.
: >"$work/layout/feed"
: >"$work/layout/log"
printf '0 511\n' >"$work/layout/titlebars"
cat >"$work/layout-stub" <<'STUB'
#!/bin/sh
d=$LAYOUT_DIR
case "$1 $2" in
'dwm-layout-settings watch') exec tail -n +1 -f "$d/feed" ;;
'dwm-layout-settings set')
	shift 2
	sleep 0.4
	[ -e "$d/fail" ] && { echo 'dwm-layout-settings: cannot write layout.toml' >&2; exit 1; }
	echo "set $*" >>"$d/log"
	;;
'dwm-settings-theme titlebars-status')
	echo status >>"$d/log"
	read -r e m <"$d/titlebars"
	printf 'appearance-titlebars-protocol\t1\t0\ntitlebars\t%s\t%s\n' "$e" "$m"
	;;
'dwm-settings-theme titlebars')
	printf '%s %s\n' "$3" "$4" >"$d/titlebars"
	echo "titlebars $3 $4" >>"$d/log"
	;;
*) exit 0 ;;
esac
STUB
chmod +x "$work/layout-stub"

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
	LAYOUT_STUB="$work/layout-stub" LAYOUT_DIR="$work/layout" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
if [ "$status" -ne 0 ] || ! grep -Fq 'Layout settings model: PASS' "$work/ui.log" ||
	grep -Eq 'Layout settings model FAILED|ReferenceError:|TypeError:|LayoutSettings(Model|Section)\.qml:[0-9]' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Layout settings model: PASS\n'
