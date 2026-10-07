#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
work=$(mktemp -d)
trap 'find "$work" -depth -delete' EXIT

for command_name in pacman sort comm awk; do
	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'Missing required Arch package-check command: %s\n' \
			"$command_name" >&2
		exit 1
	fi
done

# shellcheck source=scripts/dwm-utils.sh
source "$repo/scripts/dwm-utils.sh"
# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"

if [[ $DISTRO_ID != arch || $DISTRO_FAMILY != arch ]]; then
	printf 'Arch package validation requires Arch Linux; detected %s.\n' \
		"$DISTRO_NAME" >&2
	exit 1
fi

mapfile -t packages < <(
	{
		dwm_packages arch required
		dwm_packages arch desktop
		dwm_packages arch browser
		dwm_packages arch system-management
		dwm_packages arch system-management-optional
	} | awk 'NF' | sort -u
)
if ((${#packages[@]} == 0)); then
	printf 'Arch package map returned no required, desktop, or system-management packages.\n' >&2
	exit 1
fi

printf '%s\n' "${packages[@]}" >"$work/expected"
: >"$work/available"
for package in "${packages[@]}"; do
	if pacman -Si -- "$package" >/dev/null 2>&1; then
		printf '%s\n' "$package" >>"$work/available"
	fi
done
sort -u -o "$work/available" "$work/available"
comm -23 "$work/expected" "$work/available" >"$work/missing"
if [[ -s $work/missing ]]; then
	printf 'Unavailable Arch package-map entries:\n' >&2
	sed 's/^/  /' "$work/missing" >&2
	exit 1
fi

mkdir -p "$work/bin"
cat >"$work/bin/pacman" <<'EOF'
#!/bin/sh
[ "$*" = '-Qq power-profiles-daemon' ] || exit 2
[ "${DWM_TEST_PPD_PROVIDER:-0}" = 1 ]
EOF
chmod +x "$work/bin/pacman"

installed_provider_packages=$(PATH="$work/bin:$PATH" DWM_TEST_PPD_PROVIDER=1 bash -c '
	. "$1"
	DISTRO_FAMILY=arch
	install_packages() { printf "%s\n" "$@"; }
	dwm_install_package_profile desktop
' _ "$repo/scripts/dwm-packages.sh")
if printf '%s\n' "$installed_provider_packages" | grep -Fxq power-profiles-daemon; then
	printf 'Existing Power Profiles provider would be replaced.\n' >&2
	exit 1
fi
printf '%s\n' "$installed_provider_packages" | grep -Fxq upower
printf '%s\n' "$installed_provider_packages" | grep -Fxq inotify-tools

missing_provider_packages=$(PATH="$work/bin:$PATH" DWM_TEST_PPD_PROVIDER=0 bash -c '
	. "$1"
	DISTRO_FAMILY=arch
	install_packages() { printf "%s\n" "$@"; }
	dwm_install_package_profile desktop
' _ "$repo/scripts/dwm-packages.sh")
printf '%s\n' "$missing_provider_packages" | grep -Fxq power-profiles-daemon

# The browser (#240): Firefox, unless the user's default https handler is
# another browser that is installed.
recommended_packages=$(dwm_packages arch recommended)
grep -Fxq firefox <<<"$recommended_packages" ||
	{
		printf 'firefox is not in the recommended packages.\n' >&2
		exit 1
	}
cat >"$work/bin/xdg-mime" <<'EOF'
#!/bin/sh
[ "$*" = 'query default x-scheme-handler/https' ] || exit 2
[ -n "${DWM_TEST_BROWSER:-}" ] && printf '%s\n' "$DWM_TEST_BROWSER"
exit 0
EOF
chmod +x "$work/bin/xdg-mime"
mkdir -p "$work/share/applications"
printf '[Desktop Entry]\nType=Application\nExec=chromium %%U\n' >"$work/share/applications/chromium.desktop"
printf '#!/bin/sh\nexit 0\n' >"$work/bin/chromium"
chmod +x "$work/bin/chromium"
# A leftover entry whose browser was removed.
printf '[Desktop Entry]\nType=Application\nExec=/opt/gone/browser %%U\n' >"$work/share/applications/gone.desktop"
browser_install() { # DEFAULT-BROWSER
	# shellcheck disable=SC2016 # expanded by the inner shell
	PATH="$work/bin:$PATH" DWM_TEST_BROWSER="$1" XDG_DATA_HOME="$work/none" XDG_DATA_DIRS="$work/share" bash -c '
		. "$1"
		DISTRO_FAMILY=arch
		install_packages() { printf "INSTALL %s\n" "$*"; }
		dwm_install_package_profile browser
	' _ "$repo/scripts/dwm-packages.sh" 2>&1
}
for case in '' firefox.desktop removed.desktop gone.desktop; do
	out=$(browser_install "$case")
	[[ $out == 'INSTALL firefox' ]] || {
		printf 'Firefox was not installed with the default browser %s: %s\n' "${case:-unset}" "$out" >&2
		exit 1
	}
done
out=$(browser_install chromium.desktop)
[[ $out == 'Keeping the default browser (chromium.desktop); skipping firefox.' ]] || {
	printf 'Firefox was installed beside the default browser chromium: %s\n' "$out" >&2
	exit 1
}

# Several profiles must resolve to a single transaction, with no package
# repeated across them.
batched=$(bash -c '
	. "$1"
	. "$2"
	DISTRO_FAMILY=arch
	calls=0
	install_packages() {
		calls=$((calls + 1))
		printf "CALL%s %s\n" "$calls" "$*"
	}
	dwm_install_package_profile build x11 runtime-required
' _ "$repo/scripts/dwm-utils.sh" "$repo/scripts/dwm-packages.sh")
if [[ $(printf '%s\n' "$batched" | grep -c '^CALL') -ne 1 ]]; then
	printf 'Required profiles were installed in more than one transaction:\n%s\n' \
		"$batched" >&2
	exit 1
fi
batched_packages=$(printf '%s\n' "$batched" | sed 's/^CALL1 //' | tr ' ' '\n')
if [[ $(printf '%s\n' "$batched_packages" | sort | uniq -d | wc -l) -ne 0 ]]; then
	printf 'Batched transaction repeats a package:\n%s\n' \
		"$(printf '%s\n' "$batched_packages" | sort | uniq -d)" >&2
	exit 1
fi
printf '%s\n' "$batched_packages" | grep -Fxq make
printf '%s\n' "$batched_packages" | grep -Fxq xorg-server

# An optional profile queries availability once and installs what exists in
# one transaction, still reporting each package it had to skip.
optional_out=$(bash -c '
	. "$1"
	. "$2"
	DISTRO_FAMILY=arch
	dwm_packages() { printf "alpha\nabsent-one\nbeta\nabsent-two\n"; }
	available_packages() {
		printf "QUERY %s\n" "$*" >&2
		for candidate in "$@"; do
			case $candidate in
			absent-*) continue ;;
			esac
			printf "%s\n" "$candidate"
		done
	}
	install_packages() { printf "INSTALL %s\n" "$*"; }
	dwm_install_available_package_profile fake
' _ "$repo/scripts/dwm-utils.sh" "$repo/scripts/dwm-packages.sh" 2>"$work/optional.err") &&
	{
		printf 'Optional profile with missing packages should report failure.\n' >&2
		exit 1
	}
if [[ $(printf '%s\n' "$optional_out" | grep -c '^INSTALL') -ne 1 ]]; then
	printf 'Optional profile did not install in a single transaction:\n%s\n' \
		"$optional_out" >&2
	exit 1
fi
printf '%s\n' "$optional_out" | grep -Fqx 'INSTALL alpha beta'
if [[ $(grep -c '^QUERY' "$work/optional.err") -ne 1 ]]; then
	printf 'Optional profile did not probe availability in a single query.\n' >&2
	cat "$work/optional.err" >&2
	exit 1
fi
grep -Fq 'unavailable in enabled repositories: absent-one' "$work/optional.err"
grep -Fq 'unavailable in enabled repositories: absent-two' "$work/optional.err"

"$repo/install.sh" --dry-run --non-interactive --profile core >/dev/null

# The login keyring is part of the desktop group, not an optional extra (Sync
# Sprint 15 S15-01, decision D-24), and is listed once.
dwm_packages arch keyring | grep -Fxq gnome-keyring
dwm_packages arch desktop | grep -Fxq gnome-keyring
if dwm_packages arch desktop-optional | grep -Fxq gnome-keyring; then
	printf 'gnome-keyring is still in desktop-optional.\n' >&2
	exit 1
fi
[[ $(dwm_packages arch full | grep -Fxc gnome-keyring) -eq 1 ]]

# docs/src/dependencies.md documents every package the map can install (Sync
# Sprint 11 S11-05). The misses are collected in a variable and tested afterwards:
# an exit inside a pipeline would only leave that pipeline's subshell.
undocumented=$(
	for profile in full iso terminal terminal-primary lightdm qml-development qml-validation; do
		dwm_packages arch "$profile"
	done | awk 'NF' | sort -u |
		while IFS= read -r package; do
			grep -Fq -- "\`$package\`" "$repo/docs/src/dependencies.md" || printf '%s\n' "$package"
		done
)
if [[ -n $undocumented ]]; then
	printf 'docs/src/dependencies.md does not mention:\n%s\n' "$undocumented" >&2
	exit 1
fi

# Sync Sprint 16: Steam's Vulkan drivers, named for the GPU so pacman never picks
# a provider (with the CachyOS repositories it picked mesa-git, which conflicts
# with mesa). lspci and pacman are stubbed.
vulkan_work=$(mktemp -d)
trap 'rm -rf "$vulkan_work"' EXIT
cat >"$vulkan_work/lspci" <<'EOF'
#!/bin/sh
printf '%s\n' "${STUB_LSPCI:-}"
EOF
cat >"$vulkan_work/pacman" <<'EOF'
#!/bin/sh
printf '%s\n' ${STUB_PACMAN_Q:-}
EOF
chmod +x "$vulkan_work/lspci" "$vulkan_work/pacman"
vulkan() {
	# shellcheck disable=SC2016 # expanded by the inner bash
	env PATH="$vulkan_work:$PATH" STUB_LSPCI="$1" STUB_PACMAN_Q="${2:-}" bash -c \
		'. "$0" && dwm_vulkan_driver_packages | tr "\n" " "' "$repo/scripts/dwm-packages.sh"
}
[[ $(vulkan '00:02.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 22') == 'vulkan-radeon lib32-vulkan-radeon ' ]]
[[ $(vulkan '00:02.0 VGA compatible controller: Intel Corporation UHD Graphics 630') == 'vulkan-intel lib32-vulkan-intel ' ]]
[[ $(vulkan '01:00.0 VGA compatible controller: NVIDIA Corporation GA104' 'nvidia-utils') == 'nvidia-utils lib32-nvidia-utils ' ]]
[[ $(vulkan '01:00.0 VGA compatible controller: NVIDIA Corporation GM204' 'nvidia-580xx-utils') == 'nvidia-580xx-utils lib32-nvidia-580xx-utils ' ]]
[[ $(vulkan '01:00.0 VGA compatible controller: NVIDIA Corporation GK104') == 'vulkan-nouveau lib32-vulkan-nouveau ' ]]
[[ $(vulkan '00:01.0 VGA compatible controller: Red Hat, Inc. Virtio 1.0 GPU') == 'vulkan-swrast lib32-vulkan-swrast ' ]]
# A laptop with two GPUs gets both drivers.
[[ $(vulkan $'00:02.0 VGA compatible controller: Intel Corporation\n01:00.0 3D controller: NVIDIA Corporation' 'nvidia-utils') == 'vulkan-intel lib32-vulkan-intel nvidia-utils lib32-nvidia-utils ' ]]
# install.sh installs them before the gaming profile.
vulkan_line=$(grep -n 'mapfile -t vulkan_drivers < <(dwm_vulkan_driver_packages)' "$repo/install.sh" | cut -d: -f1)
gaming_line=$(grep -n 'dwm_install_available_package_profile gaming;' "$repo/install.sh" | cut -d: -f1)
[[ -n $vulkan_line && -n $gaming_line ]] && ((vulkan_line < gaming_line))

printf 'Arch required, desktop, and system-management package map: PASS (%s packages)\n' \
	"${#packages[@]}"
