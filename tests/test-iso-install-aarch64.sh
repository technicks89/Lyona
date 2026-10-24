#!/usr/bin/env bash
# The CODE strings below are expanded by the inner shell, not here.
# shellcheck disable=SC2016
set -euo pipefail

# The image installer on aarch64 (ARM2-03), the experimental Arch Linux ARM
# medium. One wizard and one postinstall for both architectures; on aarch64:
# - no CachyOS (x86_64 only): neither the wizard nor the postinstall runs the
#   helper, or warns that it failed;
# - no NVIDIA question (its driver profiles are x86_64 only);
# - archinstall's configuration has no [multilib], keeps kernels ["linux"],
#   which Arch Linux ARM's linux-aarch64 provides, and installs
#   archlinuxarm-keyring, so the new system trusts Arch Linux ARM's packages;
# - the new system gets the hook that keeps /boot/vmlinuz-linux a copy of
#   linux-aarch64's /boot/Image, which GRUB pairs with initramfs-linux.img;
# - a firmware boot entry for GRUB's removable path, replacing an earlier one;
# - the kernel console on the display (console=tty0), not only the firmware's
#   serial port, and Plymouth drawing despite that port, through a GRUB
#   drop-in.
# x86_64 keeps all of it as before.
#
# The wizard is loaded as a library, the postinstall's functions are taken from
# it, and every command that would touch the machine is a stub.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

root=$repo/archiso/airootfs/root
wizard=$root/lyona-install.sh
postinstall=$root/lyona-postinstall.sh

cat >"$work/bin/gum" <<'EOF'
#!/bin/bash
case $1 in
choose | filter | input | confirm)
	printf 'gum %s\n' "$*" >>"$STUB_DIR/gum.log"
	exit 99
	;;
spin)
	while (($# > 0)) && [[ $1 != -- ]]; do shift; done
	shift
	exec "$@"
	;;
style) printf '%s\n' "${@: -1}" ;;
*) exit 0 ;;
esac
EOF
# An NVIDIA card: on x86_64 the wizard would ask about its driver.
# lspci's two forms: the description, and the IDs nvidia_gpu_branch reads.
cat >"$work/bin/lspci" <<'EOF'
#!/bin/sh
case "$*" in
"-n -mm -d 10de::0300") printf '%s\n' '01:00.0 "0300" "10de" "2786" -ra1 "10de" "16fa"' ;;
-n*) ;;
*) printf '%s\n' '01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce RTX 4070] [10de:2786] (rev a1)' ;;
esac
EOF
cat >"$work/bin/blockdev" <<'EOF'
#!/bin/sh
echo 34359738368
EOF
# The CachyOS helper must not run on aarch64.
cat >"$work/bin/lyona-cachyos" <<'EOF'
#!/bin/sh
printf 'lyona-cachyos %s\n' "$*" >>"$STUB_DIR/calls.log"
EOF
for cmd in clear tput sleep; do
	printf '#!/bin/sh\nexit 0\n' >"$work/bin/$cmd"
done
chmod +x "$work/bin/"*

# wizard ARCH CODE: CODE with the wizard loaded as a library on ARCH.
wizard() {
	: >"$work/gum.log"
	: >"$work/calls.log"
	env PATH="$work/bin:$PATH" STUB_DIR="$work" LYONA_INSTALL_LIB=1 ARCH="$1" \
		LYONA_UI_LIB="$root/lyona-ui.sh" LYONA_NVIDIA_LIB="$root/lyona-nvidia.sh" \
		LYONA_WIFI_LIB="$root/lyona-wifi.sh" LYONA_LOGO_PATH=/nonexistent \
		LOG_FILE="$work/install.log" \
		bash -c '. "$1"; CACHYOS_HELPER=$2; eval "$3"' bash "$wizard" "$work/bin/lyona-cachyos" "$2" \
		>"$work/out.log" 2>&1
}

# --- The wizard -------------------------------------------------------------

wizard aarch64 'setup_cachyos_repositories; printf "PACKAGES=[%s]\n" "$CACHYOS_PACKAGES"' ||
	fail "the CachyOS step failed on aarch64: $(cat "$work/out.log")"
