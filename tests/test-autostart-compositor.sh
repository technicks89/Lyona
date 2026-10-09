#!/usr/bin/env bash
set -euo pipefail

# #244: autostart starts Picom through dwm-settings-picom, and says so once when
# it cannot: a missing Picom with the lyona desktop installed, or a failed start.
# The notification waits for the notification service a bounded number of times,
# then gives up; a core install (no Quickshell) is not told anything.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

{
	sed -n '/^notify_retry() {/,/^}$/p' "$repo/scripts/autostart.sh"
	sed -n '/^notify_session_problem() {$/,/^}$/p' "$repo/scripts/autostart.sh"
	sed -n '/^start_compositor() {$/,/^}$/p' "$repo/scripts/autostart.sh"
} >"$work/compositor.sh"
grep -q '^start_compositor() {$' "$work/compositor.sh" || fail 'start_compositor not found in autostart.sh'
grep -q '^notify_session_problem() {$' "$work/compositor.sh" || fail 'notify_session_problem not found in autostart.sh'
grep -Fxq 'start_compositor &' "$repo/scripts/autostart.sh" || fail 'autostart.sh does not start the compositor in the background'

mkdir -p "$work/stubs"
for tool in sleep cat; do
	ln -s "$(command -v "$tool")" "$work/stubs/$tool"
done
cat >"$work/stubs/dwm-settings-picom" <<'EOF'
#!/bin/sh
[ "$1" = start ] || exit 2
if [ "${STUB_PICOM_FAILS:-0}" = 1 ]; then
	printf 'Picom failed to start; see /run/user/1000/lyona-picom/picom.log\n' >&2
	exit 1
fi
printf '{"protocol": 1, "message": "Picom active"}\n'
EOF
# Fails while the notification service is "not up yet": the first STUB_NOTIFY_DOWN calls.
cat >"$work/stubs/notify-send" <<'EOF'
#!/bin/sh
count=$(($(cat "$TEST_DIR/notify.count" 2>/dev/null || printf 0) + 1))
printf '%s\n' "$count" >"$TEST_DIR/notify.count"
[ "$count" -gt "${STUB_NOTIFY_DOWN:-0}" ] || exit 1
printf '%s\n' "$*" >>"$TEST_DIR/notify.log"
EOF
chmod +x "$work/stubs/dwm-settings-picom" "$work/stubs/notify-send"

run_case() { # HAVE-PICOM HAVE-QUICKSHELL
	local name
	rm -f "$work/notify.count" "$work/notify.log" "$work/stubs/picom" "$work/stubs/quickshell"
	for name in picom quickshell; do
		[[ $name == picom && $1 == yes || $name == quickshell && $2 == yes ]] || continue
		printf '#!/bin/sh\nexit 0\n' >"$work/stubs/$name"
		chmod +x "$work/stubs/$name"
	done
	# shellcheck disable=SC2016 # expanded by the inner sh
	env -i PATH="$work/stubs" TEST_DIR="$work" DWM_AUTOSTART_NOTIFY_INTERVAL=0 \
		STUB_PICOM_FAILS="${STUB_PICOM_FAILS:-0}" STUB_NOTIFY_DOWN="${STUB_NOTIFY_DOWN:-0}" \
		DWM_AUTOSTART_NOTIFY_TRIES="${DWM_AUTOSTART_NOTIFY_TRIES:-15}" \
		/bin/sh -c '. "$1" && start_compositor' sh "$work/compositor.sh"
}
notified() { # COUNT
	local lines=0
	[[ ! -f $work/notify.log ]] || lines=$(wc -l <"$work/notify.log")
	[[ $lines == "$1" ]]
}

# Picom starts: nothing to say.
run_case yes yes || fail 'a working start failed'
notified 0 || fail 'a working start sent a notification'

# The start fails: one notification, with the helper's message in it.
STUB_PICOM_FAILS=1 run_case yes yes || fail 'a failed start stopped autostart'
notified 1 || fail 'a failed start was not notified exactly once'
grep -Fq -- '-a lyona -u critical -- Picom could not start Window previews in the overview are off.' "$work/notify.log" ||
	fail 'the failed-start notification is not the expected one'
grep -Fq 'see /run/user/1000/lyona-picom/picom.log' "$work/notify.log" || fail 'the notification does not carry the log path'
# #293: it points at the backend that usually works, not at a restart.
grep -Fq 'Try the XRender backend in Settings > Appearance > Compositor.' "$work/notify.log" ||
	fail 'the failed-start notification does not point at XRender'

# Picom missing with the desktop installed: one notification.
run_case no yes || fail 'a missing Picom stopped autostart'
notified 1 || fail 'a missing Picom was not notified exactly once'
grep -Fq 'Picom is not installed' "$work/notify.log" || fail 'the missing-Picom notification is not the expected one'

# A core install (no Quickshell, no Picom): nothing.
run_case no no || fail 'a core session failed'
notified 0 || fail 'a core session was told about Picom'

# The notification service comes up on the third try: delivered once.
STUB_PICOM_FAILS=1 STUB_NOTIFY_DOWN=2 run_case yes yes
notified 1 || fail 'a late notification service did not get the message once'
[[ $(cat "$work/notify.count") == 3 ]] || fail 'the notification was not retried until the service was up'

# It never comes up: given up after the tries, and autostart goes on.
STUB_PICOM_FAILS=1 STUB_NOTIFY_DOWN=99 DWM_AUTOSTART_NOTIFY_TRIES=4 run_case yes yes ||
	fail 'an absent notification service stopped autostart'
notified 0 || fail 'a notification was recorded without a service'
[[ $(cat "$work/notify.count") == 4 ]] || fail 'the notification was not given up after the tries'

printf 'Autostart compositor and its one message: PASS\n'
