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
# What did not go as chosen, one line each, for the closing screen (Sync Sprint
# 16 R16-22): the steps' output only reaches the log.
export LYONA_WARNINGS=${LYONA_WARNINGS:-/run/lyona-install-warnings}

fail() {
	printf 'lyona-postinstall: %s\n' "$1" >&2
	exit 1
}

# note_warning MESSAGE: said in the log as before, and kept for the closing screen.
note_warning() {
	printf 'lyona-postinstall: %s\n' "$1"
	printf '%s\n' "$1" >>"$LYONA_WARNINGS"
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
		# Without the key every sync fails, so a failure here is not hidden.
		if ! arch-chroot "$TARGET" pacman-key --populate cachyos >/dev/null 2>&1; then
			note_warning 'Could not trust the CachyOS signing key on the new system; package updates will fail until it is (pacman-key --populate cachyos).'
		fi
		: >"$CACHYOS_MARKER"
		return 0
	fi

	# Fallback for a target installed some other way (plain archinstall
	# followed by this script by hand).
	if ! arch-chroot "$TARGET" env LYONA_CACHYOS_NONINTERACTIVE=1 \
		"$CACHYOS_HELPER" add-repos; then
		note_warning 'CachyOS repository setup failed; continuing with the stock Arch repositories.'
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
		note_warning 'The CachyOS kernels could not be installed; the stock kernel remains in place.'
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

# A listed AUR use (Sync Sprint 14, docs/AUR-PACKAGES.md): the legacy NVIDIA
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
				note_warning 'Could not remove the newly installed legacy NVIDIA packages.'
		fi
		printf 'lyona-postinstall: the CachyOS repository could not supply it; building it from the AUR instead.\n'
	fi

	IFS=$'\t' read -r _ base ref < <(awk -F '\t' -v branch="$branch" '$1 == branch' <<<"$LEGACY_NVIDIA_PINS") || :
	if [[ -z ${base:-} || ! ${ref:-} =~ ^[0-9a-f]{40}$ ]]; then
		note_warning "No pinned AUR source for the NVIDIA $branch driver; the open-source nouveau driver is in use instead."
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
	note_warning "The NVIDIA $branch driver could not be built; the open-source nouveau driver is in use instead."
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
			*) note_warning "No packaged NVIDIA driver supports GPU 10de:$device; the open-source nouveau driver is in use instead." ;;
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

# Topgrade (Sync Sprint 15 S15-06, decision D-28), built only after the install's
# passwordless sudo is gone (install.sh runs with --skip-topgrade): the build
# runs a few hundred crates' build scripts as the new user, and none of them may
# reach root. rustup comes from the map, installed as root; the build runs as
# the user. A failure leaves the machine without Topgrade, never without a
# desktop.
install_topgrade() {
	local -a toolchain
	local other
	# A target that already has another Rust toolchain (Arch's rust, say) keeps
	# it, and its cargo builds Topgrade: the shared rule, asked inside the target.
	# shellcheck disable=SC2016 # $1 is the inner bash's
	if other=$(arch-chroot "$TARGET" bash -c '. "$1" && dwm_other_rust_toolchain' _ \
		"$target_home/$checkout_rel/scripts/dwm-packages.sh"); then
		printf 'Keeping the installed Rust toolchain (%s); skipping rustup.\n' "$other"
	else
		mapfile -t toolchain < <(dwm_packages arch rust-toolchain)
		arch-chroot "$TARGET" pacman -S --noconfirm --needed "${toolchain[@]}"
	fi
	# shellcheck disable=SC2016 # $HOME is the user's, expanded in their login shell
	arch-chroot "$TARGET" su - "$target_user" -c '"$HOME/'"$checkout_rel"'/scripts/install-topgrade"'
}

