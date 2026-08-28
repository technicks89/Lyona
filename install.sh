#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/dwm-utils.sh
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/dwm-utils.sh"
# shellcheck source=scripts/dwm-packages.sh
# shellcheck disable=SC1091
source "$REPO_DIR/scripts/dwm-packages.sh"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' CYAN='\033[0;36m' NC='\033[0m'
info() { printf "${CYAN}[INFO]${NC} %s\n" "$1"; }
ok() { printf "${GREEN}[OK]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
err() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

usage() {
	cat <<EOF
Usage: ./install.sh [options]

Options:
  --profile PROFILE      Install profile: core, recommended, or full.
                         Defaults to DWM_INSTALL_PROFILE or full.
  --non-interactive      Use unattended defaults and do not prompt.
  --yes                  Accept the interactive install summary.
  --install-herdr        Install verified Herdr as an optional workspace.
  --skip-herdr           Do not install Herdr.
  --enable-arch-gaming-repos
                         Approve enabling the multilib repository for gaming.
  --enable-cachyos-repos Add the CachyOS repositories for this CPU, replacing
                         pacman with the CachyOS build and upgrading the system
                         to the optimized packages.
  --cachyos-kernel       Install the linux-cachyos kernel and add a boot entry
                         for it. Implies --enable-cachyos-repos.
  --dry-run              Print the resolved plan and exit before changes.
  -h, --help             Show this help.
EOF
}

case "$DISTRO_FAMILY" in
arch)
	command -v pacman &>/dev/null || {
		err "Arch Linux was detected, but pacman was not found."
		exit 1
	}
	;;
*)
	err "Unsupported distribution: $DISTRO_NAME"
	err "lyona supports Arch Linux only."
	exit 1
	;;
esac

BG_DIR="$HOME/Pictures/backgrounds"
MESLO_VERSION="3.4.0"
MESLO_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${MESLO_VERSION}/Meslo.zip"
MESLO_SHA256="13b502ac8c2bd9d3161018064560e23cd42b175bb730780a270975265a19ad57"
ARCH="$(uname -m)"
YAY_BIN_URL="https://aur.archlinux.org/yay-bin.git"
INSTALL_PROFILE="${DWM_INSTALL_PROFILE:-full}"
HERDR_INSTALL_MODE="${DWM_INSTALL_HERDR:-false}"
NON_INTERACTIVE=false
ASSUME_YES=false
ARCH_GAMING_REPOS_APPROVED=false
CACHYOS_REPOS_APPROVED="${DWM_INSTALL_CACHYOS_REPOS:-false}"
CACHYOS_KERNEL_MODE="${DWM_INSTALL_CACHYOS_KERNEL:-false}"
CACHYOS_KERNEL=linux-cachyos
DRY_RUN=false

while (($# > 0)); do
	case "$1" in
	--profile)
		if (($# < 2)); then
			err "--profile requires a value."
			exit 1
		fi
		INSTALL_PROFILE=$2
		shift 2
		;;
	--profile=*)
		INSTALL_PROFILE=${1#*=}
		shift
		;;
	--non-interactive)
		NON_INTERACTIVE=true
		ASSUME_YES=true
		shift
		;;
	--yes)
		ASSUME_YES=true
		shift
		;;
	--install-herdr)
		HERDR_INSTALL_MODE=true
		shift
		;;
	--skip-herdr)
		HERDR_INSTALL_MODE=false
		shift
		;;
	--enable-arch-gaming-repos)
		ARCH_GAMING_REPOS_APPROVED=true
		shift
		;;
	--enable-cachyos-repos)
		CACHYOS_REPOS_APPROVED=true
		shift
		;;
	--cachyos-kernel)
		CACHYOS_KERNEL_MODE=true
		shift
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		err "Unknown option: $1"
		usage >&2
		exit 1
		;;
	esac
done

case "$INSTALL_PROFILE" in
core | minimal)
	INSTALL_PROFILE="core"
	;;
recommended | full) ;;
*)
	err "Unsupported DWM_INSTALL_PROFILE: $INSTALL_PROFILE"
	err "Supported profiles: core, recommended, full"
	exit 1
	;;
esac

case "$HERDR_INSTALL_MODE" in
auto)
	HERDR_INSTALL_MODE=false
	;;
