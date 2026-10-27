#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo scripts/build-lyona-rpi-image.sh [--output DIR] [--version VERSION]
       scripts/build-lyona-rpi-image.sh --check-root DIR

Build the lyona Raspberry Pi image (experimental; ARM Sprint 3): a disk image
with lyona installed, for the Pi 4 and the Pi 5 (A-5), written to an SD card
with dd, Raspberry Pi Imager or balenaEtcher. A Pi has no installer in the PC
sense, so the image is the installed system itself, minus the user: the
first-boot wizard (ARM3-02) creates the user and finishes the install for it.

The image is built natively on an aarch64 Arch Linux ARM host, as root, never
under emulation (ARM64.md A-3):
  1. pacstrap the dependency map's rpi-image profile (scripts/dwm-packages.sh)
     from Arch Linux ARM's signed repositories into a directory;
  2. run install.sh --profile full in a chroot, as a temporary build user
     with passwordless sudo, as the install medium's postinstall does;
  3. add the first boot (rpi/), which creates the user and finishes the
     install for it (ARM3-02), then remove the build user and everything
     personal: no user, no machine-id, no SSH host keys, no pacman keyring,
     an empty package cache;
  4. make the FAT boot partition and the ext4 root partition from that
     directory (mtools, mkfs.ext4 -d: no loop device or mount), and join
     them in an MBR disk image, compressed with xz, with its SHA-256.

Writes lyona-VERSION-rpi-aarch64.img.xz and its .sha256 to DIR. The version
comes from config.mk unless --version overrides it.

Options:
  --output DIR       Write the image to DIR (default: ./out).
  --version VERSION  Stamp VERSION instead of the config.mk VERSION.
                     Accepts 0.1.0 or v0.1.0.
  --check-root DIR   Check a staged root filesystem for anything personal and
                     for lyona's installed files, then exit: what step 3
                     leaves, checked before the image is made. Needs neither
                     root nor an aarch64 host.
  -h, --help         Show this help.

LYONA_RPI_BOOT_MIB sets the boot partition's size (default 512). The root
partition is made just large enough; the first boot grows it to the card.
EOF
}

err() {
	printf 'build-lyona-rpi-image: %s\n' "$*" >&2
}

info() {
	printf 'build-lyona-rpi-image: %s\n' "$*"
}

# The temporary user install.sh runs as. Removed before the image is made, so
# the first user the wizard creates takes UID 1000.
build_user=lyona-image-build

