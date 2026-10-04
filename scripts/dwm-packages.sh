#!/usr/bin/env bash

dwm_packages() {
	local family=$1
	local profile=$2

	case "$family:$profile" in
	arch:build)
		printf '%s\n' \
			gcc make pkgconf base-devel libx11 libxft \
			libxinerama libxrender imlib2 libxcb \
			xcb-util freetype2 fontconfig
		;;
	arch:x11)
		printf '%s\n' xorg-server xorg-xinit xorg-xrandr xorg-xrdb xorg-xset xorg-xsetroot xorg-xinput xorg-setxkbmap xsettingsd
		;;
	arch:runtime-required)
		printf '%s\n' dbus curl git procps-ng psmisc unzip util-linux xclip xdotool xorg-xprop xdg-utils
		;;
	arch:ci-smoke)
		# The hosted CI smoke job: build dwm, then start the real managed
		# Quickshell shell against it in a private Xvfb+dbus session and
		# exercise the launcher. Kept separate from `required` because
		# nothing outside this one CI job needs xorg-server-xvfb or a
		# desktop Quickshell on a build-only host.
		dwm_packages "$family" required
		dwm_packages "$family" fonts
		printf '%s\n' quickshell xorg-server-xvfb inotify-tools jq
		;;
	arch:ci-tools)
		# What the full-suite CI job needs beyond the desktop: linters, the
		# ISO builder, and the Xvfb/dbus/X11 tools the acceptance tests drive.
		printf '%s\n' shellcheck shfmt archiso python-dbus python-pillow \
			xorg-server-xvfb xorg-xauth xdotool dbus inotify-tools jq
		;;
	arch:ci-full)
		# Everything the full-suite workflow installs, and what
		# scripts/ci-local.sh installs into its image: one definition, so the
		# two cannot drift (tests/test-ci-parity.sh).
		dwm_packages "$family" full
		dwm_packages "$family" ci-smoke
		dwm_packages "$family" qml-validation
		dwm_packages "$family" ci-tools
		;;
	arch:desktop)
		printf '%s\n' \
			quickshell picom python feh dex mate-polkit \
			alsa-utils brightnessctl inotify-tools jq libpulse pipewire pavucontrol \
			pipewire-pulse wireplumber libnotify light-locker xf86-input-libinput \
			bluez bluez-utils blueman playerctl upower power-profiles-daemon flatpak xdg-desktop-portal-gtk \
			pciutils gum cosign
		dwm_packages "$family" keyring
		dwm_packages "$family" update-indicator
		;;
	arch:keyring)
		# Secret storage, and the login keyring's unlock at a password login.
		# pam_gnome_keyring.so ships in gnome-keyring itself (Arch has no
		# separate PAM package), and the display manager's PAM stack loads it
		# (Sync Sprint 15 S15-01; in desktop by decision D-24).
		printf '%s\n' gnome-keyring
		;;
	arch:update-indicator)
		# checkupdates, which the panel's update indicator counts package
		# updates with: it syncs a private copy of the package databases and
		# never takes pacman's lock. Its fakeroot comes from base-devel, in
		# build (Sync Sprint 15 S15-02).
		printf '%s\n' pacman-contrib
		;;
	arch:desktop-optional)
		# Every package here is in the official repositories (the AUR is
		# limited to the uses docs/AUR-PACKAGES.md lists, enforced by
		# check-aur-policy). The XKB
		# AccessX controls (sticky/slow/bounce/mouse keys) used to need the
		# AUR-only xkbset; they are now served by the in-tree
		# scripts/dwm-xkbset.
		printf '%s\n' \
			thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs networkmanager \
			rsync autorandr
		;;
	arch:system-management)
		# PackageKit on Arch is a first-class alpm frontend: the `packagekit`
		# package depends on `pacman` and `libalpm.so` and ships
		# `usr/lib/packagekit-backend/libpk_backend_alpm.so`. python-gobject
		# supplies gi.repository.Gio/GLib and the PackageKitGlib typelib comes
		# from libpackagekit-glib, which `packagekit` already depends on.
		printf '%s\n' \
			python python-gobject packagekit accountsservice cups
		;;
	arch:system-management-optional)
		# Delegated administration targets. Each one missing disables only its
		# own `*-open` action; readable state is unaffected.
		# arch-audit adds CVE severity that the alpm sync database does not
		# carry; it needs the network and does not cover CachyOS packages.
		printf '%s\n' \
			system-config-printer arch-audit
		;;
	arch:gaming)
		if [[ ${ARCH:-$(uname -m)} == x86_64 ]]; then
			printf '%s\n' \
				steam gamescope gamemode lib32-gamemode \
				mangohud lib32-mangohud
		fi
		;;
	arch:theme)
		# The icon themes give every GTK application icons on a fresh install
		# (upstream #301); theme-apply.sh selects between them.
		printf '%s\n' dconf adwaita-icon-theme papirus-icon-theme
		;;
	arch:theme-gtk)
		printf '%s\n' \
			adw-gtk-theme deepin-gtk-theme
		;;
	arch:theme-optional)
		printf '%s\n' qt6ct qt5ct
		;;
	arch:iso)
		# Only the live medium needs these. plymouth draws the boot splash over
		# the `quiet splash` console the ISO boots with; an installed system has
		# no splash configured, and the package pulls in ~13 MiB of cairo, pango
		# and fonts that nothing else here uses.
		printf '%s\n' plymouth
		;;
	# The live medium's postinstall installs these onto the target by what it
	# detects (Sync Sprint 12 S12-15): CPU microcode, a GPU driver, NetworkManager
	# and the QEMU/KVM guest tools. The NVIDIA DKMS driver also needs each
	# installed kernel's -headers, which the postinstall derives from the kernels.
	# Arch replaced nvidia and nvidia-dkms with the open kernel modules, which
	# support Turing (GTX 16xx, RTX 20xx) and newer; older cards need the
	# AUR-only nvidia-580xx and stay on nouveau.
	arch:microcode-intel)
		printf '%s\n' intel-ucode
		;;
	arch:microcode-amd)
		printf '%s\n' amd-ucode
		;;
	arch:gpu-nvidia)
		printf '%s\n' nvidia-open nvidia-utils
		;;
	arch:gpu-nvidia-dkms)
		printf '%s\n' nvidia-open-dkms nvidia-utils
		;;
	# The legacy drivers for older cards (Sync Sprint 14, decision D-23): from the
	# CachyOS repository when the medium added it, else built from pinned AUR
	# PKGBUILDs (a listed AUR use; docs/AUR-PACKAGES.md). DKMS only.
	arch:gpu-nvidia-580xx)
		printf '%s\n' nvidia-580xx-dkms nvidia-580xx-utils
		;;
	arch:gpu-nvidia-470xx)
		printf '%s\n' nvidia-470xx-dkms nvidia-470xx-utils
		;;
	arch:gpu-amd)
		printf '%s\n' xf86-video-amdgpu
		;;
	arch:gpu-intel)
		printf '%s\n' mesa vulkan-intel libva-intel-driver
		;;
	arch:network)
		printf '%s\n' networkmanager
		;;
	arch:vm-guest)
		printf '%s\n' virtiofsd qemu-guest-agent spice-vdagent qemu-hw-display-virtio-vga
		;;
	# What scripts/install-mybash checks for and installs before it clones the
	# configuration (S12-15); install.sh installs arch:shell first.
	arch:mybash-bootstrap)
		printf '%s\n' bash bash-completion tar bat tree unzip fontconfig git fzf
		;;
	arch:xscreensaver)
		printf '%s\n' xscreensaver
		;;
	arch:rust-toolchain)
		# rustup, for cargo: Topgrade is built with it (Sync Sprint 15 S15-06,
		# decision D-28), as it is AUR-only. rustup conflicts with Arch's
		# rust and cargo packages, so dwm_install_package_profile leaves it out
		# when another Rust toolchain is installed (dwm_other_rust_toolchain).
		printf '%s\n' rustup
		;;
	arch:shell)
		# The interactive shell configuration from technicks89/mybash. Its own
		# setup.sh pipes an installer from starship.rs and pulls an unpinned
		# Nerd Font archive; both come from the repositories here instead, and
		# the font we already ship covers the glyphs its prompt uses.
		#
		# starship, zoxide and fastfetch are what the configuration is for:
		# its .bashrc guards each behind command -v, so a missing one is not
		# an error -- it silently leaves you with a stock bash prompt and no
		# fetch, which is the feature simply not working. The rest back its
		# aliases.
		printf '%s\n' \
			starship zoxide fzf fastfetch \
			bat tree trash-cli bash-completion
		;;
	arch:fonts)
		printf '%s\n' noto-fonts-emoji noto-fonts
		;;
	arch:qml-development)
		printf '%s\n' qt6-declarative
		;;
	arch:qml-validation)
		printf '%s\n' quickshell
		dwm_packages "$family" qml-development
		;;
	arch:lightdm)
		printf '%s\n' lightdm lightdm-slick-greeter
		;;
	arch:terminal)
		printf '%s\n' alacritty kitty
		;;
	arch:terminal-primary)
		printf '%s\n' alacritty
		;;
	arch:media)
		# Fresh-install media and image defaults (upstream #308): Celluloid
		# plays audio and video, sxiv views images, and desktop-file-utils
		# keeps the desktop database current. seed-default-apps.sh makes them
		# the handlers on a new account. nsxiv is the maintained fork, but
		# #308 names sxiv, so this keeps parity.
		printf '%s\n' celluloid mpv sxiv desktop-file-utils
		;;
	arch:screenshot-optional)
		printf '%s\n' maim
		;;
	arch:required)
		dwm_packages "$family" build
		dwm_packages "$family" x11
		dwm_packages "$family" runtime-required
		;;
	arch:recommended)
		dwm_packages "$family" desktop
		dwm_packages "$family" media
		dwm_packages "$family" system-management
		dwm_packages "$family" screenshot-optional
		dwm_packages "$family" theme
		dwm_packages "$family" theme-gtk
		dwm_packages "$family" fonts
		dwm_packages "$family" shell
		dwm_packages "$family" rust-toolchain
		;;
	arch:optional)
		dwm_packages "$family" theme-optional
		dwm_packages "$family" desktop-optional
		dwm_packages "$family" system-management-optional
		;;
	arch:full)
		dwm_packages "$family" required
		dwm_packages "$family" recommended
		dwm_packages "$family" optional
		dwm_packages "$family" gaming
		;;
	*)
		return 1
		;;
	esac
}