1 | true | yes)
	HERDR_INSTALL_MODE=true
	;;
0 | false | no)
	HERDR_INSTALL_MODE=false
	;;
*)
	err "Unsupported DWM_INSTALL_HERDR: $HERDR_INSTALL_MODE"
	err "Supported values: auto, true, false"
	exit 1
	;;
esac

for cachyos_setting in CACHYOS_REPOS_APPROVED CACHYOS_KERNEL_MODE; do
	case "${!cachyos_setting}" in
	1 | true | yes)
		printf -v "$cachyos_setting" true
		;;
	0 | false | no)
		printf -v "$cachyos_setting" false
		;;
	*)
		err "Unsupported $cachyos_setting value: ${!cachyos_setting}"
		err "Supported values: true, false"
		exit 1
		;;
	esac
done
unset cachyos_setting

if [[ $CACHYOS_KERNEL_MODE == true ]]; then
	CACHYOS_REPOS_APPROVED=true
fi

if [[ ! -t 0 || ! -t 1 ]]; then
	NON_INTERACTIVE=true
	ASSUME_YES=true
fi

if [[ $EUID -eq 0 && $DRY_RUN != true ]]; then
	err "Run this installer as a normal user. It invokes sudo only when needed."
	exit 1
fi

install_recommended_profile() {
	[[ $INSTALL_PROFILE == "recommended" || $INSTALL_PROFILE == "full" ]]
}

install_optional_profile() {
	[[ $INSTALL_PROFILE == "full" ]]
}

herdr_arch_supported() {
	case $ARCH in
	x86_64 | amd64 | aarch64 | arm64)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

install_herdr_profile() {
	[[ $HERDR_INSTALL_MODE == true ]] && herdr_arch_supported
}

arch_gaming_profile() {
	[[ $DISTRO_ID == "arch" && $INSTALL_PROFILE == "full" && $ARCH == "x86_64" ]]
}

arch_multilib_enabled() {
	pacman-conf --repo-list 2>/dev/null | command grep -Fxq multilib
}

cachyos_supported() {
	[[ $DISTRO_ID == "arch" && $ARCH == "x86_64" ]]
}

cachyos_repos_configured() {
	"$REPO_DIR/scripts/lyona-cachyos" status 2>/dev/null |
		command grep -Fxq 'cachyos-repos: configured'
}

confirm_cachyos_setup() {
	local answer

	cachyos_supported || {
		if [[ $CACHYOS_REPOS_APPROVED == true ]]; then
			warn "The CachyOS repositories are x86_64 Arch only; skipping them."
			CACHYOS_REPOS_APPROVED=false
			CACHYOS_KERNEL_MODE=false
		fi
		return
	}
	if cachyos_repos_configured; then
		CACHYOS_REPOS_APPROVED=true
	fi
	if [[ $NON_INTERACTIVE == true || $DRY_RUN == true ]]; then
		return
	fi

	if [[ $CACHYOS_REPOS_APPROVED != true ]]; then
		printf 'Add the CachyOS repositories? This adds third-party repositories, replaces\n'
		printf 'pacman with the CachyOS build, and upgrades the system to the optimized\n'
		printf 'packages for this CPU. [y/N] '
		read -r answer
		case "$answer" in
		y | Y | yes | YES)
			CACHYOS_REPOS_APPROVED=true
			;;
		*)
			info "Continuing with the stock Arch repositories."
			return
			;;
		esac
	fi

	if [[ $CACHYOS_KERNEL_MODE != true ]]; then
		printf 'Install the %s kernel and add a boot entry for it? [y/N] ' "$CACHYOS_KERNEL"
		read -r answer
		case "$answer" in
		y | Y | yes | YES)
			CACHYOS_KERNEL_MODE=true
			;;
		esac
	fi
}

