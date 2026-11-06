#!/usr/bin/env bash
set -euo pipefail

# Snapdragon X groundwork (ARM Sprint 6), statically: the device-tree lookup
# names the XPS 13 9345's device tree only when the machine says so and the
# kernel has it, and the firmware profile is aarch64 only.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

lib=$repo/scripts/lyona-snapdragon.sh
bash -n "$lib"

dmi=$work/dmi
dtbs=$work/dtbs
mkdir -p "$dmi" "$dtbs/qcom"
lookup() { # ARCH
	# shellcheck disable=SC2016 # expanded by the inner bash
	ARCH=$1 LYONA_DMI_ROOT=$dmi LYONA_DTB_DIR=$dtbs bash -c '. "$0"; lyona_snapdragon_dtb' "$lib"
}
set_dmi() {
	printf '%s\n' "$1" >"$dmi/sys_vendor"
	printf '%s\n' "$2" >"$dmi/product_name"
}

# Not a covered laptop: nothing, status 1, and no failure under set -e callers.
set_dmi 'QEMU' 'KVM Virtual Machine'
touch "$dtbs/qcom/x1e80100-dell-xps13-9345.dtb"
if out=$(lookup aarch64); then fail "a virtual machine got a device tree: $out"; fi
[[ -z $out ]] || fail "a virtual machine printed: $out"

# The XPS, with its device tree installed.
set_dmi 'Dell Inc.' 'XPS 13 9345'
[[ $(lookup aarch64) == qcom/x1e80100-dell-xps13-9345.dtb ]] || fail "the XPS 13 9345 did not get its device tree."

# Not on x86_64, and not when the kernel lacks the device tree.
if lookup x86_64 >/dev/null; then fail "x86_64 got a device tree."; fi
rm "$dtbs/qcom/x1e80100-dell-xps13-9345.dtb"
if lookup aarch64 >/dev/null; then fail "a device tree the kernel lacks was named."; fi

# No DMI at all (a board with no SMBIOS).
rm -f "$dmi/sys_vendor"
if lookup aarch64 >/dev/null; then fail "a machine with no DMI got a device tree."; fi

# The firmware profile: aarch64 only, from the map.
profile() { # ARCH
	# shellcheck disable=SC2016 # expanded by the inner bash
	ARCH=$1 bash -c '. "$0"; dwm_packages arch soc-snapdragon' "$repo/scripts/dwm-packages.sh" | sort
}
[[ $(profile aarch64 | tr '\n' ' ') == 'linux-firmware-atheros linux-firmware-qcom ' ]] ||
	fail "the soc-snapdragon profile is not the Qualcomm and Atheros firmware on aarch64."
[[ -z $(profile x86_64) ]] || fail "the soc-snapdragon profile resolves packages on x86_64."

# The postinstall step: on the XPS it installs the firmware, writes the kernel
# arguments (with the TPM wait off, ARM6-01) and the device-tree hook; anywhere
# else it writes nothing. The step runs against a staged target.
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
sed -n '/^install_snapdragon_support() {$/,/^}$/p' "$postinstall" >"$work/step.sh"
grep -q '^install_snapdragon_support() {$' "$work/step.sh" || fail 'install_snapdragon_support not found in the postinstall'
grep -Eq '^[[:space:]]+install_snapdragon_support \\$' "$postinstall" || fail 'install_snapdragon_support is not exported for run_logged'
grep -q 'run_logged "Setting up a Snapdragon X laptop..." install_snapdragon_support' "$postinstall" ||
	fail 'the postinstall does not run the Snapdragon X step'
step_line=$(grep -n 'run_logged "Setting up a Snapdragon X laptop..."' "$postinstall" | cut -d: -f1)
install_line=$(grep -n 'run_logged "Running install.sh' "$postinstall" | cut -d: -f1)
[[ $step_line -lt $install_line ]] || fail 'the Snapdragon X step must come before install.sh regenerates grub.cfg'

# run_logged runs each step in a fresh `bash -c`, so only what the postinstall
# exports exists there. dwm_packages calls dwm_aarch64_only and dwm_x86_64_only:
# unexported, the profile came back empty (status 127) and pacman had no
# targets, on the first real XPS install. Run it the way run_logged does.
exported=$(sed -n '/^export -f /,/[^\\]$/p' "$postinstall" | tr -d '\\\n' | sed 's/^export -f //')
[[ -n $exported ]] || fail 'the postinstall has no export -f list.'
# shellcheck disable=SC2016 # expanded by the inner bash
fresh=$(ARCH=aarch64 EXPORTED=$exported bash -c '
	. "$0"
	for f in $EXPORTED; do declare -F "$f" >/dev/null && export -f "$f"; done
	bash -c "set -Eeuo pipefail; dwm_packages arch soc-snapdragon" 2>&1' "$repo/scripts/dwm-packages.sh") ||
	fail "dwm_packages arch soc-snapdragon fails in a fresh shell: $fresh"
[[ $(printf '%s\n' "$fresh" | sort | tr '\n' ' ') == 'linux-firmware-atheros linux-firmware-qcom ' ]] ||
	fail "in a fresh shell the soc-snapdragon profile resolves: $fresh"

run_step() { # TARGET
	(
		# shellcheck disable=SC2034 # read by the sourced step and libraries
		TARGET=$1 REPO_SRC=$repo ARCH=aarch64 LYONA_DMI_ROOT=$dmi
		# shellcheck disable=SC2329 # called by the sourced step
		arch-chroot() { printf '%s\n' "$*" >>"$work/chroot.log"; }
		# shellcheck disable=SC1091
		. "$repo/scripts/dwm-packages.sh"
		# shellcheck disable=SC1091
		. "$work/step.sh"
		install_snapdragon_support
	)
}
target=$work/target
mkdir -p "$target/boot/dtbs/qcom"
touch "$target/boot/dtbs/qcom/x1e80100-dell-xps13-9345.dtb"
: >"$work/chroot.log"

set_dmi 'QEMU' 'KVM Virtual Machine'
run_step "$target" >/dev/null
[[ ! -e $target/etc/grub.d/09_lyona_dtb && ! -e $target/etc/default/grub.d/90-lyona-snapdragon.cfg && ! -s $work/chroot.log ]] ||
	fail 'a machine that is not a Snapdragon X laptop was changed.'

set_dmi 'Dell Inc.' 'XPS 13 9345'
run_step "$target" >/dev/null
grep -Fq 'pacman -S --noconfirm --needed' "$work/chroot.log" ||
	fail 'the XPS did not get the Qualcomm firmware.'
grep -Fq 'linux-firmware-qcom' "$work/chroot.log" ||
	fail 'the XPS did not get the Qualcomm firmware.'
cfg=$target/etc/default/grub.d/90-lyona-snapdragon.cfg
for arg in efi=noruntime clk_ignore_unused pd_ignore_unused arm64.nopauth systemd.tpm2_wait=0; do
	grep -Fq "$arg" "$cfg" || fail "the kernel arguments lack $arg."
done
hook=$target/etc/grub.d/09_lyona_dtb
[[ -x $hook ]] || fail 'the device-tree hook is not executable.'
grep -Fq 'dtb=/boot/dtbs/qcom/x1e80100-dell-xps13-9345.dtb' "$hook" || fail 'the device-tree hook names the wrong file.'
sh -n "$hook" || fail 'the device-tree hook is not valid sh.'

printf 'Snapdragon X groundwork: PASS\n'
