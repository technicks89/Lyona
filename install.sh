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
# Every warning is kept for the closing screen (#290): in the middle of
# pacman's output it scrolls past unread.
INSTALL_WARNINGS=()
warn() {
	printf "${YELLOW}[WARN]${NC} %s\n" "$1"
	INSTALL_WARNINGS+=("$1")
}
err() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# Where the install's time goes (#250). step_timer LABEL ends the section
# before it, saying how long that took, and starts LABEL;
# print_step_timer_summary ends the last one and prints every section's time.
STEP_TIMER_LABEL=
STEP_TIMER_START=0
STEP_TIMER_ROWS=()

# format_duration SECONDS: "42s", or "3m 05s".
format_duration() {
	if (($1 < 60)); then
		printf '%ds' "$1"
	else
		printf '%dm %02ds' "$(($1 / 60))" "$(($1 % 60))"
	fi
}

step_timer() {
	local now=$SECONDS elapsed
	if [[ -n $STEP_TIMER_LABEL ]]; then
		elapsed=$((now - STEP_TIMER_START))
		STEP_TIMER_ROWS+=("$elapsed"$'\t'"$STEP_TIMER_LABEL")
		printf '[TIME] %s: done in %s\n' "$STEP_TIMER_LABEL" "$(format_duration "$elapsed")"
	fi
	STEP_TIMER_LABEL=${1:-}
	STEP_TIMER_START=$now
}

print_step_timer_summary() {
	local row seconds label total=0
	step_timer
	((${#STEP_TIMER_ROWS[@]} > 0)) || return 0
	echo ""
	printf 'Step times\n%-10s %s\n' "Time" "Step"
	for row in "${STEP_TIMER_ROWS[@]}"; do
		seconds=${row%%$'\t'*}
		label=${row#*$'\t'}
		printf '%-10s %s\n' "$(format_duration "$seconds")" "$label"
		total=$((total + seconds))
	done
	printf '%-10s %s\n' "$(format_duration "$total")" "Total of the steps above"
}

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
  --skip-topgrade        Do not install Topgrade (recommended and full profiles).
  --configure-build      Ask the dwm build questions (refresh rate, font size,
                         modifier key, layout) before the summary. Without it,
                         a new config.h uses config.def.h's defaults; an
                         existing config.h is always kept.
  --with-gearlever       Also install Gear Lever from Flathub as the AppImage
                         manager (recommended and full profiles). Without it,
                         lyona-appimage opens AppImages.
  --enable-arch-gaming-repos
                         Approve enabling the multilib repository for gaming.
  --enable-cachyos-repos Add the CachyOS repositories for this CPU, replacing
                         pacman with the CachyOS build and upgrading the system
                         to the optimized packages.
  --cachyos-kernel       Install the linux-cachyos kernel and add a boot entry
                         for it. Implies --enable-cachyos-repos.
  --skip-grub-theme      Install the GRUB theme files but leave the bootloader
                         configuration untouched.
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
ARCH="$(uname -m)"
# The wallpapers, pinned to a reviewed commit (Sync Sprint 16 R16-16): they are
# fetched while sudo is cached. Re-pin after looking at what changed.
WALLPAPERS_URL="https://github.com/technicks89/nord-background.git"
WALLPAPERS_REF="8f3dc598c132eaabdba7e7af5dc0acb45fbaa2b3"
YAY_BIN_URL="https://aur.archlinux.org/yay-bin.git"
# Reviewed AUR PKGBUILD commit (yay-bin 13.0.1): downloads a checksummed
# release tarball from github.com/Jguer/yay, no arbitrary build step. Re-pin
# after reviewing the diff since the last pin.
YAY_BIN_REF="13e0a4754d106a9252b7479bf1b370fbe454fc48"
INSTALL_PROFILE="${DWM_INSTALL_PROFILE:-full}"
HERDR_INSTALL_MODE="${DWM_INSTALL_HERDR:-false}"
TOPGRADE_INSTALL_MODE="${DWM_INSTALL_TOPGRADE:-true}"
GEARLEVER_INSTALL_MODE="${DWM_INSTALL_GEARLEVER:-false}"
# The dwm build questions, only when asked for (#289): they are dwm internals
# most users cannot judge, and a typo in one used to stop the install.
CONFIGURE_BUILD=false
NON_INTERACTIVE=false
ASSUME_YES=false
ARCH_GAMING_REPOS_APPROVED=false
CACHYOS_REPOS_APPROVED="${DWM_INSTALL_CACHYOS_REPOS:-false}"
CACHYOS_KERNEL_MODE="${DWM_INSTALL_CACHYOS_KERNEL:-false}"
CACHYOS_KERNEL=linux-cachyos
GRUB_THEME_MODE="${DWM_INSTALL_GRUB_THEME:-true}"
GRUB_THEME_NAME=CyberRe
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
	--skip-topgrade)
		TOPGRADE_INSTALL_MODE=false
		shift
		;;
	--with-gearlever)
		GEARLEVER_INSTALL_MODE=true
		shift
		;;
	--configure-build)
		CONFIGURE_BUILD=true
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
	--skip-grub-theme)
		GRUB_THEME_MODE=false
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

