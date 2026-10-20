#!/usr/bin/env bash
set -euo pipefail

# The image postinstall gives the new system the medium's lyona boot splash:
# Plymouth, its hook before encrypt, and `splash` in a GRUB drop-in that
# install.sh's GRUB theme step picks up. A failure puts the hooks back, writes
# no drop-in and leaves a warning.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
sed -n '/^install_boot_splash() {$/,/^}$/p; /^splash_in_initramfs() {$/,/^}$/p' "$postinstall" >"$work/splash.sh"
grep -q '^install_boot_splash() {$' "$work/splash.sh" || fail 'install_boot_splash not found in the postinstall'
grep -q '^splash_in_initramfs() {$' "$work/splash.sh" || fail 'splash_in_initramfs not found in the postinstall'
grep -Eq '^[[:space:]]+install_boot_splash splash_in_initramfs \\$' "$postinstall" ||
	fail 'the boot splash functions are not exported for run_logged'
splash_line=$(grep -n 'run_logged "Setting up the boot splash..." install_boot_splash' "$postinstall" | cut -d: -f1)
install_line=$(grep -n 'run_logged "Running install.sh' "$postinstall" | cut -d: -f1)
[[ -n $splash_line && -n $install_line && $splash_line -lt $install_line ]] ||
	fail 'the boot splash must be set up before install.sh, whose GRUB theme step regenerates grub.cfg'

medium=$work/medium
mkdir -p "$medium/usr/share/plymouth/themes/lyona" "$medium/etc/plymouth"
printf '[Plymouth Theme]\n' >"$medium/usr/share/plymouth/themes/lyona/lyona.plymouth"
printf 'logo\n' >"$medium/usr/share/plymouth/themes/lyona/logo.png"
printf '[Daemon]\nTheme=lyona\n' >"$medium/etc/plymouth/plymouthd.conf"

# new_target HOOKS: a target root as archinstall leaves it, with one initramfs.
new_target() {
	rm -rf "$work/target"
	mkdir -p "$work/target/etc/default" "$work/target/boot"
	printf '# vim:set ft=sh\nMODULES=()\nHOOKS=(%s)\n' "$1" >"$work/target/etc/mkinitcpio.conf"
	printf 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"\n' >"$work/target/etc/default/grub"
	: >"$work/target/boot/initramfs-linux-cachyos.img"
}

# run_case [FAIL_ON] [INSTALLED]: runs the step against $work/target. FAIL_ON is
# the first word of an arch-chroot command that fails; INSTALLED=1 has the
# package installed already, so pacman builds nothing. An initramfs carries
# Plymouth when it was built with the hook in place ($work/target/built-splash).
# The stubs, TARGET and LYONA_MEDIUM_ROOT are used by the sourced functions.
# shellcheck disable=SC2034,SC2329
run_case() {
	: >"$work/warnings"
	: >"$work/commands"
	(
		STUB_FAIL=${1:-} STUB_INSTALLED=${2:-0} TARGET=$work/target LYONA_MEDIUM_ROOT=$medium
		build() {
			if grep -Eq '^HOOKS=\(.*\<plymouth\>' "$TARGET/etc/mkinitcpio.conf"; then
				: >"$TARGET/built-splash"
			else
				rm -f "$TARGET/built-splash"
			fi
		}
		arch-chroot() {
			shift
			[[ $1 == lsinitcpio ]] || printf '%s\n' "$*" >>"$work/commands"
			[[ $1 != "$STUB_FAIL" ]] || return 1
			case $1 in
			pacman)
				[[ $STUB_INSTALLED == 1 ]] || {
					: >"$TARGET/etc/plymouth/plymouthd.conf.pacnew"
					build
				}
				;;
			mkinitcpio) build ;;
			lsinitcpio)
				printf 'usr/bin/kmod\n'
				[[ ! -e $TARGET/built-splash ]] || printf 'usr/bin/plymouthd\n'
				;;
			esac
		}
		dwm_packages() { [[ "$1 $2" == 'arch boot-splash' ]] && printf '%s\n' plymouth; }
		note_warning() { printf '%s\n' "$1" >>"$work/warnings"; }
		# shellcheck source=/dev/null
		. "$work/splash.sh"
		install_boot_splash >/dev/null
	)
}

hooks() { sed -n 's/^HOOKS=//p' "$work/target/etc/mkinitcpio.conf"; }
dropin=$work/target/etc/default/grub.d/90-lyona-splash.cfg

# The archinstall layout, with encryption: one build, by the package.
new_target 'base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck'
run_case
[[ $(hooks) == '(base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont block encrypt filesystems fsck)' ]] ||
	fail "the plymouth hook is not after udev and before encrypt: $(hooks)"
grep -Fxq 'pacman -S --noconfirm --needed plymouth' "$work/commands" || fail 'plymouth was not installed'
! grep -Fxq 'mkinitcpio -P' "$work/commands" || fail 'the initramfs was built a second time'
! grep -q grub-mkconfig "$work/commands" || fail 'the step ran grub-mkconfig; install.sh regenerates grub.cfg (#246)'
# shellcheck disable=SC2016 # the literal line grub-mkconfig expands
grep -Fxq 'GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} splash"' "$dropin" ||
	fail 'the GRUB drop-in does not add splash'
