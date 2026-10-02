#!/usr/bin/env bash
set -euo pipefail

# Sync Sprint 14 S14-02 and S14-03: the live medium's driver for an older NVIDIA
# card. The postinstall's own functions run against a stub arch-chroot that logs
# every command and emulates git, makepkg and the file operations in a scratch
# target. Checked: the CachyOS repository comes first; failing that, the pinned
# AUR PKGBUILD is built, its dependencies installed by root, makepkg run only as
# the new user, and only the profile's packages installed; a failed build
# installs nothing and leaves nouveau; and each kind of card reaches the right
# path.

# shellcheck source=tests/lib.sh
. "$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)/lib.sh"
make_workspace

postinstall=$repo/archiso/airootfs/root/lyona-postinstall.sh
functions=$work/functions.sh
{
	awk '/^export LEGACY_NVIDIA_PINS=/{f=1} f{print} f && /'"'"'$/{exit}' "$postinstall"
	for name in installed_kernels install_legacy_nvidia_driver install_gpu_drivers; do
		awk -v name="$name" '$0 ~ "^" name "\\(\\) \\{$" {f=1} f{print} f && /^}$/{exit}' "$postinstall"
	done
} >"$functions"
for name in installed_kernels install_legacy_nvidia_driver install_gpu_drivers; do
	grep -q "^$name() {" "$functions" || fail "could not read $name from the postinstall"
done
grep -q '^export LEGACY_NVIDIA_PINS=' "$functions" || fail 'could not read the pin table'

stub=$work/stub
mkdir -p "$stub/bin"
cat >"$stub/bin/arch-chroot" <<'STUB'
#!/bin/bash
root=$1
shift
printf '%s\n' "$*" >>"$STUB_LOG"
case $1 in
pacman)
	if [[ $2 == -Qq ]]; then
		if (($# > 2)); then
			[[ -e $root/packages/$3 ]] || exit 1
			printf '%s\n' "$3"
		else
			printf 'linux\nlinux-cachyos\nlinux-firmware\n'
		fi
		exit 0
	fi
	if [[ -n ${STUB_PACMAN_FAIL:-} && " $* " == *"$STUB_PACMAN_FAIL"* ]]; then
		for package in ${STUB_PARTIAL_INSTALL:-}; do
			: >"$root/packages/$package"
		done
		exit 1
	fi
	if [[ $2 == -R ]]; then
		[[ -z ${STUB_REMOVE_FAIL:-} ]] || exit 1
		shift 3
		for package in "$@"; do rm -f -- "$root/packages/$package"; done
	fi
	exit 0
	;;
rm) rm -rf -- "$root${*: -1}" ;;
install) mkdir -p -- "$root${*: -1}" ;;
runuser)
	# runuser -u USER -- env HOME=DIR COMMAND...
	shift 6
	case "$1 $2" in
	"git clone") mkdir -p -- "$root${*: -1}" ;;
	"git -C") ;;
	"sh -c")
		dir=${*: -1}
		case $3 in
		*--printsrcinfo*) cat "$STUB_SRCINFO" ;;
		*makepkg*)
			[[ -z ${STUB_MAKEPKG_FAIL:-} ]] || exit 1
			for package in "nvidia-$STUB_BRANCH-utils" "opencl-nvidia-$STUB_BRANCH" "nvidia-$STUB_BRANCH-dkms"; do
				: >"$root$dir/$package-1.0-1-x86_64.pkg.tar.zst"
			done
			;;
		esac
		;;
	*) exit 9 ;;
	esac
	;;
*) exit 9 ;;
esac
STUB
cat >"$stub/bin/lspci" <<'STUB'
#!/bin/sh
if [ "$#" = 0 ]; then
	printf '01:00.0 VGA compatible controller: NVIDIA Corporation Device\n'
	exit 0
fi
[ "$*" = "-n -mm -d 10de::0300" ] || exit 0
printf '01:00.0 "0300" "10de" "%s" -ra1 "1458" "3717"\n' "$STUB_DEVICE"
STUB
chmod +x "$stub/bin/arch-chroot" "$stub/bin/lspci"
printf '%s\n' 'pkgbase = nvidia-580xx-utils' $'\tpkgver = 1.0' $'\tmakedepends = foo-make' \
	$'\tdepends = libglvnd' $'\tdepends = egl-wayland>=2:1.1' 'pkgname = nvidia-580xx-utils' \
	$'\tdepends = libglvnd' 'pkgname = opencl-nvidia-580xx' $'\tdepends = zlib' \
	'pkgname = nvidia-580xx-dkms' $'\tdepends = dkms' $'\tdepends = nvidia-580xx-utils=1.0' >"$work/srcinfo"

