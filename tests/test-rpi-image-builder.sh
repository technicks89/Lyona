#!/usr/bin/env bash
# The builder's lines below are matched literally, not expanded here.
# shellcheck disable=SC2016
set -euo pipefail

# The Raspberry Pi image builder (ARM3-01), statically: its package list comes
# from the dependency map, it refuses a host it cannot build on before doing
# anything, and its root-filesystem check (--check-root) finds each personal
# thing an image must not carry. The build itself needs an aarch64 Arch Linux
# ARM host and root; docs/evidence/arm3-01-pi-image-builder.md records one.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

builder=$repo/scripts/build-lyona-rpi-image.sh
bash -n "$builder"
[[ -x $builder ]] || fail "scripts/build-lyona-rpi-image.sh is not executable."

# --- The package list ----------------------------------------------------------
# The base system is the map's rpi-image profile (AGENTS.md: no package lists
# outside the map): the Raspberry Pi kernel and firmware, no U-Boot or mainline
# kernel (A-5), and nothing on x86_64, where none of it exists.
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'mapfile -t base_packages < <(dwm_packages arch rpi-image)' "$builder" ||
	fail "the builder does not take its base packages from the rpi-image profile."
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq 'pacstrap -c -M -C "$repo_dir/archiso-aarch64/pacman.conf" "$root" "${base_packages[@]}"' "$builder" ||
	fail "the builder's pacstrap line changed: it must install the map's packages only, with the host's cache (-c) and Arch Linux ARM's mirrorlist (-M)."
if grep -nE '(pacstrap|pacman -S)[^#]*\b(linux-rpi|raspberrypi-bootloader|firmware-raspberrypi|linux-aarch64|uboot-raspberrypi)\b' "$builder"; then
	fail "the builder names a package the map should give it."
fi
rpi_profile() { # ARCH
	# shellcheck disable=SC2016 # expanded by the inner bash
	ARCH=$1 bash -c '. "$0"; dwm_packages arch rpi-image' "$repo/scripts/dwm-packages.sh" | sort
}
aarch64_packages=$(rpi_profile aarch64)
for package in base linux-rpi raspberrypi-bootloader firmware-raspberrypi archlinuxarm-keyring sudo gum zram-generator; do
	grep -Fqx "$package" <<<"$aarch64_packages" || fail "the rpi-image profile lacks $package on aarch64."
done
for package in linux-aarch64 uboot-raspberrypi linux-rpi-16k; do
	if grep -Fqx "$package" <<<"$aarch64_packages"; then
		fail "the rpi-image profile has $package; A-5 chose one image on linux-rpi."
	fi
done
[[ -z $(rpi_profile x86_64) ]] || fail "the rpi-image profile resolves packages on x86_64."

# --- The install ---------------------------------------------------------------
# install.sh runs as the build user, for the full profile (the one that sets up
# LightDM, as on the install medium), without the
# GRUB theme (a Pi boots through its firmware). Its passwordless sudo is
# removed before Topgrade is built and before the user is.
# shellcheck disable=SC2016 # the literal shell source text is what we look for
grep -Fq './install.sh --non-interactive --profile full --skip-topgrade --skip-yay --skip-grub-theme' "$builder" ||
	fail "the builder does not run install.sh for the full profile without the GRUB theme."
# The stamp records that same profile, for the first boot to record for the
# account (found on the Pi 4: the account had none).
grep -Fxq 'LYONA_INSTALL_PROFILE=full' "$builder" ||
	fail "the image's stamp does not record the full profile install.sh runs with."
# Empty when the line is missing, so the check below names the step.
line_of() { grep -nF -- "$1" "$builder" | head -n 1 | cut -d: -f1 || :; }
sudo_added=$(line_of 'printf '"'"'%s ALL=(ALL) NOPASSWD: ALL\n'"'"' "$build_user" >"$build_sudoers"')
sudo_removed=$(line_of 'rm -f -- "$build_sudoers"')
install_run=$(line_of './install.sh --non-interactive')
yay_built=$(line_of 'build_aur_package install-yay yay')
topgrade_built=$(line_of 'build_aur_package install-topgrade topgrade')
user_removed=$(line_of 'arch-chroot "$root" userdel -r "$build_user"')
root_checked=$(line_of 'check_root "$root" || {')
image_made=$(line_of 'mkfs.ext4 -q -L lyona-root -d "$root"')
for position in sudo_added sudo_removed install_run yay_built topgrade_built user_removed root_checked image_made; do
	[[ -n ${!position} ]] || fail "the builder's $position step is missing."
