# shellcheck shell=bash
# Snapdragon X laptops (ARM Sprint 6). Sourced, not run.
#
# A Snapdragon X laptop boots Linux from a device tree, one per laptop. This
# names the device tree of the laptop it runs on, for the installer to hand
# GRUB's `devicetree` line (A-11 (a)). It prints nothing, and returns 1, on any
# other machine: a virtual machine, a server or a Pi boots as it does today.
#
# Two ways to name it, in this order:
#   1. A table of laptops validated on the machine, from the SMBIOS strings
#      the kernel exports under /sys/class/dmi/id. Only the XPS 13 9345 is
#      validated (ARM6-06); its DMI strings are confirmed on the machine in
#      ARM6-01. An entry here also overrides a wrong match from 2.
#   2. The device tree the live medium booted with (#92): systemd-stub picked
#      it from the laptop's hardware IDs (A-10, ARM6-02), so the running
#      kernel's root `compatible` names the board. The file of the same board
#      in the new system's kernel, among the Snapdragon X trees (qcom/x1e*,
#      qcom/x1p*, not the -el2 ones), is the answer when exactly one matches.
#      Untested on hardware other than the XPS: such laptops are experimental
#      (SPEC.md section 4).
#
# A laptop is covered only if mainline Linux has its device tree and
# linux-firmware its firmware (docs/evidence/arm6-00-static-survey.md).
#
# LYONA_DMI_ROOT and LYONA_DT_ROOT redirect the DMI directory and the running
# device tree, for tests.

# Kernel device trees: Arch Linux ARM's linux-aarch64 installs them here.
LYONA_DTB_DIR=${LYONA_DTB_DIR:-/boot/dtbs}

# lyona_snapdragon_dtb: print the device tree's path relative to the dtbs
# directory (qcom/x1e80100-dell-xps13-9345.dtb), if the machine is a covered
# Snapdragon X laptop and the installed kernel has that device tree.
lyona_snapdragon_dtb() {
	local dmi=${LYONA_DMI_ROOT:-/sys/class/dmi/id} vendor product dtb=''
	[[ ${ARCH:-$HOSTTYPE} == aarch64 ]] || return 1
	if [[ -r $dmi/sys_vendor && -r $dmi/product_name ]]; then
		vendor=$(<"$dmi/sys_vendor")
		product=$(<"$dmi/product_name")
		case "$vendor|$product" in
		'Dell Inc.|XPS 13 9345') dtb=qcom/x1e80100-dell-xps13-9345.dtb ;;
		esac
	fi
	if [[ -z $dtb ]]; then
		dtb=$(lyona_snapdragon_dtb_from_running) || return 1
	fi
	# A kernel without that device tree cannot use it: boot as today.
	[[ -f $LYONA_DTB_DIR/$dtb ]] || return 1
	printf '%s\n' "$dtb"
}

# lyona_snapdragon_dtb_from_running: the Snapdragon X tree in LYONA_DTB_DIR
# whose root compatible is the running device tree's (way 2 above).
lyona_snapdragon_dtb_from_running() {
	local dt=${LYONA_DT_ROOT:-/sys/firmware/devicetree/base} board='' file
	local helper=${LYONA_DTB_COMPATIBLE:-${BASH_SOURCE[0]%/*}/lyona-dtb-compatible}
	local -a files=() matches=()
	# No device tree: an ACPI machine (a virtual machine, a server).
	[[ -r $dt/compatible ]] || return 1
	# The property is NUL-separated strings; the first names the board.
	IFS= read -r -d '' board <"$dt/compatible" || [[ -n $board ]] || return 1
	[[ -n $board ]] || return 1
	for file in "$LYONA_DTB_DIR"/qcom/x1e*.dtb "$LYONA_DTB_DIR"/qcom/x1p*.dtb; do
		[[ -f $file && $file != *-el2.dtb ]] && files+=("$file")
	done
	((${#files[@]})) || return 1
	command -v python3 >/dev/null 2>&1 && [[ -r $helper ]] || return 1
	mapfile -t matches < <(python3 "$helper" "${files[@]}" 2>/dev/null |
		awk -F '\t' -v board="$board" '$1 == board { print $2 }')
	# None, or more than one tree for the same board: do not guess.
	((${#matches[@]} == 1)) || return 1
	printf '%s\n' "${matches[0]#"$LYONA_DTB_DIR"/}"
}
