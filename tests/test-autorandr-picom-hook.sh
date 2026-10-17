#!/usr/bin/env bash
set -euo pipefail

# The autorandr hook that keeps Picom out of a layout change (#386): Picom is
# stopped before the change and started after it, only when it was running,
# and started again by itself if autorandr never reaches postswitch.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
hook="$repo/config/autorandr/50-lyona-picom"

work="$(mktemp -d "${DWM_TEST_TMP_ROOT:-$HOME/tmp}/autorandr-picom.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/run" "$work/bin" "$work/pre/preswitch.d" "$work/post/postswitch.d"
cp "$hook" "$work/pre/preswitch.d/50-lyona-picom"
cp "$hook" "$work/post/postswitch.d/50-lyona-picom"

# A stand-in for dwm-settings-picom: "state" is whether Picom runs.
cat >"$work/bin/dwm-settings-picom" <<'STUB'
#!/bin/sh
state=$STUB_DIR/state
printf '%s\n' "$1" >>"$STUB_DIR/calls"
case $1 in
status) [ "$(cat "$state" 2>/dev/null)" = running ] && echo '{"running": true}' || echo '{"running": false}' ;;
stop) echo stopped >"$state" ;;
start) [ -e "$STUB_DIR/startfails" ] && exit 1; echo running >"$state" ;;
esac
STUB
chmod +x "$work/bin/dwm-settings-picom"

run() { # run PHASE
	env -i PATH="$work/bin:/usr/bin:/bin" STUB_DIR="$work" XDG_RUNTIME_DIR="$work/run" \
		LYONA_AUTORANDR_PICOM_GRACE="${GRACE:-30}" "$work/$1/$1switch.d/50-lyona-picom"
}
reset() {
	: >"$work/calls"
	rm -f "$work/run/lyona-autorandr-picom" "$work/startfails"
	echo "$1" >"$work/state"
}
state() { cat "$work/state"; }
calls() { tr '\n' ' ' <"$work/calls"; }

# Running Picom: stopped before, started after.
reset running
run pre
[[ $(state) == stopped ]] || fail "preswitch left Picom running"
[[ -e $work/run/lyona-autorandr-picom ]] || fail "preswitch left no marker"
run post
[[ $(state) == running ]] || fail "postswitch did not start Picom"
[[ ! -e $work/run/lyona-autorandr-picom ]] || fail "postswitch left the marker"
[[ $(calls) == "status stop start " ]] || fail "unexpected calls: $(calls)"

# Picom not running: it stays that way.
reset stopped
run pre
run post
[[ $(state) == stopped ]] || fail "a stopped Picom was started"
[[ $(calls) == "status " ]] || fail "unexpected calls with Picom stopped: $(calls)"

# autorandr skips postswitch when the change fails: the grace period starts it.
reset running
GRACE=1 run pre
[[ $(state) == stopped ]] || fail "preswitch left Picom running (grace case)"
sleep 3
[[ $(state) == running ]] || fail "Picom was not started after the grace period"
[[ ! -e $work/run/lyona-autorandr-picom ]] || fail "grace restart left the marker"

# ...and once postswitch ran, the grace period starts nothing again.
reset running
GRACE=1 run pre
run post
echo stopped >"$work/state"
sleep 3
[[ $(state) == stopped ]] || fail "the grace restart ran after postswitch"

# A failing start or a missing helper never fails the hook.
reset running
run pre
: >"$work/startfails"
run post 2>/dev/null || fail "hook failed when Picom would not start"
reset running
(
	export PATH=/usr/bin:/bin
	env -i PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$work/run" "$work/pre/preswitch.d/50-lyona-picom"
) || fail "hook failed without the helper"

echo "autorandr Picom hook: ok"
