#!/bin/bash
# shellcheck disable=SC2059

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A checkout keeps the shared shell code beside the scripts; an install keeps it
# in PREFIX/lib/lyona, beside PREFIX/bin (Sync Sprint 12 S12-13).
lyona_lib=$SCRIPT_DIR
[[ -f $lyona_lib/dwm-utils.sh ]] || lyona_lib=${lyona_lib%bin}lib/lyona
# shellcheck disable=SC1091
source "$lyona_lib/dwm-utils.sh"
# shellcheck disable=SC1091
source "$lyona_lib/dwm-packages.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

MISSING=0

# -i / --interactive (#500, upstream dwm-titus #394): after the report, offer to
# install what the shared dependency map would and is not installed, in this
# terminal, through `sudo pacman -S --needed`: visible, confirmed here and by
# pacman. It never upgrades the system (no -y: see install_missing). The exit
# status is the report's: non-zero while anything is missing.
INTERACTIVE=0
case ${1:-} in
'') ;;
-i | --interactive) INTERACTIVE=1 ;;
-h | --help)
	printf 'usage: %s [-i|--interactive]\n' "${0##*/}"
	exit 0
	;;
*)
	printf 'usage: %s [-i|--interactive]\n' "${0##*/}" >&2
	exit 2
	;;