grep -Fxq 'PACKAGES=[]' "$work/out.log" || fail "aarch64 got CachyOS packages: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "the CachyOS helper ran on aarch64: $(cat "$work/calls.log")"
grep -Fq 'CachyOS is x86_64 only' "$work/out.log" || fail 'skipping CachyOS on aarch64 was not said'
! grep -Fq 'setup failed' "$work/out.log" || fail 'skipping CachyOS on aarch64 was reported as a failure'
wizard x86_64 'setup_cachyos_repositories; printf "PACKAGES=[%s]\n" "$CACHYOS_PACKAGES"' ||
	fail "the CachyOS step failed on x86_64: $(cat "$work/out.log")"
grep -Fxq 'lyona-cachyos add-repos --no-upgrade --baseline' "$work/calls.log" ||
	fail 'the CachyOS helper no longer runs on x86_64'

wizard aarch64 'ask_nvidia; printf "OPT_IN=%s DETECTED=%s\n" "$NVIDIA_OPT_IN" "$NVIDIA_DETECTED"' ||
	fail "the NVIDIA step failed on aarch64: $(cat "$work/out.log")"
grep -Fxq 'OPT_IN=0 DETECTED=0' "$work/out.log" || fail "aarch64 took up the NVIDIA card: $(cat "$work/out.log")"
[[ ! -s $work/gum.log ]] || fail "the NVIDIA question was asked on aarch64: $(cat "$work/gum.log")"
# On x86_64 the same card is asked about (the stubbed answer cancels).
wizard x86_64 'ask_nvidia' || true
grep -Fq 'NVIDIA GPU detected' "$work/gum.log" || fail 'the NVIDIA question is no longer asked on x86_64'

configure='detect_firmware() { :; }; FIRMWARE=uefi DISK=/dev/vda FILESYSTEM=ext4 ENCRYPT=0
	HOSTNAME=host KEYMAP=us TIMEZONE=UTC USERNAME=user PASSWORD=pass
	generate_configs; cp "$CONFIG_JSON" "$STUB_DIR/config.json"'
wizard aarch64 "$configure" || fail "the configuration failed on aarch64: $(cat "$work/out.log")"
python3 -c 'import json, sys
c = json.load(open(sys.argv[1]))
repos, kernels = c["mirror_config"]["optional_repositories"], c["kernels"]
if repos != []:
    sys.exit("aarch64 optional repositories: %r" % repos)
if kernels != ["linux"]:
    sys.exit("aarch64 kernels: %r" % kernels)
if c["packages"] != ["archlinuxarm-keyring"]:
    sys.exit("aarch64 packages: %r" % c["packages"])' \
	"$work/config.json" || fail 'the aarch64 archinstall configuration is wrong'
wizard x86_64 "$configure" || fail "the configuration failed on x86_64: $(cat "$work/out.log")"
python3 -c 'import json, sys
c = json.load(open(sys.argv[1]))
repos = c["mirror_config"]["optional_repositories"]
if repos != ["multilib"]:
    sys.exit("x86_64 optional repositories: %r" % repos)
if "archlinuxarm-keyring" in c["packages"]:
    sys.exit("x86_64 packages: %r" % c["packages"])' \
	"$work/config.json" || fail 'the x86_64 archinstall configuration lost [multilib]'

# --- The postinstall --------------------------------------------------------

# The postinstall's functions, without the script around them.
for function in note_warning add_cachyos_repositories install_cachyos_kernel drop_fallback_initramfs \
	keep_vmlinuz_linux add_firmware_boot_entry use_display_console; do
	sed -n "/^$function() {\$/,/^}\$/p" "$postinstall"
done >"$work/postinstall-functions.sh"
for function in add_cachyos_repositories keep_vmlinuz_linux add_firmware_boot_entry use_display_console; do
	grep -q "^$function() {\$" "$work/postinstall-functions.sh" || fail "the postinstall has no $function"
