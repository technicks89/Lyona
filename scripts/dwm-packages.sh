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
	arch:aur-build)
		# What makepkg needs for an AUR build (yay-bin, the legacy NVIDIA
		# drivers): the image's postinstall installs these before building
		# as the new user (#339).
		printf '%s\n' base-devel git
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
			pciutils gum cosign xorg-xmessage
		dwm_packages "$family" appimage
		dwm_packages "$family" keyring
		dwm_packages "$family" update-indicator
		# Super+E's file manager and the panel's network status (#292): the
		# everyday desktop had neither before full.
		dwm_packages "$family" file-manager
		dwm_packages "$family" network
		;;
	arch:file-manager)
		printf '%s\n' \
			thunar gvfs gvfs-smb tumbler thunar-archive-plugin file-roller \
			xdg-user-dirs
		;;
	arch:browser)
		# A web browser, for SUPER+B and links from other programs (#240):
		# without one, dwm-default-apps open has nothing to open. A fresh
		# account gets it as its default (seed-default-apps.sh), and
		# dwm_install_package_profile leaves it out where the user's default
		# browser is another one already installed.
		printf '%s\n' firefox
		;;
	arch:appimage)
		# AppImages (#260): fuse2 runs the classic type-2 AppImages (libfuse.so.2;
		# fuse3 alone runs only the newer static-runtime ones), and
		# squashfs-tools' unsquashfs lets lyona-appimage read an AppImage's
		# launcher entry and icon without running it.
		printf '%s\n' fuse2 squashfs-tools
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
		printf '%s\n' rsync autorandr
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
		# Qt theming: qt6ct, one fixed package (#247). qt5ct, the other choice
		# the installer used to probe for, only themes Qt 5 applications.
		printf '%s\n' qt6ct
		;;
	arch:iso)
		# What the live medium itself runs, layered onto releng: the image's
		# whole package list (archiso/packages.x86_64). The desktop is not on it:
		# the new system downloads every package it installs, so the image's copy
		# was never used, and left out it is about 700 MB smaller (#229).
		# - plymouth: the boot splash over the `quiet splash` console;
		# - gum: the wizard's screens; jq: the credentials file;
		# - curl: the network check, the timezone and the CachyOS setup;
		# - openssl: the password hash; pciutils: lspci, for the GPU;
		# - reflector: ranks the mirrors in the user's country (#249). releng
		#   has it too; listed because the wizard depends on it.
		printf '%s\n' plymouth gum jq curl openssl pciutils reflector
		;;
	# The live medium's postinstall installs these onto the target by what it
	# detects (Sync Sprint 12 S12-15): a GPU driver, NetworkManager
	# and the QEMU/KVM guest tools. The NVIDIA DKMS driver also needs each
	# installed kernel's -headers, which the postinstall derives from the kernels.
	# Arch replaced nvidia and nvidia-dkms with the open kernel modules, which
	# support Turing (GTX 16xx, RTX 20xx) and newer; older cards need the
	# AUR-only nvidia-580xx and stay on nouveau.
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
		dwm_packages "$family" font-meslo
		;;
	arch:font-meslo)
		# The terminal, bar and shell font, MesloLGS Nerd Font, from the
		# repositories rather than a 112 MB release zip (#250).
		printf '%s\n' ttf-meslo-nerd
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
		dwm_packages "$family" browser
		dwm_packages "$family" media
		dwm_packages "$family" system-management
		dwm_packages "$family" screenshot-optional
		dwm_packages "$family" theme
		dwm_packages "$family" theme-gtk
		dwm_packages "$family" fonts
		dwm_packages "$family" shell
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
# absence degrades it but does not break the session. Compositor: Picom, part of
# the lyona desktop, whose window previews need it (#244); required when the
# desktop is installed (dwm_desktop_installed), optional in a core install.
dwm_command_tier() { # required|desktop|compositor
	case $1 in
	required) printf '%s\n' startx xrandr xset xsetroot xclip xdotool ;;
	desktop)
		printf '%s\n' quickshell feh maim xdg-open notify-send amixer brightnessctl \
			light-locker gsettings xprop jq bluetoothctl blueman-applet cosign
		;;
	compositor) printf '%s\n' picom ;;
	*) return 2 ;;
	esac
}

# Whether the lyona desktop, the managed Quickshell shell, is installed: then
# the compositor tier is required (#244).
dwm_desktop_installed() {
	command -v quickshell >/dev/null 2>&1
}

# dwm_collect_packages PROFILE...: every package of the profiles, once each and
# in order, less those the keep rules leave out: an installed Power Profiles
# provider, and a default browser other than Firefox. What the rules leave out
# is said on stderr.
dwm_collect_packages() {
	local profile package other_browser
	local -A queued=()

	for profile in "$@"; do
		while IFS= read -r package; do
			[[ -n $package ]] || continue
			[[ -z ${queued[$package]:-} ]] || continue
			queued[$package]=1
			if [[ $package == power-profiles-daemon ]] && dwm_power_profiles_provider_installed; then
				printf '%s\n' \
					'Retaining installed Power Profiles provider (ppd-service); skipping power-profiles-daemon.' >&2
				continue
			fi
			if [[ $package == firefox ]] && other_browser=$(dwm_other_default_browser); then
				printf 'Keeping the default browser (%s); skipping firefox.\n' "$other_browser" >&2
				continue
			fi
			printf '%s\n' "$package"
		done < <(dwm_packages "$DISTRO_FAMILY" "$profile")
	done
}

