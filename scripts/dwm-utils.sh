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

if [[ $DISTRO_ID == "arch" ]]; then
	DISTRO_FAMILY="arch"
fi

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
		printf 'Unsupported distribution: %s (Arch Linux is required)\n' "$DISTRO_NAME" >&2
		return 1
		;;
	esac
}

package_available() {
	case "$DISTRO_FAMILY" in
	arch)
		pacman -Si -- "$1" >/dev/null 2>&1
		;;
	*)
		return 1
		;;
	esac
}

install_optional_package() {
	local package=$1

	if package_available "$package"; then
		install_packages "$package"
		return
	fi

	printf 'Optional package is unavailable in enabled repositories: %s\n' "$package" >&2
	return 1
}

# Prints the subset of the given packages that exists in the enabled
# repositories, one per line, using a single pacman query rather than one per
# package. A package carried by more than one repository is listed once.
available_packages() {
	(($# > 0)) || return 0

	case "$DISTRO_FAMILY" in
	arch)
		pacman -Si -- "$@" 2>/dev/null |
			awk '/^Name[[:space:]]*:/ { print $3 }' |
			sort -u
		;;
	*)
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
