#!/bin/sh

set -eu

# Sync Sprint 12 S12-06: text from other programs is shown as text, never as
# markup. Runs dwm and the full managed Quickshell on an isolated Xvfb and D-Bus
# session with a local HTTP listener, then sends a notification whose summary and
# body carry <img src> tags pointing at the listener, opens a window whose title
# carries one, and opens the overview, which lists that title. With Qt's default
# Text.AutoText the shell fetched the images (a tracking beacon) and parsed the
# title as markup; now nothing reaches the listener and Qt logs no <img> handling.
# Positive controls: the notification did reach the shell (it is in the history),
# and the listener does log a request.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"

for cmd in Xvfb xprop xdotool quickshell dbus-run-session notify-send python3 curl feh; do
	command -v "$cmd" >/dev/null 2>&1 || {
		printf 'SKIP: %s is unavailable\n' "$cmd"
		exit 77
	}
done
[ -x "$repo/dwm" ] || {
	printf 'SKIP: dwm is not built (run make all)\n'
	exit 77
}
if [ "${DWM_PLAIN_TEXT_DBUS_SESSION:-0}" != 1 ]; then
	exec env DWM_PLAIN_TEXT_DBUS_SESSION=1 dbus-run-session -- "$0" "$@"
fi

work=$(mktemp -d "${DWM_TEST_TMP_ROOT:-${TMPDIR:-/tmp}}/plain-text.XXXXXX")
pids=
cleanup() {
	status=$?
	set +e
	if [ "$status" -ne 0 ] && [ -f "$work/quickshell.log" ]; then
		tail -40 "$work/quickshell.log" >&2
	fi
	for pid in $pids; do kill "$pid" 2>/dev/null; done
	rm -rf "$work"
	exit "$status"
}
trap cleanup EXIT
trap 'exit 143' HUP INT TERM

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

home=$work/home
runtime=$work/runtime
mkdir -p "$home/.config/quickshell" "$home/.config/lyona" "$home/.cache" "$home/.local/share/lyona" "$runtime"
chmod 700 "$runtime"
cp -a "$repo/config/quickshell/." "$home/.config/quickshell/"
cp "$repo/config/"*.toml "$home/.config/lyona/"
cp -a "$repo/scripts" "$home/.local/share/lyona/scripts"
# Helpers are no longer looked up in a per-user copy; the developer override
# names the directory holding this test's helpers (Sync Sprint 12 S12-13).
export LYONA_DEV_SCRIPTS="$home/.local/share/lyona/scripts"

# The listener: every request is logged to $work/requests.
python3 - "$work/port" "$work/requests" <<'PY' &
import http.server, socketserver, sys
port_file, log_file = sys.argv[1], sys.argv[2]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(log_file, 'a') as f:
            f.write(self.path + '\n')
        self.send_response(404)
        self.end_headers()
    def log_message(self, *args):
        pass
with socketserver.TCPServer(('127.0.0.1', 0), Handler) as server:
    with open(port_file + '.tmp', 'w') as f:
        f.write(str(server.server_address[1]))
    import os
    os.rename(port_file + '.tmp', port_file)
    server.serve_forever()
PY
pids="$pids $!"
i=0
until [ -s "$work/port" ]; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'the listener did not start'
	sleep 0.05
done
port=$(cat "$work/port")
: >"$work/requests"

display=":$((($$ % 400) + 1500))"
Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp >"$work/xvfb.log" 2>&1 &
pids="$pids $!"
i=0
until DISPLAY=$display xprop -root >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'Xvfb did not start'
	sleep 0.05
done

run_env() {
	env DISPLAY="$display" HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_DATA_HOME="$home/.local/share" \
		XDG_CACHE_HOME="$home/.cache" XDG_RUNTIME_DIR="$runtime" \
		QSG_RHI_BACKEND=software QT_QUICK_BACKEND=software QT_QPA_PLATFORMTHEME= \
		DWM_AUTOSTART_NO_INPUT_WATCH=1 PATH="$repo/scripts:$PATH" "$@"
}
run_env "$repo/dwm" >"$work/dwm.log" 2>&1 &
pids="$pids $!"
run_env quickshell --no-duplicate >"$work/quickshell.log" 2>&1 &
pids="$pids $!"

# The shell's notification server is up once a notification reaches the history.
history=$home/.cache/lyona/notification-history.json
img() { printf '<img src="http://127.0.0.1:%s/%s.png">' "$port" "$1"; }
i=0
until [ -f "$history" ] && grep -Fq 'lyona-plain-text-summary' "$history"; do
	[ $((i % 20)) != 0 ] || run_env notify-send --app-name='Plain Text Test' \
		"lyona-plain-text-summary $(img summary)" "body text $(img body)" 2>/dev/null || :
	i=$((i + 1))
	[ "$i" -lt 400 ] || fail 'the notification never reached the shell'
	sleep 0.05
done

# A focused window whose title carries markup, shown by the panel.
python3 -c 'from PIL import Image; Image.new("RGB", (64, 64), (40, 80, 120)).save("'"$work"'/pic.png")'
run_env feh --title "lyona-title $(img title)" "$work/pic.png" >/dev/null 2>&1 &
pids="$pids $!"
i=0
until DISPLAY=$display xdotool search --name 'lyona-title' >/dev/null 2>&1; do
	i=$((i + 1))
	[ "$i" -lt 100 ] || fail 'the test window did not appear'
	sleep 0.05
done

# The overview lists the window with its title (OverviewCard.qml).
ipc_ok=0
i=0
while [ "$i" -lt 100 ]; do
	if run_env quickshell ipc --path "$home/.config/quickshell/shell.qml" call overview open >/dev/null 2>&1; then
		ipc_ok=1
		break
	fi
	i=$((i + 1))
	sleep 0.05
done
[ "$ipc_ok" = 1 ] || fail 'could not open the overview'

# Give the popup, the history, the panel title and the overview time to render.
sleep 3

[ ! -s "$work/requests" ] || fail "the shell fetched markup images: $(tr '\n' ' ' <"$work/requests")"
! grep -Fq 'img tag' "$work/quickshell.log" || fail "Qt parsed markup: $(grep -F 'img tag' "$work/quickshell.log" | head -2)"

# Positive control: the listener logs a request that does arrive.
curl -s -o /dev/null "http://127.0.0.1:$port/control.png" || :
grep -Fxq '/control.png' "$work/requests" || fail 'the listener does not log requests'

printf 'Quickshell plain text (notification summary and body, window title in the panel and overview): PASS\n'