export -f note_warning dwm_packages add_cachyos_repositories install_cachyos_kernels installed_kernels \
	install_microcode lyona_nvidia_branch nvidia_gpu_branch install_nvidia_driver \
	install_legacy_nvidia_driver install_gpu_drivers \
	install_networkmanager setup_swap_if_needed install_qemu_guest_utils install_topgrade

mountpoint -q "$TARGET" || fail "$TARGET is not a mounted target root. Complete a base Arch install to $TARGET first (e.g. with archinstall), then re-run this script."
[[ -d $REPO_SRC ]] || fail "checkout not found at $REPO_SRC (this script expects to run from the lyona live medium)."
command -v arch-chroot >/dev/null 2>&1 || fail "arch-chroot is required (part of arch-install-scripts)."

target_user=$(
	awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ "^/home/" && $7 !~ /(nologin|false)$/ { print $1; exit }' \
		"$TARGET/etc/passwd"
)
[[ -n $target_user ]] || fail "No regular user was found in $TARGET/etc/passwd. Create one (archinstall does this) before running this script."

# Root has no password of its own and cannot log in: the user administers
# through sudo (decision R16-18). Locked whatever the base system's default.
arch-chroot "$TARGET" passwd -l root >/dev/null
target_home=$(arch-chroot "$TARGET" getent passwd "$target_user" | cut -d: -f6)
target_group=$(arch-chroot "$TARGET" id -gn "$target_user")
# The steps run in fresh shells (run_logged); the legacy NVIDIA build needs these.
# The new user's copy of this checkout, relative to their home: a source
# directory, not ~/.local/share/lyona, which holds lyona's per-user data and
# which updates back up (Sync Sprint 16 R16-54).
checkout_rel=.local/src/lyona
export target_user target_home target_group lyona_nvidia_table checkout_rel
target_repo_dir="$target_home/$checkout_rel"

# A Retry starts a fresh list.
: >"$LYONA_WARNINGS"
# Every run_logged step below, the install.sh and Topgrade ones too (Sync
# Sprint 16 R16-29).
set_total_steps 10
# The CachyOS step first: the new system's pacman.conf already lists the CachyOS
# repositories (archinstall copied this medium's), and this step trusts their
# key there. Updating first failed every sync with "unknown trust" (Sync Sprint
# 16, found in a VM once the wizard's CachyOS step ran again).
run_logged "Adding the CachyOS repositories..." add_cachyos_repositories
run_logged "Updating the new system..." arch-chroot "$TARGET" pacman -Syu --noconfirm
run_logged "Installing the CachyOS kernels..." install_cachyos_kernels
run_logged "Installing CPU microcode..." install_microcode
run_logged "Installing GPU drivers..." install_gpu_drivers
run_logged "Configuring NetworkManager..." install_networkmanager
run_logged "Checking swap..." setup_swap_if_needed
run_logged "Checking for a QEMU/KVM hypervisor..." install_qemu_guest_utils

chmod +x "$REPO_SRC/install.sh"
find "$REPO_SRC/scripts" -maxdepth 1 -type f -exec chmod +x {} +

say --foreground $COLOR_ACCENT -- "-> Copying checkout to $TARGET$target_repo_dir..."
for xdg_dir in "$target_home/.local" "$target_home/.local/share" "$target_home/.local/src" "$target_home/.config"; do
	install -d -m 0755 "$TARGET$xdg_dir"
	arch-chroot "$TARGET" chown "$target_user:$target_group" "$xdg_dir"
done
rm -rf "${TARGET:?}$target_repo_dir"
cp -a "$REPO_SRC" "$TARGET$target_repo_dir"
arch-chroot "$TARGET" chown -R "$target_user:$target_group" "$target_repo_dir"

