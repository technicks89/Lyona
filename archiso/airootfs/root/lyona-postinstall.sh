#!/usr/bin/env bash
set -Eeuo pipefail

export TARGET=/mnt
export REPO_SRC=/root/lyona
export LOG_FILE=/var/log/lyona-postinstall.log
export CACHYOS_HELPER=/usr/local/bin/lyona-cachyos
export CACHYOS_KERNELS="linux-cachyos linux-cachyos-lts"
export CACHYOS_MARKER=/run/lyona-cachyos-ready
# Left when the NVIDIA driver was built from the AUR, for the closing message.
export NVIDIA_AUR_MARKER=${NVIDIA_AUR_MARKER:-/run/lyona-nvidia-aur}

fail() {
	printf 'lyona-postinstall: %s\n' "$1" >&2
	exit 1
}

# shellcheck source=lyona-ui.sh
source /root/lyona-ui.sh
# Package names come from the shared map, as everywhere else (Sync Sprint 12
# S12-15). The functions below run in fresh shells, so dwm_packages is exported
# with them.
# shellcheck source=scripts/dwm-packages.sh
source "$REPO_SRC/scripts/dwm-packages.sh"
# shellcheck source=lyona-nvidia.sh
source /root/lyona-nvidia.sh
require_gum
: >"$LOG_FILE"
install_error_trap "$@"
show_logo