setup_cachyos() {
	[[ $CACHYOS_REPOS_APPROVED == true ]] || return 0
	cachyos_supported || return 0

	if [[ $NON_INTERACTIVE == true ]]; then
		export LYONA_CACHYOS_NONINTERACTIVE=1
	fi

	info "Configuring the CachyOS repositories..."
	if ! "$REPO_DIR/scripts/lyona-cachyos" add-repos; then
		warn "CachyOS repository setup failed; continuing with the stock repositories."
		return 0
	fi
	ok "CachyOS repositories configured."

	if [[ $CACHYOS_KERNEL_MODE != true ]]; then
		return 0
	fi
	info "Installing the $CACHYOS_KERNEL kernel..."
	if ! "$REPO_DIR/scripts/lyona-cachyos" install-kernel "$CACHYOS_KERNEL"; then
		warn "The $CACHYOS_KERNEL kernel could not be installed."
		return 0
	fi
	ok "$CACHYOS_KERNEL installed."
}

confirm_arch_multilib_repository() {
	local answer

	if ! arch_gaming_profile || [[ $ARCH_GAMING_REPOS_APPROVED == true ]]; then
		return
	fi
	if arch_multilib_enabled; then
		ARCH_GAMING_REPOS_APPROVED=true
		return
	fi
	if [[ $NON_INTERACTIVE == true ]]; then
		warn "Skipping Arch gaming packages because the multilib repository was not approved."
		warn "Re-run with --enable-arch-gaming-repos to approve enabling [multilib]."
		return
	fi

	printf 'Enable the [multilib] repository for Steam, Gamescope, GameMode, and MangoHud? [y/N] '
	read -r answer
	case "$answer" in
	y | Y | yes | YES)
		ARCH_GAMING_REPOS_APPROVED=true
		;;
	*)
		warn "Multilib repository declined; skipping Steam, Gamescope, GameMode, and MangoHud."
		;;
	esac
}

configure_arch_multilib_repository() {
	local pacman_conf="/etc/pacman.conf"

	if [[ $DISTRO_ID != "arch" || $INSTALL_PROFILE != "full" || $ARCH != "x86_64" ]]; then
		return 1
	fi
	if [[ $ARCH_GAMING_REPOS_APPROVED != true ]]; then
		return 1
	fi

	if arch_multilib_enabled; then
		ok "The multilib repository is already enabled."
		return 0
	fi

	if [[ ! -f $pacman_conf ]]; then
		warn "pacman.conf not found; cannot enable the multilib repository."
		return 1
	fi

	info "Enabling the multilib repository..."
	if ! sudo sed -i \
		-e '/^#\[multilib\]/,/^#Include/ s/^#//' \
		"$pacman_conf"; then
		warn "Could not enable the multilib repository; skipping Arch gaming packages."
		return 1
	fi
	if ! arch_multilib_enabled; then
		warn "multilib section not found in pacman.conf; skipping Arch gaming packages."
		return 1
	fi
	if ! sudo pacman -Sy; then
		warn "Could not refresh pacman databases after enabling multilib."
		return 1
	fi
}

configure_arch_gamemode_access() {
	local target_user

	if [[ $DISTRO_ID != "arch" || $INSTALL_PROFILE != "full" ]]; then
		return
	fi
	if ! getent group gamemode >/dev/null 2>&1; then
		warn "GameMode was not installed; skipping privileged tuning access."
		return
	fi

	target_user=$(id -un)
	if id -nG "$target_user" | tr ' ' '\n' | command grep -Fxq gamemode; then
		ok "$target_user already has GameMode tuning access."
		return
	fi

	info "Adding $target_user to the gamemode group..."
	sudo usermod -aG gamemode "$target_user"
	warn "Log out and back in before using GameMode privileged tuning."
}

ensure_yay_installed() {
	local tmp_dir

	if command -v yay &>/dev/null || command -v paru &>/dev/null; then
		ok "An AUR helper is already installed."
		return 0
	fi
	if ! command -v git &>/dev/null || ! command -v makepkg &>/dev/null; then
		warn "git or makepkg is unavailable; skipping yay installation."
		return 1
	fi

	info "Installing yay as a standing AUR helper..."
	tmp_dir="$(mktemp -d)"
	if ! git clone --depth 1 "$YAY_BIN_URL" "$tmp_dir/yay-bin" 2>/dev/null; then
		rm -rf "$tmp_dir"
		warn "Could not download yay; continuing without an AUR helper."
		return 1
	fi
	if ! (cd "$tmp_dir/yay-bin" && makepkg -si --noconfirm); then
		rm -rf "$tmp_dir"
		warn "yay build failed; continuing without an AUR helper."
		return 1
	fi
	rm -rf "$tmp_dir"
	ok "yay installed."
}