# Passwordless sudo, only while install.sh runs as the new user. It is removed
# however the run ends (lyona-ui.sh's clean-up), and a stale copy from an
# earlier, failed run is removed first (Sync Sprint 16 R16-01).
install_sudoers="$TARGET/etc/sudoers.d/90-lyona-install"
LYONA_CLEANUP_FILES+=("$install_sudoers")
rm -f -- "$install_sudoers"
install -m 0440 /dev/null "$install_sudoers"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$target_user" >"$install_sudoers"
LYONA_RECOVER_HINT="The base Arch system is installed on $TARGET, but lyona is not finished. Choose Retry to run the lyona install again. Or reboot, log in as $target_user, and run ~/$checkout_rel/install.sh."

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

# install.sh's own warnings, from what it adds to the log.
log_mark=$(wc -l <"$LOG_FILE" 2>/dev/null || printf '0')
run_logged "Running install.sh --profile full as $target_user..." \
	arch-chroot "$TARGET" su - "$target_user" -c \
	"cd \"\$HOME/$checkout_rel\" && env LYONA_SOURCE=iso LYONA_COMMIT=$iso_commit ./install.sh --non-interactive --profile full --skip-topgrade"

rm -f -- "$install_sudoers"
tail -n "+$((log_mark + 1))" "$LOG_FILE" | sed 's/\x1b\[[0-9;]*m//g' |
	sed -n 's/^\[WARN\] /install.sh: /p' >>"$LYONA_WARNINGS" || :
# shellcheck disable=SC2034 # read by lyona-ui.sh's recovery menu
LYONA_RECOVER_HINT="lyona is installed on $TARGET. Only the last steps failed; after rebooting, log in as $target_user."

if ! run_logged "Building Topgrade as $target_user (this takes a few minutes)..." install_topgrade; then
	say --foreground "$COLOR_DANGER" -- "-> Topgrade was not installed; after logging in, run install-topgrade."
	note_warning 'Topgrade was not installed; after logging in, run install-topgrade.' >/dev/null
fi

arch-chroot "$TARGET" bash -c '
	find /usr/share/xsessions -mindepth 1 -maxdepth 1 -type f ! -name dwm.desktop -delete 2>/dev/null || true
	find /usr/share/wayland-sessions -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
	if systemctl -q list-unit-files lightdm.service >/dev/null 2>&1; then
		systemctl enable lightdm.service
	fi
	systemctl enable power-profiles-daemon.service 2>/dev/null || true
	systemctl set-default graphical.target
'

# The log, root-only, where it can be read after the reboot.
install -Dm600 "$LOG_FILE" "$TARGET/var/log/lyona-postinstall.log" 2>/dev/null || :

echo
if [[ -s $LYONA_WARNINGS ]]; then
	reboot_note="Read the notes below, then press Enter to reboot."
else
	reboot_note="Rebooting automatically in 15 seconds."
fi
say --border rounded --border-foreground $COLOR_OK --foreground $COLOR_OK --bold --padding "1 2" \
	"lyona installed into $TARGET for $target_user." \
	"$reboot_note"
echo
if [[ -s $LYONA_WARNINGS ]]; then
	say --foreground "$COLOR_DANGER" --bold "Not everything went as chosen:"
	while IFS= read -r warning; do
		say --foreground "$COLOR_DANGER" "  - $warning"
	done <"$LYONA_WARNINGS"
	say --foreground "$COLOR_DIM" "The full log is /var/log/lyona-postinstall.log on the new system (root only)."
	echo
fi
if [[ -e $NVIDIA_AUR_MARKER ]]; then
	say --foreground "$COLOR_ACCENT" \
		"The NVIDIA driver was built from the AUR: pacman -Syu does not update it. Update it with yay."
	echo
fi
# Not "remove it now": this live system may still be running from the medium,
# and pulling it out before the reboot crashed the reboot (Sync Sprint 16,
# found in a VM). The new disk comes first in the boot order archinstall sets.
say --foreground "$COLOR_DIM" \
	"Leave the install medium in until the screen goes dark. If the installer starts again instead of lyona, remove the medium and restart."

if [[ -s $LYONA_WARNINGS ]]; then
	read -r -p "Press Enter to reboot. " _ || :
else
	sleep 15
fi
systemctl reboot