esac
[[ $# -le 1 ]] || {
	printf 'usage: %s [-i|--interactive]\n' "${0##*/}" >&2
	exit 2
}

check_cmd() {
	if command -v "$1" &>/dev/null; then
		printf "  ${GREEN}✓${NC} %s\n" "$1"
	else
		printf "  ${RED}✗${NC} %s ${YELLOW}(missing)${NC}\n" "$1"
		MISSING=$((MISSING + 1))
	fi
}

check_optional_cmd() {
	if command -v "$1" &>/dev/null; then
		printf "  ${GREEN}✓${NC} %s\n" "$1"
	else
		printf "  ${YELLOW}!${NC} %s ${YELLOW}(optional, missing)${NC}\n" "$1"
	fi
}

check_pkg_config() {
	if pkg-config --exists "$1" 2>/dev/null; then
		printf "  ${GREEN}✓${NC} pkg-config:%s\n" "$1"
	else
		printf "  ${RED}✗${NC} pkg-config:%s ${YELLOW}(missing)${NC}\n" "$1"
		MISSING=$((MISSING + 1))
	fi
}

check_font() {
	local label="$1"
	shift

	if [ "$#" -eq 0 ]; then
		set -- "$label"
	fi

	local pattern
	for pattern in "$@"; do
		if fc-list 2>/dev/null | command grep -qi "$pattern"; then
			printf "  ${GREEN}✓${NC} %s\n" "$label"
			return
		fi
	done

	printf "  ${RED}✗${NC} %s ${YELLOW}(not found)${NC}\n" "$label"
	MISSING=$((MISSING + 1))
}

check_font_any() {
	local label="$1"
	shift
	check_font "$label" "$@"
}

print_package_profile() {
	local label=$1
	local profile=$2
	local packages

	if ! packages="$(dwm_packages "$DISTRO_FAMILY" "$profile" | paste -sd ' ' -)"; then
		return
	fi

	if [ -n "$packages" ]; then
		printf "  %s: %s\n" "$label" "$packages"
	fi
}

echo "═══ lyona Dependency Check ═══"
echo ""
echo "Distribution: $DISTRO_NAME"
echo "Family: $DISTRO_FAMILY"
echo ""

echo "Build Dependencies (required to compile):"
check_cmd "cc"
check_cmd "make"
check_cmd "pkg-config"
for module in x11 xft xinerama xrender imlib2 x11-xcb xcb xcb-res xcb-xfixes; do
	check_pkg_config "$module"
done
echo ""

echo "X Server Components:"
if command -v Xorg &>/dev/null || command -v Xlibre &>/dev/null; then
	printf "  ${GREEN}✓${NC} X11 server\n"
else
	printf "  ${RED}✗${NC} Xorg or Xlibre ${YELLOW}(missing)${NC}\n"
	MISSING=$((MISSING + 1))
fi
# The tiers dwm-diagnostics uses too, from the shared map (Sync Sprint 16
# R16-45): a missing desktop command is a warning, not a missing dependency.
while IFS= read -r command; do
	check_cmd "$command"
done < <(dwm_command_tier required)
echo ""

echo "Desktop (recommended; the session runs without them):"
while IFS= read -r command; do
	check_optional_cmd "$command"
done < <(dwm_command_tier desktop)
if command -v dex &>/dev/null || command -v dex-autostart &>/dev/null; then
	printf "  ${GREEN}✓${NC} XDG autostart runner\n"
else
	printf "  ${YELLOW}!${NC} dex or dex-autostart ${YELLOW}(optional, missing)${NC}\n"
fi
echo ""

# Picom is part of the lyona desktop: required with it, optional without (#244).
echo "Compositor (required with the lyona desktop; window previews need it):"
while IFS= read -r command; do
	if dwm_desktop_installed; then
		check_cmd "$command"
	else
		check_optional_cmd "$command"
	fi
done < <(dwm_command_tier compositor)
echo ""

echo "Terminal Emulators (at least one required):"
TERM_FOUND=0
# Detect every terminal dwm-terminal can launch (st and warp-terminal are not in
# the official repositories, so they are recognised but never recommended).
for term in alacritty kitty st warp-terminal xterm; do
	if command -v "$term" &>/dev/null; then
		printf "  ${GREEN}✓${NC} %s\n" "$term"
		TERM_FOUND=1
	fi
done
if [ $TERM_FOUND -eq 0 ]; then
	printf "  ${RED}✗${NC} No supported terminal found ${YELLOW}(install alacritty, kitty, or xterm)${NC}\n"
	MISSING=$((MISSING + 1))
fi
if command -v herdr &>/dev/null; then
	printf "  ${GREEN}✓${NC} Herdr workspace\n"
elif [ -x "$HOME/.local/bin/herdr" ]; then
	printf "  ${GREEN}✓${NC} Herdr workspace ($HOME/.local/bin/herdr)\n"
else
	printf "  ${YELLOW}○${NC} Herdr workspace ${YELLOW}(optional; plain terminals remain available)${NC}\n"
fi
echo ""

echo "Optional (recommended):"
check_cmd "xdg-open"
echo ""

echo "Fonts:"
check_font_any "MesloLGS Nerd Font (NF compatible)" "MesloLGS Nerd Font" "MesloLGS Nerd Font Mono" "MesloLGS NF"
check_font "Noto Color Emoji"
echo ""

echo "Session Setup:"
if [ -f /usr/share/xsessions/dwm.desktop ]; then
	printf "  ${GREEN}✓${NC} dwm.desktop in /usr/share/xsessions/\n"
else
	printf "  ${YELLOW}○${NC} dwm.desktop not found (run './install.sh')\n"
fi
if [ -f "$HOME/.xinitrc" ]; then
	printf "  ${GREEN}✓${NC} ~/.xinitrc exists\n"
else
	printf "  ${YELLOW}○${NC} ~/.xinitrc not found (needed for startx)\n"
fi
echo ""

if [ $MISSING -eq 0 ]; then
	printf "${GREEN}All dependencies satisfied. Ready to build!${NC}\n"
	[ "$INTERACTIVE" = 1 ] || echo "  Run: make && sudo make install-system && make install-user"
	STATUS=0
else
	printf "${RED}$MISSING missing dependency/dependencies.${NC}\n"
	if [ "$INTERACTIVE" = 0 ] && [ "$DISTRO_FAMILY" != "unknown" ]; then
		echo ""
		echo "Package suggestions from the shared dependency map:"
		print_package_profile "Required" required
		print_package_profile "Recommended desktop" recommended
		print_package_profile "Optional extras" optional
		print_package_profile "Supported terminals" terminal
	fi
	[ "$INTERACTIVE" = 1 ] || echo "  Run: ./install.sh   (automated install)"
	STATUS=1
fi
[ "$INTERACTIVE" = 1 ] || exit "$STATUS"

# What the Control Center's install used to install: the build, X11, required
# runtime and desktop profiles, and the fonts checked above; and the primary
# terminal only when the check above found no supported one.
INSTALL_PROFILES='build x11 runtime-required desktop fonts'
[ "$TERM_FOUND" -eq 1 ] || INSTALL_PROFILES+=' terminal-primary'
readonly INSTALL_PROFILES

wait_for_enter() {
	printf '\nPress Enter to close...'
	read -r _ || :
}

# Installs PACKAGES with pacman's own summary and question. Without -y: a
# refresh without the upgrade (-Sy) is a partial upgrade, and -Syu would turn a
# dependency install into a full system upgrade. So a package database too old
# for the mirrors fails here, and says what to do instead.
install_missing() {
	local log status
	log=$(mktemp) || return 1
	sudo pacman -S --needed "$@" 2>&1 | tee "$log"
	status=${PIPESTATUS[0]}
	if [ "$status" -ne 0 ] && command grep -Eq 'failed retrieving file|target not found' "$log"; then
		printf "\n${YELLOW}Your package database is out of date: update the system first (sudo pacman -Syu), then run this check again.${NC}\n"
	fi
	rm -f "$log"
	return "$status"
}

if [ "$DISTRO_FAMILY" != arch ] || ! command -v pacman >/dev/null 2>&1; then
	echo ""
	echo "Installing needs pacman on Arch Linux; nothing was installed."
	wait_for_enter
	exit "$STATUS"
fi
read -r -a PROFILES <<<"$INSTALL_PROFILES"
mapfile -t WANTED < <(dwm_collect_packages "${PROFILES[@]}" 2>/dev/null)
# pacman -T prints the ones not installed: it exits 0 when there are none and
# 127 when there are some. Anything else is a failed query, never "nothing to
# install".
ABSENT_STATUS=0
ABSENT_TEXT=$(pacman -T "${WANTED[@]}" 2>/dev/null) || ABSENT_STATUS=$?
if [ "$ABSENT_STATUS" -ne 0 ] && [ "$ABSENT_STATUS" -ne 127 ]; then
	echo ""
	printf "${RED}Could not ask pacman which packages are installed (status %s); nothing was installed.${NC}\n" "$ABSENT_STATUS"
	wait_for_enter
	exit 1
fi
ABSENT=()
[ -z "$ABSENT_TEXT" ] || mapfile -t ABSENT <<<"$ABSENT_TEXT"
echo ""
if [ "${#ABSENT[@]}" -eq 0 ]; then
	if [ "$STATUS" -eq 0 ]; then
		echo "Nothing to install."
	else
		echo "Every package the dependency map installs is installed; see the report above for the rest."
	fi
	wait_for_enter
	exit "$STATUS"
fi
echo "Not installed: ${ABSENT[*]}"
printf 'Install now? [y/N] '
read -r ANSWER || ANSWER=
case $ANSWER in
y | Y | yes | YES | Yes) ;;
*)
	echo "Nothing was installed."
	wait_for_enter
	exit "$STATUS"
	;;
esac
if install_missing "${ABSENT[@]}"; then
	echo ""
	echo "Checking again:"
	echo ""
	"$0"
	STATUS=$?
else
	printf "\n${RED}The install did not complete.${NC}\n"
	STATUS=1
fi
wait_for_enter
exit "$STATUS"