# Accepts one or more profiles and installs them as a single transaction.
dwm_install_package_profile() {
	local -a packages
	mapfile -t packages < <(dwm_collect_packages "$@")
	((${#packages[@]} > 0)) || return 0
	install_packages "${packages[@]}"
}

# dwm_install_batch [--noconfirm] REQUIRED OPTIONAL: the packages of the two
# named arrays, as one pacman -Syu --needed transaction (#247): one dependency
# resolution, one download that fills ParallelDownloads, one run of each hook,
# and the upgrade with the install, so never a partial upgrade.
#
# A transaction fails whole on "target not found", and nothing checks the
# repositories beforehand any more (make check-aur-policy does, before a
# release). So when targets are not found, and none of them is in REQUIRED, it
# retries once without them; their names are left in DWM_BATCH_SKIPPED for the
# caller to warn about. A required one missing fails it, before anything is
# installed. --noconfirm is for a non-interactive run.
DWM_BATCH_SKIPPED=()
dwm_install_batch() {
	local noconfirm=false
	if [[ ${1:-} == --noconfirm ]]; then
		noconfirm=true
		shift
	fi
	local -n dwm_batch_required=$1 dwm_batch_optional=$2
	local -a pacman_command packages not_found kept
	local -A is_required=() queued=()
	local package errors status=0 required_missing=false

	DWM_BATCH_SKIPPED=()
	for package in "${dwm_batch_required[@]}"; do
		is_required[$package]=1
	done
	for package in "${dwm_batch_required[@]}" "${dwm_batch_optional[@]}"; do
		[[ -n $package && -z ${queued[$package]:-} ]] || continue
		queued[$package]=1
		packages+=("$package")
	done
	((${#packages[@]} > 0)) || return 0

	# In the C locale, so "target not found" below is pacman's English message
	# whatever the user's language. Through env, after sudo: sudo's policy can
	# refuse a variable set on its own command line.
	pacman_command=(env LC_ALL=C pacman -Syu --needed)
	! $noconfirm || pacman_command+=(--noconfirm)
	((EUID == 0)) || pacman_command=(sudo "${pacman_command[@]}")
	errors=$(mktemp) || return 1
	# pacman's errors are shown as they come and kept, to read the missing
	# targets from; its output and prompts stay on the terminal (fd 3). The
	# status goes through a file: the pipe's own is tee's.
	{
		{
			"${pacman_command[@]}" -- "${packages[@]}" 2>&1 1>&3 3>&- && status=0 || status=$?
			printf '%s\n' "$status" >"$errors.status"
		} | tee "$errors" >&2
	} 3>&1
	status=$(cat "$errors.status" 2>/dev/null) || status=1
	mapfile -t not_found < <(sed -n 's/^error: target not found: //p' "$errors" | sort -u)
	rm -f -- "$errors" "$errors.status"
	((status != 0)) || return 0
	((${#not_found[@]} > 0)) || return "$status"

	for package in "${not_found[@]}"; do
		if [[ -n ${is_required[$package]:-} ]]; then
			printf 'A required package is not in the enabled repositories: %s\n' "$package" >&2
			required_missing=true
		fi
	done
	! $required_missing || return 1

	# shellcheck disable=SC2034 # read by the callers
	DWM_BATCH_SKIPPED=("${not_found[@]}")
	for package in "${packages[@]}"; do
		[[ " ${not_found[*]} " == *" $package "* ]] || kept+=("$package")
	done
	printf 'Not in the enabled repositories, so left out: %s. Retrying once without them.\n' "${not_found[*]}" >&2
	((${#kept[@]} > 0)) || return 0
	"${pacman_command[@]}" -- "${kept[@]}"
}

# dwm_repair_qt_set [--noconfirm]: the installed Qt 6 modules all from one Qt
# release. The CachyOS repositories, ahead of Arch's in pacman.conf, can publish
# part of a Qt release before the rest (2026-10-07: qt6-declarative 6.12.0 with
# qt6-base 6.11.2). The dependencies name no versions, so pacman installs the mix,
# and nothing built on QML starts, Quickshell included. Arch publishes each Qt
# release whole, so on a mix the modules are installed again from [extra]; a
# later update brings CachyOS's builds back once theirs is newer. The modules are
# the installed qt6-* packages whose [extra] version is qt6-base's release there.
# Nothing is installed when they already match. The modules installed again are
# left in DWM_QT_REPAIRED. It fails when pacman cannot list the installed
# packages or [extra], as when the install fails.
DWM_QT_REPAIRED=()
dwm_repair_qt_set() {
	local noconfirm=false
	if [[ ${1:-} == --noconfirm ]]; then
		noconfirm=true
		shift
	fi
	local name version base_release mixed=false base=qt6-base listing
	local -A installed=() arch_release=()
	local -a modules=() mix=() pacman_command

	DWM_QT_REPAIRED=()
	# Either listing failing is an error, not an empty list: the check could
	# not be made.
	listing=$(LC_ALL=C pacman -Q 2>/dev/null) || return
	# The Qt release of a pacman version, less any epoch and the package
	# release: 1:6.12.0-2.1 is 6.12.0.
	while read -r name version; do
		[[ $name == qt6-* ]] || continue
		version=${version#*:}
		installed[$name]=${version%-*}
	done <<<"$listing"
	[[ -n ${installed[$base]:-} ]] || return 0
	listing=$(LC_ALL=C pacman -Sl extra 2>/dev/null) || return
	while read -r _ name version _; do
		[[ $name == qt6-* ]] || continue
		version=${version#*:}
		arch_release[$name]=${version%-*}
	done <<<"$listing"
	base_release=${arch_release[$base]:-}
	[[ -n $base_release ]] || return 0

	for name in "${!installed[@]}"; do
		[[ ${arch_release[$name]:-} == "$base_release" ]] || continue
		modules+=("$name")
		if [[ ${installed[$name]} != "${installed[$base]}" ]]; then
			mixed=true
			mix+=("$name ${installed[$name]}")
		fi
	done
	$mixed || return 0

	mapfile -t modules < <(printf '%s\n' "${modules[@]}" | sort)
	mapfile -t mix < <(printf '%s\n' "${mix[@]}" | sort)
	printf 'The installed Qt modules are from different Qt releases (qt6-base %s; %s): the CachyOS repositories are part way through a Qt update. Installing Arch'"'"'s Qt %s instead.\n' \
		"${installed[$base]}" "$(printf '%s, ' "${mix[@]}" | sed 's/, $//')" "$base_release" >&2
	pacman_command=(env LC_ALL=C pacman -S --needed)
	! $noconfirm || pacman_command+=(--noconfirm)
	((EUID == 0)) || pacman_command=(sudo "${pacman_command[@]}")
	"${pacman_command[@]}" -- "${modules[@]/#/extra/}" || return
	# shellcheck disable=SC2034 # read by the callers
	DWM_QT_REPAIRED=("${modules[@]}")
}

# The user's default browser, by desktop ID, when it is installed and is not
# Firefox: the https handler xdg-mime reports, found as a desktop entry in the
# XDG data directories whose program (TryExec, else Exec) is installed. A
# leftover entry for a removed browser does not count. Nothing is printed, and
# it fails, otherwise.
dwm_other_default_browser() {
	# All four are set by lyona_xdg_dirs; only data_home is read.
	# shellcheck disable=SC2034
	local id dir config_home data_home state_home cache_home
	local -a dirs
	command -v xdg-mime >/dev/null 2>&1 || return 1
	id=$(xdg-mime query default x-scheme-handler/https 2>/dev/null) || return 1
	[[ $id == *.desktop && $id != */* && $id != firefox.desktop ]] || return 1
	# dwm-xdg.sh is beside this file, in a checkout and in an install alike.
	# Not followed: its directories are locals here, and following it would
	# make shellcheck track them in every script that sources this one.
	if ! declare -F lyona_xdg_dirs >/dev/null; then
		# shellcheck source=/dev/null
		. "${BASH_SOURCE[0]%/*}/dwm-xdg.sh" || return 1
	fi
	lyona_xdg_dirs lenient
	IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
	for dir in "$data_home" "${dirs[@]}"; do
		[[ -n $dir && -f $dir/applications/$id ]] || continue
		# The first entry found is the one used, as in xdg-open.
		dwm_desktop_entry_runnable "$dir/applications/$id" || return 1
		printf '%s\n' "$id"
		return 0
	done
	return 1
}

# Whether a desktop entry's program is installed: its TryExec, else the first
# word of its Exec, found on PATH (or as an absolute path).
dwm_desktop_entry_runnable() { # FILE
	local program try
	# Through the shared reader (#308), sourced from beside this file.
	if ! declare -F desktop_entry_get >/dev/null; then
		# shellcheck source=scripts/dwm-desktop-entry.sh
		. "${BASH_SOURCE[0]%/*}/dwm-desktop-entry.sh" || return 1
	fi
	program=$(desktop_entry_get "$1" Exec) || program=
	try=$(desktop_entry_get "$1" TryExec) || try=
	[[ -z $try ]] || program=$try
	program=${program%% *}
	program=${program#\"}
	program=${program%\"}
	[[ -n $program ]] && command -v -- "$program" >/dev/null 2>&1
}

dwm_power_profiles_provider_installed() {
	command -v pacman >/dev/null 2>&1 &&
		pacman -Qq power-profiles-daemon >/dev/null 2>&1
}

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
