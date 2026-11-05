# shellcheck shell=bash
# Snapdragon X laptops (ARM Sprint 6). Sourced, not run.
#
# A Snapdragon X laptop boots Linux from a device tree, one per laptop. This
# names the device tree of the laptop it runs on, from the SMBIOS strings the
# kernel exports under /sys/class/dmi/id, for the installer to hand GRUB's
# `devicetree` line (A-11 (a)). It prints nothing, and returns 1, on any other
# machine: a virtual machine, a server or a Pi boots as it does today.
#
# The table holds laptops whose device tree is in mainline Linux AND whose
# firmware is in linux-firmware (docs/evidence/arm6-00-static-survey.md). A
# laptop is added when its DMI strings are known from the machine itself.
# Only the XPS 13 9345 is validated (ARM6-06); the DMI strings below are
# Dell's published names and are confirmed on the machine in ARM6-01.
#
# LYONA_DMI_ROOT redirects the DMI directory, for tests.

# Kernel device trees: Arch Linux ARM's linux-aarch64 installs them here.
LYONA_DTB_DIR=${LYONA_DTB_DIR:-/boot/dtbs}

# lyona_snapdragon_dtb: print the device tree's path relative to the dtbs
# directory (qcom/x1e80100-dell-xps13-9345.dtb), if the machine is a covered
# Snapdragon X laptop and the installed kernel has that device tree.
lyona_snapdragon_dtb() {
	local dmi=${LYONA_DMI_ROOT:-/sys/class/dmi/id} vendor product dtb
	[[ ${ARCH:-$HOSTTYPE} == aarch64 ]] || return 1
	[[ -r $dmi/sys_vendor && -r $dmi/product_name ]] || return 1
	vendor=$(<"$dmi/sys_vendor")
	product=$(<"$dmi/product_name")
	case "$vendor|$product" in
	'Dell Inc.|XPS 13 9345') dtb=qcom/x1e80100-dell-xps13-9345.dtb ;;
	*) return 1 ;;
	esac
	# A kernel without that device tree cannot use it: boot as today.
	[[ -f $LYONA_DTB_DIR/$dtb ]] || return 1
	printf '%s\n' "$dtb"
}
