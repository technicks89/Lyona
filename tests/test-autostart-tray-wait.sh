#!/usr/bin/env bash
set -euo pipefail

# #288: at login, autostart waits for the tray before starting tray apps. It
# waits on the tray's D-Bus name with one gdbus process rather than asking
# Quickshell over IPC every 0.1 s, and still polls when gdbus or the session bus
# is missing. Either way it gives up after about 5 seconds.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

sed -n '/^wait_for_quickshell_tray() {$/,/^}$/p' "$repo/scripts/autostart.sh" >"$work/wait.sh"
grep -q '^wait_for_quickshell_tray() {$' "$work/wait.sh" || fail 'wait_for_quickshell_tray not found in autostart.sh'

mkdir -p "$work/bin" "$work/nogdbus"
cat >"$work/bin/gdbus" <<'STUB'
#!/bin/sh
printf 'gdbus %s\n' "$*" >>"$STUB_LOG"
exit "${STUB_GDBUS_STATUS:-0}"
STUB
cat >"$work/bin/quickshell" <<'STUB'
#!/bin/sh
printf 'quickshell %s\n' "$*" >>"$STUB_LOG"
exit 0
STUB
chmod +x "$work/bin/gdbus" "$work/bin/quickshell"
ln -s "$work/bin/quickshell" "$work/nogdbus/quickshell"
for tool in timeout sh sleep; do
	ln -s "$(command -v "$tool")" "$work/nogdbus/$tool"
done

run_wait() { # PATH BUS
	rm -f "$work/log"
	# shellcheck disable=SC2016 # expanded by the inner shell
	env -i PATH="$1" DBUS_SESSION_BUS_ADDRESS="$2" XDG_RUNTIME_DIR="$work/runtime" STUB_LOG="$work/log" \
		sh -c '. "$1"; wait_for_quickshell_tray /config' sh "$work/wait.sh"
}

# A session bus: one gdbus wait for the tray's name, no IPC.
run_wait "$work/bin:/usr/bin:/bin" unix:path=/run/bus || fail 'the D-Bus wait failed'
grep -Fqx 'gdbus wait --session --timeout 5 org.kde.StatusNotifierWatcher' "$work/log" ||
	fail "autostart did not wait on the tray's D-Bus name: $(cat "$work/log")"
grep -q '^quickshell ' "$work/log" && fail 'autostart polled Quickshell although it could wait on D-Bus'
# No session bus: the IPC poll, which ends as soon as Quickshell answers.
run_wait "$work/bin:/usr/bin:/bin" '' || fail 'the IPC wait failed'
grep -Fqx 'quickshell ipc --path /config call tray count' "$work/log" || fail 'autostart did not fall back to the IPC poll'
grep -q '^gdbus ' "$work/log" && fail 'autostart ran gdbus without a session bus'
# No gdbus: the IPC poll too.
run_wait "$work/nogdbus" unix:path=/run/bus || fail 'the IPC wait without gdbus failed'
grep -Fqx 'quickshell ipc --path /config call tray count' "$work/log" || fail 'autostart did not poll without gdbus'

printf 'Autostart waits for the tray on D-Bus, polling only without it: PASS\n'