done
((yay_built < sudo_added && sudo_added < install_run && install_run < sudo_removed)) ||
	fail "yay must be built before the build user's sudo exists, and install.sh must run only while it does."
((sudo_removed < topgrade_built)) || fail "Topgrade must be built after the build user's sudo is removed."
((topgrade_built < user_removed && user_removed < root_checked && root_checked < image_made)) ||
	fail "the build user must be removed, and the root checked, before the image is made."

# --- Hosts it cannot build on --------------------------------------------------
# Each refusal comes before anything is made: no work directory is left.
stub_bin=$work/stub-bin
mkdir -p "$stub_bin"
refusal_case() { # HOST-ARCH WANT-MESSAGE
	local out status=0
	printf '#!/bin/sh\necho %s\n' "$1" >"$stub_bin/uname"
	chmod +x "$stub_bin/uname"
	out=$(env PATH="$stub_bin:$PATH" TMPDIR="$work/tmp" "$builder" --output "$work/out" 2>&1) || status=$?
	((status == 1)) || fail "a $1 host: the builder exited $status, not 1: $out"
	grep -Fq -- "$2" <<<"$out" || fail "a $1 host: expected '$2', got: $out"
	[[ ! -e $work/out ]] || fail "a $1 host: the builder made its output directory."
}
mkdir -p "$work/tmp"
refusal_case x86_64 'the Raspberry Pi image builds on an aarch64 host; this one is x86_64.'
# On an aarch64 host the next refusal is root's; never run as root here, where
# the builder would really build.
if ((EUID != 0)); then
	refusal_case aarch64 'the image is built as root (pacstrap and chroot).'
fi
out=$("$builder" --version nope 2>&1) && fail "a bad --version was accepted."
grep -Fq 'version must look like MAJOR.MINOR' <<<"$out" || fail "a bad --version: $out"
out=$(env LYONA_RPI_BOOT_MIB=64 "$builder" 2>&1) && fail "a 64 MiB boot partition was accepted."
grep -Fq 'LYONA_RPI_BOOT_MIB must be a whole number of MiB, 128 or more' <<<"$out" ||
	fail "LYONA_RPI_BOOT_MIB=64: $out"