done
# post ARCH CODE: CODE with those functions on ARCH, TARGET a fake new system.
post() {
	: >"$work/calls.log"
	env PATH="$work/bin:$PATH" STUB_DIR="$work" MACHINE_ARCH="$1" TARGET="$work/target" \
		REPO_SRC="$repo" CACHYOS_HELPER=/usr/local/bin/lyona-cachyos \
		CACHYOS_MARKER="$work/cachyos-ready" CACHYOS_KERNEL=linux-cachyos \
		LYONA_WARNINGS="$work/warnings" LYONA_SYSFS="$work/sys" \
		bash -c '. "$1"; eval "$2"' bash "$work/postinstall-functions.sh" "$2" >"$work/out.log" 2>&1
}
cat >"$work/bin/arch-chroot" <<'EOF'
#!/bin/sh
printf 'arch-chroot %s\n' "$*" >>"$STUB_DIR/calls.log"
EOF
chmod +x "$work/bin/arch-chroot"
mkdir -p "$work/target/boot" "$work/target/etc/mkinitcpio.d"

post aarch64 'add_cachyos_repositories' || fail "the CachyOS step failed on aarch64: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "the postinstall ran CachyOS on aarch64: $(cat "$work/calls.log")"
[[ ! -e $work/target/usr/local/bin/lyona-cachyos ]] || fail 'the CachyOS helper was installed on aarch64'
[[ ! -s $work/warnings ]] || fail "skipping CachyOS on aarch64 left a warning: $(cat "$work/warnings")"
post aarch64 'install_cachyos_kernel' || fail "the kernel step failed on aarch64: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "the kernel step ran CachyOS on aarch64: $(cat "$work/calls.log")"
grep -Fq 'keeping the stock kernel' "$work/out.log" || fail 'keeping the stock kernel on aarch64 was not said'

# The kernel copy GRUB boots, and the hook that keeps it current.
hook=etc/pacman.d/hooks/lyona-vmlinuz-linux.hook
printf 'kernel 1\n' >"$work/target/boot/Image"
post aarch64 'keep_vmlinuz_linux' || fail "the kernel copy failed: $(cat "$work/out.log")"
cmp -s "$repo/archiso-aarch64/airootfs/$hook" "$work/target/$hook" || fail 'the new system did not get the kernel-name hook'
cmp -s "$work/target/boot/Image" "$work/target/boot/vmlinuz-linux" || fail '/boot/vmlinuz-linux is not a copy of /boot/Image'
# A stale copy is replaced; a current one is left alone.
printf 'kernel 2\n' >"$work/target/boot/Image"
post aarch64 'keep_vmlinuz_linux' || fail "replacing a stale kernel copy failed: $(cat "$work/out.log")"
grep -Fxq 'kernel 2' "$work/target/boot/vmlinuz-linux" || fail 'a stale /boot/vmlinuz-linux was kept'
post aarch64 'keep_vmlinuz_linux' || fail "a current kernel copy failed: $(cat "$work/out.log")"
! grep -Fq 'Copied' "$work/out.log" || fail 'a current /boot/vmlinuz-linux was copied again'
# Nothing to boot is a failure.
rm -f "$work/target/boot/Image" "$work/target/boot/vmlinuz-linux"
if post aarch64 'keep_vmlinuz_linux'; then
	fail 'a new system with no kernel passed'
fi
grep -Fq 'no /boot/vmlinuz-linux to boot' "$work/out.log" || fail "a missing kernel was not said: $(cat "$work/out.log")"

