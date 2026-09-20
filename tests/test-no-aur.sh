#!/usr/bin/env bash
# Lyona keeps an AUR helper installed for the user (install.sh bootstraps a
# pinned yay-bin), but no package Lyona installs may depend on the AUR: every
# package the profiles and the live ISO name must resolve in core, extra or
# multilib, and the helper must never be used to install one. docs/AUR-PACKAGES.md
# records the audit behind this.
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

# ── 1. the AUR helper is a convenience, never a package source ───────────

self=$repo/tests/test-no-aur.sh
surfaces=("$repo/install.sh" "$repo/Makefile" "$repo/scripts" "$repo/archiso" "$repo/config" "$repo/.github/workflows")

helper_installs=$(grep -rInE '(^|[^[:alnum:]_-])(yay|paru|trizen|pikaur|aurman)[[:space:]]+(-S[[:alpha:]]*|--sync|install)([[:space:]]|$)' \
	"${surfaces[@]}" 2>/dev/null | grep -Fv "$self" || true)
if [[ -n $helper_installs ]]; then
	printf 'An AUR helper is used to install packages:\n%s\n' "$helper_installs" >&2
	fail 'packages must come from the official repositories, not through an AUR helper'
fi

# The only place that may reach the AUR is the helper bootstrap in install.sh.
stray=$(grep -rInE 'aur\.archlinux\.org|(^|[^[:alnum:]_-])makepkg([^[:alnum:]_-]|$)' \
	"$repo/Makefile" "$repo/scripts" "$repo/archiso" "$repo/config" "$repo/.github/workflows" 2>/dev/null |
	grep -Fv "$self" || true)
if [[ -n $stray ]]; then
	printf 'AUR access outside the helper bootstrap in install.sh:\n%s\n' "$stray" >&2
	fail 'only install.sh may reach the AUR, and only to bootstrap the helper'
fi

# ── 2. every named package resolves in an official repository ────────────

if ! command -v pacman >/dev/null 2>&1 || ! command -v pacman-conf >/dev/null 2>&1; then
	printf 'No AUR package sources found. pacman is unavailable, so repository membership was not checked.\n'
	printf 'No-AUR guard: PASS\n'
	exit 0
fi

official=()
for candidate in core extra multilib; do
	if pacman-conf --repo-list 2>/dev/null | grep -Fxq "$candidate" &&
		[[ -n $(pacman -Sl "$candidate" 2>/dev/null | head -n 1) ]]; then
		official+=("$candidate")
	fi
done
if [[ " ${official[*]} " != *" core "* || " ${official[*]} " != *" extra "* ]]; then
	printf 'No AUR package sources found. core and extra are not synced here, so repository membership was not checked.\n'
	printf 'No-AUR guard: PASS\n'
	exit 0
fi

# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"

profiles=$(sed -n 's/^\t\(arch:[a-z0-9-]*\))$/\1/p' "$repo/scripts/dwm-packages.sh" | sed 's/^arch://' | sort -u)
[[ -n $profiles ]] || fail 'could not enumerate the package profiles'

names=$work/names
{
	for profile in $profiles; do
		# Same architecture gate the profiles use; gaming is x86_64 only.
		ARCH=x86_64 dwm_packages arch "$profile"
	done
	grep -Ev '^[[:space:]]*(#|$)' "$repo/archiso/packages.x86_64"
} | sort -u >"$names"
[[ -s $names ]] || fail 'no package names were collected'

missing=()
while IFS= read -r package; do
	resolved=false
	for repository in "${official[@]}"; do
		if pacman -Si "$repository/$package" >/dev/null 2>&1; then
			resolved=true
			break
		fi
	done
	# base-devel and similar are groups, not packages.
	if [[ $resolved == false ]] && pacman -Sg "$package" >/dev/null 2>&1; then
		resolved=true
	fi
	[[ $resolved == true ]] || missing+=("$package")
done <"$names"

# A host without multilib cannot vouch for the lib32-* packages; do not fail
# them, but do not hide that they went unchecked either.
if [[ " ${official[*]} " != *" multilib "* ]]; then
	remaining=()
	for package in "${missing[@]}"; do
		case $package in
		lib32-* | steam) printf 'Not checked (multilib is not enabled here): %s\n' "$package" ;;
		*) remaining+=("$package") ;;
		esac
	done
	missing=("${remaining[@]}")
fi

if ((${#missing[@]} > 0)); then
	printf 'Not in core, extra or multilib (AUR-only, renamed or removed): %s\n' "${missing[*]}" >&2
	fail 'a package profile names something outside the official repositories'
fi

printf 'Checked %s packages against: %s\n' "$(wc -l <"$names" | tr -d ' ')" "${official[*]}"
printf 'No-AUR guard: PASS\n'