# --- --check-root --------------------------------------------------------------
# A root filesystem as the builder leaves it, then one fault at a time: a
# personal thing left, or a part of the install missing.
make_root() { # DIR
	local root=$1
	mkdir -p "$root"/{etc/sudoers.d,etc/pacman.d,etc/ssh,usr/local/bin,usr/local/src/lyona,home,root} \
		"$root"/{boot,var/cache/pacman/pkg,var/lib/systemd,var/lib/dbus,var/tmp}
	printf '%s\n' 'root:x:0:0::/root:/bin/bash' 'lightdm:x:620:620::/var/lib/lightdm:/usr/bin/nologin' \
		'nobody:x:65534:65534:Kernel Overflow User:/:/usr/bin/nologin' >"$root/etc/passwd"
	printf '%s\n' 'root:x:0:root' 'wheel:x:998:' 'lightdm:x:620:' >"$root/etc/group"
	printf '%s\n' 'root:!*:14871::::::' 'lightdm:!*:20000::::::' >"$root/etc/shadow"
	: >"$root/etc/gshadow"
	printf 'uninitialized\n' >"$root/etc/machine-id"
	printf 'LYONA_VERSION=0\n' >"$root/etc/lyona-release"
	printf '%s\n' LYONA_ISO_KIND=rpi-aarch64 LYONA_INSTALL_PROFILE=full >"$root/etc/lyona-iso-release"
	printf '#!/bin/sh\n' >"$root/usr/local/bin/dwm"
	printf '#!/bin/sh\n' >"$root/usr/local/src/lyona/install.sh"
	chmod +x "$root/usr/local/bin/dwm" "$root/usr/local/src/lyona/install.sh"
	: >"$root/boot/kernel8.img"
	printf 'root=PARTUUID=1a2b3c4d-02 rw rootwait console=serial0,115200 console=tty1 fsck.repair=yes quiet loglevel=3\n' \
		>"$root/boot/cmdline.txt"
	printf '%%wheel ALL=(ALL:ALL) ALL\n' >"$root/etc/sudoers.d/10-wheel"
	mkdir -p "$root/etc/systemd/system/multi-user.target.wants"
	ln -s /usr/lib/systemd/system/NetworkManager.service \
		"$root/etc/systemd/system/multi-user.target.wants/NetworkManager.service"
	ln -s /usr/lib/systemd/system/lightdm.service "$root/etc/systemd/system/display-manager.service"
	ln -s /usr/lib/systemd/system/graphical.target "$root/etc/systemd/system/default.target"
	mkdir -p "$root/usr/local/libexec/lyona" "$root/usr/local/lib/lyona" "$root/usr/bin" \
		"$root/etc/systemd/system/lightdm.service.d"
	printf '#!/bin/sh\n' >"$root/usr/local/libexec/lyona/lyona-firstboot"
	printf '#!/bin/sh\n' >"$root/usr/bin/gum"
	chmod +x "$root/usr/local/libexec/lyona/lyona-firstboot" "$root/usr/bin/gum"
	ln -s /etc/systemd/system/lyona-firstboot.service \
		"$root/etc/systemd/system/multi-user.target.wants/lyona-firstboot.service"
	cp "$repo/rpi/lightdm-after-firstboot.conf" "$root/etc/systemd/system/lightdm.service.d/lyona-firstboot.conf"
	printf 'lyona_console_colors() { :; }\n' >"$root/usr/local/lib/lyona/firstboot-console.sh"
	printf 'LANG=en_US.UTF-8\n' >"$root/etc/locale.conf"
	ln -s /dev/null "$root/etc/systemd/system/systemd-firstboot.service"
	mkdir -p "$root/etc/systemd/system-preset"
	printf '%s\n' '# comment' 'enable NetworkManager.service' 'enable lightdm.service' \
		'enable lyona-firstboot.service' 'disable *' >"$root/etc/systemd/system-preset/10-lyona-image.preset"
}
check() { "$builder" --check-root "$1" 2>&1; }

make_root "$work/clean"
out=$(check "$work/clean") || fail "a clean root failed the check: $out"
grep -Fq 'nothing personal is left, and lyona is installed.' <<<"$out" || fail "a clean root: $out"
# An empty machine-id passes too: systemd treats it as the first boot as well.
: >"$work/clean/etc/machine-id"
out=$(check "$work/clean") || fail "an empty machine-id failed the check: $out"

personal_case() { # WANT-MESSAGE COMMAND... (run in the root's directory)
	local want=$1 dir out
	shift
	dir=$work/case-$((++case_number))
	make_root "$dir"
	(cd "$dir" && "$@")
	if out=$(check "$dir"); then
		fail "the check passed with: $want"
	fi
	grep -Fq -- "$want" <<<"$out" || fail "expected '$want', got: $out"
}
case_number=0
personal_case 'a user is left in /etc/passwd: pi' \
	sh -c 'echo "pi:x:1000:1000::/home/pi:/bin/bash" >>etc/passwd'
personal_case 'the build user is left in /etc/passwd' \
	sh -c 'echo "lyona-image-build:x:59000:59000::/var/empty:/bin/bash" >>etc/passwd'
personal_case 'the build user is left in /etc/passwd-' \
	sh -c 'echo "lyona-image-build:x:1000:1000::/home/lyona-image-build:/bin/bash" >etc/passwd-'
personal_case 'the build user is left in /etc/subuid-' \
	sh -c 'echo "lyona-image-build:524288:65536" >etc/subuid-'
personal_case 'the build user is left in /etc/shadow' \
	sh -c 'echo "lyona-image-build:!:20000::::::" >>etc/shadow'
personal_case 'the build user is still a group member in /etc/group' \
	sh -c 'echo "video:x:985:lyona-image-build" >>etc/group'
personal_case '/home is not empty' mkdir home/lyona-image-build
personal_case 'root has a password' \
	sh -c 'echo "root:\$6\$salt\$hash:20000::::::" >etc/shadow'
personal_case 'a NOPASSWD rule is left in /etc/sudoers.d' \
	sh -c 'echo "lyona-image-build ALL=(ALL) NOPASSWD: ALL" >etc/sudoers.d/90-lyona-image-build'
