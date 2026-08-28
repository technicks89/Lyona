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
	} | awk 'NF' | sort -u
)
if ((${#packages[@]} == 0)); then
	printf 'Arch package map returned no required or desktop packages.\n' >&2
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

printf 'Arch required and desktop package map: PASS (%s packages)\n' \
	"${#packages[@]}"
