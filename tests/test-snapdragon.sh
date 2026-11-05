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

printf 'Snapdragon X groundwork: PASS\n'
