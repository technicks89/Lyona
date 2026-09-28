#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
work=$(mktemp -d)
runner_identities=()

process_starttime() {
	local pid=$1
	awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); if (fields[20] ~ /^[0-9]+$/) print fields[20] }' "/proc/$pid/stat" 2>/dev/null
}

process_matches() {
	local identity=$1
	local pid=${identity%%:*} expected=${identity#*:} current
	current=$(process_starttime "$pid")
	[ -n "$current" ] && [ "$current" = "$expected" ]
}

track_runner() {
	local pid=$1 starttime
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		starttime=$(process_starttime "$pid")
		if [ -n "$starttime" ]; then
			runner_identities+=("$pid:$starttime")
			return 0
		fi
		sleep 0.01
	done
	return 1
}

cleanup() {
	local identity pid
	for identity in "${runner_identities[@]}"; do
		process_matches "$identity" || continue
		pid=${identity%%:*}
		kill -TERM "$pid" 2>/dev/null || true
	done
	sleep 0.1
	for identity in "${runner_identities[@]}"; do
		process_matches "$identity" || continue
		pid=${identity%%:*}
		kill -KILL "$pid" 2>/dev/null || true
	done
	for identity in "${runner_identities[@]}"; do
		wait "${identity%%:*}" 2>/dev/null || true
	done
	rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$work/bin" "$work/power/BAT0" "$work/runtime"
chmod 700 "$work/runtime"
printf '82\n' >"$work/power/BAT0/capacity"
printf 'Discharging\n' >"$work/power/BAT0/status"

# dwm-status publishes power only; a pactl on PATH must not be used.
cat >"$work/bin/pactl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DWM_STATUS_TEST_STATE/pactl.calls"
exit 1
SH
chmod +x "$work/bin/pactl"

cat >"$work/bin/udevadm" <<'SH'
#!/bin/sh
starttime=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' "/proc/$$/stat")
printf '%s:%s\n' "$$" "$starttime" >"$DWM_STATUS_TEST_STATE/udevadm.pid"
if [ "${DWM_STATUS_TEST_RESTART_ONCE:-0}" = 1 ] ||
	[ "${DWM_STATUS_TEST_ALWAYS_EXIT:-0}" = 1 ]; then
	count=0
	[ ! -f "$DWM_STATUS_TEST_STATE/udevadm.count" ] || count=$(cat "$DWM_STATUS_TEST_STATE/udevadm.count")
	count=$((count + 1))
	printf '%s\n' "$count" >"$DWM_STATUS_TEST_STATE/udevadm.count"
	if [ "${DWM_STATUS_TEST_ALWAYS_EXIT:-0}" = 1 ] || [ "$count" -eq 1 ]; then
		exit 0
	fi
fi
trap '' TERM
exec sleep 60
SH
chmod +x "$work/bin/udevadm"

# The read-back on a tick with nothing new to publish: the last name written, or
# another client's once (the stub consumes the marker) after the test has marked it
# overwritten; it fails once the test has marked the display gone.
cat >"$work/bin/xprop" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$DWM_STATUS_TEST_STATE/xprop.calls"
[ ! -e "$DWM_STATUS_TEST_STATE/display-gone" ] || exit 1
if rm "$DWM_STATUS_TEST_STATE/overwritten" 2>/dev/null; then
	printf 'WM_NAME = "%s"\n' 'someone else'
else
	printf 'WM_NAME = "%s"\n' "$(tail -n 1 "$DWM_STATUS_TEST_LOG" 2>/dev/null)"
fi
SH
chmod +x "$work/bin/xprop"

cat >"$work/bin/xsetroot" <<'SH'
#!/bin/sh
if [ "${DWM_STATUS_TEST_BLOCK_PUBLISH:-0}" = 1 ]; then
	printf '%s\n' "$$" >"$DWM_STATUS_TEST_STATE/xsetroot.pid"
	: >"$DWM_STATUS_TEST_STATE/xsetroot.blocked"
	trap 'exit 0' HUP INT TERM
	while :; do sleep 1; done
fi
while [ "$#" -gt 0 ]; do
	case "$1" in
	-name)
		printf '%s\n' "$2" >>"$DWM_STATUS_TEST_LOG"
		exit 0
		;;
	esac
	shift
done
SH
chmod +x "$work/bin/xsetroot"

cat >"$work/bin/awk" <<'SH'
#!/bin/sh
case ${DWM_STATUS_TEST_CAPTURE_FAIL:-0}:$* in
1:*'/proc/'*'/stat'*)
	count=0
	[ ! -f "$DWM_STATUS_TEST_STATE/awk-proc.count" ] || count=$(cat "$DWM_STATUS_TEST_STATE/awk-proc.count")
	count=$((count + 1))
	printf '%s\n' "$count" >"$DWM_STATUS_TEST_STATE/awk-proc.count"
	[ "$count" -eq 1 ] || exit 1
	;;
