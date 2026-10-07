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

# #247: dwm_install_batch installs every package as one pacman -Syu --needed
# transaction, required first and each once. Missing optional packages are
# retried without, once; a missing required one fails, with no retry. pacman and
# sudo are stubs: pacman logs each call, and on the call numbered STUB_FAIL_CALL
# reports STUB_NOT_FOUND as not found (or fails plainly without them).
batch_work=$(mktemp -d)
cat >"$batch_work/sudo" <<'EOF'
#!/bin/sh
exec "$@"
EOF
cat >"$batch_work/pacman" <<'EOF'
#!/bin/bash
calls=$(($(cat "$STUB_DIR/calls" 2>/dev/null || echo 0) + 1))
printf '%s\n' "$calls" >"$STUB_DIR/calls"
printf 'LC_ALL=%s pacman %s\n' "${LC_ALL:-}" "$*" >>"$STUB_DIR/pacman.log"
[[ $calls == "${STUB_FAIL_CALL:-0}" ]] || exit 0
for name in ${STUB_NOT_FOUND:-}; do printf 'error: target not found: %s\n' "$name" >&2; done
exit 1
EOF
chmod +x "$batch_work/sudo" "$batch_work/pacman"
batch() { # FLAGS REQUIRED OPTIONAL: prints the skipped packages, then the status
	rm -f "$batch_work/calls" "$batch_work/pacman.log"
	# shellcheck disable=SC2016 # expanded by the inner bash
	# A German locale: pacman must still be run in C, for its error messages.
	env PATH="$batch_work:$PATH" STUB_DIR="$batch_work" LANG=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 bash -c '
		set -u
		. "$1"
		. "$2"
		DISTRO_FAMILY=arch
		read -ra required <<<"$4"
		read -ra optional <<<"$5"
		status=0
		dwm_install_batch $3 required optional || status=$?
		printf "SKIPPED %s\nSTATUS %s\n" "${DWM_BATCH_SKIPPED[*]}" "$status"
	' _ "$repo/scripts/dwm-utils.sh" "$repo/scripts/dwm-packages.sh" "$@" 2>"$batch_work/err"
}
batch_fail() {
	printf '%s\n' "$1" >&2
	cat "$batch_work/pacman.log" "$batch_work/err" >&2 2>/dev/null
	exit 1
}
out=$(batch --noconfirm 'make xorg-server' 'alacritty make maim')
[[ $out == $'SKIPPED \nSTATUS 0' ]] || batch_fail "a full batch: $out"
[[ $(cat "$batch_work/pacman.log") == 'LC_ALL=C pacman -Syu --needed --noconfirm -- make xorg-server alacritty maim' ]] ||
	batch_fail 'the batch is not one pacman -Syu --needed transaction, required first, each package once'
batch '' 'make' 'maim' >/dev/null
[[ $(cat "$batch_work/pacman.log") == 'LC_ALL=C pacman -Syu --needed -- make maim' ]] ||
	batch_fail 'an interactive batch was given --noconfirm'
out=$(STUB_FAIL_CALL=1 STUB_NOT_FOUND='absent-one absent-two' batch --noconfirm 'make' 'absent-one maim absent-two')
[[ $out == $'SKIPPED absent-one absent-two\nSTATUS 0' ]] || batch_fail "missing optional packages: $out"
[[ $(cat "$batch_work/pacman.log") == $'LC_ALL=C pacman -Syu --needed --noconfirm -- make absent-one maim absent-two\nLC_ALL=C pacman -Syu --needed --noconfirm -- make maim' ]] ||
	batch_fail 'missing optional packages were not retried once without them'
grep -Fq 'Not in the enabled repositories, so left out: absent-one absent-two. Retrying once without them.' "$batch_work/err" ||
	batch_fail 'the retry was not said'
out=$(STUB_FAIL_CALL=1 STUB_NOT_FOUND='make absent-one' batch --noconfirm 'make' 'absent-one maim')
[[ $out == $'SKIPPED \nSTATUS 1' ]] || batch_fail "a missing required package: $out"
[[ $(wc -l <"$batch_work/pacman.log") == 1 ]] || batch_fail 'a missing required package was retried'
grep -Fq 'A required package is not in the enabled repositories: make' "$batch_work/err" ||
	batch_fail 'a missing required package was not named'
out=$(STUB_FAIL_CALL=1 batch --noconfirm 'make' 'maim')
[[ $out == $'SKIPPED \nSTATUS 1' && $(wc -l <"$batch_work/pacman.log") == 1 ]] ||
	batch_fail "a failure that is not a missing target was retried, or passed: $out"
out=$(STUB_FAIL_CALL=2 STUB_NOT_FOUND=absent batch --noconfirm 'make' 'maim')
[[ $out == $'SKIPPED \nSTATUS 0' ]] || batch_fail "a later call failing changed the first: $out"
rm -rf "$batch_work"
# Nothing asks the repositories at install time any more: make check-aur-policy
# checks every profile's packages against them before a release.
if grep -nE 'pacman -Si|available_packages|dwm_install_available_package_profile|dwm_install_first_available' \
	"$repo/install.sh" "$repo/scripts/dwm-utils.sh" "$repo/scripts/dwm-packages.sh" | grep -v ':[[:space:]]*#' | grep -q .; then
	printf 'The installer still checks the repositories one profile at a time.\n' >&2
	exit 1
fi
[[ $(dwm_packages arch theme-optional) == qt6ct ]] || {
	printf 'Qt theming is not the one fixed package qt6ct.\n' >&2
	exit 1
}
[[ $(dwm_packages arch terminal-primary) == alacritty ]]
# install.sh: one transaction for the profiles, and the version check after it.
# shellcheck disable=SC2016 # the literal text in install.sh
[[ $(grep -c 'dwm_install_batch "${batch_flags\[@\]}" batch_required batch_optional' "$repo/install.sh") == 1 ]] || {
	printf 'install.sh does not install the profiles in one dwm_install_batch.\n' >&2
	exit 1
}
if grep -nE '^[[:space:]]*dwm_install_package_profile ' "$repo/install.sh" | grep -q .; then
	printf 'install.sh still installs a profile on its own: %s\n' "$(grep -nE '^[[:space:]]*dwm_install_package_profile ' "$repo/install.sh")" >&2
	exit 1
fi

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
# install.sh installs them in the same transaction as the gaming profile.
vulkan_line=$(grep -n 'mapfile -t gaming_packages < <(dwm_vulkan_driver_packages)' "$repo/install.sh" | cut -d: -f1)
gaming_line=$(grep -n 'gaming_packages < <(dwm_collect_packages gaming)' "$repo/install.sh" | cut -d: -f1)
[[ -n $vulkan_line && -n $gaming_line ]] && ((vulkan_line < gaming_line))
# shellcheck disable=SC2016 # the literal text in install.sh
grep -Fq 'dwm_install_batch "${batch_flags[@]}" gaming_required gaming_packages' "$repo/install.sh"

printf 'Arch required, desktop, and system-management package map: PASS (%s packages)\n' \
	"${#packages[@]}"