package_line() {
	local profile=$1

	dwm_packages "$DISTRO_FAMILY" "$profile" | paste -sd ' ' -
}

print_summary_profile() {
	local label=$1
	local profile=$2
	local packages

	packages="$(package_line "$profile")"
	if [[ -n $packages ]]; then
		printf '  %s: %s\n' "$label" "$packages"
	else
		printf '  %s: none\n' "$label"
	fi
}

print_install_summary() {
	echo ""
	echo "Installation summary:"
	printf '  Distribution: %s\n' "$DISTRO_NAME"
	printf '  Family: %s\n' "$DISTRO_FAMILY"
	printf '  Package manager: %s\n' "$PKG_CMD"
	printf '  Profile: %s\n' "$INSTALL_PROFILE"
	printf '  Mode: %s\n' "$([[ $NON_INTERACTIVE == true ]] && echo non-interactive || echo interactive)"
	print_summary_profile "Required packages" required
	if install_recommended_profile; then
		print_summary_profile "Recommended packages" recommended
		printf '  Gear Lever: user-scoped Flathub install (%s)\n' 'it.mijorus.gearlever'
	else
		printf '  Recommended packages: skipped\n'
	fi
	if install_optional_profile; then
		print_summary_profile "Optional extras" optional
		if arch_gaming_profile; then
			print_summary_profile "Arch gaming packages" gaming
			if [[ $ARCH_GAMING_REPOS_APPROVED == true ]]; then
				printf '  Third-party repositories: approved\n'
			elif arch_multilib_enabled; then
				printf '  Third-party repositories: [multilib] already enabled\n'
			else
				printf '  Third-party repositories: require separate confirmation\n'
			fi
		fi
	else
		printf '  Optional extras: skipped\n'
	fi
	if cachyos_supported; then
		if cachyos_repos_configured; then
			printf '  CachyOS repositories: already configured\n'
		elif [[ $CACHYOS_REPOS_APPROVED == true ]]; then
			printf '  CachyOS repositories: approved\n'
		else
			printf '  CachyOS repositories: not requested (use --enable-cachyos-repos)\n'
		fi
		if [[ $CACHYOS_KERNEL_MODE == true ]]; then
			printf '  CachyOS kernel: %s with a boot entry\n' "$CACHYOS_KERNEL"
		else
			printf '  CachyOS kernel: not requested (use --cachyos-kernel)\n'
		fi
	fi
	print_summary_profile "Terminal candidates" terminal
	if install_herdr_profile; then
		printf '  Herdr workspace: verified user install from https://herdr.dev/install.sh\n'
	elif [[ $HERDR_INSTALL_MODE == true ]]; then
		printf '  Herdr workspace: skipped (unsupported architecture: %s)\n' "$ARCH"
	else
		printf '  Herdr workspace: skipped (optional; use --install-herdr to enable)\n'
	fi
	echo ""
}

confirm_install_summary() {
	local answer

	print_install_summary

	if [[ $DRY_RUN == true ]]; then
		ok "Dry run complete; no changes were made."
		exit 0
	fi

	if [[ $ASSUME_YES == true ]]; then
		return
	fi

	printf 'Continue with installation? [y/N] '
	read -r answer
	case "$answer" in
	y | Y | yes | YES) ;;
	*)
		err "Installation cancelled."
		exit 1
		;;
	esac
}

install_meslo_nerd_font() {
	local font_dir="$HOME/.local/share/fonts/Meslo"
	local tmp_dir
	local archive

	if fc-list 2>/dev/null | command grep -Eqi 'MesloLGS (NF|Nerd Font)'; then
		ok "MesloLGS Nerd Font is already installed."
		return
	fi

	tmp_dir="$(mktemp -d)"
	archive="$tmp_dir/Meslo.zip"

	info "Downloading Meslo Nerd Font v${MESLO_VERSION}..."
	if ! curl --fail --location --show-error --silent "$MESLO_URL" --output "$archive"; then
		rm -rf "$tmp_dir"
		err "Failed to download Meslo Nerd Font."
		return 1
	fi

	if ! printf '%s  %s\n' "$MESLO_SHA256" "$archive" | sha256sum --check --status; then
		rm -rf "$tmp_dir"
		err "Meslo Nerd Font checksum verification failed."
		return 1
	fi

	mkdir -p "$font_dir"
	unzip -j -q -o "$archive" '*.ttf' -d "$font_dir"
	rm -rf "$tmp_dir"
	fc-cache -f "$font_dir" >/dev/null 2>&1
	ok "MesloLGS Nerd Font installed."
}

