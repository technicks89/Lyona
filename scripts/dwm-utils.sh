#!/usr/bin/env bash

DISTRO_ID="unknown"
DISTRO_NAME="Unknown Linux"
DISTRO_FAMILY="unknown"
DWM_PACKAGE_COMMAND=()
OS_RELEASE_FILE="/etc/os-release"
if [[ ${DWM_TEST_MODE:-0} == 1 && -n ${DWM_OS_RELEASE:-} ]]; then
	OS_RELEASE_FILE=$DWM_OS_RELEASE
fi

if [[ -r $OS_RELEASE_FILE ]]; then
	# shellcheck disable=SC1090
	source "$OS_RELEASE_FILE"
	DISTRO_ID="${ID:-unknown}"
	DISTRO_NAME="${PRETTY_NAME:-${NAME:-Unknown Linux}}"
fi

# The architecture lyona installs for: bash's own, which is the userland's and
# so pacman's (a 32-bit Arch Linux ARM userland on a 64-bit kernel is not
# aarch64, whatever uname says). A shell variable, so sourcing this file starts
# no process. DWM_MACHINE in test mode.
DISTRO_MACHINE=$HOSTTYPE
if [[ ${DWM_TEST_MODE:-0} == 1 && -n ${DWM_MACHINE:-} ]]; then
	DISTRO_MACHINE=$DWM_MACHINE
fi

# The identities lyona accepts (SPEC.md section 4): Arch Linux (ID=arch), and
# Arch Linux ARM (ID=archarm) on aarch64 only, experimental (decision A-1,
# docs/sprints/ARM64.md). Nothing is accepted for its ID_LIKE alone, and
# 32-bit Arch Linux ARM (armv7h) is not.
case $DISTRO_ID in
arch) DISTRO_FAMILY="arch" ;;
archarm) [[ $DISTRO_MACHINE != aarch64 ]] || DISTRO_FAMILY="arch" ;;
esac

# The Arch family: every path an accepted identity takes. Architecture gates
# (CachyOS and gaming are x86_64 only) stay where they are.
is_arch_family() {
	[[ $DISTRO_FAMILY == "arch" ]]
}

case "$DISTRO_FAMILY" in
arch)
	if ((EUID == 0)); then
		DWM_PACKAGE_COMMAND=(pacman -S --needed --noconfirm)
	else
		DWM_PACKAGE_COMMAND=(sudo pacman -S --needed --noconfirm)
	fi
	PKG_CMD="${DWM_PACKAGE_COMMAND[*]}"
	;;
*)
	PKG_CMD="unavailable"
	;;
esac
export PKG_CMD

install_packages() {
	case "$DISTRO_FAMILY" in
	arch)
		"${DWM_PACKAGE_COMMAND[@]}" "$@"
		;;
	*)
		printf 'Unsupported distribution: %s (Arch Linux, or Arch Linux ARM on aarch64, is required)\n' "$DISTRO_NAME" >&2
		return 1
		;;
	esac
}

detect_gpu() {
	if command -v lspci &>/dev/null; then
		local vga
		vga=$(lspci 2>/dev/null | command grep -i 'vga\|3d\|display' || true)
		if echo "$vga" | command grep -qi nvidia; then
			echo "nvidia"
		elif echo "$vga" | command grep -qi 'amd\|radeon'; then
			echo "amd"
		elif echo "$vga" | command grep -qi intel; then
			echo "intel"
		else
			echo "unknown"
		fi
	else
		echo "unknown"
	fi
}

detect_battery() {
	command ls /sys/class/power_supply/ 2>/dev/null | command grep -E '^BAT[0-9]' | head -1
}

detect_adapter() {
	command ls /sys/class/power_supply/ 2>/dev/null | command grep -Ev '^BAT' | head -1
}

is_laptop() {
	[ -n "$(detect_battery)" ]
}

detect_terminal() {
	for t in alacritty kitty st warp-terminal xterm; do
		if command -v "$t" &>/dev/null; then
			echo "$t"
			return
		fi
	done
	echo "xterm"
}
