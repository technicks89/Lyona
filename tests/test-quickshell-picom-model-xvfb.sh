#!/bin/sh
set -eu

# Opening the Picom settings must not read the configuration twice when nothing
# changed, and must still show an edit made between the first read and the
# moment the watcher went live. Driven through the real PicomModel with the
# Picom helper replaced by a stub that plays scripted watcher scenarios.

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
for command_name in Xvfb dbus-run-session quickshell timeout python3; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'SKIP: %s is unavailable\n' "$command_name"
		exit 77
	fi
done
if [ "${DWM_PICOM_MODEL_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_PICOM_MODEL_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
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
	"$work/data/lyona/scripts" "$work/runtime" "$work/state/lyona"
chmod 700 "$work/runtime"
cp -a "$repo/config/quickshell/." "$work/qml/"
cp "$repo/config/"*.toml "$work/home/.config/lyona/"
cp "$repo/tests/fixtures/picom-stub.sh" "$work/data/lyona/scripts/dwm-settings-picom"
chmod +x "$work/data/lyona/scripts/dwm-settings-picom"
python3 "$repo/tests/fixtures/picom-model.py" "$work/qml" "$repo/tests/qml/PicomModel.inc"

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

# run_scenario NAME RUN_MS EXPECTED_READS EXPECTED_REVISION WHY
run_scenario() {
	name=$1 run_ms=$2 want_reads=$3 want_revision=$4 why=$5
	ctl=$work/ctl-$name
	rm -rf "$ctl"
	mkdir -p "$ctl"
	printf 'r1\n' >"$ctl/revision"
	status=0
	timeout --foreground --kill-after=2s 60s env DISPLAY=":$display_number" HOME="$work/home" \
		XDG_CONFIG_HOME="$work/home/.config" XDG_DATA_HOME="$work/data" \
		XDG_STATE_HOME="$work/state" XDG_RUNTIME_DIR="$work/runtime" \
		QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software \
		PICOM_STUB_DIR="$ctl" PICOM_SCENARIO="$name" PICOM_RUN_MS="$run_ms" \
		quickshell --no-duplicate --path "$work/qml/shell.qml" >"$work/ui-$name.log" 2>&1 || status=$?
	reads=0
	[ ! -f "$ctl/status.log" ] || reads=$(wc -l <"$ctl/status.log")
	result=$(grep -F 'Picom result:' "$work/ui-$name.log" || true)
	if [ "$status" -ne 0 ] || [ -z "$result" ] || grep -Eq 'ReferenceError:|TypeError:' "$work/ui-$name.log"; then
		cat "$work/ui-$name.log" >&2
		printf 'Picom model: %s did not run cleanly\n' "$name" >&2
		exit 1
	fi
	case $result in
	*"revision=$want_revision busy=false failure="*) ;;
	*)
		printf 'Picom model: %s ended with [%s], expected revision %s and idle\n' "$name" "$result" "$want_revision" >&2
		exit 1
		;;
	esac
	if [ "$reads" -ne "$want_reads" ]; then
		printf 'Picom model: %s made %s status reads, expected %s (%s)\n' "$name" "$reads" "$want_reads" "$why" >&2
		exit 1
	fi
	printf '  %-15s %s read(s), shows %s\n' "$name" "$reads" "$want_revision"
}

run_scenario unchanged 3000 1 r1 'nothing changed, so the watcher handshake needs no second read'
run_scenario edited 3000 2 r2 'an edit between the read and the watcher going live must be shown'
run_scenario slow-unchanged 4000 1 r1 'ready arrived during the first read and matches it'
run_scenario slow-edited 5000 2 r2 'an edit during the first read must be shown'
run_scenario bare-ready 3000 2 r1 'a watcher that cannot say what it saw means read again'
run_scenario failed-read 3000 2 r1 'a failed first read is retried once the watcher is ready'
run_scenario failed-matching-revision 4000 3 r1 'a failed read with a matching watcher revision is retried'
run_scenario changed-only 4000 2 r3 'one change, one read, and no read loop'
run_scenario changed-real 4000 2 r3 'a change followed by the re-armed ready is still one read'
printf 'Picom model: PASS\n'