install_microcode() {
	local pkg
	if grep -q GenuineIntel /proc/cpuinfo; then
		pkg=$(dwm_packages arch microcode-intel)
	elif grep -q AuthenticAMD /proc/cpuinfo; then
		pkg=$(dwm_packages arch microcode-amd)
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
	local -a kernel_pkgs headers=() driver
	local kernel_pkg

	mapfile -t kernel_pkgs < <(installed_kernels)
	((${#kernel_pkgs[@]} > 0)) || kernel_pkgs=(linux)

	if ((${#kernel_pkgs[@]} == 1)) && [[ ${kernel_pkgs[0]} == linux ]]; then
		printf 'Installing NVIDIA driver (nvidia-open) for kernel linux...\n'
		mapfile -t driver < <(dwm_packages arch gpu-nvidia)
		arch-chroot "$TARGET" pacman -S --noconfirm --needed "${driver[@]}"
		return 0
	fi

	for kernel_pkg in "${kernel_pkgs[@]}"; do
		headers+=("${kernel_pkg}-headers")
	done
	printf 'Installing NVIDIA driver (nvidia-open-dkms) for kernels: %s...\n' "${kernel_pkgs[*]}"
	mapfile -t driver < <(dwm_packages arch gpu-nvidia-dkms)
	arch-chroot "$TARGET" pacman -S --noconfirm --needed "${driver[@]}" "${headers[@]}"
}

# The one AUR exception (Sync Sprint 14, docs/AUR-PACKAGES.md): the legacy NVIDIA
# drivers, when the CachyOS repository cannot supply them (decision D-22). Each
# branch's packages come from one AUR base, pinned to a commit whose PKGBUILD was
# reviewed: its sources download from download.nvidia.com over HTTPS, each with
# a checksum, and its install script does no more than Arch's own nvidia-utils.
# Re-pin only after reviewing the diff since the last pin.
# branch<TAB>AUR base<TAB>commit
export LEGACY_NVIDIA_PINS='580xx	nvidia-580xx-utils	3d31a20c08a1e6c11c1abe953954f44158c9a592
470xx	nvidia-470xx-utils	af0b7617132e32dd39174779aa8ced2a726afc51'

# install_legacy_nvidia_driver BRANCH DEVICE: the 580xx or 470xx driver, with the
# headers of every installed kernel (they are DKMS-only). From the CachyOS
# repository when the medium added it; otherwise built from the pinned AUR
# PKGBUILD as the new user (makepkg never runs as root), its dependencies
# installed by root first. Any failure leaves nouveau in place and the rest of
# the install going: it returns 0 either way, having said which.
install_legacy_nvidia_driver() {
	local branch=$1 device=$2 base ref kernel_pkg build srcinfo package file
	local -a packages kernel_pkgs headers=() built=() needed=() own=()
	local -a legacy_packages absent_before=() newly_installed=()

	mapfile -t packages < <(dwm_packages arch "gpu-nvidia-$branch")
	mapfile -t kernel_pkgs < <(installed_kernels)
	((${#kernel_pkgs[@]} > 0)) || kernel_pkgs=(linux)
	for kernel_pkg in "${kernel_pkgs[@]}"; do
		headers+=("${kernel_pkg}-headers")
	done

	if [[ -e $CACHYOS_MARKER ]]; then
		# Track both legacy branches, including DKMS packages so their utils
		# can be removed without ignoring dependencies or removing old packages.
		mapfile -t legacy_packages < <(
			dwm_packages arch gpu-nvidia-580xx
			dwm_packages arch gpu-nvidia-470xx
		)
		for package in "${legacy_packages[@]}"; do
			if ! arch-chroot "$TARGET" pacman -Qq "$package" >/dev/null 2>&1; then
				absent_before+=("$package")
			fi
		done
		printf 'Installing the NVIDIA %s driver for GPU 10de:%s from the CachyOS repository...\n' "$branch" "$device"
		if arch-chroot "$TARGET" pacman -S --noconfirm --needed "${packages[@]/#/cachyos/}" "${headers[@]}"; then
			return 0
		fi
		# A failed transaction can still have installed nouveau-blacklisting
		# utils. Remove only packages added by this attempt before falling back.
		for package in "${absent_before[@]}"; do
			if arch-chroot "$TARGET" pacman -Qq "$package" >/dev/null 2>&1; then
				newly_installed+=("$package")
			fi
		done
		if ((${#newly_installed[@]} > 0)); then
			arch-chroot "$TARGET" pacman -R --noconfirm "${newly_installed[@]}" ||
				printf 'lyona-postinstall: could not remove the newly installed legacy NVIDIA packages.\n'
		fi
		printf 'lyona-postinstall: the CachyOS repository could not supply it; building it from the AUR instead.\n'
	fi

	IFS=$'\t' read -r _ base ref < <(awk -F '\t' -v branch="$branch" '$1 == branch' <<<"$LEGACY_NVIDIA_PINS") || :
	if [[ -z ${base:-} || ! ${ref:-} =~ ^[0-9a-f]{40}$ ]]; then
		printf 'lyona-postinstall: no pinned AUR source for the NVIDIA %s driver; leaving nouveau in place.\n' "$branch"
		return 0
	fi
	printf 'Building the NVIDIA %s driver for GPU 10de:%s from the AUR (%s at %s)...\n' \
		"$branch" "$device" "$base" "${ref:0:12}"
	build=/var/tmp/lyona-nvidia-$branch
	as_user() {
		arch-chroot "$TARGET" runuser -u "$target_user" -- env HOME="$target_home" "$@"
	}
	# shellcheck disable=SC2016 # $1 is the inner sh's, in both makepkg calls
	if arch-chroot "$TARGET" pacman -S --noconfirm --needed --asdeps base-devel git &&
		arch-chroot "$TARGET" pacman -S --noconfirm --needed "${headers[@]}" &&
		arch-chroot "$TARGET" rm -rf -- "$build" &&
		arch-chroot "$TARGET" install -d -o "$target_user" -g "$target_group" -m 700 -- "$build" &&
		as_user git clone --quiet -- "https://aur.archlinux.org/$base.git" "$build/src" &&
		as_user git -C "$build/src" checkout --quiet --detach "$ref" &&
		srcinfo=$(as_user sh -c 'cd "$1" && makepkg --printsrcinfo' sh "$build/src"); then
		# The dependencies, less the packages this base itself builds, by name.
		mapfile -t own < <(sed -n -E 's/^pkgname = (.+)$/\1/p' <<<"$srcinfo")
		while IFS= read -r package; do
			package=${package%%[<>=]*}
			[[ -n $package && " ${own[*]} " != *" $package "* && " ${needed[*]} " != *" $package "* ]] &&
				needed+=("$package")
		done < <(sed -n -E 's/^[[:space:]]+(make)?depends = (.+)$/\2/p' <<<"$srcinfo")
		# shellcheck disable=SC2016 # $1 is the inner sh's
		if { ((${#needed[@]} == 0)) || arch-chroot "$TARGET" pacman -S --noconfirm --needed --asdeps "${needed[@]}"; } &&
			as_user sh -c 'cd "$1" && makepkg --noconfirm --nocheck' sh "$build/src"; then
			for package in "${packages[@]}"; do
				for file in "$TARGET$build/src/$package"-[0-9]*.pkg.tar.*; do
					[[ -f $file && $file != *.sig ]] && built+=("${file#"$TARGET"}")
				done
			done
		fi
	fi
	if ((${#built[@]} == ${#packages[@]})) &&
		arch-chroot "$TARGET" pacman -U --noconfirm --needed "${built[@]}"; then
		arch-chroot "$TARGET" rm -rf -- "$build"
		printf 'lyona-postinstall: the NVIDIA %s driver was built from the AUR. pacman -Syu does not update it; update it with yay.\n' "$branch"
		: >"$NVIDIA_AUR_MARKER"
		return 0
	fi
	arch-chroot "$TARGET" rm -rf -- "$build" || :
	printf 'lyona-postinstall: the NVIDIA %s driver could not be built; leaving the open-source nouveau driver in place.\n' "$branch"
	return 0
}

install_gpu_drivers() {
	if ! command -v lspci >/dev/null 2>&1; then
		printf 'lyona-postinstall: lspci not found; skipping GPU driver detection.\n'
		return 0
	fi

	local gpu_info
	local -a driver
	gpu_info=$(lspci | grep -E "VGA|3D|Display" || true)

	if grep -qE "NVIDIA|GeForce" <<<"$gpu_info"; then
		if [[ ${LYONA_NVIDIA_DRIVER:-} == 1 ]]; then
			# The driver this card needs (Sync Sprint 14 S14-02).
			local branch device
			read -r branch device < <(nvidia_gpu_branch || printf 'unsupported unknown\n')
			case $branch in
			open) install_nvidia_driver ;;
			580xx | 470xx) install_legacy_nvidia_driver "$branch" "$device" ;;
			*) printf 'lyona-postinstall: no packaged NVIDIA driver supports GPU 10de:%s; leaving the open-source nouveau driver in place.\n' "$device" ;;
			esac
		else
			printf 'lyona-postinstall: NVIDIA GPU detected; leaving the open-source nouveau driver in place.\n'
			printf 'lyona-postinstall: re-run with LYONA_NVIDIA_DRIVER=1 to opt into the proprietary NVIDIA driver instead.\n'
		fi
	elif grep -qE "Radeon|AMD" <<<"$gpu_info"; then
		printf 'Installing AMD GPU driver...\n'
		mapfile -t driver < <(dwm_packages arch gpu-amd)
		arch-chroot "$TARGET" pacman -S --noconfirm --needed "${driver[@]}"
	elif grep -qiE "Intel" <<<"$gpu_info"; then
		printf 'Installing Intel GPU driver...\n'
		mapfile -t driver < <(dwm_packages arch gpu-intel)
		arch-chroot "$TARGET" pacman -S --noconfirm --needed "${driver[@]}"
	else
		printf 'lyona-postinstall: no known GPU vendor detected; skipping driver install.\n'
	fi
}

install_networkmanager() {
	local -a network
	mapfile -t network < <(dwm_packages arch network)
	if ! arch-chroot "$TARGET" pacman -Qq "${network[@]}" >/dev/null 2>&1; then
		printf 'Installing NetworkManager...\n'
		arch-chroot "$TARGET" pacman -S --noconfirm --needed "${network[@]}"
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
	local -a guest
	mapfile -t guest < <(dwm_packages arch vm-guest)
	arch-chroot "$TARGET" pacman -S --noconfirm --needed "${guest[@]}"
	arch-chroot "$TARGET" systemctl enable qemu-guest-agent.service
	arch-chroot "$TARGET" systemctl enable spice-vdagentd.service
}

export -f dwm_packages add_cachyos_repositories install_cachyos_kernels installed_kernels \
	install_microcode lyona_nvidia_branch nvidia_gpu_branch install_nvidia_driver \
	install_legacy_nvidia_driver install_gpu_drivers \
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
# The steps run in fresh shells (run_logged); the legacy NVIDIA build needs these.
export target_user target_home target_group lyona_nvidia_table
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

# UPDATE-001 install provenance: the live medium's own build already computed
# a commit for /etc/lyona-iso-release (scripts/build-lyona-arch-iso.sh); carry
# it through to the target so an ISO-installed machine records a real commit
# and LYONA_SOURCE=iso, not "unknown". `su -` starts a login shell that resets
# the environment, so these are passed inside the command string, not
# exported beforehand.
iso_commit=unknown
if [[ -r /etc/lyona-iso-release ]]; then
	iso_commit=$(awk -F= '$1 == "LYONA_ISO_COMMIT" { print $2; exit }' /etc/lyona-iso-release)
	[[ -n $iso_commit ]] || iso_commit=unknown
fi
install -Dm644 /etc/lyona-iso-release "$TARGET/etc/lyona-iso-release" 2>/dev/null || true

run_logged "Running install.sh --profile full as $target_user..." \
	arch-chroot "$TARGET" su - "$target_user" -c \
	"cd \"\$HOME/.local/share/lyona\" && env LYONA_SOURCE=iso LYONA_COMMIT=$iso_commit ./install.sh --non-interactive --profile full"

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
if [[ -e $NVIDIA_AUR_MARKER ]]; then
	say --foreground "$COLOR_ACCENT" \
		"The NVIDIA driver was built from the AUR: pacman -Syu does not update it. Update it with yay."
	echo
fi
say --foreground $COLOR_DANGER \
	"If the live medium is still attached and boots before the disk, this will land back in the installer instead of the new system. Detach/eject it now, or Ctrl+C to cancel the reboot."

sleep 15
systemctl reboot
