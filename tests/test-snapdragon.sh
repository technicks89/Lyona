#!/usr/bin/env bash
set -euo pipefail

# Snapdragon X groundwork (ARM Sprint 6), statically: the device-tree lookup
# names the XPS 13 9345's device tree when the machine says so, or another
# laptop's from the device tree the live medium booted with (#92), only when
# the kernel has it; and the firmware profile is aarch64 only.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

lib=$repo/scripts/lyona-snapdragon.sh
bash -n "$lib"

dmi=$work/dmi
dtbs=$work/dtbs
# The running device tree: absent (an ACPI machine) until a case makes it.
dt=$work/devicetree
mkdir -p "$dmi" "$dtbs/qcom"
lookup() { # ARCH
	# shellcheck disable=SC2016 # expanded by the inner bash
	ARCH=$1 LYONA_DMI_ROOT=$dmi LYONA_DT_ROOT=$dt LYONA_DTB_DIR=$dtbs bash -c '. "$0"; lyona_snapdragon_dtb' "$lib"
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

# Another laptop, from the device tree the medium booted with (#92). make_dtb
# writes a real flattened device tree: a root node with the given properties
# and one child node, as the kernel's trees have.
make_dtb() { # FILE ROOT_COMPATIBLE [CHILD_COMPATIBLE]
	python3 -I - "$@" <<'PY'
import struct, sys
path, root = sys.argv[1], sys.argv[2]
child = sys.argv[3] if len(sys.argv) > 3 else "qcom,x1e80100-pdc"
strings = b"model\0compatible\0"
def prop(name_off, value):
    out = struct.pack(">III", 3, len(value), name_off) + value
    return out + b"\0" * (-len(out) % 4)
def node(name):
    out = struct.pack(">I", 1) + name + b"\0"
    return out + b"\0" * (-len(out) % 4)
struct_block = (node(b"") + prop(0, b"A laptop\0") +
                prop(6, root.encode() + b"\0qcom,x1e80100\0") +
                node(b"soc") + prop(6, child.encode() + b"\0") +
                struct.pack(">I", 2) + struct.pack(">I", 2) + struct.pack(">I", 9))
off_rsv = 40
off_struct = off_rsv + 16
off_strings = off_struct + len(struct_block)
total = off_strings + len(strings)
header = struct.pack(">10I", 0xD00DFEED, total, off_struct, off_strings, off_rsv,
                     17, 16, 0, len(strings), len(struct_block))
with open(path, "wb") as f:
    f.write(header + b"\0" * 16 + struct_block + strings)
PY
}
helper=$repo/scripts/lyona-dtb-compatible
[[ -x $helper ]] || fail 'lyona-dtb-compatible is not executable.'
make_dtb "$dtbs/qcom/x1e78100-lenovo-thinkpad-t14s.dtb" 'lenovo,thinkpad-t14s'
make_dtb "$dtbs/qcom/x1e78100-lenovo-thinkpad-t14s-el2.dtb" 'lenovo,thinkpad-t14s'
make_dtb "$dtbs/qcom/x1e80100-asus-vivobook-s15.dtb" 'asus,vivobook-s15'
make_dtb "$dtbs/qcom/x1p42100-asus-zenbook-a14.dtb" 'asus,zenbook-a14'
# A child node's compatible is not the board's.
make_dtb "$dtbs/qcom/x1e80100-crd.dtb" 'qcom,x1e80100-crd' 'lenovo,yoga-slim7x'
printf 'not a device tree\n' >"$dtbs/qcom/x1e80100-broken.dtb"
out=$("$helper" "$dtbs/qcom/x1e80100-asus-vivobook-s15.dtb" "$dtbs/qcom/x1e80100-broken.dtb") ||
	fail 'lyona-dtb-compatible read nothing.'
[[ $out == "asus,vivobook-s15	$dtbs/qcom/x1e80100-asus-vivobook-s15.dtb" ]] ||
	fail "lyona-dtb-compatible printed: $out"
if "$helper" "$dtbs/qcom/x1e80100-broken.dtb" >/dev/null; then fail 'a file that is no device tree was read.'; fi

running() { # COMPATIBLE...: the running device tree's root compatible
	mkdir -p "$dt"
	printf '%s\0' "$@" >"$dt/compatible"
}
set_dmi 'LENOVO' '21N1CTO1WW'
running 'lenovo,thinkpad-t14s' 'qcom,x1e78100' 'qcom,x1e80100'
[[ $(lookup aarch64) == qcom/x1e78100-lenovo-thinkpad-t14s.dtb ]] ||
	fail "the T14s did not get its device tree (not the -el2 one): $(lookup aarch64 || :)"
running 'asus,zenbook-a14' 'qcom,x1p42100'
[[ $(lookup aarch64) == qcom/x1p42100-asus-zenbook-a14.dtb ]] || fail 'an X Plus laptop did not get its device tree.'
running 'lenovo,yoga-slim7x' 'qcom,x1e80100'
if out=$(lookup aarch64); then fail "a board named only by a child node got a device tree: $out"; fi
running 'radxa,rock-5b' 'rockchip,rk3588'
if out=$(lookup aarch64); then fail "a board that is no Snapdragon X laptop got a device tree: $out"; fi
if lookup x86_64 >/dev/null; then fail "x86_64 got a device tree from the running one."; fi
# Two trees for one board: no guess.
make_dtb "$dtbs/qcom/x1e80100-asus-vivobook-s15-copy.dtb" 'asus,vivobook-s15'
running 'asus,vivobook-s15' 'qcom,x1e80100'
if out=$(lookup aarch64); then fail "two trees for one board, and one was chosen: $out"; fi
rm "$dtbs/qcom/x1e80100-asus-vivobook-s15-copy.dtb"
# The table wins over the running device tree: the XPS stays as validated.
set_dmi 'Dell Inc.' 'XPS 13 9345'
touch "$dtbs/qcom/x1e80100-dell-xps13-9345.dtb"
running 'asus,vivobook-s15' 'qcom,x1e80100'
[[ $(lookup aarch64) == qcom/x1e80100-dell-xps13-9345.dtb ]] || fail 'the table did not win for the XPS 13 9345.'
rm -r "$dt" "$dtbs/qcom/x1e80100-dell-xps13-9345.dtb"

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
		TARGET=$1 REPO_SRC=$repo ARCH=aarch64 LYONA_DMI_ROOT=$dmi LYONA_DT_ROOT=$dt
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
[[ ! -e $target/etc/grub.d/09_lyona_dtb && ! -e $target/etc/default/grub.d/90-lyona-snapdragon.cfg &&
	! -e $target/etc/tmpfiles.d/90-lyona-cpufreq.conf && ! -s $work/chroot.log ]] ||
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
tmpf=$target/etc/tmpfiles.d/90-lyona-cpufreq.conf
grep -Fq 'cpufreq/scaling_governor - - - - schedutil' "$tmpf" || fail 'the CPU governor rule is missing.'
hook=$target/etc/grub.d/09_lyona_dtb
[[ -x $hook ]] || fail 'the device-tree hook is not executable.'
grep -Fq 'dtb=/boot/dtbs/qcom/x1e80100-dell-xps13-9345.dtb' "$hook" || fail 'the device-tree hook names the wrong file.'
sh -n "$hook" || fail 'the device-tree hook is not valid sh.'
# The line it prints is guarded, so a kernel upgrade that drops the file boots
# as any machine does, not into a GRUB error (ARM6-03).
grep -Fq 'if [ -f %s ]; then' "$hook" || fail 'the device-tree line is not guarded by a file test.'

# The kernel-upgrade check: a pacman hook on linux-aarch64 that runs a script,
# which stays quiet while the device tree is there and says so when it is gone.
check=$target/usr/local/lib/lyona/snapdragon-dtb-check
pachook=$target/etc/pacman.d/hooks/lyona-snapdragon-dtb.hook
[[ -x $check ]] || fail 'the device-tree check is not executable.'
sh -n "$check" || fail 'the device-tree check is not valid sh.'
for line in 'Operation = Install' 'Operation = Upgrade' 'Target = linux-aarch64' 'When = PostTransaction' \
	'Exec = /usr/local/lib/lyona/snapdragon-dtb-check'; do
	grep -Fxq "$line" "$pachook" || fail "the pacman hook lacks: $line"
done
# Run the check against the staged target: its paths are absolute on a real system.
run_check() { # HOOK_FILE
	sed -e "s#/etc/grub.d/09_lyona_dtb#$1#" "$check" >"$work/check.sh"
	sh "$work/check.sh" 2>&1
}
with_dtb() { # DTB_PATH: a copy of the hook naming that device tree
	sed -e "s#^dtb=.*#dtb=$1#" "$hook" >"$work/hook-copy"
	printf '%s\n' "$work/hook-copy"
}
msg=$(run_check "$(with_dtb "$target/boot/dtbs/qcom/x1e80100-dell-xps13-9345.dtb")") ||
	fail 'the check failed with the device tree present.'
[[ -z $msg ]] || fail "the check spoke with the device tree present: $msg"
msg=$(run_check "$(with_dtb "$target/boot/dtbs/qcom/gone.dtb")") || fail 'the check failed (it must never fail an upgrade).'
[[ $msg == *'no '*'gone.dtb any more'* ]] || fail "the check did not warn about a missing device tree: $msg"
msg=$(run_check "$target/nonexistent") || fail 'the check failed with no hook.'
[[ -z $msg ]] || fail "the check spoke on a system with no device-tree hook: $msg"

# Another laptop through the postinstall step (#92): the medium booted it with
# its tree, so the new system gets the firmware, the arguments and a hook that
# names that tree.
target2=$work/target2
mkdir -p "$target2/boot/dtbs/qcom"
make_dtb "$target2/boot/dtbs/qcom/x1e78100-lenovo-thinkpad-t14s.dtb" 'lenovo,thinkpad-t14s'
: >"$work/chroot.log"
set_dmi 'LENOVO' '21N1CTO1WW'
running 'lenovo,thinkpad-t14s' 'qcom,x1e78100'
run_step "$target2" >/dev/null
grep -Fq 'linux-firmware-qcom' "$work/chroot.log" || fail 'the T14s did not get the Qualcomm firmware.'
[[ -f $target2/etc/default/grub.d/90-lyona-snapdragon.cfg ]] || fail 'the T14s did not get the kernel arguments.'
grep -Fq 'dtb=/boot/dtbs/qcom/x1e78100-lenovo-thinkpad-t14s.dtb' "$target2/etc/grub.d/09_lyona_dtb" ||
	fail 'the T14s hook does not name its device tree.'
rm -r "$dt"

printf 'Snapdragon X groundwork: PASS\n'