# The firmware boot entry.
mkdir -p "$work/target/boot/EFI/BOOT" "$work/sys/firmware/efi/efivars" "$work/sys/class/block/vda1"
: >"$work/target/boot/EFI/BOOT/BOOTAA64.EFI"
printf '1\n' >"$work/sys/class/block/vda1/partition"
cat >"$work/bin/findmnt" <<'EOF'
#!/bin/sh
[ "$*" = "-n -o SOURCE --target $TARGET/boot" ] || exit 1
echo /dev/vda1
EOF
cat >"$work/bin/lsblk" <<'EOF'
#!/bin/sh
[ "$*" = "-n -d -o PKNAME /dev/vda1" ] || exit 1
echo vda
EOF
# An earlier run's entry (Boot0003) beside the firmware's own; tabs as
# efibootmgr prints them.
cat >"$work/bin/efibootmgr" <<'EOF'
#!/bin/sh
printf 'efibootmgr %s\n' "$*" >>"$STUB_DIR/calls.log"
[ $# -eq 0 ] || exit 0
printf 'BootCurrent: 0001\nBootOrder: 0003,0001,0000\n'
printf 'Boot0000* UiApp\tFvVol(64074afe)/FvFile(462caa21)\n'
printf 'Boot0001* UEFI Misc Device\tPciRoot(0x0)/Pci(0x1,0x0)\n'
printf 'Boot0003* lyona\tHD(1,GPT,0b8e,0x800,0x100000)/\\EFI\\BOOT\\BOOTAA64.EFI\n'
printf 'Boot0004* lyona-old\tHD(1,GPT,0b8e,0x800,0x100000)/\\EFI\\BOOT\\BOOTAA64.EFI\n'
EOF
chmod +x "$work/bin/findmnt" "$work/bin/lsblk" "$work/bin/efibootmgr"
post aarch64 'add_firmware_boot_entry' || fail "the firmware boot entry failed: $(cat "$work/out.log")"
expected=$(printf '%s\n' 'efibootmgr ' 'efibootmgr -q -b 0003 -B' \
	'efibootmgr -q --create --disk /dev/vda --part 1 --label lyona --loader \EFI\BOOT\BOOTAA64.EFI')
[[ $(cat "$work/calls.log") == "$expected" ]] ||
	fail "the firmware boot entry was made with: $(cat "$work/calls.log")"
# Not booted with UEFI: nothing to add, and no failure.
rm -rf "$work/sys/firmware/efi"
post aarch64 'add_firmware_boot_entry' || fail "a non-UEFI boot failed the firmware step: $(cat "$work/out.log")"
[[ ! -s $work/calls.log ]] || fail "efibootmgr ran without UEFI: $(cat "$work/calls.log")"
# No GRUB at the removable path is a failure.
mkdir -p "$work/sys/firmware/efi/efivars"
rm -f "$work/target/boot/EFI/BOOT/BOOTAA64.EFI"
if post aarch64 'add_firmware_boot_entry'; then
	fail 'a firmware boot entry was added for a missing GRUB'
fi

# The console on the display.
post aarch64 'use_display_console' || fail "the console step failed: $(cat "$work/out.log")"
expected='GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE_LINUX_DEFAULT} console=tty0 plymouth.ignore-serial-consoles"'
[[ $(grep -v '^#' "$work/target/etc/default/grub.d/90-lyona-console.cfg") == "$expected" ]] ||
	fail "the console drop-in is: $(cat "$work/target/etc/default/grub.d/90-lyona-console.cfg")"
# install.sh's GRUB theme step regenerates grub.cfg, once (#246).
[[ ! -s $work/calls.log ]] || fail "the console step ran a command in the new system: $(cat "$work/calls.log")"
# Run again (a Retry), it is the same one line.
post aarch64 'use_display_console' || fail "the console step failed a second time: $(cat "$work/out.log")"
[[ $(grep -vc '^#' "$work/target/etc/default/grub.d/90-lyona-console.cfg") == 1 ]] ||
	fail 'a second console step added its line again'

# The aarch64 steps run on aarch64 only, before and after the system update.
grep -Pzq '\nif \[\[ \$MACHINE_ARCH == aarch64 \]\]; then\n\trun_logged "Keeping the kernel where GRUB finds it\.\.\." keep_vmlinuz_linux\nfi\nrun_logged "Updating the new system\.\.\."' \
	"$postinstall" || fail 'the kernel copy does not run on aarch64 just before the system update'
grep -Fq 'run_logged "Adding a firmware boot entry..." add_firmware_boot_entry' "$postinstall" ||
	fail 'the postinstall does not add the firmware boot entry'
grep -B1 'run_logged "Adding a firmware boot entry..."' "$postinstall" | grep -Fq '[[ $MACHINE_ARCH == aarch64 ]]' ||
	fail 'the firmware boot entry is not for aarch64 only'
grep -Pzq '\nif \[\[ \$MACHINE_ARCH == aarch64 \]\]; then\n\trun_logged "Putting the console on the display\.\.\." use_display_console\nfi\n' \
	"$postinstall" || fail 'the console step is not for aarch64 only'
# shellcheck disable=SC1003 # the backslash is matched literally: the postinstall's line continuation
grep -Fq 'keep_vmlinuz_linux add_firmware_boot_entry use_display_console \' "$postinstall" ||
	fail 'the aarch64 steps are not exported for run_logged'

printf 'Image installer, aarch64 path: PASS\n'