case $TOPGRADE_INSTALL_MODE in
1 | true | yes) TOPGRADE_INSTALL_MODE=true ;;
0 | false | no) TOPGRADE_INSTALL_MODE=false ;;
*)
	err "Unsupported DWM_INSTALL_TOPGRADE: $TOPGRADE_INSTALL_MODE"
	err "Supported values: true, false"
	exit 1
	;;
esac

case $GEARLEVER_INSTALL_MODE in
1 | true | yes) GEARLEVER_INSTALL_MODE=true ;;
0 | false | no) GEARLEVER_INSTALL_MODE=false ;;
*)
	err "Unsupported DWM_INSTALL_GEARLEVER: $GEARLEVER_INSTALL_MODE"
	err "Supported values: true, false"
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

case "$GRUB_THEME_MODE" in
1 | true | yes)
	GRUB_THEME_MODE=true
	;;
0 | false | no)
	GRUB_THEME_MODE=false
	;;
*)
	err "Unsupported DWM_INSTALL_GRUB_THEME: $GRUB_THEME_MODE"
	err "Supported values: true, false"
	exit 1
	;;
esac

if [[ $CACHYOS_KERNEL_MODE == true ]]; then
	CACHYOS_REPOS_APPROVED=true
fi

if [[ ! -t 0 || ! -t 1 ]]; then
	NON_INTERACTIVE=true
	ASSUME_YES=true
fi

# After the terminal check: --non-interactive, or no terminal, both mean no one
# can answer the questions.
if [[ $CONFIGURE_BUILD == true && $NON_INTERACTIVE == true ]]; then
	err "--configure-build asks questions, so it needs a terminal and cannot run with --non-interactive; set DWM_REFRESH_RATE and the other DWM_* values instead (scripts/configure-build.sh --help)."
	exit 1
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

# Topgrade (Sync Sprint 15 S15-06, decision D-28): from the AUR (#245) for the
# recommended and full profiles, unless --skip-topgrade.
install_topgrade_profile() {
	install_recommended_profile && [[ $TOPGRADE_INSTALL_MODE == true ]]
}

# Gear Lever (#260): opt-in with --with-gearlever. It needs about 1.7 GB of
# Flatpak runtimes; lyona-appimage opens AppImages without them.
install_gearlever_profile() {
	install_recommended_profile && [[ $GEARLEVER_INSTALL_MODE == true ]]
}

install_herdr_profile() {
	[[ $HERDR_INSTALL_MODE == true ]] && herdr_arch_supported
}

# Time synchronization (#258): systemd-timesyncd, part of systemd, is enabled
# when nothing else keeps the clock. Another NTP service, enabled or running, is
# the user's choice and is kept, as is a masked systemd-timesyncd. Prints one of
# other:UNIT, enabled, masked, missing, turned-off or off. The image install has
# it enabled already: archinstall's "ntp": true.
#
# Once lyona has seen it on, it records that (time_sync_marker), so a later
# "off" is the user's choice, from Settings or timedatectl set-ntp false: a
# re-run leaves it off (turned-off) instead of turning it back on (#268).
time_sync_marker() {
	printf '%s\n' "${LYONA_TIME_SYNC_MARKER:-/var/lib/lyona/time-sync}"
}

time_sync_state() {
	local unit state
	for unit in chronyd.service ntpd.service openntpd.service; do
		# Enabled to start at boot, not merely static, indirect or an alias,
		# which is-enabled also exits 0 for.
		state=$(systemctl is-enabled "$unit" 2>/dev/null) || :
		if [[ $state == enabled || $state == enabled-runtime ]] ||
			systemctl is-active --quiet "$unit" 2>/dev/null; then
			printf 'other:%s\n' "$unit"
			return 0
		fi
	done
	state=$(systemctl is-enabled systemd-timesyncd.service 2>/dev/null) || :
	case $state in
	enabled | enabled-runtime) printf 'enabled\n' ;;
	masked | masked-runtime) printf 'masked\n' ;;
	not-found | '') printf 'missing\n' ;;
	*)
		if [[ -e $(time_sync_marker) ]]; then
			printf 'turned-off\n'
		else
			printf 'off\n'
		fi
		;;
	esac
}

# Records that time synchronization has been on, once.
mark_time_sync() {
	local marker
	marker=$(time_sync_marker)
	[[ -e $marker ]] || sudo install -D -m 0644 /dev/null "$marker" 2>/dev/null || :
}

configure_time_sync() {
	local state
	state=$(time_sync_state)
	case $state in
	other:*) ok "Time synchronization: keeping ${state#other:}." ;;
	enabled)
		if systemctl is-active --quiet systemd-timesyncd.service 2>/dev/null; then
			ok "Time synchronization (systemd-timesyncd) is already enabled."
		elif [[ ${LYONA_SOURCE:-} == iso ]] || systemd-detect-virt --chroot >/dev/null 2>&1; then
			# The image install's chroot, where systemctl start is ignored: it
			# starts at the first boot.
			ok "Time synchronization (systemd-timesyncd) is enabled; it starts at boot."
		else
			info "Starting systemd-timesyncd, which is enabled but not running..."
			if sudo systemctl start systemd-timesyncd.service; then
				ok "systemd-timesyncd started."
			else
				warn "systemd-timesyncd could not be started; it starts at the next boot."
			fi
		fi
		mark_time_sync
		;;
	turned-off) info "Time synchronization is off: it was turned off after lyona set it up, so it stays off (turn it on in Settings or with timedatectl set-ntp true)." ;;
	masked) info "systemd-timesyncd is masked, so time synchronization was left off (sudo systemctl unmask systemd-timesyncd to use it)." ;;
	missing) warn "systemd-timesyncd was not found, so time synchronization was left off." ;;
	*)
		info "Enabling time synchronization (systemd-timesyncd)..."
		if sudo systemctl enable --now systemd-timesyncd.service; then
			ok "systemd-timesyncd enabled and started."
			mark_time_sync
		else
			warn "systemd-timesyncd could not be enabled; turn time synchronization on in Settings or with timedatectl set-ntp true."
		fi
		;;
	esac
}