install_supported_terminal() {
	if ! dwm_install_first_available_profile terminal; then
		err "No supported terminal is available in the enabled repositories."
		return 1
	fi
}

configure_quickshell_picom_opacity() {
	local config="/etc/xdg/picom.conf"
	local backup="${config}.lyona.bak"
	local tooltip_rule="^([[:space:]]*\"[0-9]+([.][0-9]+)?:window_type = 'tooltip')(\"[[:space:]]*,?[[:space:]]*)$"
	local configured_rule="^[[:space:]]*\"[0-9]+([.][0-9]+)?:window_type = 'tooltip' && name != 'quickshell'\"[[:space:]]*,?[[:space:]]*$"
	local tmp

	if [[ ! -f $config ]]; then
		warn "Picom system config not found; skipping Quickshell opacity override."
		return
	fi
	if sudo grep -Eq "$configured_rule" "$config"; then
		ok "Quickshell Picom opacity is already configured."
		return
	fi
	if ! sudo grep -Eq "$tooltip_rule" "$config"; then
		warn "Recognized Picom tooltip opacity rule not found; preserving $config."
		return
	fi

	tmp="$(mktemp)"
	if ! sudo sed -E \
		"s/${tooltip_rule}/\\1 \&\& name != 'quickshell'\\3/" \
		"$config" | tee "$tmp" >/dev/null; then
		rm -f "$tmp"
		warn "Could not prepare the Quickshell Picom opacity override."
		return
	fi

	if [[ ! -f $backup ]]; then
		sudo install -o root -g root -m 0644 "$config" "$backup"
	fi
	sudo install -o root -g root -m 0644 "$tmp" "$config"
	rm -f "$tmp"
	ok "Configured fully opaque Quickshell windows in Picom."
}

configure_displays_after_install() {
	local answer

	if [[ $NON_INTERACTIVE == true ]]; then
		warn "Display setup deferred for non-interactive installation."
		warn "Run dwm-display-setup from an X11 session after login."
		return 0
	fi
	if [[ -z ${DISPLAY:-} ]] || ! command -v xrandr >/dev/null 2>&1; then
		warn "Display setup needs an active X11 session and was deferred."
		warn "After login, run: dwm-display-setup"
		return 0
	fi
	if ! xrandr --query 2>/dev/null | awk '$2 == "connected" { found = 1 } END { exit !found }'; then
		warn "No connected X11 outputs were detected; display setup was deferred."
		return 0
	fi

	printf 'Configure persistent display resolution and positioning now? [Y/n] '
	read -r answer
	case $answer in
	n | N | no | NO)
		warn "Display setup skipped. Run dwm-display-setup when ready."
		;;
	*)
		if ! "$REPO_DIR/scripts/dwm-display-setup" wizard; then
			warn "Display setup did not complete. Existing Xorg configuration was preserved."
			warn "Run dwm-display-setup to try again."
		fi
		;;
	esac
}

detect_display_manager() {
	local unit

	unit="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
	case "$(basename "$unit")" in
	lightdm.service)
		echo "lightdm"
		return
		;;
	gdm.service)
		echo "gdm"
		return
		;;
	sddm.service)
		echo "sddm"
		return
		;;
	esac

	for unit in lightdm gdm sddm; do
		if command -v "$unit" &>/dev/null; then
			echo "$unit"
			return
		fi
	done
}

