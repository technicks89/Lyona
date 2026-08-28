#!/usr/bin/env bash
set -Eeuo pipefail

export TARGET=/mnt
export REPO_SRC=/root/lyona
export LOG_FILE=/var/log/lyona-postinstall.log
export CACHYOS_HELPER=/usr/local/bin/lyona-cachyos
export CACHYOS_KERNELS="linux-cachyos linux-cachyos-lts"
export CACHYOS_MARKER=/run/lyona-cachyos-ready

fail() {
	printf 'lyona-postinstall: %s\n' "$1" >&2
	exit 1
}

# shellcheck source=lyona-ui.sh
source /root/lyona-ui.sh
require_gum
: >"$LOG_FILE"
install_error_trap "$@"
show_logo

install_microcode() {
	local pkg
	if grep -q GenuineIntel /proc/cpuinfo; then
		pkg=intel-ucode
	elif grep -q AuthenticAMD /proc/cpuinfo; then
		pkg=amd-ucode
	else
		printf 'lyona-postinstall: could not determine CPU vendor; skipping microcode.\n'
		return 0
	fi

	printf 'Installing %s...\n' "$pkg"
	arch-chroot "$TARGET" pacman -S --noconfirm --needed "$pkg"

	if [[ -f "$TARGET/boot/grub/grub.cfg" ]]; then
		arch-chroot "$TARGET" grub-mkconfig -o /boot/grub/grub.cfg
	else
		printf 'lyona-postinstall: non-GRUB bootloader detected; add %s to its boot entries manually if needed.\n' "$pkg"
	fi
}

add_cachyos_repositories() {
	rm -f "$CACHYOS_MARKER"
	install -Dm755 "$REPO_SRC/scripts/lyona-cachyos" "$TARGET$CACHYOS_HELPER"

	# The live medium adds the repositories before archinstall runs, so the
	# installed system inherits them along with this medium's pacman.conf.
	# Carry over the mirrorlists those sections include in case the package
	# that owns them has not landed yet -- a pacman.conf that Includes a
	# missing file fails to parse at all.
	for mirrorlist in /etc/pacman.d/cachyos*-mirrorlist /etc/pacman.d/cachyos-mirrorlist; do
		[[ -f $mirrorlist ]] || continue
		[[ -f "$TARGET$mirrorlist" ]] && continue
		install -Dm644 "$mirrorlist" "$TARGET$mirrorlist"
	done

	if arch-chroot "$TARGET" "$CACHYOS_HELPER" status 2>/dev/null |
		grep -Fqx 'cachyos-repos: configured'; then
		printf 'lyona-postinstall: CachyOS repositories already present on the target.\n'
		arch-chroot "$TARGET" pacman-key --populate cachyos >/dev/null 2>&1 || true
		: >"$CACHYOS_MARKER"
		return 0
	fi

	# Fallback for a target installed some other way (plain archinstall
	# followed by this script by hand).
	if ! arch-chroot "$TARGET" env LYONA_CACHYOS_NONINTERACTIVE=1 \
		"$CACHYOS_HELPER" add-repos; then
		printf 'lyona-postinstall: CachyOS repository setup failed; continuing with the stock Arch repositories.\n'
		return 0
	fi
	: >"$CACHYOS_MARKER"
}

install_cachyos_kernels() {
	local -a kernels

	if [[ ! -e $CACHYOS_MARKER ]]; then
		printf 'lyona-postinstall: skipping the CachyOS kernels because their repositories are unavailable.\n'
		return 0
	fi

	read -r -a kernels <<<"$CACHYOS_KERNELS"
	if ! arch-chroot "$TARGET" env LYONA_CACHYOS_NONINTERACTIVE=1 \
		"$CACHYOS_HELPER" install-kernel "${kernels[@]}"; then
		printf 'lyona-postinstall: the CachyOS kernels could not be installed; the stock kernel remains in place.\n'
	fi
}

installed_kernels() {
	arch-chroot "$TARGET" pacman -Qq 2>/dev/null |
		grep -E '^linux(-cachyos)?(-lts|-zen|-hardened|-rt)?$' || true
}