# What step 3 must leave, and lyona's install must have put there. Prints
# each problem and returns 1 if there was one. DIR is a root filesystem with
# its /boot.
check_root() {
	local root=$1 problems=0 file entry
	problem() {
		printf 'build-lyona-rpi-image: %s: %s\n' "$root" "$*" >&2
		problems=1
	}

	[[ -d $root/etc && -d $root/usr ]] || {
		problem "not a root filesystem"
		return 1
	}

	# No user: the first-boot wizard creates the first one.
	if [[ -f $root/etc/passwd ]]; then
		entry=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1 }' "$root/etc/passwd")
		[[ -z $entry ]] || problem "a user is left in /etc/passwd: $(tr '\n' ' ' <<<"$entry")"
		! grep -q "^$build_user:" "$root/etc/passwd" || problem "the build user is left in /etc/passwd"
	else
		problem "no /etc/passwd"
	fi
	# shadow's tools keep the previous copy of each file as FILE-.
	for file in passwd- group shadow shadow- gshadow gshadow- subuid subuid- subgid subgid- group-; do
		[[ ! -f $root/etc/$file ]] || ! grep -q "^$build_user:" "$root/etc/$file" ||
			problem "the build user is left in /etc/$file"
	done
	if [[ -f $root/etc/group ]] && grep -q ":.*\b$build_user\b" "$root/etc/group"; then
		problem "the build user is still a group member in /etc/group"
	fi
	if [[ -d $root/home ]] && [[ -n $(find "$root/home" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
		problem "/home is not empty"
	fi
	# Root cannot log in: the user administers through sudo (R16-18).
	if [[ -f $root/etc/shadow ]]; then
		entry=$(awk -F: '$1 == "root" { print $2 }' "$root/etc/shadow")
		[[ $entry == '!'* || $entry == '*'* ]] || problem "root has a password"
	else
		problem "no /etc/shadow"
	fi
	# The build's passwordless sudo, and any other.
	if [[ -d $root/etc/sudoers.d ]] &&
		grep -rqs 'NOPASSWD' "$root/etc/sudoers.d"; then
		problem "a NOPASSWD rule is left in /etc/sudoers.d"
	fi

	# Generated at first boot, so each Pi has its own.
	if [[ -s $root/etc/machine-id ]] &&
		[[ $(<"$root/etc/machine-id") != uninitialized ]]; then
		problem "/etc/machine-id is set"
	fi
	[[ ! -s $root/var/lib/dbus/machine-id ]] || problem "/var/lib/dbus/machine-id is set"
	[[ ! -e $root/var/lib/systemd/random-seed ]] || problem "the systemd random seed is left"
	[[ ! -L $root/etc/pacman.d/hooks/90-packagekit-refresh.hook ]] ||
		problem "the build's PackageKit hook mask is left"
	for file in "$root"/etc/ssh/ssh_host_*; do
		[[ ! -e $file ]] || problem "an SSH host key is left: ${file#"$root"}"
	done
	# pacstrap's keyring has a private key of its own: every image would share
	# it. The first boot initialises the keyring (ARM3-02).
	if [[ -d $root/etc/pacman.d/gnupg ]] &&
		[[ -n $(find "$root/etc/pacman.d/gnupg" -mindepth 1 -print -quit) ]]; then
		problem "the pacman keyring is left in /etc/pacman.d/gnupg"
	fi
	if [[ -d $root/var/cache/pacman/pkg ]] &&
		[[ -n $(find "$root/var/cache/pacman/pkg" -mindepth 1 -print -quit) ]]; then
		problem "the package cache is not empty"
	fi
	for file in root/.bash_history root/.gnupg root/.cache var/tmp/lyona-yay var/tmp/lyona-topgrade; do
		[[ ! -e $root/$file ]] || problem "/$file is left"
	done

	# lyona's system half is installed, and the source the first boot finishes
	# the per-user half from (ARM3-02).
	[[ -f $root/etc/lyona-release ]] || problem "no /etc/lyona-release: lyona is not installed"
	[[ -x $root/usr/local/bin/dwm ]] || problem "no /usr/local/bin/dwm"
	[[ -x $root/usr/local/src/lyona/install.sh ]] || problem "no lyona source at /usr/local/src/lyona"
	[[ -f $root/etc/lyona-iso-release ]] || problem "no /etc/lyona-iso-release"
	grep -Eqx 'LYONA_INSTALL_PROFILE=(core|recommended|full)' "$root/etc/lyona-iso-release" 2>/dev/null ||
		problem "/etc/lyona-iso-release records no install profile for the first boot"
	# What the image enables itself: the network, then the greeter (links, so
	# -L: their targets are absolute paths in the image).
	[[ -L $root/etc/systemd/system/multi-user.target.wants/NetworkManager.service ]] ||
		problem "NetworkManager is not enabled"
	[[ $(readlink "$root/etc/systemd/system/display-manager.service" 2>/dev/null) == */lightdm.service ]] ||
		problem "LightDM is not the display manager"
	[[ $(readlink "$root/etc/systemd/system/default.target" 2>/dev/null) == */graphical.target ]] ||
		problem "the default target is not graphical.target"
	# The first boot (ARM3-02), not yet run: its wizard, enabled, with LightDM
	# waiting for it, and what it needs.
	[[ -x $root/usr/local/libexec/lyona/lyona-firstboot ]] || problem "no first-boot wizard"
	[[ -L $root/etc/systemd/system/multi-user.target.wants/lyona-firstboot.service ]] ||
		problem "the first boot is not enabled"
	grep -qsx 'ConditionPathExists=/var/lib/lyona/firstboot-done' \
		"$root/etc/systemd/system/lightdm.service.d/lyona-firstboot.conf" ||
		problem "LightDM does not wait for the first boot"
	[[ ! -e $root/var/lib/lyona/firstboot-done ]] || problem "the first boot is marked done"
	[[ -x $root/usr/bin/gum ]] || problem "no gum for the first-boot wizard"
	[[ $(readlink "$root/etc/systemd/system/systemd-firstboot.service" 2>/dev/null) == /dev/null ]] ||
		problem "systemd-firstboot is not masked"
	file=$root/etc/systemd/system-preset/10-lyona-image.preset
	if [[ -f $file ]]; then
		for entry in lightdm.service NetworkManager.service lyona-firstboot.service; do
			grep -qx "enable $entry" "$file" || problem "the image's preset does not enable $entry"
		done
		[[ $(grep -v '^#' "$file" | tail -n 1) == 'disable *' ]] ||
			problem "the image's preset does not end with disable *"
	else
		problem "no preset of the image's own: systemd's first boot would change its units"
	fi
	grep -qsw quiet "$root/boot/cmdline.txt" || problem "/boot/cmdline.txt does not boot quiet"
	[[ -s $root/usr/local/lib/lyona/firstboot-console.sh ]] || problem "no first-boot console palette"
	grep -qsx 'LANG=en_US.UTF-8' "$root/etc/locale.conf" || problem "the locale is not en_US.UTF-8"
	# The Pi kernel the firmware boots, and the root it is given.
	[[ -f $root/boot/kernel8.img ]] || problem "no /boot/kernel8.img (linux-rpi)"
	if [[ -f $root/boot/cmdline.txt ]]; then
		grep -Eq '(^| )root=PARTUUID=[0-9a-f]{8}-02( |$)' "$root/boot/cmdline.txt" ||
			problem "/boot/cmdline.txt does not name the root partition by PARTUUID"
	else
		problem "no /boot/cmdline.txt"
	fi

	return "$problems"
}

output_dir="$PWD/out"
image_version=
check_dir=

while (($# > 0)); do
	case "$1" in
	--output)
		if (($# < 2)); then
			err "--output requires a value."
			exit 1
		fi
		output_dir=$2
		shift 2
		;;
	--output=*)
		output_dir=${1#*=}
		shift
		;;
	--version)
		if (($# < 2)); then
			err "--version requires a value."
			exit 1
		fi
		image_version=$2
		shift 2
		;;
	--version=*)
		image_version=${1#*=}
		shift
		;;
	--check-root)
		if (($# < 2)); then
			err "--check-root requires a directory."
			exit 1
		fi
		check_dir=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		err "unknown argument: $1"
		usage >&2
		exit 1
		;;
	esac
done

if [[ -n $check_dir ]]; then
	if check_root "$check_dir"; then
		info "$check_dir: nothing personal is left, and lyona is installed."
		exit 0
	fi
	exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_mk="$repo_dir/config.mk"

if [[ -z $image_version ]]; then
	[[ -f $config_mk ]] || {
		err "missing config.mk at $config_mk"
		exit 1
	}
	image_version="$(
		awk -F= '
			$1 ~ /^[[:space:]]*VERSION[[:space:]]*$/ {
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
				print $2
				exit
			}
		' "$config_mk"
	)"
	[[ -n $image_version ]] || {
		err "could not read VERSION from config.mk"
		exit 1
	}
fi
image_version=${image_version#v}
if [[ ! $image_version =~ ^[0-9]+(\.[0-9]+){1,2}(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
	err "version must look like MAJOR.MINOR or MAJOR.MINOR.PATCH, optionally with"
	err "an -alpha.N, -beta.N or -rc.N pre-release suffix: $image_version"
	exit 1
fi

boot_mib=${LYONA_RPI_BOOT_MIB:-512}
if ! [[ $boot_mib =~ ^[0-9]+$ ]] || ((boot_mib < 128)); then
	err "LYONA_RPI_BOOT_MIB must be a whole number of MiB, 128 or more: $boot_mib"
	exit 1
fi

# Native only (A-3). Before the root check, so the reason is the one shown.
host_arch=$(uname -m)
if [[ $host_arch != aarch64 ]]; then
	err "the Raspberry Pi image builds on an aarch64 host; this one is $host_arch."
	exit 1
fi
if [[ $EUID -ne 0 ]]; then
	err "the image is built as root (pacstrap and chroot)."
	exit 1
fi
# The Pi kernel and firmware are Arch Linux ARM's.
if ! grep -qs '^ID=archarm$' /etc/os-release; then
	err "the Raspberry Pi image builds on Arch Linux ARM, for its repositories and keyring."
	exit 1
fi
missing=()
for tool in pacstrap arch-chroot rsync sfdisk mkfs.ext4 e2fsck mkfs.fat mcopy xz sha256sum; do
	command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if ((${#missing[@]} > 0)); then
	err "missing: ${missing[*]}. Install arch-install-scripts, rsync, util-linux,"
	err "e2fsprogs, dosfstools, mtools and xz first."
	exit 1
fi

ARCH=aarch64
export ARCH
# shellcheck source=scripts/dwm-packages.sh
source "$repo_dir/scripts/dwm-packages.sh"
mapfile -t base_packages < <(dwm_packages arch rpi-image)
((${#base_packages[@]} > 0)) || {
	err "the dependency map's rpi-image profile is empty."
	exit 1
}

work_dir="$(mktemp -d -p /var/tmp lyona-rpi.XXXXXX)"
root=$work_dir/root
cleanup() {
	if mountpoint -q "$root" 2>/dev/null; then
		umount -R "$root" || umount -l "$root" || :
	fi
	rm -rf -- "$work_dir"
}
trap cleanup EXIT
mkdir -p "$root"
# arch-chroot wants a mount point; the directory is bound onto itself.
mount --bind "$root" "$root"

# The MBR disk identifier, so cmdline.txt and fstab name the partitions by
# PARTUUID (<id>-01, <id>-02), which holds on SD, USB and NVMe alike.
disk_id=$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n')
[[ $disk_id =~ ^[0-9a-f]{8}$ ]] || {
	err "could not make a disk identifier."
	exit 1
}

info "Installing the base system: ${base_packages[*]}..."
# -c: the host's package cache, so the image's stays empty; -M: Arch Linux
# ARM's own mirrorlist (pacman-mirrorlist), not the build host's.
pacstrap -c -M -C "$repo_dir/archiso-aarch64/pacman.conf" "$root" "${base_packages[@]}"

info "Naming the partitions by PARTUUID $disk_id..."
cmdline=$root/boot/cmdline.txt
if ! [[ -f $cmdline ]] || ! grep -q 'root=/dev/mmcblk0p2' "$cmdline"; then
	err "linux-rpi's cmdline.txt has no root=/dev/mmcblk0p2 to replace; its format changed."
	exit 1
fi
# quiet loglevel=3, as the install medium boots: the kernel's messages,
# audit's among them, otherwise print over the first-boot wizard on tty1.
sed -i -e "s|root=/dev/mmcblk0p2|root=PARTUUID=$disk_id-02|" -e 's|$| quiet loglevel=3|' "$cmdline"
cat >>"$root/etc/fstab" <<EOF
PARTUUID=$disk_id-02	/	ext4	rw,relatime	0 1
PARTUUID=$disk_id-01	/boot	vfat	rw,relatime,fmask=0022,dmask=0022	0 2
EOF

# The install medium's locale and swap (archinstall's en_US.UTF-8 and zram
# with zstd); the keyboard and timezone are the first boot's questions.
info "Setting the locale and swap..."
sed -i 's/^#\(en_US\.UTF-8 UTF-8\)/\1/' "$root/etc/locale.gen"
# glibc's lines end in spaces.
grep -Eq '^en_US\.UTF-8 UTF-8[[:space:]]*$' "$root/etc/locale.gen" || {
	err "/etc/locale.gen has no en_US.UTF-8 line to enable; its format changed."
	exit 1
}
arch-chroot "$root" locale-gen
printf 'LANG=en_US.UTF-8\n' >"$root/etc/locale.conf"
printf '[zram0]\ncompression-algorithm = zstd\n' >"$root/etc/systemd/zram-generator.conf"

info "Copying this checkout to /usr/local/src/lyona..."
# The source the first boot finishes the install from, as the new user
# (ARM3-02). Root-owned and read-only to users. The excludes are the install
# medium's (build-lyona-arch-iso.sh).
rsync_excludes=(
	--exclude='.git/' --exclude='.cache/' --exclude='release/' --exclude='config.h'
	--exclude='*.o' --exclude='dwm' --exclude='out/' --exclude='*.iso' --exclude='*.img*'
)
install -d -m 0755 "$root/usr/local/src"
rsync -a --delete --chown=0:0 --chmod=go-w "${rsync_excludes[@]}" \
	"$repo_dir/" "$root/usr/local/src/lyona/"

build_commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
build_date="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" --utc +%Y-%m-%dT%H:%M:%SZ)"
# The same stamp the install medium writes; LYONA_ISO_KIND says which image.
# LYONA_INSTALL_PROFILE is the profile install.sh runs with below: the first
# boot records it for the new account, as install.sh records it for its user.
cat >"$root/etc/lyona-iso-release" <<EOF
LYONA_ISO_VERSION=$image_version
LYONA_ISO_KIND=rpi-aarch64
LYONA_ISO_COMMIT=$build_commit
LYONA_ISO_BUILD_DATE=$build_date
LYONA_INSTALL_PROFILE=full
EOF
chmod 644 "$root/etc/lyona-iso-release"

info "Creating the temporary build user $build_user..."
arch-chroot "$root" useradd -m -U -s /bin/bash "$build_user"
build_home=/home/$build_user
checkout_rel=.local/src/lyona
arch-chroot "$root" install -d -o "$build_user" -g "$build_user" -m 0755 \
	"$build_home/.local" "$build_home/.local/src" "$build_home/.config"
rsync -a --delete "${rsync_excludes[@]}" "$repo_dir/" "$root$build_home/$checkout_rel/"
arch-chroot "$root" chown -R "$build_user:$build_user" "$build_home/$checkout_rel"

# yay, then Topgrade after install.sh: built from their pinned PKGBUILDs as the
# build user while it has no sudo, installed by root from the built package,
# as the install medium's postinstall does (#328, #339).
build_aur_package() { # SCRIPT NAME
	local script=$1 name=$2 build=/var/tmp/lyona-$2 package
	arch-chroot "$root" rm -rf -- "$build"
	arch-chroot "$root" install -d -o "$build_user" -g "$build_user" -m 700 -- "$build"
	package=$(arch-chroot "$root" runuser -u "$build_user" -- env HOME="$build_home" \
		"$build_home/$checkout_rel/scripts/$script" --build-only "$build")
	[[ $package == "$build/$name"-bin-*.pkg.tar.* ]] || {
		err "$script built no $name-bin package."
		return 1
	}
	arch-chroot "$root" pacman -U --noconfirm --needed -- "$package"
	arch-chroot "$root" rm -rf -- "$build"
}

# PackageKit's pacman hook asks its daemon over D-Bus, which a chroot does not
# have; pacman then fails the transaction's last step (the install medium's
# postinstall only warns of it, docs/evidence/arm2-05-generic-image.md). An
# /etc/pacman.d/hooks file of the same name masks it (alpm-hooks(5)) for the
# build only, removed before the root is checked.
packagekit_mask=$root/etc/pacman.d/hooks/90-packagekit-refresh.hook
install -d -m 0755 "$root/etc/pacman.d/hooks"
ln -sfT /dev/null "$packagekit_mask"

info "Building yay as $build_user..."
mapfile -t aur_build < <(dwm_packages arch aur-build)
arch-chroot "$root" pacman -S --needed --noconfirm "${aur_build[@]}"
build_aur_package install-yay yay

info "Running install.sh --profile full as $build_user..."
build_sudoers=$root/etc/sudoers.d/90-lyona-image-build
install -m 0440 /dev/null "$build_sudoers"
printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$build_user" >"$build_sudoers"
# LYONA_SOURCE=iso: install.sh's image install, in a chroot where nothing is
# started (install.sh's LYONA_SOURCE=iso cases). The full profile, as on the
# install medium: only it installs the display manager the first boot ends in.
# The GRUB theme is left out: a Pi boots through its firmware, not GRUB.
install_status=0
arch-chroot "$root" su - "$build_user" -c \
	"cd \"\$HOME/$checkout_rel\" && env LYONA_SOURCE=iso LYONA_COMMIT=$build_commit ./install.sh --non-interactive --profile full --skip-topgrade --skip-yay --skip-grub-theme" ||
	install_status=$?
rm -f -- "$build_sudoers"
((install_status == 0)) || {
	err "install.sh failed ($install_status)."
	exit 1
}

info "Building Topgrade as $build_user..."
build_aur_package install-topgrade topgrade

# What install.sh leaves to the image in an image install (LYONA_SOURCE=iso),
# as the install medium's postinstall does it: NetworkManager (the map's
# network profile), only lyona's session, LightDM, power profiles and
# Bluetooth, which bluez does not enable itself (#380). The Wi-Fi country
# needs the user's timezone: the first boot sets it (ARM3-02).
info "Enabling NetworkManager, LightDM and Bluetooth..."
mapfile -t network < <(dwm_packages arch network)
arch-chroot "$root" pacman -S --noconfirm --needed "${network[@]}"
arch-chroot "$root" systemctl enable NetworkManager.service
find "$root/usr/share/xsessions" -mindepth 1 -maxdepth 1 -type f ! -name dwm.desktop -delete 2>/dev/null || :
find "$root/usr/share/wayland-sessions" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || :
arch-chroot "$root" systemctl enable lightdm.service
arch-chroot "$root" systemctl enable power-profiles-daemon.service 2>/dev/null || :
if arch-chroot "$root" systemctl -q list-unit-files bluetooth.service >/dev/null 2>&1; then
	arch-chroot "$root" systemctl enable bluetooth.service
fi
arch-chroot "$root" systemctl set-default graphical.target

# The first boot (ARM3-02): its wizard on tty1, then LightDM, which waits for
# it. The console in the boot splash's palette, as on the install medium.
info "Adding the first boot..."
install -Dm755 "$repo_dir/rpi/lyona-firstboot.sh" "$root/usr/local/libexec/lyona/lyona-firstboot"
install -Dm644 "$repo_dir/rpi/lyona-firstboot.service" "$root/etc/systemd/system/lyona-firstboot.service"
install -Dm644 "$repo_dir/rpi/lightdm-after-firstboot.conf" \
	"$root/etc/systemd/system/lightdm.service.d/lyona-firstboot.conf"
install -d -m 0755 "$root/usr/local/lib/lyona"
"$repo_dir/scripts/lyona-console-theme" generate tokyonight "$repo_dir/config/themes.toml" \
	"$root/usr/local/lib/lyona/firstboot-console.sh"
chmod 644 "$root/usr/local/lib/lyona/firstboot-console.sh"
arch-chroot "$root" systemctl enable lyona-firstboot.service
# systemd's own first-boot questions (timezone, root password and more) on the
# console before lyona's, because the machine-id is uninitialized: masked, as
# the wizard asks them (found booting the image, ARM3-02).
arch-chroot "$root" systemctl mask systemd-firstboot.service

# The machine-id is uninitialized, so the first boot is systemd's first boot
# too, where it applies the presets to every unit (preset-all): Arch's end in
# "disable *", which disabled LightDM, Bluetooth and power profiles, and its own
# enable systemd-networkd and systemd-homed (found booting the image,
# ARM3-02). A preset of the image's own, read first, says what this build
# enabled and nothing else, so the presets keep the image as it was built.
info "Recording the enabled units as the image's preset..."
image_preset=$root/etc/systemd/system-preset/10-lyona-image.preset
install -d -m 0755 "${image_preset%/*}"
{
	printf '# The units the lyona Raspberry Pi image enables (build-lyona-rpi-image.sh),
'
	printf "# so systemd's first-boot presets keep them, and enable nothing else.
"
	arch-chroot "$root" systemctl list-unit-files --state=enabled --no-legend --no-pager |
		awk '{ print "enable " $1 }' | LC_ALL=C sort -u
	printf 'disable *
'
} >"$image_preset"
for unit in lightdm.service NetworkManager.service lyona-firstboot.service; do
	grep -qx "enable $unit" "$image_preset" || {
		err "$unit is not enabled in the image's preset; the build went wrong."
		exit 1
	}
done

rm -f -- "$packagekit_mask"
rmdir --ignore-fail-on-non-empty -- "$root/etc/pacman.d/hooks"

info "Removing the build user and everything personal..."
arch-chroot "$root" userdel -r "$build_user"
arch-chroot "$root" passwd -l root >/dev/null
# The copies useradd and userdel keep from before, which name the build user.
rm -f -- "$root"/etc/{passwd,group,shadow,gshadow,subuid,subgid}-
rm -rf -- "$root/etc/pacman.d/gnupg" "$root/var/cache/pacman/pkg"
install -d -m 0755 "$root/var/cache/pacman/pkg"
printf 'uninitialized\n' >"$root/etc/machine-id"
rm -f -- "$root/var/lib/dbus/machine-id" "$root/var/lib/systemd/random-seed" \
	"$root"/etc/ssh/ssh_host_*
rm -rf -- "$root/root/.bash_history" "$root/root/.gnupg" "$root/root/.cache" \
	"$root/var/tmp/lyona-yay" "$root/var/tmp/lyona-topgrade" "$root/var/spool/mail/$build_user"
rm -rf -- "${root:?}/var/log/journal/"*

info "Checking the root filesystem..."
check_root "$root" || {
	err "the root filesystem is not ready for an image; see above."
	exit 1
}

umount "$root"

info "Making the boot partition (${boot_mib} MiB, FAT32)..."
boot_img=$work_dir/boot.img
boot_bytes=$(du -sb "$root/boot" | cut -f1)
((boot_bytes < boot_mib * 1024 * 1024 * 9 / 10)) || {
	err "/boot holds $boot_bytes bytes, too much for a ${boot_mib} MiB partition; raise LYONA_RPI_BOOT_MIB."
	exit 1
}
mkfs.fat -F 32 -n LYONA_BOOT -C "$boot_img" $((boot_mib * 1024)) >/dev/null
mcopy -s -p -m -i "$boot_img" "$root/boot/"* ::
find "$root/boot" -mindepth 1 -delete

info "Making the root partition (ext4)..."
root_img=$work_dir/root.img
# Its contents and a fifth more, rounded up to 64 MiB: the first boot grows it
# to the card (ARM3-02).
root_mib=$(du -sm "$root" | cut -f1)
root_mib=$(((root_mib * 6 / 5 + 256 + 63) / 64 * 64))
mkfs.ext4 -q -L lyona-root -d "$root" "$root_img" "${root_mib}M"
e2fsck -fn "$root_img" >/dev/null

info "Joining them in a disk image..."
mkdir -p "$output_dir"
image_name=lyona-$image_version-rpi-aarch64.img
image=$work_dir/$image_name
# The first partition at 4 MiB, as Raspberry Pi OS lays it out.
offset_mib=4
truncate -s $(((offset_mib + boot_mib + root_mib) * 1024 * 1024)) "$image"
sfdisk --quiet "$image" <<EOF
label: dos
label-id: 0x$disk_id
unit: sectors

start=$((offset_mib * 2048)), size=$((boot_mib * 2048)), type=c, bootable
start=$(((offset_mib + boot_mib) * 2048)), size=$((root_mib * 2048)), type=83
EOF
dd if="$boot_img" of="$image" bs=1M seek="$offset_mib" conv=notrunc,sparse status=none
dd if="$root_img" of="$image" bs=1M seek=$((offset_mib + boot_mib)) conv=notrunc,sparse status=none

info "Compressing $image_name.xz..."
xz -T0 -6 -c "$image" >"$output_dir/$image_name.xz"
(cd "$output_dir" && sha256sum "$image_name.xz" >"$image_name.xz.sha256")
info "Done. $(du -h "$output_dir/$image_name.xz" | cut -f1) image, $((offset_mib + boot_mib + root_mib)) MiB written out, at $output_dir/$image_name.xz"