cmp -s "$medium/etc/plymouth/plymouthd.conf" "$work/target/etc/plymouth/plymouthd.conf" ||
	fail 'plymouthd.conf was not copied'
[[ -f $work/target/usr/share/plymouth/themes/lyona/logo.png ]] || fail 'the theme was not copied'
grep -Fxq 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' "$work/target/etc/default/grub" ||
	fail 'the GRUB defaults file was edited'
[[ ! -e $work/target/etc/plymouth/plymouthd.conf.pacnew ]] || fail "the package's plymouthd.conf.pacnew was left"
[[ ! -s $work/warnings ]] || fail "a good run left a warning: $(cat "$work/warnings")"

# A Retry: the package is there and the initramfs has the splash. Nothing doubled.
run_case '' 1
[[ $(hooks) == *'udev plymouth autodetect'* && $(hooks) != *'plymouth plymouth'* ]] || fail "a second run doubled the hook: $(hooks)"
! grep -Fxq 'mkinitcpio -P' "$work/commands" || fail 'a second run rebuilt an initramfs that had the splash'
[[ $(grep -c splash "$dropin") == 2 ]] || fail 'a second run changed the drop-in'

# Installed already, but built before the hook: one build of its own.
new_target 'base udev autodetect block filesystems fsck'
run_case '' 1
[[ $(grep -cFx 'mkinitcpio -P' "$work/commands") == 1 ]] || fail 'an initramfs without the splash was not rebuilt once'
[[ -f $dropin && ! -s $work/warnings ]] || fail 'the rebuilt case did not finish'

# A systemd initramfs.
new_target 'base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck'
run_case
[[ $(hooks) == '(base systemd plymouth autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)' ]] ||
	fail "the plymouth hook is not after systemd: $(hooks)"

# expect_restored WHY: the hooks are as before, no drop-in, a warning.
expect_restored() {
	cmp -s "$work/mkinitcpio.before" "$work/target/etc/mkinitcpio.conf" || fail "$1 left the hook in: $(hooks)"
	[[ ! -e $dropin ]] || fail "$1 wrote the GRUB drop-in"
	[[ ! -e $work/target/built-splash ]] || fail "$1 left an initramfs with the splash"
	grep -Fq 'could not be set up' "$work/warnings" || fail "$1 left no warning"
}

new_target 'base udev autodetect block encrypt filesystems fsck'
cp "$work/target/etc/mkinitcpio.conf" "$work/mkinitcpio.before"
run_case pacman
expect_restored 'a failed package install'

new_target 'base udev autodetect block encrypt filesystems fsck'
cp "$work/target/etc/mkinitcpio.conf" "$work/mkinitcpio.before"
run_case mkinitcpio 1
expect_restored 'a failed initramfs build'

# The GRUB drop-in cannot be written (grub.d is a file): the step still ends in
# the warning, with the hooks and the initramfs as they were.
new_target 'base udev autodetect block encrypt filesystems fsck'
cp "$work/target/etc/mkinitcpio.conf" "$work/mkinitcpio.before"
: >"$work/target/etc/default/grub.d"
# Not in a condition: errexit stays on, as under run_logged.
run_case
cmp -s "$work/mkinitcpio.before" "$work/target/etc/mkinitcpio.conf" || fail "a failed drop-in left the hook in: $(hooks)"
[[ ! -e $work/target/built-splash ]] || fail 'a failed drop-in left an initramfs with the splash'
grep -Fq 'could not be set up' "$work/warnings" || fail 'a failed drop-in left no warning'

# The theme cannot be copied (its directory is a file): a warning, nothing installed.
new_target 'base udev autodetect block encrypt filesystems fsck'
cp "$work/target/etc/mkinitcpio.conf" "$work/mkinitcpio.before"
mkdir -p "$work/target/usr/share/plymouth/themes"
: >"$work/target/usr/share/plymouth/themes/lyona"
run_case
! grep -q '^pacman' "$work/commands" || fail 'plymouth was installed without its theme'
expect_restored 'a failed theme copy'

# No udev or systemd hook to follow: nothing installed.
new_target 'base autodetect block filesystems fsck'
cp "$work/target/etc/mkinitcpio.conf" "$work/mkinitcpio.before"
run_case
! grep -q '^pacman' "$work/commands" || fail 'plymouth was installed with nowhere to put its hook'
grep -Fq 'could not be set up' "$work/warnings" || fail 'no hook position left no warning'

# A medium without the theme: nothing done.
rm "$medium/usr/share/plymouth/themes/lyona/lyona.plymouth"
new_target 'base udev autodetect block filesystems fsck'
run_case
[[ ! -s $work/commands && ! -e $dropin ]] || fail "a medium without the theme still ran: $(cat "$work/commands")"
grep -Fq 'no lyona boot splash' "$work/warnings" || fail 'a medium without the theme left no warning'

printf 'Image install boot splash (hooks, one build, GRUB drop-in, Retry, failures): PASS\n'