esac
exec /usr/bin/awk "$@"
SH
chmod +x "$work/bin/awk"

PATH="$work/bin:/usr/bin:/bin" \
	DISPLAY=:199 \
	DWM_STATUS_TEST_LOG="$work/status.log" \
	DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" \
	DWM_STATUS_POWER_POLL_INTERVAL=0.1 \
	XDG_RUNTIME_DIR="$work/runtime" \
	"$repo/scripts/dwm-status" &
status_runner=$!
track_runner "$status_runner"

display_key=$(printf '%s' :199 | sha256sum | awk '{ print $1 }')
identity_file=$work/runtime/lyona/dwm-status.$display_key.identity
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ -s "$identity_file" ] && break
	sleep 0.02
done
[ "$(cat "$identity_file")" = "$status_runner:$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[20] }' "/proc/$status_runner/stat")" ]

sleep 0.3
# Three ticks with the same battery: nothing rewritten, but the display was checked.
[ "$(wc -l <"$work/status.log")" -eq 1 ] || {
	printf 'An unchanged power state was published again:\n' >&2
	cat "$work/status.log" >&2
	exit 1
}
[ -s "$work/xprop.calls" ]
printf '81\n' >"$work/power/BAT0/capacity"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	grep -Fqx 'BAT 81% Discharging' "$work/status.log" && break
	sleep 0.05
done
kill "$status_runner" 2>/dev/null || true
wait "$status_runner" || status=$?

case ${status:-0} in
0 | 143) ;;
*) exit "$status" ;;
esac
[ ! -e "$identity_file" ]

test -s "$work/udevadm.pid"
provider_identity=$(cat "$work/udevadm.pid")
if process_matches "$provider_identity"; then
	printf 'Provider survived status teardown: %s\n' "$provider_identity" >&2
	exit 1
fi
[ ! -e "$work/pactl.calls" ]

[ "$(sed -n 1p "$work/status.log")" = 'BAT 82% Discharging' ]
[ "$(sed -n 2p "$work/status.log")" = 'BAT 81% Discharging' ]
[ "$(wc -l <"$work/status.log")" -eq 2 ]

: >"$work/invalid-status.log"
PATH="$work/bin:/usr/bin:/bin" \
	DISPLAY=:199 \
	DWM_STATUS_TEST_LOG="$work/invalid-status.log" \
	DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" \
	DWM_STATUS_POWER_POLL_INTERVAL=invalid \
	XDG_RUNTIME_DIR="$work/runtime" \
	"$repo/scripts/dwm-status" &
invalid_runner=$!
track_runner "$invalid_runner"
for _ in 1 2 3 4 5 6 7 8 9 10; do
	[ "$(wc -l <"$work/invalid-status.log")" -ge 1 ] && break
	sleep 0.02
done
sleep 0.2
kill -TERM "$invalid_runner"
wait "$invalid_runner" || invalid_status=$?
[ "${invalid_status:-0}" -eq 143 ]
[ "$(wc -l <"$work/invalid-status.log")" -eq 1 ]

: >"$work/restart-status.log"
rm -f "$work/udevadm.count"
PATH="$work/bin:/usr/bin:/bin" \
	DISPLAY=:200 \
	DWM_STATUS_TEST_LOG="$work/restart-status.log" \
	DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_TEST_RESTART_ONCE=1 \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" \
	DWM_STATUS_POWER_POLL_INTERVAL=30 \
	XDG_RUNTIME_DIR="$work/runtime" \
	"$repo/scripts/dwm-status" &