# NetworkManager, on recommended and full (#292): the panel's network status
# and Wi-Fi come from it. It is enabled only when nothing else manages the
# network, so a working systemd-networkd, iwd, ConnMan, dhcpcd or netctl setup
# is never taken over. Prints image, enabled, masked, other:UNIT or off.
network_manager_state() {
	local unit state
	# The image install: its postinstall enables NetworkManager itself, and in
	# its chroot systemctl answers for the live medium, which runs networkd.
	if [[ ${LYONA_SOURCE:-} == iso ]] || systemd-detect-virt --chroot >/dev/null 2>&1; then
		printf 'image\n'
		return 0
	fi
	state=$(systemctl is-enabled NetworkManager.service 2>/dev/null) || :
	case $state in
	enabled | enabled-runtime)
		printf 'enabled\n'
		return 0
		;;
	masked | masked-runtime)
		printf 'masked\n'
		return 0
		;;
	esac
	for unit in systemd-networkd.service iwd.service connman.service dhcpcd.service; do
		state=$(systemctl is-enabled "$unit" 2>/dev/null) || :
		if [[ $state == enabled || $state == enabled-runtime ]] ||
			systemctl is-active --quiet "$unit" 2>/dev/null; then
			printf 'other:%s\n' "$unit"
			return 0
		fi
	done
	# netctl runs one unit per profile.
	unit=$(systemctl list-units --type=service --state=active --plain --no-legend 'netctl*' 2>/dev/null |
		awk 'NR == 1 { print $1 }') || :
	if [[ -n $unit ]]; then
		printf 'other:%s\n' "$unit"
		return 0
	fi
	printf 'off\n'
}

# Enabled, not started: the install still downloads after this, and
# NetworkManager taking over the interfaces could drop the connection.
configure_network_manager() {
	local state
	state=$(network_manager_state)
	case $state in
	image) ok "NetworkManager is set up by the image installer." ;;
	enabled) ok "NetworkManager is already enabled." ;;
	masked) info "NetworkManager is masked, so it was left off (sudo systemctl unmask NetworkManager to use it)." ;;
	other:*) info "NetworkManager was installed but not enabled: ${state#other:} manages the network. The panel's network status needs NetworkManager." ;;
	*)
		info "Enabling NetworkManager..."
		if sudo systemctl enable NetworkManager.service; then
			ok "NetworkManager enabled; it starts at the next boot."
		else
			warn "NetworkManager could not be enabled; the panel shows no network status until it is (sudo systemctl enable --now NetworkManager)."
		fi
		;;
	esac
}

# Same override the helper reads, so both agree about which machine they are
# looking at and either branch can be exercised in a test.
grub_in_use() {
	[[ -f ${LYONA_GRUB_DEFAULTS:-/etc/default/grub} ]] &&
		command -v grub-mkconfig &>/dev/null
}