install_lightdm_config() {
	local lightdm_seat_section="Seat:*"
	local lightdm_greeter_session="lightdm-slick-greeter"
	local lightdm_session_wrapper="/etc/lightdm/Xsession"
	local lightdm_logind_check=true

	sudo make -C "$REPO_DIR/lightdm" \
		LIGHTDM_SEAT_SECTION="$lightdm_seat_section" \
		LIGHTDM_GREETER_SESSION="$lightdm_greeter_session" \
		LIGHTDM_SESSION_WRAPPER="$lightdm_session_wrapper" \
		LIGHTDM_LOGIND_CHECK="$lightdm_logind_check" \
		install
}

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║              lyona Installer              ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Distribution: $DISTRO_NAME"
info "Family: $DISTRO_FAMILY"
info "Package manager: $PKG_CMD"
info "Install profile: $INSTALL_PROFILE"
confirm_cachyos_setup
confirm_install_summary
confirm_arch_multilib_repository
setup_cachyos

if [[ $NON_INTERACTIVE != true ]]; then
	"$REPO_DIR/scripts/configure-build.sh"
else
	"$REPO_DIR/scripts/configure-build.sh" --non-interactive
fi

info "Installing required build and runtime dependencies..."
dwm_install_package_profile build x11 runtime-required
ok "Required build and runtime dependencies installed."

if install_recommended_profile; then
	info "Installing recommended desktop dependencies..."
	dwm_install_package_profile desktop
	if ! env -u DWM_TEST_MODE -u DWM_TEST_QUICKSHELL_VERSION \
		"$REPO_DIR/scripts/dwm-quickshell-version-check"; then
		err "The installed Quickshell build is incompatible with lyona."
		exit 1
	fi
	if ! dwm_install_available_package_profile screenshot-optional; then
		warn "maim is unavailable in the enabled repositories; screenshot hotkeys will remain disabled."
	fi
	dwm_install_package_profile theme
	if ! dwm_install_available_package_profile theme-gtk; then
		warn "Some GTK theme packages were unavailable in enabled repositories."
	fi
	dwm_install_package_profile fonts
	# Before install-mybash runs. That script installs starship, fzf and
	# zoxide itself and falls back to piping an installer from the network
	# when pacman fails; installing them from the repositories first means
	# that fallback is never reached. It also covers fastfetch, which the
	# linked .bashrc runs at startup and that script does not install at all.
	dwm_install_package_profile shell
	info "Setting up Gear Lever for AppImage management..."
	if "$REPO_DIR/scripts/install-gearlever"; then
		ok "Gear Lever is installed."
	else
		warn "Gear Lever setup failed; retry with scripts/install-gearlever when Flathub is reachable."
	fi
	ok "Recommended desktop dependencies installed."
else
	warn "Skipping recommended desktop dependencies for core profile."
fi

if command -v picom >/dev/null 2>&1; then
	configure_quickshell_picom_opacity
fi

if install_optional_profile; then
	info "Installing optional desktop extras..."
	if ! dwm_install_available_package_profile optional; then
		warn "Some optional desktop extras were unavailable in enabled repositories."
	fi
	if arch_gaming_profile; then
		if [[ $ARCH_GAMING_REPOS_APPROVED != true ]]; then
			warn "Arch gaming packages were skipped because the multilib repository was not approved."
		elif configure_arch_multilib_repository; then
			info "Installing Arch gaming packages..."
			if ! dwm_install_available_package_profile gaming; then
				warn "Some Arch gaming packages were unavailable in the multilib repository."
			fi
			configure_arch_gamemode_access
		else
			warn "Multilib repository setup failed; no gaming packages were installed."
		fi
	fi
	ok "Optional desktop extras processed."
else
	warn "Skipping optional desktop extras for $INSTALL_PROFILE profile."
fi

if install_recommended_profile; then
	info "Configuring Qt/GTK dark-mode dependencies..."
	dwm_install_first_available_profile theme-optional ||
		warn "Neither qt6ct nor qt5ct is available - Qt apps may not respect dark mode."
	ok "Qt/GTK theming dependencies configured."
fi

if install_recommended_profile; then
	info "Installing fonts..."
	FONT_DIR="$HOME/.local/share/fonts"
	mkdir -p "$FONT_DIR"
	install_meslo_nerd_font
	ok "Fonts installed."

	# Replaces ~/.bashrc with a link, keeping the previous file as
	# ~/.bashrc.bak, so this stays inside the recommended profile rather than
	# running for a core install.
	info "Installing the mybash shell configuration..."
	if "$REPO_DIR/scripts/install-mybash"; then
		ok "mybash shell configuration installed; open a new shell to pick it up."
	else
		warn "The mybash shell configuration was not installed; the default bash prompt remains."
	fi
