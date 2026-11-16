#!/bin/sh
set -eu

# Settings > Fingerprint (#483) in the shell: the section is listed with a
# reader, or while a use is on without one (#522); the fingers and uses are
# read; the pane loads; enrolling shows its
# progress and result; a use is asked to change; bad requests never reach the
# helper. Every helper is `true` but dwm-settings-fingerprint, a stub;
# check-settings-fingerprint and check-fingerprint-pam check the real ones.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_FINGERPRINT_SETTINGS_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_FINGERPRINT_SETTINGS_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
	"$work/data/checkout/scripts" "$work/runtime" "$work/state/lyona" "$work/fingerprint"
export LYONA_DEV_SCRIPTS="$work/data/checkout/scripts"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
python3 "$repo/tests/fixtures/shell-stub.py" "$work/qml" "$repo/tests/qml/FingerprintSettings.inc" dwm-settings-fingerprint:FINGERPRINT_STUB:action
# The stub: status from a file (no reader at first), calls logged, an enroll
# that streams fprintd's statuses.
printf 'fingerprint-protocol\t1\nreader\tnone\tNo fingerprint reader was found\nmodule\tavailable\t/usr/lib/security/pam_fprintd.so\nuse\tlightdm\toff\tThe password only\nuse\tpolkit\toff\tThe password only\nuse\tsudo\toff\tThe password only\ncomplete\tstatus\n' \
	>"$work/fingerprint/status"
printf 'fingerprint-protocol\t1\nreader\tavailable\tTest Reader\nfinger\tright-index-finger\nfinger-added\tright-index-finger\nmodule\tavailable\t/usr/lib/security/pam_fprintd.so\nuse\tlightdm\texternal\tfprintd was added to /etc/pam.d/lightdm outside Lyona\nuse\tpolkit\ton\tA finger is accepted, or the password\nuse\tsudo\toff\tThe password only\ncomplete\tstatus\n' \
	>"$work/fingerprint/status-reader"
printf 'fingerprint-protocol\t1\nreader\tnone\tNo fingerprint reader was found\nmodule\tavailable\t/usr/lib/security/pam_fprintd.so\nuse\tlightdm\toff\tThe password only\nuse\tpolkit\toff\tThe password only\nuse\tsudo\ton\tA finger is accepted, or the password\ncomplete\tstatus\n' \
	>"$work/fingerprint/status-noreader-on"
: >"$work/fingerprint/log"
cat >"$work/fingerprint-stub" <<'EOF'
#!/bin/sh
d=$FINGERPRINT_DIR
case $1 in
status)
	# The PAM-only read (#532) is logged, so the test can tell it apart.
	[ "${2:-}" = --uses ] && echo 'status --uses' >>"$d/log"
	cat "$d/status"
	;;
enroll)
	printf 'enroll-status\tenroll-stage-passed\n'
	printf 'enroll-status\tenroll-retry-scan\n'
	printf 'enroll-status\tenroll-stage-passed\n'
	printf 'enroll-status\tenroll-completed\n'
	printf 'enroll-result\tcompleted\tenroll-completed\n'
	echo "enroll $2" >>"$d/log"
	;;
set)
	echo "$*" >>"$d/log"
	# The password dialog dismissed, for the login use (#529).
	if [ "$2" = lightdm ]; then
		echo 'dwm-settings-fingerprint: not changed: the password prompt was cancelled' >&2
		exit 3
	fi
	;;
*) echo "$*" >>"$d/log" ;;
esac
EOF
chmod +x "$work/fingerprint-stub"

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
	FINGERPRINT_STUB="$work/fingerprint-stub" FINGERPRINT_DIR="$work/fingerprint" \
	QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
	quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui.log" 2>&1 || status=$?
# The pane and its model load without a warning of their own.
if [ "$status" -ne 0 ] || ! grep -Fq 'Fingerprint settings: PASS' "$work/ui.log" ||
	grep -Eq 'Fingerprint settings FAILED|ReferenceError:|TypeError:|Fingerprint(SettingsPane|Model)\.qml:[0-9]' "$work/ui.log"; then
	cat "$work/ui.log" >&2
	exit 1
fi
printf 'Fingerprint settings: PASS\n'
