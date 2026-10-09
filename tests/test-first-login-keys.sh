#!/usr/bin/env bash
set -euo pipefail

# #295: after an image install, the first keys (Super+/, Super+R, Super+F1) are
# on the installer's last screen and in one notification at the first login.
# The postinstall leaves a marker; the session's autostart shows the
# notification and removes the marker once it was shown, so later logins stay
# quiet and a login without notifications tries again.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

autostart=$repo/scripts/autostart.sh
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
{
	sed -n '/^notify_retry() {/,/^}$/p' "$autostart"
	awk '/^# The first keys, once, after an image install/ { f = 1 } f { print } f && /^fi$/ { exit }' "$autostart"
} >"$work/block.sh"
grep -q 'first-login-keys' "$work/block.sh" || fail 'the first-login block is missing from autostart.sh'
grep -q '^notify_retry() {' "$work/block.sh" || fail 'notify_retry is missing from autostart.sh'

mkdir -p "$work/bin"
cat >"$work/bin/notify-send" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$STUB_LOG"
exit "${STUB_STATUS:-0}"
STUB
chmod +x "$work/bin/notify-send"
state_home=$work/state
marker=$state_home/lyona/first-login-keys
run_block() { # [STATUS]
	rm -f "$work/log"
	# shellcheck disable=SC2016 # expanded by the inner shell
	env PATH="$work/bin:$PATH" STUB_LOG="$work/log" STUB_STATUS="${1:-0}" \
		DWM_AUTOSTART_NOTIFY_TRIES=2 DWM_AUTOSTART_NOTIFY_INTERVAL=0 \
		state_home="$state_home" sh -c '. "$1"; wait' sh "$work/block.sh"
}

# No marker (an install.sh install, or a later login): nothing is shown.
run_block
[[ ! -e $work/log ]] || fail "a notification was shown without the marker: $(cat "$work/log")"
# The notification could not be shown: the marker stays for the next login.
mkdir -p "$state_home/lyona"
: >"$marker"
run_block 1
[[ -e $marker ]] || fail 'the marker was removed though the notification was never shown'
[[ $(wc -l <"$work/log") == 2 ]] || fail "the notification was not retried as configured: $(cat "$work/log")"
# Shown: it names the three keys, and the marker is gone.
run_block 0
grep -Fq 'Welcome to lyona' "$work/log" || fail "no welcome notification: $(cat "$work/log")"
for key in 'Super+/' 'Super+R' 'Super+F1'; do
	grep -Fq "$key" "$work/log" || fail "the notification does not name $key"
done
grep -Fq -- '-u normal' "$work/log" || fail 'the welcome was not a normal notification'
[[ ! -e $marker ]] || fail 'the marker was kept after the notification was shown'
# The next login: quiet.
run_block 0
[[ ! -e $work/log ]] || fail 'the welcome was shown again'

# The postinstall leaves the marker, as the user, and its last screen names the keys.
grep -Fq '.local/state/lyona/first-login-keys' "$postinstall" || fail 'the postinstall leaves no first-login marker'
# shellcheck disable=SC2016 # the literal text in the postinstall
grep -Fq 'arch-chroot "$TARGET" runuser -u "$target_user"' <(grep -B2 'first-login-keys' "$postinstall") ||
	fail 'the first-login marker is not created as the user'
grep -Fq 'Super+/ shows every key, Super+R opens the app launcher, Super+F1 the Control Center.' "$postinstall" ||
	fail "the installer's last screen does not name the first keys"

printf 'First keys at first login (shown once, kept until shown, last screen): PASS\n'