target=$work/target
legacy() { # BRANCH, with the stub's settings in the environment
	rm -rf "$target" "$work/log" "$work/aur-marker"
	mkdir -p "$target/packages"
	local package
	for package in ${STUB_PREINSTALLED:-}; do
		: >"$target/packages/$package"
	done
	: >"$work/log"
	# shellcheck disable=SC2016 # $1 to $3 are the inner bash's
	env STUB_LOG="$work/log" STUB_SRCINFO="$work/srcinfo" STUB_BRANCH="$1" PATH="$stub/bin:$PATH" \
		TARGET="$target" CACHYOS_MARKER="${cachyos_marker:-$work/no-cachyos}" \
		NVIDIA_AUR_MARKER="$work/aur-marker" target_user=tester target_group=tester \
		target_home=/home/tester bash -c '
			set -Eeuo pipefail
			. "$1/scripts/dwm-packages.sh"
			. "$2"
			install_legacy_nvidia_driver "$3" 1b80
		' sh "$repo" "$functions" "$1"
}

# ── the CachyOS repository first, prebuilt ──────────────────────────────
: >"$work/cachyos"
out=$(cachyos_marker=$work/cachyos legacy 580xx)
assert_equals 'pacman -S --noconfirm --needed cachyos/nvidia-580xx-dkms cachyos/nvidia-580xx-utils linux-headers linux-cachyos-headers' \
	"$(grep '^pacman -S' "$work/log")" 'the CachyOS install'
grep -q '^runuser' "$work/log" && fail 'the CachyOS path built from the AUR as well'
assert_string_contains "$out" 'from the CachyOS repository'

# ── the CachyOS repository failing falls back to the AUR ────────────────
out=$(cachyos_marker=$work/cachyos STUB_PACMAN_FAIL=cachyos/ legacy 580xx)
assert_string_contains "$out" 'building it from the AUR instead'
grep -q 'makepkg --noconfirm' "$work/log" || fail 'no AUR build after the CachyOS repository failed'

# Failed transactions clean up only newly installed legacy packages, before
# an AUR build that can also fail. Existing packages and other deps survive.
grep -q '^pacman -R' "$work/log" && fail 'removed packages after an atomic failure'
for branch in 580xx 470xx; do
	out=$(cachyos_marker=$work/cachyos STUB_PACMAN_FAIL=cachyos/ STUB_MAKEPKG_FAIL=1 \
		STUB_PREINSTALLED="nvidia-470xx-utils linux-headers" \
		STUB_PARTIAL_INSTALL="nvidia-580xx-dkms nvidia-580xx-utils nvidia-470xx-dkms linux-cachyos-headers" legacy "$branch")
	assert_equals 'pacman -R --noconfirm nvidia-580xx-dkms nvidia-580xx-utils nvidia-470xx-dkms' \
		"$(grep '^pacman -R' "$work/log")" 'remove only newly installed legacy packages'
	assert_file "$target/packages/nvidia-470xx-utils" 'pre-existing legacy utils'
	assert_file "$target/packages/linux-headers" 'pre-existing headers'
	assert_file "$target/packages/linux-cachyos-headers" 'new unrelated headers'
	assert_no_file "$target/packages/nvidia-580xx-utils" 'new nouveau blacklist removed'
	assert_string_contains "$out" 'leaving the open-source nouveau driver in place'
	awk '/^pacman -R/ { cleaned=1 } /makepkg/ && !cleaned { exit 1 }' "$work/log" || fail 'cleanup ran after AUR build'
done
out=$(cachyos_marker=$work/cachyos STUB_PACMAN_FAIL=cachyos/ STUB_MAKEPKG_FAIL=1 \
	STUB_PREINSTALLED='nvidia-580xx-utils' STUB_PARTIAL_INSTALL='nvidia-470xx-utils' legacy 580xx)
assert_file "$target/packages/nvidia-580xx-utils" 'pre-existing 580xx utils'
assert_no_file "$target/packages/nvidia-470xx-utils" 'new 470xx utils removed'
out=$(cachyos_marker=$work/cachyos STUB_PACMAN_FAIL=cachyos/ STUB_REMOVE_FAIL=1 \
	STUB_PARTIAL_INSTALL='nvidia-580xx-utils' legacy 580xx)