personal_case '/etc/machine-id is set' \
	sh -c 'echo f252267e620b4086ad1588a8aed41577 >etc/machine-id'
personal_case '/var/lib/dbus/machine-id is set' \
	sh -c 'echo f252267e620b4086ad1588a8aed41577 >var/lib/dbus/machine-id'
personal_case 'the systemd random seed is left' touch var/lib/systemd/random-seed
personal_case 'an SSH host key is left: /etc/ssh/ssh_host_ed25519_key' touch etc/ssh/ssh_host_ed25519_key
personal_case 'the pacman keyring is left in /etc/pacman.d/gnupg' \
	sh -c 'mkdir -p etc/pacman.d/gnupg/private-keys-v1.d && touch etc/pacman.d/gnupg/secring.gpg'
personal_case 'the package cache is not empty' touch var/cache/pacman/pkg/dwm-6.5-1-aarch64.pkg.tar.zst
personal_case '/root/.bash_history is left' touch root/.bash_history
personal_case "the build's PackageKit hook mask is left" \
	sh -c 'mkdir -p etc/pacman.d/hooks && ln -s /dev/null etc/pacman.d/hooks/90-packagekit-refresh.hook'
personal_case '/var/tmp/lyona-yay is left' mkdir var/tmp/lyona-yay
personal_case 'no /etc/lyona-release: lyona is not installed' rm etc/lyona-release
personal_case 'no /usr/local/bin/dwm' rm usr/local/bin/dwm
personal_case 'no lyona source at /usr/local/src/lyona' rm usr/local/src/lyona/install.sh
personal_case 'no /etc/lyona-iso-release' rm etc/lyona-iso-release
personal_case '/etc/lyona-iso-release records no install profile for the first boot' \
	sed -i '/^LYONA_INSTALL_PROFILE=/d' etc/lyona-iso-release
personal_case 'no /boot/kernel8.img (linux-rpi)' rm boot/kernel8.img
personal_case '/boot/cmdline.txt does not name the root partition by PARTUUID' \
	sh -c 'echo "root=/dev/mmcblk0p2 rw rootwait" >boot/cmdline.txt'
personal_case 'NetworkManager is not enabled' \
	rm etc/systemd/system/multi-user.target.wants/NetworkManager.service
personal_case 'LightDM is not the display manager' \
	ln -sfn /usr/lib/systemd/system/gdm.service etc/systemd/system/display-manager.service
personal_case 'the default target is not graphical.target' \
	ln -sfn /usr/lib/systemd/system/multi-user.target etc/systemd/system/default.target
personal_case 'no first-boot wizard' rm usr/local/libexec/lyona/lyona-firstboot
personal_case 'the first boot is not enabled' \
	rm etc/systemd/system/multi-user.target.wants/lyona-firstboot.service
personal_case 'LightDM does not wait for the first boot' \
	rm etc/systemd/system/lightdm.service.d/lyona-firstboot.conf
personal_case 'the first boot is marked done' \
	sh -c 'mkdir -p var/lib/lyona && touch var/lib/lyona/firstboot-done'
personal_case 'no gum for the first-boot wizard' rm usr/bin/gum
personal_case 'systemd-firstboot is not masked' rm etc/systemd/system/systemd-firstboot.service
personal_case "no preset of the image's own" rm etc/systemd/system-preset/10-lyona-image.preset
personal_case "the image's preset does not enable lightdm.service" \
	sed -i '/lightdm/d' etc/systemd/system-preset/10-lyona-image.preset
personal_case "the image's preset does not end with disable *" \
	sed -i '/^disable/d' etc/systemd/system-preset/10-lyona-image.preset
personal_case '/boot/cmdline.txt does not boot quiet' sed -i 's/ quiet loglevel=3//' boot/cmdline.txt
personal_case 'no first-boot console palette' rm usr/local/lib/lyona/firstboot-console.sh
personal_case 'the locale is not en_US.UTF-8' sh -c 'echo LANG=C >etc/locale.conf'
out=$(check "$work/nowhere") && fail "a missing directory passed the check."
grep -Fq 'not a root filesystem' <<<"$out" || fail "a missing directory: $out"

printf 'Raspberry Pi image builder: PASS (%s fault cases)\n' "$case_number"