# The theme files land with `make install-system`; this only selects one, and
# only when the machine actually boots with GRUB. It is reported in the
# summary above rather than done quietly, because it edits the bootloader.
apply_grub_theme() {
	if [[ $GRUB_THEME_MODE != true ]]; then
		info "Skipping GRUB theme selection (--skip-grub-theme)."
		return 0
	fi
	if ! grub_in_use; then
		info "No GRUB installation found; leaving the bootloader alone."
		return 0
	fi

	info "Selecting the $GRUB_THEME_NAME GRUB theme..."
	if "$REPO_DIR/scripts/lyona-grub-theme" apply "$GRUB_THEME_NAME"; then
		ok "GRUB boot menu themed."
	else
		# A failed theme edit must not fail an otherwise good install: the
		# helper backs up /etc/default/grub before touching it, and the
		# machine still boots with the configuration it had.
		warn "Could not select the GRUB theme; the bootloader was left as it was."
		warn "Re-run it by hand with: sudo lyona-grub-theme apply $GRUB_THEME_NAME"
	fi
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

# Before the summary: what this machine allows and already has, so the summary
# says it correctly.
prepare_cachyos_setup() {
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
}

# After the summary (#294): the questions, interactive runs only.
ask_cachyos_setup() {
	local answer

	cachyos_supported || return 0
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
	else
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
	fi
	# No pacman run of its own (#248): the package install right after is one
	# pacman -Syu --needed transaction, which syncs [multilib] with the other
	# databases and upgrades with it, so never -Sy alone (a partial upgrade). A
	# run that stops after enabling multilib leaves no sync behind, and the next
	# run's -Syu still upgrades.
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
	# A note, not a fault: the image install's closing screen lists warnings.
	info "Log out and back in before using GameMode privileged tuning."
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
	if ! git clone "$YAY_BIN_URL" "$tmp_dir/yay-bin" 2>/dev/null ||
		! git -C "$tmp_dir/yay-bin" checkout --quiet "$YAY_BIN_REF"; then
		rm -rf "$tmp_dir"
		warn "Could not download yay; continuing without an AUR helper."
		return 1
	fi
	# pacman's "Proceed with installation?" is answered for a non-interactive
	# run: the image install runs this behind a spinner, where nothing can answer
	# it, and it waited there forever (Sync Sprint 16, found in a VM).
	local -a makepkg_args=(-si --needed)
	[[ $NON_INTERACTIVE != true ]] || makepkg_args+=(--noconfirm)
	if ! (cd "$tmp_dir/yay-bin" && makepkg "${makepkg_args[@]}"); then
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
	local -a packages=()

	mapfile -t packages < <(dwm_packages "$DISTRO_FAMILY" "$profile")
	if ((${#packages[@]} == 0)); then
		printf '  %s: none\n' "$label"
		return 0
	fi
	# A count first; the names after it, wrapped, not as one long line (#294).
	printf '  %s: %d\n' "$label" "${#packages[@]}"
	printf '%s\n' "${packages[*]}" | fold -s -w 70 | sed 's/^/      /; s/ *$//'
}

# The plan, before anything changes: what it does to the system first, then
# the packages, then what it sets up for this account (#294).
print_install_summary() {
	echo ""
	printf 'Installation summary: %s, %s profile, %s\n' "$DISTRO_NAME" "$INSTALL_PROFILE" \
		"$([[ $NON_INTERACTIVE == true ]] && echo non-interactive || echo interactive)"

	echo ""
	echo "System changes:"
	# One transaction for every repository package (#247), gaming included
	# (#248), and the system upgrade with it.
	printf '  System upgrade: every installed package, in the same pacman -Syu --needed transaction as the packages below\n'
	if install_recommended_profile; then
		# Every change it makes is listed (Sync Sprint 16 R16-28).
		printf '  Shell configuration: mybash replaces ~/.bashrc, ~/.config/starship.toml, the fastfetch config and ~/.local/bin/starship-theme with links (previous files kept as .bak.<time>)\n'
	fi
	if [[ $GRUB_THEME_MODE != true ]]; then
		printf '  GRUB theme: files installed, bootloader left unchanged (--skip-grub-theme)\n'
	elif grub_in_use; then
		printf '  GRUB theme: %s, selected in /etc/default/grub (backed up first)\n' "$GRUB_THEME_NAME"
		# lyona-grub-theme leaves a GRUB_DISABLE_BOOTNEXT the user set alone.
		if command grep -Eq '^[[:space:]]*GRUB_DISABLE_BOOTNEXT=' "${LYONA_GRUB_DEFAULTS:-/etc/default/grub}"; then
			printf '  GRUB firmware entries: as GRUB_DISABLE_BOOTNEXT in /etc/default/grub sets them (kept)\n'
		else
			printf '  GRUB firmware entries: "(EFI BootNext)" entries hidden (/etc/default/grub.d/90-lyona-menu.cfg)\n'
		fi
	else
		printf '  GRUB theme: files installed; this machine does not boot with GRUB\n'
	fi
	if install_optional_profile; then
		local dm
		dm=$(detect_display_manager)
		if [[ -n $dm ]]; then
			printf '  Display manager: %s, already installed\n' "$dm"
		else
			printf '  Display manager: LightDM, installed and enabled\n'
		fi
		if arch_gaming_profile; then
			# Arch's own [multilib], not a third-party repository.
			if [[ $ARCH_GAMING_REPOS_APPROVED == true ]]; then
				printf '  Arch [multilib] repository: approved\n'
			elif arch_multilib_enabled; then
				printf '  Arch [multilib] repository: already enabled\n'
			else
				printf '  Arch [multilib] repository: requires separate confirmation\n'
			fi
			printf '  gamemode group: %s is added to it, with the gaming packages\n' "$(id -un)"
		fi
	fi
	if cachyos_supported; then
		if cachyos_repos_configured; then
			printf '  CachyOS repositories: already configured\n'
		elif [[ $CACHYOS_REPOS_APPROVED == true ]]; then
			printf '  CachyOS repositories: approved; they replace pacman with the CachyOS build and upgrade to optimized packages\n'
		elif [[ $NON_INTERACTIVE == true ]]; then
			printf '  CachyOS repositories: not requested (use --enable-cachyos-repos)\n'
		else
			printf '  CachyOS repositories: not requested (use --enable-cachyos-repos); an interactive install asks after this summary\n'
		fi
		if [[ $CACHYOS_KERNEL_MODE == true ]]; then
			printf '  CachyOS kernel: %s with a boot entry\n' "$CACHYOS_KERNEL"
		else
			printf '  CachyOS kernel: not requested (use --cachyos-kernel)\n'
		fi
	fi
	if install_recommended_profile; then
		local network
		network=$(network_manager_state)
		case $network in
		image) printf '  NetworkManager: set up by the image installer\n' ;;
		enabled) printf '  NetworkManager: already enabled\n' ;;
		masked) printf '  NetworkManager: installed; masked, left as it is\n' ;;
		other:*) printf '  NetworkManager: installed, not enabled (%s manages the network)\n' "${network#other:}" ;;
		*) printf '  NetworkManager: installed and enabled; starts at the next boot\n' ;;
		esac
	fi
	local time_sync
	time_sync=$(time_sync_state)
	case $time_sync in
	other:*) printf '  Time synchronization: %s, kept\n' "${time_sync#other:}" ;;
	enabled) printf '  Time synchronization: systemd-timesyncd, already enabled\n' ;;
	masked) printf '  Time synchronization: systemd-timesyncd is masked, left as it is\n' ;;
	turned-off) printf '  Time synchronization: turned off since lyona set it up, left off\n' ;;
	missing) printf '  Time synchronization: systemd-timesyncd not found, left off\n' ;;
	*) printf '  Time synchronization: systemd-timesyncd, enabled and started\n' ;;
	esac
	if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
		printf '  AUR helper: already installed\n'
	else
		printf '  AUR helper: yay-bin, built from its pinned AUR PKGBUILD with makepkg\n'
	fi

	echo ""
	echo "Packages:"
	print_summary_profile "Required packages" required
	if install_recommended_profile; then
		print_summary_profile "Recommended packages" recommended
	else
		printf '  Recommended packages: skipped\n'
	fi
	if install_optional_profile; then
		print_summary_profile "Optional extras" optional
		if arch_gaming_profile; then
			print_summary_profile "Arch gaming packages" gaming
		fi
	else
		printf '  Optional extras: skipped\n'
	fi
	print_summary_profile "Terminal candidates" terminal

	echo ""
	echo "For this account:"
	local build_overrides='' build_variable
	for build_variable in DWM_REFRESH_RATE DWM_FONT_SIZE DWM_MODKEY DWM_MFACT DWM_NMASTER \
		DWM_CURSORWARP DWM_SWALLOWFLOATING DWM_RESIZEHINTS; do
		[[ -z ${!build_variable:-} ]] || build_overrides+=" $build_variable=${!build_variable}"
	done
	if [[ -e $REPO_DIR/config.h ]]; then
		printf '  dwm build: your existing config.h, kept\n'
	elif [[ $CONFIGURE_BUILD == true && $DRY_RUN == true ]]; then
		printf '  dwm build: the --configure-build answers, asked before this summary in a real install\n'
	elif [[ $CONFIGURE_BUILD == true ]]; then
		printf '  dwm build: your answers above, written to config.h once you continue\n'
	elif [[ -n $build_overrides ]]; then
		printf '  dwm build: config.def.h defaults, with%s\n' "$build_overrides"
	else
		printf '  dwm build: config.def.h defaults (use --configure-build to choose)\n'
	fi
	if install_recommended_profile; then
		printf '  AppImages: opened with lyona-appimage, which adds them to the launcher (unless another handler is set)\n'
		if install_gearlever_profile; then
			printf '  Gear Lever: user-scoped Flathub install (%s)\n' 'it.mijorus.gearlever'
		else
			printf '  Gear Lever: not installed (optional; use --with-gearlever)\n'
		fi
		if install_topgrade_profile; then
			printf '  Topgrade: %s\n' "$("$REPO_DIR/scripts/install-topgrade" --print-plan)"
		else
			printf '  Topgrade: skipped (--skip-topgrade)\n'
		fi
	fi
	if install_optional_profile; then
		if [[ -d $BG_DIR ]]; then
			printf '  Wallpapers: already present in %s\n' "$BG_DIR"
		else
			printf '  Wallpapers: downloaded into %s (pinned commit)\n' "$BG_DIR"
		fi
	fi
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

	# With the plan on screen, not before it on every run (#294).
	ask_cachyos_setup

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