restart_runner=$!
track_runner "$restart_runner"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70; do
	[ "$(cat "$work/udevadm.count" 2>/dev/null || printf 0)" -ge 2 ] && break
	sleep 0.05
done
[ "$(cat "$work/udevadm.count")" -eq 2 ]
sleep 0.2
[ "$(cat "$work/udevadm.count")" -eq 2 ]
kill -TERM "$restart_runner"
wait "$restart_runner" || restart_status=$?
[ "${restart_status:-0}" -eq 143 ]
provider_identity=$(cat "$work/udevadm.pid")
if process_matches "$provider_identity"; then
	printf 'Restarted provider survived status teardown: %s\n' "$provider_identity" >&2
	exit 1
fi

: >"$work/degraded-status.log"
rm -f "$work/awk-proc.count"
PATH="$work/bin:/usr/bin:/bin" DISPLAY=:201 \
	DWM_STATUS_TEST_LOG="$work/degraded-status.log" DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_TEST_CAPTURE_FAIL=1 DWM_STATUS_POWER_SUPPLY_DIR="$work/power" \
	DWM_STATUS_POWER_POLL_INTERVAL=0.1 XDG_RUNTIME_DIR="$work/runtime" \
	"$repo/scripts/dwm-status" &
degraded_runner=$!
track_runner "$degraded_runner"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	[ "$(wc -l <"$work/degraded-status.log")" -ge 1 ] && break
	sleep 0.05
done
# Still polling without its providers: a change is published.
printf '80\n' >"$work/power/BAT0/capacity"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	[ "$(wc -l <"$work/degraded-status.log")" -ge 2 ] && break
	sleep 0.05
done
[ "$(wc -l <"$work/degraded-status.log")" -eq 2 ]
kill -0 "$degraded_runner"
degraded_provider_children=
for _ in 1 2 3 4 5 6 7 8 9 10; do
	degraded_provider_children=$(pgrep -P "$degraded_runner" -x 'pactl|udevadm' 2>/dev/null || true)
	[ -z "$degraded_provider_children" ] && break
	sleep 0.05
done
[ -z "$degraded_provider_children" ]
kill -TERM "$degraded_runner"
wait "$degraded_runner" || degraded_status=$?
[ "${degraded_status:-0}" -eq 143 ]

: >"$work/churn-status.log"
rm -f "$work/udevadm.count"
PATH="$work/bin:/usr/bin:/bin" DISPLAY=:202 \
	DWM_STATUS_TEST_LOG="$work/churn-status.log" DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_TEST_ALWAYS_EXIT=1 DWM_STATUS_PROVIDER_RESTART_LIMIT=2 \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" DWM_STATUS_POWER_POLL_INTERVAL=0.1 \
	XDG_RUNTIME_DIR="$work/runtime" "$repo/scripts/dwm-status" &
churn_runner=$!
track_runner "$churn_runner"
for _ in $(seq 1 80); do
	[ "$(cat "$work/udevadm.count" 2>/dev/null || printf 0)" -ge 3 ] && break
	sleep 0.05
done
[ "$(cat "$work/udevadm.count")" -eq 3 ]
sleep 1.2
[ "$(cat "$work/udevadm.count")" -eq 3 ]
kill -TERM "$churn_runner"
wait "$churn_runner" || churn_status=$?
[ "${churn_status:-0}" -eq 143 ]

: >"$work/prefd-status.log"
rm -f "$work/xsetroot.blocked" "$work/xsetroot.pid"
PATH="$work/bin:/usr/bin:/bin" DISPLAY=:203 \
	DWM_STATUS_TEST_LOG="$work/prefd-status.log" DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_TEST_BLOCK_PUBLISH=1 DWM_STATUS_POWER_SUPPLY_DIR="$work/power" \
	DWM_STATUS_POWER_POLL_INTERVAL=30 XDG_RUNTIME_DIR="$work/runtime" \
	"$repo/scripts/dwm-status" &
