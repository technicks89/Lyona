#!/usr/bin/env bash
# shellcheck disable=SC2016 # the stand-ins' bodies expand when they run
set -euo pipefail

# dwm-settings-fingerprint (#483) against stand-ins for fprintd: the reader and
# the enrolled fingers from D-Bus, with no reader or no fprintd said plainly;
# the PAM state from lyona-fingerprint-pam; enroll streams fprintd's statuses
# and ends with a result; delete; finger names and uses are checked; set needs
# the trusted root helper, which a test run never finds.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace
helper=$repo/scripts/dwm-settings-fingerprint
bin=$work/bin
mkdir -p "$bin" "$work/root/etc/pam.d" "$work/root/usr/lib/security"
printf '#%%PAM-1.0\nauth include system-login\n' >"$work/root/etc/pam.d/lightdm"
printf '#%%PAM-1.0\nauth include system-auth\n' >"$work/root/etc/pam.d/sudo"
cat >"$work/pam-tool" <<STUB
#!/bin/sh
exec "$repo/scripts/lyona-fingerprint-pam" --root "$work/root" "\$@"
STUB

# busctl: "reader" says a device exists, "fingers" lists two, "nofprintd"
# makes every call fail.
cat >"$bin/busctl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/busctl-calls"
[ ! -e "$STUB_DIR/nofprintd" ] || exit 1
case "$*" in
*GetDevices*)
	if [ -e "$STUB_DIR/reader" ]; then echo '{"type":"ao","data":[["/net/reactivated/Fprint/Device/0"]]}'
	else echo '{"type":"ao","data":[[]]}'; fi ;;
*get-property*) printf '{"type":"s","data":"Test\\tReader"}\n' ;;
*ListEnrolledFingers*)
	[ -e "$STUB_DIR/fingers" ] || exit 1
	echo '{"type":"as","data":[["right-index-finger","left-thumb","not-a-finger"]]}' ;;
*) exit 1 ;;
esac
STUB
# dbus-send names the error busctl does not: NoEnrolledPrints with no fingers,
# another error with "listfails" (the call failed, the fingers unknown).
cat >"$bin/dbus-send" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_DIR/dbus-send-calls"
if [ -e "$STUB_DIR/nofprintd" ] || [ -e "$STUB_DIR/listfails" ]; then
	echo 'Error org.freedesktop.DBus.Error.NoReply: Did not receive a reply' >&2
	exit 1
