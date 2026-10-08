#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 16: Flatpak cannot install Gear Lever for the user inside the
# image installer's chroot, so install.sh leaves a marker there, and the first
# login's session startup installs it in the background, keeping the marker
# until it succeeds. Found installing the image in a VM.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

autostart=$repo/scripts/autostart.sh
{
	sed -n '/^start_detached() {$/,/^}$/p' "$autostart"
	awk '/^# Gear Lever, when the image installer could not set it up/ { f = 1 } f { print } f && /^fi$/ { exit }' "$autostart"
} >"$work/block.sh"
grep -q 'pending-gearlever' "$work/block.sh" || fail 'the Gear Lever block is missing from autostart.sh'

cat >"$work/bin/install-gearlever" <<'STUB'
#!/bin/sh
printf 'ran\n' >>"$STUB_LOG"
exit "${STUB_STATUS:-0}"
STUB
chmod +x "$work/bin/install-gearlever"
state_home=$work/state
marker=$state_home/lyona/pending-gearlever
run_block() { # [STATUS]
	rm -f "$work/log"
	# shellcheck disable=SC2016 # literal, or expanded by the inner shell
	env PATH="$work/bin:$PATH" STUB_LOG="$work/log" STUB_STATUS="${1:-0}" DWM_AUTOSTART_NO_SETSID=1 \
		state_home="$state_home" sh -c '. "$1"; wait' sh "$work/block.sh"
}

# No marker: nothing runs.
run_block
[[ ! -e $work/log ]] || fail 'Gear Lever was installed without a pending marker'
# A failure keeps the marker for the next login.
mkdir -p "$state_home/lyona"
: >"$marker"
run_block 1
[[ $(cat "$work/log") == ran && -e $marker ]] || fail 'a failed install did not keep the marker'
# Success removes it.
run_block 0
[[ $(cat "$work/log") == ran && ! -e $marker ]] || fail 'a successful install did not remove the marker'

# install.sh leaves the marker inside a chroot rather than failing there.
gear=$(awk '/info "Setting up Gear Lever for AppImage management..."/ { f = 1 } f { print } f && /^\tfi$/ { exit }' "$repo/install.sh")
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq 'if [[ ${LYONA_SOURCE:-} == iso ]] || systemd-detect-virt --chroot >/dev/null 2>&1; then' <<<"$gear" ||
	fail 'install.sh does not leave Gear Lever for the first login in an image install'
# shellcheck disable=SC2016 # literal, or expanded by the inner shell
grep -Fq '"$gearlever_state/pending-gearlever"' <<<"$gear" || fail 'install.sh leaves no marker'

# #260: Gear Lever is opt-in. The marker is only left with --with-gearlever, and
# without it a marker an earlier install left is cleared, so nothing installs
# Gear Lever at the first login unasked.
step=$(sed -n '/^	step_timer "Default apps and AppImages"$/,/^else$/p' "$repo/install.sh")
grep -Fqx '	if install_gearlever_profile; then' <<<"$step" ||
	fail 'install.sh sets Gear Lever up without --with-gearlever'
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fqx '	elif [[ -e $gearlever_state/pending-gearlever ]]; then' <<<"$step" ||
	fail 'install.sh does not clear a pending Gear Lever marker'
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq 'rm -f -- "$gearlever_state/pending-gearlever"' <<<"$step" ||
	fail 'install.sh does not remove the pending Gear Lever marker'

printf 'Gear Lever at first login: PASS\n'
