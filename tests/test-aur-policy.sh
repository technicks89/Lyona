#!/usr/bin/env bash
# Lyona limits the AUR to where an official package cannot do the job (decision
# D-27, docs/AUR-PACKAGES.md). Every AUR build goes through one helper,
# scripts/dwm-aur.sh, and its one table of reviewed pins (#281):
#   - install.sh bootstraps yay-bin for the user;
#   - install_legacy_nvidia_driver builds the legacy NVIDIA drivers, when the
#     CachyOS repository cannot supply them (Sprint 14);
#   - install-topgrade builds Topgrade from topgrade-bin (#245);
# and run_system in lyona-update-terminal runs the user's own `yay -Syu`
# (Sprint 15). Every package the other profiles and the live ISO name must
# resolve in core, extra or multilib. A new AUR use is added here, to
# docs/AUR-PACKAGES.md, to the pin table, and as a decision, never quietly.
set -euo pipefail

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

aur_helper=$repo/scripts/dwm-aur.sh
aur_exception_profiles='gpu-nvidia-580xx gpu-nvidia-470xx'

# The user's own update (Sync Sprint 15 S15-04, decision D-26): Settings >
# System runs `yay -Syu` in the user's terminal when yay is installed, so
# packages already built from the AUR (the legacy drivers) are updated with
# everything else. Inside run_system that exact upgrade is allowed, with no
# package names and so nothing new installed; any other helper call still fails.
user_update_file=$repo/scripts/lyona-update-terminal
user_update_function=run_system
user_update_span=$(awk -v name="$user_update_function" '
	$0 ~ "^" name "\\(\\) \\{$" { start = NR }
	start && !end && /^}$/ { end = NR }
	END { if (start && end) print start, end }
' "$user_update_file")
[[ -n $user_update_span ]] || fail "$user_update_function is missing from ${user_update_file##*/}"
read -r user_update_start user_update_end <<<"$user_update_span"
# Drop the full upgrade, and the line that announces it, inside run_system.
outside_user_update() {
	awk -v file="$user_update_file" -v start="$user_update_start" -v end="$user_update_end" '
		{
			split($0, part, ":")
			line = substr($0, length(part[1]) + length(part[2]) + 3)
			inside = part[1] == file && part[2] + 0 >= start && part[2] + 0 <= end
			if (inside && (line ~ /^[[:space:]]*yay -Syu$/ || line ~ /^[[:space:]]*printf .==> yay -Syu /)) next
			print
		}'
}

# ── 1. the AUR is reached only through dwm-aur.sh ────────────────────────

self=$repo/tests/test-aur-policy.sh
surfaces=("$repo/install.sh" "$repo/Makefile" "$repo/scripts" "$repo/archiso" "$repo/config" "$repo/.github/workflows")

helper_installs=$(grep -rInE '(^|[^[:alnum:]_-])(yay|paru|trizen|pikaur|aurman)[[:space:]]+(-S[[:alpha:]]*|--sync|install)([[:space:]]|$)' \
	"${surfaces[@]}" 2>/dev/null | grep -Fv "$self" | outside_user_update || true)
if [[ -n $helper_installs ]]; then
	printf 'An AUR helper is used outside the listed places:\n%s\n' "$helper_installs" >&2
	fail 'list a new AUR use in docs/AUR-PACKAGES.md and this test, with a decision, or use an official package'
fi

# The AUR's address, or makepkg run with options, anywhere but the helper.
stray=$(grep -rInE 'aur\.archlinux\.org|(^|[^[:alnum:]_-])makepkg[[:space:]]+-' "${surfaces[@]}" 2>/dev/null |
	grep -Fv "$self" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v "^$aur_helper:" || true)
if [[ -n $stray ]]; then
	printf 'AUR access outside dwm-aur.sh:\n%s\n' "$stray" >&2
	fail 'every AUR build goes through scripts/dwm-aur.sh build-pinned (or fetch and build), at a reviewed pin'
fi

# The one pin table: these bases, each at a full commit, and no other.
pins=$(awk '/^readonly aur_pins=/ { f = 1 } f { print } f && /'"'"'$/ { exit }' "$aur_helper" |
	sed -E "s/^readonly aur_pins='//; s/'$//")
[[ $(cut -f1 <<<"$pins" | sort | paste -sd ' ') == 'nvidia-470xx-utils nvidia-580xx-utils topgrade-bin yay-bin' ]] ||
	fail "dwm-aur.sh pins other bases than the listed AUR uses: $(cut -f1 <<<"$pins" | paste -sd ' ')"
while IFS=$'\t' read -r base ref _; do
	[[ $ref =~ ^[0-9a-f]{40}$ ]] || fail "$base is not pinned to a full commit"
	[[ $(bash "$aur_helper" pin "$base") == "$ref" ]] || fail "dwm-aur.sh pin $base does not give its table entry"
done <<<"$pins"
if bash "$aur_helper" pin not-a-pinned-base >/dev/null 2>&1; then
	fail 'dwm-aur.sh gave a pin for a base that is not in its table'
fi

# Each caller builds its own base through the helper, and only that base.
grep -Fq 'dwm-aur.sh" build-pinned yay-bin' "$repo/install.sh" ||
	fail 'install.sh does not build yay-bin through dwm-aur.sh'
grep -Fq 'build_pin topgrade-bin' "$repo/scripts/install-topgrade" ||
	fail 'install-topgrade does not build topgrade-bin through dwm-aur.sh'
postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
# shellcheck disable=SC2016 # the literal text in the postinstall
for fragment in 'base=nvidia-$branch-utils' 'dwm-aur.sh" fetch "$base"' 'dwm-aur.sh" build "$build/src"'; do
	grep -Fq "$fragment" "$postinstall" || fail "the legacy NVIDIA drivers are not built through dwm-aur.sh ($fragment)"
done

# The exception's packages each come from their branch's pinned base.
# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"
for profile in $aur_exception_profiles; do
	branch=${profile#gpu-nvidia-}
	base=nvidia-$branch-utils
	[[ $(cut -f1 <<<"$pins") == *"$base"* ]] || fail "the $profile packages have no pinned AUR base $base"
	for package in $(dwm_packages arch "$profile"); do
		[[ $package == "nvidia-$branch-"* ]] ||
			fail "$package is in $profile but not built by its pinned base $base"
	done
done

# ── 2. every named package resolves in an official repository ────────────

if ! command -v pacman >/dev/null 2>&1 || ! command -v pacman-conf >/dev/null 2>&1; then
	printf 'AUR use is limited to the listed places. pacman is unavailable, so repository membership was not checked.\n'
	printf 'AUR policy: PASS\n'
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
	printf 'AUR use is limited to the listed places. core and extra are not synced here, so repository membership was not checked.\n'
	printf 'AUR policy: PASS\n'
	exit 0
fi

# shellcheck source=scripts/dwm-packages.sh
source "$repo/scripts/dwm-packages.sh"

profiles=$(sed -n 's/^\t\(arch:[a-z0-9-]*\))$/\1/p' "$repo/scripts/dwm-packages.sh" | sed 's/^arch://' | sort -u)
# The exception's profiles are checked above, against their pins, instead.
for profile in $aur_exception_profiles; do
	profiles=$(grep -vx "$profile" <<<"$profiles")
done
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
printf 'AUR policy: PASS\n'