assert_string_contains "$out" 'could not remove the newly installed legacy NVIDIA packages'
grep -q 'makepkg --noconfirm' "$work/log" || fail 'cleanup failure stopped AUR fallback'

# ── the pinned AUR build, as the new user ───────────────────────────────
out=$(legacy 580xx)
log=$(cat "$work/log")
assert_string_contains "$log" 'pacman -S --noconfirm --needed --asdeps base-devel git'
assert_string_contains "$log" 'pacman -S --noconfirm --needed linux-headers linux-cachyos-headers'
assert_string_contains "$log" 'git clone --quiet -- https://aur.archlinux.org/nvidia-580xx-utils.git /var/tmp/lyona-nvidia-580xx/src'
assert_string_contains "$log" 'git -C /var/tmp/lyona-nvidia-580xx/src checkout --quiet --detach 3d31a20c08a1e6c11c1abe953954f44158c9a592'
# The dependencies, versions stripped, the base's own packages left out.
assert_string_contains "$log" 'pacman -S --noconfirm --needed --asdeps foo-make libglvnd egl-wayland zlib dkms'
# makepkg only ever as the new user.
grep 'makepkg' "$work/log" | grep -v '^runuser -u tester -- ' && fail 'makepkg ran other than as the new user'
# Only the profile's packages are installed, and the build directory goes.
assert_equals 'pacman -U --noconfirm --needed /var/tmp/lyona-nvidia-580xx/src/nvidia-580xx-dkms-1.0-1-x86_64.pkg.tar.zst /var/tmp/lyona-nvidia-580xx/src/nvidia-580xx-utils-1.0-1-x86_64.pkg.tar.zst' \
	"$(grep '^pacman -U' "$work/log")" 'the AUR install'
[[ ! -e $target/var/tmp/lyona-nvidia-580xx ]] || fail 'the build directory was left behind'
assert_file "$work/aur-marker" 'the AUR-built marker for the closing message'
assert_string_contains "$out" 'update it with yay'

# ── a failed build installs nothing and leaves nouveau ──────────────────
out=$(STUB_MAKEPKG_FAIL=1 legacy 580xx)
grep -q '^pacman -U' "$work/log" && fail 'a failed build still installed packages'
[[ ! -e $target/var/tmp/lyona-nvidia-580xx ]] || fail 'a failed build left its directory'
assert_no_file "$work/aur-marker" 'the AUR marker after a failed build'
assert_string_contains "$out" 'leaving the open-source nouveau driver in place'

# ── the 470xx driver uses its own pin ───────────────────────────────────
sed -i 's/580xx/470xx/g' "$work/srcinfo"
legacy 470xx >/dev/null
assert_string_contains "$(cat "$work/log")" 'git -C /var/tmp/lyona-nvidia-470xx/src checkout --quiet --detach af0b7617132e32dd39174779aa8ced2a726afc51'
assert_string_contains "$(cat "$work/log")" 'pacman -U --noconfirm --needed /var/tmp/lyona-nvidia-470xx/src/nvidia-470xx-dkms-'

# ── each kind of card reaches its path ──────────────────────────────────
dispatch() { # DEVICE OPT-IN
	# shellcheck disable=SC2016 # $1 and $2 are the inner bash's
	env PATH="$stub/bin:$PATH" STUB_DEVICE="$1" LYONA_NVIDIA_DRIVER="$2" \
		LYONA_NVIDIA_TABLE="$repo/config/nvidia-legacy-gpus.tsv" bash -c '
			set -Eeuo pipefail
			. "$1"
			. "$2"
			install_nvidia_driver() { printf "open driver\n"; }
			install_legacy_nvidia_driver() { printf "legacy %s %s\n" "$1" "$2"; }
			install_gpu_drivers
		' sh "$repo/archiso/airootfs/root/lyona-nvidia.sh" "$functions"
}
assert_string_contains "$(dispatch 2684 1)" 'open driver'
assert_string_contains "$(dispatch 1b80 1)" 'legacy 580xx 1b80'
assert_string_contains "$(dispatch 0fc6 1)" 'legacy 470xx 0fc6'
assert_string_contains "$(dispatch 06c0 1)" 'no packaged NVIDIA driver supports GPU 10de:06c0'
assert_string_contains "$(dispatch 1b80 0)" 'leaving the open-source nouveau driver in place'

printf 'Legacy NVIDIA driver install (stub chroot): PASS\n'