fi

terminal=""
if command -v alacritty &>/dev/null; then
	terminal="alacritty"
	ok "Preferred terminal already installed: $terminal"
else
	info "Installing the preferred Alacritty terminal from enabled repositories..."
	if dwm_install_first_available_profile terminal-primary; then
		terminal="alacritty"
		ok "Preferred terminal installed: $terminal"
	else
		warn "Alacritty is unavailable; falling back to another supported terminal."
		for t in kitty st warp-terminal xterm; do command -v "$t" &>/dev/null && {
			terminal="$t"
			break
		}; done
		if [ -z "$terminal" ]; then
			install_supported_terminal
			terminal="$(detect_terminal)"
		fi
	fi
fi

if install_herdr_profile; then
	info "Installing the verified Herdr workspace for interactive terminals..."
	if "$REPO_DIR/scripts/install-herdr"; then
		ok "Herdr is installed; set DWM_HERDR=1 and use dwm-terminal to open it in $terminal."
	else
		herdr_status=$?
		if [[ $herdr_status -eq 2 ]]; then
			warn "Herdr is ready, but one or more detected agent integrations could not be installed."
		else
			warn "Herdr installation failed; Alacritty remains the default terminal."
		fi
	fi
elif [[ $HERDR_INSTALL_MODE == true ]]; then
	warn "Skipping Herdr installation on unsupported architecture: $ARCH."
fi

if install_optional_profile && command -v xdg-user-dirs-update &>/dev/null; then
	xdg-user-dirs-update
fi

if install_optional_profile; then
	mkdir -p "$HOME/Pictures"
	if [ ! -d "$BG_DIR" ]; then
		info "Downloading wallpapers..."
		# Shallow, and without the repository itself: a full clone left ~139
		# MiB of history sitting in the wallpaper folder for every tool that
		# walks it, and nothing here ever pulls updates.
		if git clone --depth 1 https://github.com/technicks89/nord-background.git "$BG_DIR" 2>/dev/null; then
			rm -rf -- "$BG_DIR/.git"
			ok "Wallpapers downloaded to $BG_DIR"
		else
			warn "Failed to download wallpapers. Add your own to $BG_DIR."
		fi
	else
		ok "Wallpapers already present."
	fi
fi

currentdm="$(detect_display_manager)"

if [ -n "$currentdm" ]; then
	ok "Display manager already installed: $currentdm"
elif ! install_optional_profile; then
	warn "No display manager found; skipping display-manager installation for $INSTALL_PROFILE profile."
else
	info "No display manager found - installing LightDM..."
	dwm_install_package_profile lightdm
	sudo systemctl enable lightdm.service
	currentdm="lightdm"
	ok "LightDM installed and enabled."
fi

if [[ $currentdm == "lightdm" ]]; then
	info "Deploying LightDM Slick Greeter config..."
	install_lightdm_config
	ok "LightDM config deployed."
fi

ensure_yay_installed || true

cd "$REPO_DIR"
make clean
make
sudo make install-system \
	USER_HOME="$HOME" \
	OWNER="$(id -un)" \
	DATADIR="/usr/share"
make install-user \
	USER_HOME="$HOME" \
	OWNER="$(id -un)" \
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
	XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
configure_displays_after_install

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║          Installation Complete!           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
info "Detected: $DISTRO_NAME"
echo "  • Build configuration: $REPO_DIR/config.h"
echo "  • Reconfigure by removing config.h and running the installer again"
echo "  • Display setup: dwm-display-setup"
echo "  • Log out and select 'dwm', or start with: startx"
if [[ $currentdm == "lightdm" ]]; then
	echo "  • Start LightDM now (optional): sudo systemctl start lightdm.service"
fi
echo ""
echo "  SUPER+/   keybind viewer     SUPER+X  terminal"
echo "  SUPER+F1  control center     SUPER+R  app launcher"
echo "  SUPER+Q   close window"
echo ""
echo "  Full reference: docs/src/keybinds.md or SUPER+/ in dwm"
echo ""