# The closing banner, and every warning of the run under it (#290), so a run
# that left something out does not end on "Installation Complete!".
print_completion_banner() {
	local message
	local -A seen=()
	# The child scripts' warnings too; each once, though reconcile runs twice.
	if [[ -n ${LYONA_INSTALL_WARNINGS_FILE:-} && -s $LYONA_INSTALL_WARNINGS_FILE ]]; then
		mapfile -t -O "${#INSTALL_WARNINGS[@]}" INSTALL_WARNINGS <"$LYONA_INSTALL_WARNINGS_FILE"
	fi
	local -a unique=()
	for message in "${INSTALL_WARNINGS[@]}"; do
		[[ -z ${seen[$message]+set} ]] || continue
		seen[$message]=1
		unique+=("$message")
	done
	INSTALL_WARNINGS=("${unique[@]}")
	echo ""
	echo "╔═══════════════════════════════════════════╗"
	if ((${#INSTALL_WARNINGS[@]} == 0)); then
		echo "║          Installation Complete!           ║"
		echo "╚═══════════════════════════════════════════╝"
		echo ""
		return 0
	fi
	echo "║   Installation finished, with warnings    ║"
	echo "╚═══════════════════════════════════════════╝"
	echo ""
	printf "${YELLOW}Finished with %d warning(s):${NC}\n" "${#INSTALL_WARNINGS[@]}"
	for message in "${INSTALL_WARNINGS[@]}"; do
		printf '  - %s\n' "$message"
	done
	echo ""
}

# A tip, never a change (#249): pacman.conf is the user's, and the installer
# does not alter system policy without asking. The image sets 10.
pacman_parallel_downloads_tip() {
	local value
	command -v pacman-conf >/dev/null 2>&1 || return 0
	value=$(pacman-conf ParallelDownloads 2>/dev/null) || return 0
	[[ $value =~ ^[0-9]+$ ]] || return 0
	((value < 10)) || return 0
	info "Tip: pacman downloads $value package(s) at a time. Setting ParallelDownloads = 10 in /etc/pacman.conf makes this install faster; the installer leaves that file to you."
}

# The fallback terminals, one pacman run each, until one installs: only when
# Alacritty is missing after the package install.
install_supported_terminal() {
	local package
	while IFS= read -r package; do
		[[ $package != alacritty ]] || continue
		install_packages "$package" && return 0
	done < <(dwm_packages "$DISTRO_FAMILY" terminal)
	err "No supported terminal is available in the enabled repositories."
	return 1
}

# batch_skipped PACKAGE: whether the package install left PACKAGE out, as not in
# the enabled repositories.
batch_skipped() {
	[[ " ${DWM_BATCH_SKIPPED[*]} " == *" $1 "* ]]
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
		# Picom 13 writes its rules in another syntax, and Quickshell's windows are
		# not tooltips there, so its tooltip opacity does not reach them: nothing
		# to change, and not a warning.
		info "Picom's tooltip opacity rule was not found; $config is left as it is."
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
		info "Display setup is left for later: run dwm-display-setup after logging in to change it."
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
info "Install profile: $INSTALL_PROFILE"
pacman_parallel_downloads_tip
prepare_cachyos_setup
# Before the summary, into a staging directory (#289): the answers are part of
# what it shows, and become config.h only once the install goes ahead, so a
# declined summary leaves nothing behind. An existing config.h is kept, so then
# there is nothing to ask.
BUILD_CONFIG_STAGING=
if [[ $CONFIGURE_BUILD == true && $DRY_RUN != true ]]; then
	if [[ -e $REPO_DIR/config.h ]]; then
		info "config.h exists and is kept, so --configure-build asks nothing; remove config.h to choose again."
	else
		BUILD_CONFIG_STAGING=$(mktemp -d)
		trap 'rm -rf -- "$BUILD_CONFIG_STAGING"' EXIT
		"$REPO_DIR/scripts/configure-build.sh" --output "$BUILD_CONFIG_STAGING/config.h"
	fi
fi
confirm_install_summary
# Scripts this install runs that warn and carry on (lyona-reconcile-user, also
# under make install-user) add their warnings here, for the closing list (#290).
LYONA_INSTALL_WARNINGS_FILE=$(mktemp)
export LYONA_INSTALL_WARNINGS_FILE
trap 'rm -f -- "$LYONA_INSTALL_WARNINGS_FILE"; [[ -z ${BUILD_CONFIG_STAGING:-} ]] || rm -rf -- "$BUILD_CONFIG_STAGING"' EXIT
confirm_arch_multilib_repository
step_timer "CachyOS repositories"
setup_cachyos

step_timer "Build configuration"
if [[ -n $BUILD_CONFIG_STAGING && -f $BUILD_CONFIG_STAGING/config.h && ! -e $REPO_DIR/config.h ]]; then
	mv -fT -- "$BUILD_CONFIG_STAGING/config.h" "$REPO_DIR/config.h"
	ok "config.h written from your answers."
fi
# config.h from the defaults (or DWM_* values) when there is none yet; one made
# from the answers above, or earlier, is kept.
"$REPO_DIR/scripts/configure-build.sh" --non-interactive

# Every repository package in one pacman transaction (#247): one dependency
# resolution, one download, one run of each hook, and the system upgrade with
# it. The required profiles fail the install when a package is missing, before
# anything of lyona's is installed; any other missing package is left out with a
# warning (dwm_install_batch). Gaming too (#248), once [multilib] is set up.
step_timer "Packages"
currentdm="$(detect_display_manager)"
mapfile -t batch_required < <(dwm_collect_packages build x11 runtime-required)
batch_optional=()
if install_recommended_profile; then
	mapfile -t -O "${#batch_required[@]}" batch_required < <(dwm_collect_packages desktop)
	mapfile -t batch_optional < <(dwm_collect_packages browser media system-management screenshot-optional \
		theme theme-gtk fonts shell theme-optional)
fi
mapfile -t -O "${#batch_optional[@]}" batch_optional < <(dwm_collect_packages terminal-primary)
if install_optional_profile; then
	mapfile -t -O "${#batch_optional[@]}" batch_optional < <(dwm_collect_packages optional)
	[[ -n $currentdm ]] ||
		mapfile -t -O "${#batch_optional[@]}" batch_optional < <(dwm_collect_packages lightdm)
fi
# Gaming, in the same transaction (#248): [multilib] is enabled first, as
# approved, and this machine's Vulkan drivers come before Steam, so pacman never
# picks a Vulkan provider for it (Sync Sprint 16). A legacy NVIDIA branch's
# 32-bit utilities may not be in the repositories; then they are left out, as
# any missing gaming package is.
gaming_queued=false
if install_optional_profile && arch_gaming_profile; then
	if [[ $ARCH_GAMING_REPOS_APPROVED != true ]]; then
		warn "Arch gaming packages were skipped because the multilib repository was not approved."
	elif configure_arch_multilib_repository; then
		mapfile -t -O "${#batch_optional[@]}" batch_optional < <(dwm_vulkan_driver_packages)
		mapfile -t -O "${#batch_optional[@]}" batch_optional < <(dwm_collect_packages gaming)
		gaming_queued=true
	else
		warn "Multilib repository setup failed; no gaming packages were installed."
	fi
fi
batch_flags=()
[[ $NON_INTERACTIVE != true ]] || batch_flags=(--noconfirm)
info "Installing the packages in one transaction (pacman -Syu --needed, which also upgrades the system)..."
if ! dwm_install_batch "${batch_flags[@]}" batch_required batch_optional; then
	err "The packages could not be installed, so nothing of lyona's was installed. Fix what pacman reported above, then run the installer again."
	exit 1
fi
for package in "${DWM_BATCH_SKIPPED[@]}"; do
	warn "$package is not in the enabled repositories and was left out."
done
ok "Packages installed."
# Qt modules from two Qt releases, from a repository part way through a Qt
# update, stop Quickshell from starting: one release, from Arch, instead.
if ! dwm_repair_qt_set "${batch_flags[@]}"; then
	warn "The installed Qt modules could not be checked, or installed again from Arch as one Qt release; if Quickshell does not start, update the system again later."
elif ((${#DWM_QT_REPAIRED[@]} > 0)); then
	ok "Qt modules installed from Arch, all one release: ${DWM_QT_REPAIRED[*]}."
fi

if install_recommended_profile; then
	if ! env -u DWM_TEST_MODE -u DWM_TEST_QUICKSHELL_VERSION \
		"$REPO_DIR/scripts/dwm-quickshell-version-check"; then
		err "The installed Quickshell build is incompatible with lyona."
		exit 1
	fi
	! batch_skipped maim || warn "maim is unavailable in the enabled repositories; screenshot hotkeys will remain disabled."
	! batch_skipped qt6ct || warn "qt6ct is unavailable in the enabled repositories; Qt apps may not respect dark mode."
	step_timer "Default apps and AppImages"
	# The per-user changes every install path shares (#273): the profile record,
	# the browser, media and image defaults, the AppImage handler and the
	# hotkeys migration. Before Gear Lever, which may take AppImages over; make
	# install-user runs it again, which changes nothing.
	"$REPO_DIR/scripts/lyona-reconcile-user" --profile "$INSTALL_PROFILE" ||
		warn "The account's defaults were not all reconciled; run scripts/lyona-reconcile-user to try again."
	gearlever_state=${XDG_STATE_HOME:-$HOME/.local/state}/lyona
	if install_gearlever_profile; then
		info "Setting up Gear Lever for AppImage management..."
		# Flatpak cannot install for the user inside the image installer's chroot
		# ("User 1000 does not exist"), so there it is left for the first login,
		# whose session startup installs it (Sync Sprint 16, found in a VM). The image
		# always runs this in arch-chroot (LYONA_SOURCE=iso), which systemd-detect-virt
		# cannot see: it gives the chroot its own PID namespace.
		if [[ ${LYONA_SOURCE:-} == iso ]] || systemd-detect-virt --chroot >/dev/null 2>&1; then
			if mkdir -p -- "$gearlever_state" && : >"$gearlever_state/pending-gearlever"; then
				info "Gear Lever will be installed at your first login."
			else
				warn "Gear Lever was not set up; after logging in, run install-gearlever."
			fi
		elif "$REPO_DIR/scripts/install-gearlever"; then
			ok "Gear Lever is installed."
		else
			warn "Gear Lever setup failed; retry with scripts/install-gearlever when Flathub is reachable."
		fi
	elif [[ -e $gearlever_state/pending-gearlever ]]; then
		# Left by an earlier install for the first login: Gear Lever is opt-in now.
		rm -f -- "$gearlever_state/pending-gearlever" &&
			info "Gear Lever is no longer installed by default; its pending first-login install was cancelled (use --with-gearlever to install it)."
	fi
else
	warn "Skipping recommended desktop dependencies for core profile."
	"$REPO_DIR/scripts/lyona-reconcile-user" --profile "$INSTALL_PROFILE" ||
		warn "The account's defaults were not all reconciled; run scripts/lyona-reconcile-user to try again."
fi

if command -v picom >/dev/null 2>&1; then
	configure_quickshell_picom_opacity
fi

if install_optional_profile; then
	! $gaming_queued || configure_arch_gamemode_access
else
	warn "Skipping optional desktop extras for $INSTALL_PROFILE profile."
fi

if install_recommended_profile; then
	# Replaces ~/.bashrc with a link, keeping the previous file as a
	# timestamped ~/.bashrc.bak.*, so this stays inside the recommended profile rather than
	# running for a core install.
	step_timer "mybash"
	info "Installing the mybash shell configuration..."
	if "$REPO_DIR/scripts/install-mybash"; then
		ok "mybash shell configuration installed; open a new shell to pick it up."
	else
		warn "The mybash shell configuration was not installed; the default bash prompt remains."
	fi

fi

step_timer "Terminal"
terminal=""
if command -v alacritty &>/dev/null; then
	terminal="alacritty"
	ok "Preferred terminal already installed: $terminal"
else
	warn "Alacritty was not installed; falling back to another supported terminal."
	for t in kitty st warp-terminal xterm; do command -v "$t" &>/dev/null && {
		terminal="$t"
		break
	}; done
	if [ -z "$terminal" ]; then
		install_supported_terminal
		terminal="$(detect_terminal)"
	fi
fi

if install_herdr_profile; then
	step_timer "Herdr"
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
	step_timer "Wallpapers"
	mkdir -p "$HOME/Pictures"
	if [ ! -d "$BG_DIR" ]; then
		info "Downloading wallpapers..."
		# Shallow, and without the repository itself: a full clone left ~139
		# MiB of history sitting in the wallpaper folder for every tool that
		# walks it, and nothing here ever pulls updates. Fetched beside it and
		# moved in whole, so a failed download leaves no folder behind.
		bg_tmp=
		if bg_tmp=$(mktemp -d "$HOME/Pictures/.wallpapers.XXXXXX") &&
			git -C "$bg_tmp" init --quiet &&
			git -C "$bg_tmp" fetch --quiet --depth 1 "$WALLPAPERS_URL" "$WALLPAPERS_REF" 2>/dev/null &&
			git -C "$bg_tmp" -c advice.detachedHead=false checkout --quiet FETCH_HEAD &&
			rm -rf -- "$bg_tmp/.git" && mv -- "$bg_tmp" "$BG_DIR"; then
			ok "Wallpapers downloaded to $BG_DIR"
		else
			[[ -z $bg_tmp ]] || rm -rf -- "$bg_tmp"
			warn "Failed to download wallpapers. Add your own to $BG_DIR."
		fi
	else
		ok "Wallpapers already present."
	fi
fi

step_timer "Display manager"
if [ -n "$currentdm" ]; then
	ok "Display manager already installed: $currentdm"
elif ! install_optional_profile; then
	warn "No display manager found; skipping display-manager installation for $INSTALL_PROFILE profile."
elif pacman -Qq lightdm >/dev/null 2>&1; then
	# Installed with the other packages.
	info "No display manager was found - enabling LightDM..."
	sudo systemctl enable lightdm.service
	currentdm="lightdm"
	ok "LightDM installed and enabled."
else
	warn "LightDM could not be installed, so no display manager was enabled; start lyona with startx."
fi

step_timer "Time synchronization"
configure_time_sync

if install_recommended_profile; then
	step_timer "NetworkManager"
	configure_network_manager
fi

step_timer "yay"
ensure_yay_installed || true

step_timer "Build (make clean; make)"
cd "$REPO_DIR"
make clean
make

# After the build: the greeter's GTK theme is generated from themes.toml with
# lyona-toml, which `make` builds. Deployed before it, a fresh checkout failed
# here and the image install stopped half-done (Sync Sprint 16, found booting
# the 2026.10.0-beta.1 image in a VM).
if [[ $currentdm == "lightdm" ]]; then
	step_timer "LightDM greeter config"
	info "Deploying LightDM Slick Greeter config..."
	install_lightdm_config
	ok "LightDM config deployed."
fi
# UPDATE-001 install provenance: an ISO install passes LYONA_SOURCE/LYONA_COMMIT
# through the environment (archiso/airootfs/root/lyona-postinstall.sh); an
# existing-system install leaves both unset and the Makefile falls back to the
# local checkout's own git HEAD. Passed as make arguments, not relied on
# through `sudo`'s environment, which does not preserve it by default.
provenance_args=()
[[ -z ${LYONA_SOURCE:-} ]] || provenance_args+=("LYONA_SOURCE=$LYONA_SOURCE")
[[ -z ${LYONA_COMMIT:-} ]] || provenance_args+=("LYONA_COMMIT=$LYONA_COMMIT")
step_timer "make install-system"
sudo make install-system \
	USER_HOME="$HOME" \
	OWNER="$(id -un)" \
	DATADIR="/usr/share" \
	"${provenance_args[@]}"
step_timer "make install-user"
make install-user \
	USER_HOME="$HOME" \
	OWNER="$(id -un)" \
	XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
	XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}" \
	XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}" \
	"${provenance_args[@]}"
step_timer "GRUB theme"
apply_grub_theme
step_timer "Display setup"
configure_displays_after_install

# Topgrade last, after every privileged step (#245): makepkg builds it from
# the AUR as the user, with the sudo timestamp closed first so nothing in the
# build can reuse that authorization; sudo then asks again to install only the
# built package. In a non-interactive run, an older cargo-built Topgrade is
# described rather than offered for removal.
if install_topgrade_profile; then
	step_timer "Topgrade"
	sudo -k 2>/dev/null || :
	info "Installing Topgrade from the AUR (topgrade-bin, from a pinned PKGBUILD)..."
	topgrade_status=0
	if [[ $NON_INTERACTIVE == true ]]; then
		"$REPO_DIR/scripts/install-topgrade" </dev/null || topgrade_status=$?
	else
		"$REPO_DIR/scripts/install-topgrade" || topgrade_status=$?
	fi
	if ((topgrade_status == 0)); then
		ok "Topgrade is installed; run topgrade. It updates itself through yay."
	else
		warn "Topgrade was not installed; run install-topgrade later to try again."
	fi
fi

print_step_timer_summary

print_completion_banner
info "Detected: $DISTRO_NAME"
echo "  • Installed version: $("$REPO_DIR/scripts/lyona-version" print 2>/dev/null || echo unknown)"
echo "  • Build configuration: $REPO_DIR/config.h"
echo "  • Reconfigure by removing config.h and running the installer again"
echo "  • Display setup: dwm-display-setup"
if grub_in_use; then
	echo "  • GRUB theme: lyona-grub-theme status (remove with lyona-grub-theme remove)"
fi
echo "  • Log out and select the 'lyona' session, or start with: startx"
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