prefd_runner=$!
track_runner "$prefd_runner"
for _ in $(seq 1 50); do
	[ -s "$work/xsetroot.pid" ] && break
	sleep 0.02
done
[ -s "$work/xsetroot.pid" ]
prefd_started=$(date +%s)
kill -TERM "$prefd_runner"
wait "$prefd_runner" || prefd_status=$?
prefd_elapsed=$(($(date +%s) - prefd_started))
[ "${prefd_status:-0}" -eq 143 ]
[ "$prefd_elapsed" -lt 3 ]
xsetroot_pid=$(cat "$work/xsetroot.pid")
if kill -0 "$xsetroot_pid" 2>/dev/null; then
	xsetroot_state=$(awk '{ line = $0; sub(/^.*\) /, "", line); split(line, fields, " "); print fields[1] }' "/proc/$xsetroot_pid/stat" 2>/dev/null || true)
	[ "$xsetroot_state" = Z ]
fi

# Another client overwrote WM_NAME: the next quiet tick reads it back and writes
# the power state again, once.
: >"$work/overwrite-status.log"
PATH="$work/bin:/usr/bin:/bin" DISPLAY=:205 \
	DWM_STATUS_TEST_LOG="$work/overwrite-status.log" DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" DWM_STATUS_POWER_POLL_INTERVAL=0.1 \
	XDG_RUNTIME_DIR="$work/runtime" "$repo/scripts/dwm-status" &
overwrite_runner=$!
track_runner "$overwrite_runner"
for _ in $(seq 1 50); do
	[ -s "$work/overwrite-status.log" ] && break
	sleep 0.02
done
sleep 0.3
[ "$(wc -l <"$work/overwrite-status.log")" -eq 1 ]
: >"$work/overwritten"
for _ in $(seq 1 50); do
	[ "$(wc -l <"$work/overwrite-status.log")" -ge 2 ] && break
	sleep 0.02
done
sleep 0.3
[ "$(wc -l <"$work/overwrite-status.log")" -eq 2 ] || {
	printf 'An overwritten WM_NAME was not restored exactly once:\n' >&2
	cat "$work/overwrite-status.log" >&2
	exit 1
}
[ "$(sed -n 2p "$work/overwrite-status.log")" = "$(sed -n 1p "$work/overwrite-status.log")" ]
kill -TERM "$overwrite_runner"
wait "$overwrite_runner" || overwrite_status=$?
[ "${overwrite_status:-0}" -eq 143 ]

# Its X server gone (as after a killed session): the next quiet tick's display
# check fails and dwm-status exits, taking its providers with it.
: >"$work/gone-status.log"
rm -f "$work/udevadm.pid"
PATH="$work/bin:/usr/bin:/bin" DISPLAY=:204 \
	DWM_STATUS_TEST_LOG="$work/gone-status.log" DWM_STATUS_TEST_STATE="$work" \
	DWM_STATUS_POWER_SUPPLY_DIR="$work/power" DWM_STATUS_POWER_POLL_INTERVAL=0.1 \
	XDG_RUNTIME_DIR="$work/runtime" "$repo/scripts/dwm-status" &
gone_runner=$!
track_runner "$gone_runner"
for _ in $(seq 1 50); do
	[ -s "$work/gone-status.log" ] && [ -s "$work/udevadm.pid" ] && break
	sleep 0.02
done
[ -s "$work/gone-status.log" ]
: >"$work/display-gone"
gone_started=$(date +%s)
gone_status=0
wait "$gone_runner" || gone_status=$?
gone_elapsed=$(($(date +%s) - gone_started))
[ "$gone_status" -ne 0 ] && [ "$gone_status" -ne 143 ]
[ "$gone_elapsed" -lt 3 ]
provider_identity=$(cat "$work/udevadm.pid")
if process_matches "$provider_identity"; then
	printf 'Provider survived a lost display: %s\n' "$provider_identity" >&2
	exit 1
fi
[ "$(wc -l <"$work/gone-status.log")" -eq 1 ]

printf 'dwm-status power polling (published on change only, exits with its display): PASS\n'
