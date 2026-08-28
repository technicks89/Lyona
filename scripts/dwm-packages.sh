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
	arch:desktop)
		printf '%s\n' \
			quickshell picom feh dex mate-polkit \
			alsa-utils brightnessctl inotify-tools jq libpulse pipewire pavucontrol \
			pipewire-pulse wireplumber libnotify light-locker xf86-input-libinput \
			bluez bluez-utils blueman playerctl upower power-profiles-daemon flatpak xdg-desktop-portal-gtk \
			pciutils gum
		;;
	arch:desktop-optional)
		printf '%s\n' \
			thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs gnome-keyring networkmanager \
			rsync
		;;
	arch:gaming)
		if [[ ${ARCH:-$(uname -m)} == x86_64 ]]; then
			printf '%s\n' \
				steam gamescope gamemode lib32-gamemode \
				mangohud lib32-mangohud
		fi
		;;
	arch:theme)
		printf '%s\n' dconf
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
		dwm_packages "$family" screenshot-optional
		dwm_packages "$family" theme
		dwm_packages "$family" theme-gtk
		dwm_packages "$family" fonts
		dwm_packages "$family" shell
		;;
	arch:optional)
		dwm_packages "$family" theme-optional
		dwm_packages "$family" desktop-optional
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
dwm_install_package_profile() {
	local profile
	local packages=()
	local package
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

# Installs whatever of the profile is actually available, as one transaction:
# a single availability query for the whole profile, then a single install.
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
