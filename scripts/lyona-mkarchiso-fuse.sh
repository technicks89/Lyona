# shellcheck shell=bash
# shellcheck disable=SC2154 # the variables and _msg_* below belong to mkarchiso
#
# The aarch64 medium's device-tree step (ARM6-02). Not run on its own:
# scripts/lyona-mkarchiso-dtb splices the function below into a copy of
# mkarchiso, in place of its own _make_stubble_efi, and the builder runs that
# copy. Only the text from "_make_stubble_efi() {" to the closing brace is used.
#
# Why: archiso 91 fuses the device trees into the kernel for Arch Linux's own
# aarch64 port, with the `stubble` package and a kernel package that keeps its
# device trees under /usr/lib/modules. Arch Linux ARM has neither (ARM2-02,
# docs/evidence/arm2-01-spike.md): its linux-aarch64 installs /boot/Image and
# /boot/dtbs/qcom, and the medium drops `stubble`. systemd-stub does the same
# job itself (systemd 257 and later): it reads .dtbauto sections and a .hwids
# table, picks the device tree whose hardware IDs match the machine's SMBIOS
# data, installs it, and starts the kernel. With no match it starts the kernel
# as it is, so a machine without a covered device tree boots as before. The
# initramfs and options stay in the loader entries: the stub takes up the
# initrd the boot loader registered (systemd v262 stub.c, acquire_previous_initrd).
#
# What is fused: the Snapdragon X trees (x1e*, x1p*), found in the kernel
# package's own directory, so the set follows the kernel and no list of laptops
# is kept here. The -el2 trees are left out (each has a plain sibling with the
# same base name and hardware IDs; booting at EL2 is not in ARM Sprint 6).
_make_stubble_efi() {
	local dtb_dir hwids_path kernel_path kernelver stub
	local -a dtbs=() devicetree_args=() module_dirs=()

	_msg_info "Fusing the Snapdragon X device trees with the kernel..."
	stub="${pacstrap_dir}/usr/lib/systemd/boot/efi/linux${uefi_arch[$arch],,}.efi.stub"
	hwids_path="${pacstrap_dir}/usr/lib/systemd/boot/hwids/${uefi_arch[$arch],,}/"
	dtb_dir="${pacstrap_dir}/boot/dtbs/qcom"
	kernel_path="${boot_dir}/vmlinuz-linux"
	[[ -f ${stub} ]] || _msg_error "The systemd EFI stub '${stub}' does not exist" 1
	[[ -d ${hwids_path} ]] || _msg_error "The directory '${hwids_path}' does not exist" 1
	[[ -d ${dtb_dir} ]] || _msg_error "The directory '${dtb_dir}' does not exist" 1
	[[ -f ${kernel_path} ]] || _msg_error "The kernel '${kernel_path}' does not exist" 1

	module_dirs=("${pacstrap_dir}/usr/lib/modules/"*)
	((${#module_dirs[@]} == 1)) && [[ -d ${module_dirs[0]} ]] ||
		_msg_error "Expected one kernel under '${pacstrap_dir}/usr/lib/modules', found ${#module_dirs[@]}" 1
	kernelver="${module_dirs[0]##*/}"

	mapfile -d '' -t dtbs < <(find "${dtb_dir}" -maxdepth 1 -type f \
		\( -name 'x1e*.dtb' -o -name 'x1p*.dtb' \) ! -name '*-el2.dtb' -print0 | LC_ALL=C sort -z)
	((${#dtbs[@]} > 0)) || _msg_error "There are no Snapdragon X device trees in '${dtb_dir}'" 1
	devicetree_args=("${dtbs[@]/#/--devicetree-auto=}")

	ukify build \
		--stub="${stub}" \
		--uname="${kernelver}" \
		--linux="${kernel_path}" \
		--hwids="${hwids_path}" \
		"${devicetree_args[@]}" \
		--output="${kernel_path}.fused"
	mv -fT -- "${kernel_path}.fused" "${kernel_path}"
	_msg_info "Done! ${#dtbs[@]} device trees fused with the kernel."
}