# Accepts one or more profiles and installs them as a single transaction.
# The commands check-deps.sh and dwm-diagnostics check, by tier, so the two
# agree (Sync Sprint 16 R16-45; SPEC 5.8). Required: the X11 session and the
# tools core keybindings need, beside the build tools and a terminal, which
# both check on their own. Desktop: the recommended desktop's commands, whose
# absence degrades it but does not break the session.
dwm_command_tier() { # required|desktop
	case $1 in
	required) printf '%s\n' startx xrandr xset xsetroot xclip xdotool ;;
	desktop)
		printf '%s\n' quickshell picom feh maim xdg-open notify-send amixer brightnessctl \
			light-locker gsettings xprop jq bluetoothctl blueman-applet cosign
		;;
	*) return 2 ;;
	esac
}

dwm_install_package_profile() {
	local profile
	local packages=()
	local package other_rust
	local -A queued=()

	for profile in "$@"; do
		while IFS= read -r package; do
			[[ -n $package ]] || continue
			[[ -z ${queued[$package]:-} ]] || continue
			if [[ $package == power-profiles-daemon ]] && dwm_power_profiles_provider_installed; then
				printf '%s\n' \
					'Retaining installed Power Profiles provider (ppd-service); skipping power-profiles-daemon.' >&2
				continue
			fi
			if [[ $package == rustup ]] && other_rust=$(dwm_other_rust_toolchain); then
				printf 'Keeping the installed Rust toolchain (%s); skipping rustup.\n' "$other_rust" >&2
				continue
			fi
			queued[$package]=1
			packages+=("$package")
		done < <(dwm_packages "$DISTRO_FAMILY" "$profile")
	done

	if ((${#packages[@]} == 0)); then
		return 0
	fi

	install_packages "${packages[@]}"
}

dwm_power_profiles_provider_installed() {
	command -v pacman >/dev/null 2>&1 &&
		pacman -Qq power-profiles-daemon >/dev/null 2>&1
}

# A Rust toolchain other than Arch's rustup package, by name, when one is
# installed (Sync Sprint 15 S15-06, decision D-28): Arch's rust, any other
# package providing rust or cargo (pacman -Qq resolves provides, so it prints
# the provider, such as rust-nightly-bin), or a cargo from rustup.rs on PATH.
# rustup conflicts with those packages, and would only duplicate the other, so
# the rust-toolchain profile is skipped and that toolchain's cargo is used.
dwm_other_rust_toolchain() {
	local name provider cargo
	if command -v pacman >/dev/null 2>&1; then
		for name in rust cargo; do
			provider=$(pacman -Qq "$name" 2>/dev/null) || continue
			provider=${provider%%$'\n'*}
			[[ $provider != rustup ]] || return 1
			printf '%s\n' "$provider"
			return 0
		done
	fi
	cargo=$(command -v cargo 2>/dev/null) || return 1
	printf '%s\n' "$cargo"
}

# Installs whatever of the profile is actually available, as one transaction:
# a single availability query for the whole profile, then a single install.
# The Vulkan drivers for this machine's GPUs, 64- and 32-bit: Steam depends on
# the virtual vulkan-driver and lib32-vulkan-driver, and with --noconfirm pacman
# takes the first provider listed. With the CachyOS repositories that was
# mesa-git, which conflicts with mesa, so the gaming install failed (Sync Sprint
# 16, found in a VM). Installed first, these meet both dependencies. NVIDIA: the
# installed driver branch's utilities, else nouveau's; no known GPU (a VM, say):
# the software rasterizer.
dwm_vulkan_driver_packages() {
	local gpus driver
	local -a packages=()
	gpus=$(lspci 2>/dev/null | grep -E 'VGA|3D|Display' || true)
	# Not "ATI": case-insensitively, that matches "Corporation".
	if grep -qE 'AMD|Radeon' <<<"$gpus"; then
		packages+=(vulkan-radeon lib32-vulkan-radeon)
	fi
	if grep -qi 'Intel' <<<"$gpus"; then
		packages+=(vulkan-intel lib32-vulkan-intel)
	fi
	if grep -qiE 'NVIDIA|GeForce' <<<"$gpus"; then
		driver=$(pacman -Qq 2>/dev/null | grep -Ex 'nvidia(-[0-9]+xx)?-utils' | head -n 1 || true)
		if [[ -n $driver ]]; then
			packages+=("$driver" "lib32-$driver")
		else
			packages+=(vulkan-nouveau lib32-vulkan-nouveau)
		fi
	fi
	((${#packages[@]} > 0)) || packages=(vulkan-swrast lib32-vulkan-swrast)
	printf '%s\n' "${packages[@]}"
}

dwm_install_available_package_profile() {
	local profile=$1
	local package
	local status=0
	local wanted=()
	local install=()
	local found=()
	local -A have=()

	while IFS= read -r package; do
		[[ -n $package ]] || continue
		wanted+=("$package")
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	if ((${#wanted[@]} == 0)); then
		return 0
	fi

	mapfile -t found < <(available_packages "${wanted[@]}")
	for package in "${found[@]}"; do
		have[$package]=1
	done

	for package in "${wanted[@]}"; do
		if [[ -n ${have[$package]:-} ]]; then
			install+=("$package")
			continue
		fi
		printf 'Optional package is unavailable in enabled repositories: %s\n' "$package" >&2
		printf 'Skipping unavailable optional package: %s\n' "$package" >&2
		status=1
	done

	if ((${#install[@]} > 0)); then
		install_packages "${install[@]}" || status=1
	fi

	return "$status"
}

dwm_install_first_available_package() {
	local package

	for package in "$@"; do
		if install_optional_package "$package" 2>/dev/null; then
			return 0
		fi
	done

	return 1
}

dwm_install_first_available_profile() {
	local profile=$1
	local packages=()
	local package

	while IFS= read -r package; do
		[[ -n $package ]] && packages+=("$package")
	done < <(dwm_packages "$DISTRO_FAMILY" "$profile")

	if ((${#packages[@]} == 0)); then
		return 1
	fi

	dwm_install_first_available_package "${packages[@]}"
}