fi
[ ! -e "$STUB_DIR/fingers" ] || exit 1
echo 'Error net.reactivated.Fprint.Error.NoEnrolledPrints: Failed to discover prints' >&2
exit 1
STUB
cat >"$bin/fprintd-enroll" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_DIR/enroll-args"
echo 'Using device /net/reactivated/Fprint/Device/0'
echo 'Enrolling right-thumb finger.'
echo 'Enroll result: enroll-stage-passed'
echo 'Enroll result: enroll-retry-scan'
echo 'Enroll result: enroll-stage-passed'
if [ -e "$STUB_DIR/enrollfails" ]; then echo 'Enroll result: enroll-disconnected'; exit 1; fi
echo 'Enroll result: enroll-completed'
STUB
cat >"$bin/fprintd-delete" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$STUB_DIR/delete-args"
STUB
cat >"$bin/pkexec" <<'STUB'
#!/bin/sh
echo pkexec >>"$STUB_DIR/pkexec-calls"
STUB
chmod +x "$bin"/* "$work/pam-tool"

run() {
	env -i PATH="$bin:/usr/bin:/bin" HOME="$work" STUB_DIR="$work" LYONA_NO_TRUSTED_HELPERS=1 \
		DWM_FINGERPRINT_PAM_TOOL="$work/pam-tool" "$helper" "$@"
}
expect_fail() { # MESSAGE ARGS...
	local message=$1
	shift
	if run "$@" >"$work/out" 2>"$work/err"; then fail "accepted: $*"; fi
	grep -Fq -- "$message" "$work/err" || fail "for $*: expected '$message', got: $(cat "$work/err")"
}

# A reader with two fingers; the name's tab is taken out; an unknown finger name
# is not passed on.
: >"$work/reader"
: >"$work/fingers"
run status >"$work/status"
diff -u - "$work/status" <<EOF
fingerprint-protocol	1
reader	available	TestReader
finger	right-index-finger
finger	left-thumb
module	missing	/usr/lib/security/pam_fprintd.so
use	lightdm	off	The password only
use	polkit	unavailable	/etc/pam.d/polkit-1 does not exist
use	sudo	off	The password only
complete	status
EOF
grep -Fq "ListEnrolledFingers s $(id -un)" "$work/busctl-calls" || fail "fingers were not asked for this user: $(cat "$work/busctl-calls")"

# --uses (#532): the PAM state alone, without a word to fprintd.
: >"$work/busctl-calls"
run status --uses >"$work/status"
diff -u - "$work/status" <<EOF
fingerprint-protocol	1
module	missing	/usr/lib/security/pam_fprintd.so
use	lightdm	off	The password only
use	polkit	unavailable	/etc/pam.d/polkit-1 does not exist
use	sudo	off	The password only
complete	status
EOF
[[ ! -s $work/busctl-calls ]] || fail "status --uses asked fprintd: $(cat "$work/busctl-calls")"
expect_fail 'status takes only --uses' status --everything

# A finger enrolled outside Settings (#535): the first status took the two
# there as known; one Settings does not know is reported until acknowledged.
known=$work/.local/state/lyona/fingerprint-fingers
[[ $(cat "$known") == $'right-index-finger\nleft-thumb' ]] || fail "known fingers: $(cat "$known" 2>/dev/null)"
[[ $(stat -c %a "$known") == 600 ]] || fail "the known fingers file is mode $(stat -c %a "$known")"
printf 'right-index-finger\n' >"$known"
[[ $(run status) == *$'\nfinger\tleft-thumb\nfinger-added\tleft-thumb\n'* ]] || fail "an outside finger was not reported: $(run status)"
[[ $(run acknowledge left-thumb) == $'fingerprint-result\tacknowledge\tleft-thumb' ]] || fail 'acknowledge'
[[ $(run status) != *finger-added* ]] || fail "an acknowledged finger was still reported: $(run status)"
expect_fail 'unknown finger' acknowledge nose
# Settings' own enrolments and deletions keep the list.
run enroll right-thumb >/dev/null
grep -Fqx right-thumb "$known" || fail "an enrolled finger was not recorded: $(cat "$known")"
run delete left-thumb >/dev/null
! grep -Fqx left-thumb "$known" || fail "a deleted finger stayed known: $(cat "$known")"
printf 'right-index-finger\nleft-thumb\n' >"$known"

# No fingers enrolled (fprintd answers with an error): no finger lines.
rm "$work/fingers"
# A list that failed keeps the known fingers.
: >"$work/listfails"
[[ $(run status) != *$'\nfinger\t'* ]] || fail 'fingers from a failed list'
[[ $(cat "$known") == $'right-index-finger\nleft-thumb' ]] || fail "a failed list changed the known fingers: $(cat "$known")"
rm "$work/listfails"
# None enrolled, as fprintd says: no finger lines, and the known fingers are
# forgotten, so enrolling them again outside Settings is reported.
[[ $(run status) != *$'\nfinger\t'* ]] || fail 'fingers without any enrolled'
grep -Fq "string:$(id -un)" "$work/dbus-send-calls" || fail "dbus-send: $(cat "$work/dbus-send-calls")"
[[ ! -s $known ]] || fail "deleted fingers stayed known: $(cat "$known")"
: >"$work/fingers"
out=$(run status)
[[ $out == *$'finger-added\tright-index-finger'* && $out == *$'finger-added\tleft-thumb'* ]] ||
	fail "fingers enrolled again outside Settings were not reported: $out"
rm "$work/fingers"
# No reader.
rm "$work/reader"
[[ $(run status) == *$'\nreader\tnone\tNo fingerprint reader was found\n'* ]] || fail "no reader: $(run status)"
# No fprintd.
: >"$work/nofprintd"
[[ $(run status) == *$'\nreader\tunavailable\tfprintd is not installed'* ]] || fail "no fprintd: $(run status)"
rm "$work/nofprintd"

# Enroll: each status, then the result.
run enroll right-thumb >"$work/enroll"
diff -u - "$work/enroll" <<'EOF'
enroll-status	enroll-stage-passed
enroll-status	enroll-retry-scan
enroll-status	enroll-stage-passed
enroll-status	enroll-completed
enroll-result	completed	enroll-completed
EOF
[[ $(cat "$work/enroll-args") == '-f right-thumb' ]] || fail "enroll args: $(cat "$work/enroll-args")"
: >"$work/enrollfails"
if run enroll right-thumb >"$work/enroll"; then fail 'a failed enroll succeeded'; fi
[[ $(tail -1 "$work/enroll") == $'enroll-result\tfailed\tenroll-disconnected' ]] || fail "failed enroll: $(cat "$work/enroll")"
rm "$work/enrollfails"

# Cancelled (Settings stops the helper): fprintd-enroll is stopped with it, so
# the reader is free, and another enroll runs at once.
cat >"$bin/fprintd-enroll" <<'STUB'
#!/bin/sh
# Its PID, written once it is waiting, is the test's cue to cancel. Stopped,
# it ends by TERM (from timeout) or by SIGPIPE (its pipe closes with the
# helper), whichever comes first; either stops it at once, as either would
# stop fprintd-enroll, whose claim on the reader ends with its connection.
echo 'Enroll result: enroll-stage-passed'
echo $$ >"$STUB_DIR/enroll-pid"
if [ -e "$STUB_DIR/enrollhangs" ]; then
	while :; do sleep 0.05; done
fi
echo 'Enroll result: enroll-completed'
STUB
: >"$work/enrollhangs"
rm -f "$work/enroll-pid"
# Started directly (env becomes the helper), so the signal reaches the helper.
env -i PATH="$bin:/usr/bin:/bin" HOME="$work" STUB_DIR="$work" "$helper" enroll left-thumb >"$work/enroll" &
enroll_job=$!
for _ in $(seq 200); do
	[[ -s $work/enroll-pid ]] && break
	sleep 0.05
done
[[ -s $work/enroll-pid ]] || fail 'fprintd-enroll did not start'
enroll_pid=$(cat "$work/enroll-pid")
kill -TERM "$enroll_job"
wait "$enroll_job" || :
for _ in $(seq 100); do
	kill -0 "$enroll_pid" 2>/dev/null || break
	sleep 0.05
done
# Within 5 s, where the old helper left it running until its 120 s timeout.
if kill -0 "$enroll_pid" 2>/dev/null; then fail 'fprintd-enroll outlived a cancelled enroll'; fi
rm "$work/enrollhangs"
run enroll left-thumb >"$work/enroll" || fail 'an enroll right after a cancelled one failed'
[[ $(tail -1 "$work/enroll") == $'enroll-result\tcompleted\tenroll-completed' ]] || fail "after cancel: $(cat "$work/enroll")"

# Delete.
[[ $(run delete left-thumb) == $'fingerprint-result\tdelete\tleft-thumb' ]] || fail 'delete'
[[ $(cat "$work/delete-args") == "$(id -un) -f left-thumb" ]] || fail "delete args: $(cat "$work/delete-args")"

# Bad input.
expect_fail 'unknown finger' enroll nose
expect_fail 'unknown finger' delete '-f'
expect_fail 'unknown use' set login on
expect_fail 'must be on, off or remove-external' set sudo maybe
# set needs the trusted root helper; a test run finds none, and pkexec is never
# reached.
expect_fail 'trusted fingerprint helper is unavailable' set sudo on
[[ ! -e $work/pkexec-calls ]] || fail 'pkexec was run without a trusted helper'

printf 'Settings fingerprint helper (#483): PASS\n'