install_nvidia_driver() {
	local -a kernel_pkgs headers=()
	local kernel_pkg

	mapfile -t kernel_pkgs < <(installed_kernels)
	((${#kernel_pkgs[@]} > 0)) || kernel_pkgs=(linux)

	if ((${#kernel_pkgs[@]} == 1)) && [[ ${kernel_pkgs[0]} == linux ]]; then
		printf 'Installing NVIDIA driver (nvidia) for kernel linux...\n'
		arch-chroot "$TARGET" pacman -S --noconfirm --needed nvidia nvidia-utils
		return 0
	fi

	for kernel_pkg in "${kernel_pkgs[@]}"; do
		headers+=("${kernel_pkg}-headers")
	done
	printf 'Installing NVIDIA driver (nvidia-dkms) for kernels: %s...\n' "${kernel_pkgs[*]}"
	arch-chroot "$TARGET" pacman -S --noconfirm --needed \
		nvidia-dkms nvidia-utils "${headers[@]}"
}

install_gpu_drivers() {
	if ! command -v lspci >/dev/null 2>&1; then
		printf 'lyona-postinstall: lspci not found; skipping GPU driver detection.\n'
		return 0
	fi

	local gpu_info
	gpu_info=$(lspci | grep -E "VGA|3D|Display" || true)

	if grep -qE "NVIDIA|GeForce" <<<"$gpu_info"; then
		if [[ ${LYONA_NVIDIA_DRIVER:-} == 1 ]]; then
			install_nvidia_driver
		else
			printf 'lyona-postinstall: NVIDIA GPU detected; leaving the open-source nouveau driver in place.\n'
			printf 'lyona-postinstall: re-run with LYONA_NVIDIA_DRIVER=1 to opt into the proprietary NVIDIA driver instead.\n'
		fi
	elif grep -qE "Radeon|AMD" <<<"$gpu_info"; then
		printf 'Installing AMD GPU driver...\n'
		arch-chroot "$TARGET" pacman -S --noconfirm --needed xf86-video-amdgpu
	elif grep -qiE "Intel" <<<"$gpu_info"; then
		printf 'Installing Intel GPU driver...\n'
		arch-chroot "$TARGET" pacman -S --noconfirm --needed mesa vulkan-intel libva-intel-driver
	else
		printf 'lyona-postinstall: no known GPU vendor detected; skipping driver install.\n'
	fi
}

install_networkmanager() {
	if ! arch-chroot "$TARGET" pacman -Qq networkmanager >/dev/null 2>&1; then
		printf 'Installing NetworkManager...\n'
		arch-chroot "$TARGET" pacman -S --noconfirm --needed networkmanager
	fi
	arch-chroot "$TARGET" systemctl enable NetworkManager.service
}

setup_swap_if_needed() {
	local total_mem_kb
	total_mem_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)
	if ((total_mem_kb >= 8000000)); then
		return 0
	fi

	if arch-chroot "$TARGET" bash -c 'swapon --show --noheadings' 2>/dev/null | grep -q .; then
		printf 'lyona-postinstall: swap already active in target; skipping swapfile.\n'
		return 0
	fi
	if grep -qsE '\sswap\s' "$TARGET/etc/fstab"; then
		printf 'lyona-postinstall: swap entry already in fstab; skipping.\n'
		return 0
	fi

	printf 'Low-memory system detected (<8G RAM); creating a 2G swapfile...\n'
	install -d -m 0755 "$TARGET/opt/swap"
	if arch-chroot "$TARGET" findmnt -n -o FSTYPE / | grep -q btrfs; then
		arch-chroot "$TARGET" chattr +C /opt/swap
	fi
	dd if=/dev/zero of="$TARGET/opt/swap/swapfile" bs=1M count=2048 status=progress
	chmod 600 "$TARGET/opt/swap/swapfile"
	arch-chroot "$TARGET" mkswap /opt/swap/swapfile
	printf '/opt/swap/swapfile none swap sw 0 0\n' >>"$TARGET/etc/fstab"
}

install_qemu_guest_utils() {
	local virt
	virt=$(arch-chroot "$TARGET" systemd-detect-virt 2>/dev/null || true)

	case "$virt" in
	qemu | kvm) ;;
	*)
		printf 'lyona-postinstall: no QEMU/KVM hypervisor detected (systemd-detect-virt: %s); skipping guest utilities.\n' "${virt:-none}"
		return 0
		;;
	esac

	printf 'QEMU/KVM detected; installing guest utilities...\n'
	arch-chroot "$TARGET" pacman -S --noconfirm --needed \
		virtiofsd qemu-guest-agent spice-vdagent qemu-hw-display-virtio-vga
	arch-chroot "$TARGET" systemctl enable qemu-guest-agent.service
	arch-chroot "$TARGET" systemctl enable spice-vdagentd.service
}

export -f add_cachyos_repositories install_cachyos_kernels installed_kernels \
	install_microcode install_nvidia_driver install_gpu_drivers \
	install_networkmanager setup_swap_if_needed install_qemu_guest_utils

mountpoint -q "$TARGET" || fail "$TARGET is not a mounted target root. Complete a base Arch install to $TARGET first (e.g. with archinstall), then re-run this script."
[[ -d $REPO_SRC ]] || fail "checkout not found at $REPO_SRC (this script expects to run from the lyona live medium)."
command -v arch-chroot >/dev/null 2>&1 || fail "arch-chroot is required (part of arch-install-scripts)."

target_user=$(
	awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" && $7 !~ /(nologin|false)$/ { print $1; exit }' \
		"$TARGET/etc/passwd"
)
[[ -n $target_user ]] || fail "No regular user was found in $TARGET/etc/passwd. Create one (archinstall does this) before running this script."

target_home=$(arch-chroot "$TARGET" getent passwd "$target_user" | cut -d: -f6)
target_group=$(arch-chroot "$TARGET" id -gn "$target_user")
target_repo_dir="$target_home/.local/share/lyona"

set_total_steps 9
run_logged "Syncing package databases..." arch-chroot "$TARGET" pacman -Sy --noconfirm
run_logged "Adding the CachyOS repositories..." add_cachyos_repositories
run_logged "Installing the CachyOS kernels..." install_cachyos_kernels
run_logged "Installing CPU microcode..." install_microcode
run_logged "Installing GPU drivers..." install_gpu_drivers
run_logged "Configuring NetworkManager..." install_networkmanager
run_logged "Checking swap..." setup_swap_if_needed
run_logged "Checking for a QEMU/KVM hypervisor..." install_qemu_guest_utils

chmod +x "$REPO_SRC/install.sh"
find "$REPO_SRC/scripts" -maxdepth 1 -type f -exec chmod +x {} +

say --foreground $COLOR_ACCENT -- "-> Copying checkout to $TARGET$target_repo_dir..."
for xdg_dir in "$target_home/.local" "$target_home/.local/share" "$target_home/.config"; do
	install -d -m 0755 "$TARGET$xdg_dir"
	arch-chroot "$TARGET" chown "$target_user:$target_group" "$xdg_dir"
done
rm -rf "${TARGET:?}$target_repo_dir"
cp -a "$REPO_SRC" "$TARGET$target_repo_dir"
arch-chroot "$TARGET" chown -R "$target_user:$target_group" "$target_repo_dir"

install_sudoers="$TARGET/etc/sudoers.d/90-lyona-install"
install -m 0440 /dev/null "$install_sudoers"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$target_user" >"$install_sudoers"

run_logged "Running install.sh --profile full as $target_user..." \
	arch-chroot "$TARGET" su - "$target_user" -c \
	'cd "$HOME/.local/share/lyona" && ./install.sh --non-interactive --profile full'

rm -f "$install_sudoers"

arch-chroot "$TARGET" bash -c '
	find /usr/share/xsessions -mindepth 1 -maxdepth 1 -type f ! -name dwm.desktop -delete 2>/dev/null || true
	find /usr/share/wayland-sessions -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
	if systemctl -q list-unit-files lightdm.service >/dev/null 2>&1; then
		systemctl enable lightdm.service
	fi
	systemctl enable power-profiles-daemon.service 2>/dev/null || true
	systemctl set-default graphical.target
'

echo
say --border rounded --border-foreground $COLOR_OK --foreground $COLOR_OK --bold --padding "1 2" \
	"lyona installed into $TARGET for $target_user." \
	"Rebooting automatically in 15 seconds."
echo
say --foreground $COLOR_DANGER \
	"If the live medium is still attached and boots before the disk, this will land back in the installer instead of the new system. Detach/eject it now, or Ctrl+C to cancel the reboot."

sleep 15
systemctl reboot
