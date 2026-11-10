#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo scripts/build-lyona-arch-iso.sh [--arch ARCH] [--output DIR] [--version VERSION]

Build a lyona Arch Linux install medium by layering this checkout and
archiso/ onto the system's archiso releng profile, then running mkarchiso.
Requires the archiso package and root (mkarchiso builds as root).

The image carries the release version from config.mk unless --version
overrides it, producing lyona-VERSION-ARCH.iso and recording the build
in /etc/lyona-iso-release on the live medium.

Options:
  --arch ARCH             x86_64 (the default) or aarch64. aarch64 builds the
                          experimental Arch Linux ARM medium: archiso-aarch64/
                          over archiso 91's releng, UEFI only. It builds only
                          on an aarch64 host (ARM64.md A-3).
  --output DIR            Write the ISO to DIR (default: ./out).
  --version VERSION       Stamp VERSION instead of the config.mk VERSION.
                          Accepts 0.1.0 or v0.1.0.
  --profile-only          Stage and stamp the archiso profile under
                          DIR/profile, then stop without running mkarchiso.
                          Does not require root, or a host of ARCH.
  -h, --help              Show this help.

LYONA_RELENG_DIR overrides the archiso releng profile location
(default: /usr/share/archiso/configs/releng), and LYONA_MKARCHISO the
mkarchiso to run (default: mkarchiso on PATH). Arch Linux ARM does not
package archiso: for --arch aarch64, point both at an archiso 91 or later
checkout (its configs/releng and archiso/mkarchiso; docs/RELEASING.md).

The live medium auto-logs into a root shell on tty1. After completing a base
Arch install to /mnt (e.g. with `archinstall`), run
/root/lyona-postinstall.sh from that shell to finish installing lyona.

Verified to produce a bootable ISO on Arch Linux. Still needs VM
boot-qualification (base install + first boot) before being treated as
release-ready; see docs/RELEASING.md.
EOF
}

err() {
	printf 'build-lyona-arch-iso: %s\n' "$*" >&2
}

output_dir="$PWD/out"
iso_version=
profile_only=false
arch=x86_64

while (($# > 0)); do
	case "$1" in
	--arch)
		if (($# < 2)); then
			err "--arch requires a value."
			exit 1
		fi
		arch=$2
		shift 2
		;;
	--arch=*)
		arch=${1#*=}
		shift
		;;
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
		iso_version=$2
		shift 2
		;;
	--version=*)
		iso_version=${1#*=}
		shift
		;;
	--profile-only)
		profile_only=true
		shift
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

case $arch in
x86_64 | aarch64) ;;
*)
	err "--arch must be x86_64 or aarch64: $arch"
	exit 1
	;;
esac

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_mk="$repo_dir/config.mk"
# What differs on each architecture: the package layer, pacman.conf and, on
# aarch64, airootfs/ files. The rest of the medium is archiso/'s, shared.
case $arch in
x86_64) arch_profile_dir=$repo_dir/archiso ;;
aarch64) arch_profile_dir=$repo_dir/archiso-aarch64 ;;
esac

if [[ -z $iso_version ]]; then
	[[ -f $config_mk ]] || {
		err "missing config.mk at $config_mk"
		exit 1
	}
	iso_version="$(
		awk -F= '
			$1 ~ /^[[:space:]]*VERSION[[:space:]]*$/ {
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
				print $2
				exit
			}
		' "$config_mk"
	)"
	[[ -n $iso_version ]] || {
		err "could not read VERSION from config.mk"
		exit 1
	}
fi

iso_version=${iso_version#v}
if [[ ! $iso_version =~ ^[0-9]+(\.[0-9]+){1,2}(-(alpha|beta|rc)\.[0-9]+)?$ ]]; then
	err "version must look like MAJOR.MINOR or MAJOR.MINOR.PATCH, optionally with"
	err "an -alpha.N, -beta.N or -rc.N pre-release suffix: $iso_version"
	exit 1
fi

# An ISO9660 volume identifier admits only A-Z, 0-9 and _, and is capped at 32
# characters, so a pre-release suffix cannot be carried verbatim:
# 2026.08.0-beta.1 becomes LYONA_2026_08_0_BETA1.
iso_label="LYONA_${iso_version%%-*}"
iso_label="${iso_label//./_}"
if [[ $iso_version == *-* ]]; then
	iso_prerelease=${iso_version#*-}
	iso_label="${iso_label}_${iso_prerelease//./}"
fi
iso_label=${iso_label^^}
if ((${#iso_label} > 32)); then
	err "volume label $iso_label exceeds the 32-character ISO9660 limit"
	exit 1
fi

mkarchiso_cmd=${LYONA_MKARCHISO:-mkarchiso}
if [[ $profile_only != true ]]; then
	# Built natively, never under emulation (ARM64.md A-3): an emulated chroot
	# is slow and hides faults that only show on the real architecture. Before
	# the root check, so the reason is the one shown.
	host_arch=$(uname -m)
	if [[ $host_arch != "$arch" ]]; then
		err "an $arch medium builds on an $arch host; this one is $host_arch."
		exit 1
	fi

	if [[ $EUID -ne 0 ]]; then
		err "mkarchiso must run as root."
		exit 1
	fi

	command -v "$mkarchiso_cmd" >/dev/null 2>&1 || {
		if [[ $arch == aarch64 ]]; then
			err "mkarchiso not found. Arch Linux ARM does not package archiso: set"
			err "LYONA_MKARCHISO and LYONA_RELENG_DIR to an archiso 91 checkout."
		else
			err "mkarchiso not found. Install the archiso package first."
		fi
		exit 1
	}

	# The aarch64 medium fuses the Snapdragon X device trees into its kernel
	# with ukify (ARM6-02). Without it mkarchiso only warns and builds a medium
	# that cannot pick a device tree, so it is required here.
	if [[ $arch == aarch64 ]] && ! command -v ukify >/dev/null 2>&1; then
		err "ukify not found. Install the systemd-ukify package: the aarch64 medium"
		err "fuses the Snapdragon X device trees into its kernel with it."
		exit 1
	fi
fi

# rsync embeds the checkout in the profile, in --profile-only too. archiso does
# not depend on it, so a host can lack it; say so before anything is staged.
command -v rsync >/dev/null 2>&1 || {
	err "rsync not found. Install the rsync package first."
	exit 1
}

# The palette the boot splash is generated from. The installed system can
# follow the user's chosen theme later; the ISO has no user yet.
splash_palette="${LYONA_SPLASH_PALETTE:-tokyonight}"
releng_dir="${LYONA_RELENG_DIR:-/usr/share/archiso/configs/releng}"
[[ -d $releng_dir ]] || {
	err "releng profile not found at $releng_dir. Reinstall the archiso package."
	exit 1
}
# archiso 91 added aarch64 to releng: its package list and its kernel
# parameters. Older releng profiles have neither, and mkarchiso before 91
# cannot build an aarch64 UEFI medium (docs/evidence/arm2-01-spike.md).
if [[ $arch == aarch64 ]] &&
	{ [[ ! -f $releng_dir/packages.aarch64 ]] ||
		! grep -q '^kernel_params_aarch64=' "$releng_dir/profiledef.sh"; }; then
	err "the releng profile at $releng_dir has no aarch64 support; it needs archiso 91 or later."
	exit 1
fi

work_dir="$(mktemp -d -p /var/tmp)"
trap 'rm -rf "$work_dir"' EXIT

if [[ $profile_only == true ]]; then
	mkdir -p "$output_dir"
	profile_dir="$output_dir/profile"
	rm -rf "$profile_dir"
else
	profile_dir="$work_dir/profile"
fi

info() { printf 'build-lyona-arch-iso: %s\n' "$*"; }

info "Copying the releng base profile..."
cp -a "$releng_dir" "$profile_dir"

# releng's aarch64 profile is written for Arch Linux's own aarch64 port, which
# has no public repositories; this makes it Arch Linux ARM's (ARM2-02, from
# the ARM2-01 spike: docs/evidence/arm2-01-spike.md). Every edit checks the
# shape it changes, so a new releng fails here rather than in the image.
adapt_releng_aarch64() {
	local packages=$profile_dir/packages.aarch64
	local profiledef=$profile_dir/profiledef.sh
	local hooks_conf=$profile_dir/airootfs/etc/mkinitcpio.conf.d/archiso.conf
	local package

	info "Adapting releng's aarch64 profile to Arch Linux ARM..."
	# UEFI only: aarch64 has no BIOS, and syslinux no aarch64 build.
	grep -q "'uefi.systemd-boot'" "$profiledef" || {
		err "releng's profiledef.sh has no uefi.systemd-boot boot mode; the archiso profile format changed."
		exit 1
	}
	sed -i "s/'bios\.syslinux'//" "$profiledef"
	! grep -q 'bios\.syslinux' "$profiledef" || {
		err "the bios.syslinux boot mode was not removed."
		exit 1
	}
	rm -rf -- "$profile_dir/syslinux"
	rm -f -- "$profile_dir"/efiboot/loader/entries/*memtest86*

	# linux-aarch64 has CONFIG_XZ_DEC_ARM64 but not CONFIG_XZ_DEC_X86: a
	# root image block mksquashfs compressed with the x86 filter cannot be
	# read on the booted medium.
	grep -q "'-Xbcj' 'x86,arm64'" "$profiledef" || {
		err "releng's squashfs options have no -Xbcj x86,arm64; the archiso profile format changed."
		exit 1
	}
	sed -i "s/'-Xbcj' 'x86,arm64'/'-Xbcj' 'arm64'/" "$profiledef"

	# memdisk is syslinux's BIOS RAM-disk boot; its hook fails the
	# initramfs build on aarch64 (no phram module, no memdiskfind).
	grep -q '^HOOKS=(.* memdisk ' "$hooks_conf" || {
		err "releng's HOOKS line has no memdisk hook; the archiso profile format changed."
		exit 1
	}
	sed -i '/^HOOKS=(/ s/ memdisk / /' "$hooks_conf"

	# Arch Linux ARM's kernel, linux-aarch64, carries its own device trees;
	# the other four are not in its repositories.
	grep -Fqx linux "$packages" || {
		err "releng's packages.aarch64 has no linux kernel; the archiso profile format changed."
		exit 1
	}
	for package in linux linux-dtbs stubble edk2-shell ghostty-terminfo; do
		sed -i "/^${package}\$/d" "$packages"
	done
	printf '%s\n' linux-aarch64 archlinuxarm-keyring >>"$packages"

	# releng's linux-firmware pulls every vendor's firmware: about 280 MB of
	# Intel, NVIDIA, AMD, Radeon and TI files that no Arch Linux ARM board this
	# medium targets uses. On the XPS 13 9345 the root image is copied into RAM
	# over a link that runs at USB 2.0 speed (about 30 MB/s) until the USB-C
	# port is set up, so every 30 MB cut is about a second off the black
	# screen. Qualcomm and Atheros (the XPS) stay, with the Wi-Fi vendors a
	# USB dongle may need.
	grep -Fqx linux-firmware "$packages" || {
		err "releng's packages.aarch64 has no linux-firmware; the archiso profile format changed."
		exit 1
	}
	sed -i '/^linux-firmware$/d' "$packages"
	for package in linux-firmware-qcom linux-firmware-atheros linux-firmware-broadcom \
		linux-firmware-mediatek linux-firmware-realtek linux-firmware-other linux-firmware-whence; do
		grep -Fqx "$package" "$packages" || printf '%s\n' "$package" >>"$packages"
	done
}

if [[ $arch == aarch64 ]]; then
	adapt_releng_aarch64
fi

info "Layering lyona packages onto packages.$arch..."
cat "$arch_profile_dir/packages.$arch" >>"$profile_dir/packages.$arch"
sort -u -o "$profile_dir/packages.$arch" "$profile_dir/packages.$arch"

info "Applying lyona pacman.conf..."
cp -f "$arch_profile_dir/pacman.conf" "$profile_dir/pacman.conf"

if [[ $arch == aarch64 ]]; then
	info "Adding the aarch64 medium's own files..."
	cp -a "$arch_profile_dir/airootfs/." "$profile_dir/airootfs/"
fi

info "Rebranding profiledef.sh for lyona $iso_version..."
sed -i \
	-e 's/^iso_name=.*/iso_name="lyona"/' \
	-e "s/^iso_label=.*/iso_label=\"$iso_label\"/" \
	-e "s/^iso_version=.*/iso_version=\"$iso_version\"/" \
	-e 's|^iso_publisher=.*|iso_publisher="lyona <https://github.com/technicks89/Lyona>"|' \
	-e "s/^iso_application=.*/iso_application=\"lyona $iso_version Arch Linux install medium\"/" \
	"$profile_dir/profiledef.sh"

for key in iso_name iso_label iso_version iso_application; do
	grep -q "^$key=" "$profile_dir/profiledef.sh" || {
		err "releng profiledef.sh has no $key to rebrand; the archiso profile format changed."
		exit 1
	}
done

info "Quieting the primary boot entries' console output..."
# The primary entry's parameters end at archisosearchuuid, then, since archiso
# 91, a %KERNEL_PARAMS% placeholder. The accessibility entry's go on to
# accessibility=on, so it stays as releng wrote it.
# copytoram=n: archiso otherwise reads the whole root image into RAM from a
# USB stick before boot continues, tens of seconds behind a silent splash on
# real hardware. The stick stays in for the install anyway.
# aarch64 differs in three ways (ARM6-02, the XPS 13 9345):
# - copytoram=y: read from the stick as the squashfs, the boot stick drops off
#   the bus about 71 s in ("usb 3-1: USB disconnect", back 0.7 s later as a new
#   device) when the ADSP comes up and the USB-C port is reconfigured, so reads
#   of the mounted image return I/O errors (loop0, SQUASHFS error -5) on any
#   stick, USB 2 or 3, on both ports. Copying the image into RAM first, which
#   finishes before that, boots; the cost is a minute before the shell is up.
# - plymouth.force-scale=1: the panel is 2560x1600 and Plymouth's automatic
#   HiDPI scale of 2 made the splash logo land in the bottom right corner,
#   cut off. At scale 1 it is centred.
# - systemd.tpm2_wait=0: the firmware reports a TPM but this kernel exposes no
#   device for it, so systemd waited its 90 s device timeout for /dev/tpm0
#   before the installer started. The option tells it not to wait.
uefi_boot_args='copytoram=n quiet splash loglevel=3 vt.global_cursor_default=0'
if [[ $arch == aarch64 ]]; then
	uefi_boot_args='copytoram=y quiet splash loglevel=3 vt.global_cursor_default=0 plymouth.force-scale=1 systemd.tpm2_wait=0'
fi
sed -E -i \
	"/^options.*archisosearchuuid=%ARCHISO_UUID%( %KERNEL_PARAMS%)?\$/ s/\$/ $uefi_boot_args/" \
	"$profile_dir/efiboot/loader/entries/01-archiso-linux.conf"

grep -Fq "$uefi_boot_args" "$profile_dir/efiboot/loader/entries/01-archiso-linux.conf" || {
	err "releng's UEFI boot entry has no matching options line to quiet; the archiso profile format changed."
	exit 1
}
# syslinux, the BIOS loader, is x86_64 only (the aarch64 medium is UEFI only).
if [[ $arch == x86_64 ]]; then
	sed -E -i \
		'/^APPEND.*archisosearchuuid=%ARCHISO_UUID%( %KERNEL_PARAMS%)?$/ s/$/ copytoram=n quiet splash loglevel=3 vt.global_cursor_default=0/' \
		"$profile_dir/syslinux/archiso_sys-linux.cfg"

	grep -q 'copytoram=n quiet splash loglevel=3 vt.global_cursor_default=0' "$profile_dir/syslinux/archiso_sys-linux.cfg" || {
		err "releng's BIOS boot entry has no matching APPEND line to quiet; the archiso profile format changed."
		exit 1
	}
fi

info "Booting straight into the installer, without a boot menu..."
# There is one thing to boot on this medium and it launches the installer on
# login, so a menu asking which is a step with no choice in it. Both loaders
# keep an escape hatch: systemd-boot shows the menu if a key is held during
# firmware handover, and the syslinux entries remain defined and reachable
# from its boot prompt.
loader_conf="$profile_dir/efiboot/loader/loader.conf"
grep -q '^timeout ' "$loader_conf" || {
	err "releng's loader.conf has no timeout to remove; the archiso profile format changed."
	exit 1
}
sed -i -e 's/^timeout .*/timeout 0/' -e 's/^beep .*/beep off/' "$loader_conf"
grep -Fqx 'timeout 0' "$loader_conf" || {
	err "the UEFI boot menu timeout was not disabled."
	exit 1
}

if [[ $arch == x86_64 ]]; then
	# vesamenu.c32 always draws, whatever the timeout, so the menu module itself
	# has to go rather than just its countdown.
	syslinux_head="$profile_dir/syslinux/archiso_head.cfg"
	syslinux_sys="$profile_dir/syslinux/archiso_sys.cfg"
	grep -q '^UI vesamenu.c32$' "$syslinux_head" || {
		err "releng's syslinux head has no vesamenu UI line; the archiso profile format changed."
		exit 1
	}
	grep -q '^TIMEOUT ' "$syslinux_sys" || {
		err "releng's syslinux config has no TIMEOUT to shorten; the archiso profile format changed."
		exit 1
	}
	sed -i 's/^UI vesamenu.c32$/PROMPT 0/' "$syslinux_head"
	sed -i 's/^TIMEOUT .*/TIMEOUT 1/' "$syslinux_sys"
	grep -Fqx 'PROMPT 0' "$syslinux_head" || {
		err "the BIOS boot menu was not disabled."
		exit 1
	}
	grep -Fqx 'TIMEOUT 1' "$syslinux_sys" || {
		err "the BIOS boot menu timeout was not shortened."
		exit 1
	}
fi

grep -q '^file_permissions=($' "$profile_dir/profiledef.sh" || {
	err "releng's profiledef.sh has no file_permissions=( line; the archiso profile format changed."
	exit 1
}
sed -i '/^file_permissions=($/a\
  ["/root/lyona-postinstall.sh"]="0:0:755"\
  ["/usr/local/bin/lyona-install"]="0:0:755"' \
	"$profile_dir/profiledef.sh"

info "Adding the plymouth hook to the initramfs..."
# Ordered right after udev, which is where plymouth needs to start to own the
# console before the boot messages the entries above just suppressed.
archiso_mkinitcpio="$profile_dir/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
[[ -f $archiso_mkinitcpio ]] || {
	err "releng has no airootfs/etc/mkinitcpio.conf.d/archiso.conf; the archiso profile format changed."
	exit 1
}
grep -q '^HOOKS=(base udev ' "$archiso_mkinitcpio" || {
	err "releng's HOOKS line does not start with base udev; the archiso profile format changed."
	exit 1
}
sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' "$archiso_mkinitcpio"
grep -q '^HOOKS=(base udev plymouth ' "$archiso_mkinitcpio" || {
	err "the plymouth hook was not inserted into the archiso HOOKS line."
	exit 1
}

info "Generating the lyona boot splash from the $splash_palette palette..."
"$repo_dir/scripts/lyona-plymouth-theme" generate "$splash_palette" \
	"$repo_dir/config/themes.toml" "$repo_dir/assets/logo" \
	"$profile_dir/airootfs/usr/share/plymouth/themes/lyona"
install -Dm644 "$repo_dir/archiso/airootfs/etc/plymouth/plymouthd.conf" \
	"$profile_dir/airootfs/etc/plymouth/plymouthd.conf"
if [[ $arch == aarch64 ]]; then
	# Plymouth waits DeviceTimeout (8 s by default) for a DRM device before it
	# falls back to the firmware framebuffer. On the XPS 13 9345 the msm DRM
	# device appears only after about 68 s, so the splash waited about 8 s
	# for nothing. Not yet tried: whether the framebuffer then draws.
	sed -i '/^\[Daemon\]$/ a DeviceTimeout=1' \
		"$profile_dir/airootfs/etc/plymouth/plymouthd.conf"
	grep -Fqx 'DeviceTimeout=1' "$profile_dir/airootfs/etc/plymouth/plymouthd.conf" || {
		err "plymouthd.conf has no [Daemon] section to set DeviceTimeout in."
		exit 1
	}
	# Experiment (ARM6-02, untried): on the XPS 13 9345 msm's DisplayPort
	# controllers bind about 0.06 s after "remoteproc0: adsp is available", the
	# registration of the ADSP by qcom_q6v5_pas, and before the ADSP is powered
	# up. That module was never in the initramfs, which is why carrying only
	# pmic_glink, qrtr and the others (new6) changed nothing: the root image's
	# udev loaded qcom_q6v5_pas at about 36 s. Loading it in the initramfs
	# should bring the DRM device (and the splash on the panel) up before the
	# copy of the root image. The ADSP firmware is in the root image, so the
	# ADSP may not boot until it is started by hand; that is not handled here.
	sed -i '/^HOOKS=(/ i MODULES+=(qcom_q6v5_pas pmic_glink pmic_glink_altmode qcom_pd_mapper qrtr qrtr-smd)' \
		"$archiso_mkinitcpio"
	grep -Fqx 'MODULES+=(qcom_q6v5_pas pmic_glink pmic_glink_altmode qcom_pd_mapper qrtr qrtr-smd)' "$archiso_mkinitcpio" || {
		err "the early display modules were not added to the initramfs MODULES."
		exit 1
	}
fi

info "Suppressing the optical-drive loopback attach on boot..."
install -Dm644 "$repo_dir/archiso/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules" \
	"$profile_dir/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules"

systemd_udev_rules=/usr/lib/udev/rules.d/99-systemd.rules
if [[ -f $systemd_udev_rules ]] &&
	! grep -q 'ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP' "$systemd_udev_rules"; then
	info "note: this host's systemd no longer keys the optical loopback attach on"
	info "      ID_PART_GPT_AUTO_ROOT_DISK_NEEDS_LOOP; recheck"
	info "      archiso/airootfs/etc/udev/rules.d/90-lyona-optical-no-loop.rules."
fi

info "Embedding this checkout at /root/lyona in the live medium..."
mkdir -p "$profile_dir/airootfs/root"
rsync -a --delete \
	--exclude='.git/' \
	--exclude='.cache/' \
	--exclude='release/' \
	--exclude='config.h' \
	--exclude='*.o' \
	--exclude='dwm' \
	--exclude='out/' \
	--exclude='*.iso' \
	"$repo_dir/" "$profile_dir/airootfs/root/lyona/"

install -Dm755 "$repo_dir/archiso/airootfs/root/lyona-postinstall.sh" \
	"$profile_dir/airootfs/root/lyona-postinstall.sh"

# mkarchiso gives every file it does not find in file_permissions mode 644, so
# the embedded checkout lost its executable bits: lyona-install then took the
# CachyOS helper for missing (Sync Sprint 16, found installing in a VM). Each
# file executable in the checkout keeps its bit, owned by root.
info "Keeping the embedded checkout's executable files executable..."
mapfile -d '' -t executables < <(cd "$profile_dir/airootfs" &&
	find root/lyona -type f -perm -u+x -print0 | LC_ALL=C sort -z)
((${#executables[@]} > 0)) || {
	err "the embedded checkout has no executable files; its copy went wrong."
	exit 1
}
permissions=
for executable in "${executables[@]}"; do
	permissions+="  [\"/$executable\"]=\"0:0:755\""$'\n'
done
awk -v entries="$permissions" '
	{ print }
	/^file_permissions=\($/ && !done { printf "%s", entries; done = 1 }
' "$profile_dir/profiledef.sh" >"$profile_dir/profiledef.sh.new"
mv -fT -- "$profile_dir/profiledef.sh.new" "$profile_dir/profiledef.sh"

info "Installing shared installer UI helpers..."
install -Dm644 "$repo_dir/archiso/airootfs/root/lyona-ui.sh" \
	"$profile_dir/airootfs/root/lyona-ui.sh"
install -Dm644 "$repo_dir/archiso/airootfs/root/lyona-nvidia.sh" \
	"$profile_dir/airootfs/root/lyona-nvidia.sh"
install -Dm644 "$repo_dir/archiso/airootfs/root/lyona-wifi.sh" \
	"$profile_dir/airootfs/root/lyona-wifi.sh"
install -Dm644 "$repo_dir/archiso/airootfs/root/lyona-logo.txt" \
	"$profile_dir/airootfs/root/lyona-logo.txt"

info "Generating the console palette from the $splash_palette palette..."
# The same palette the splash is generated from, so the console the installer
# runs on is a continuation of the boot screen rather than stock VGA.
"$repo_dir/scripts/lyona-console-theme" generate "$splash_palette" \
	"$repo_dir/config/themes.toml" \
	"$profile_dir/airootfs/root/lyona-console.sh"
chmod 644 "$profile_dir/airootfs/root/lyona-console.sh"

info "Installing lyona-install as a live-medium command..."
install -Dm755 "$repo_dir/archiso/airootfs/root/lyona-install.sh" \
	"$profile_dir/airootfs/usr/local/bin/lyona-install"

info "Going straight from the splash to the installer on tty1..."
# Between the splash and the installer's first screen, tty1 used to show a root
# console for a moment: agetty's /etc/issue banner and "login: root (automatic
# login)" line, then login's message of the day (releng's Arch install guide
# text), over the boot text --noclear had kept. Now agetty clears the screen
# and prints nothing (--skip-login still logs root in with --autologin; on a
# virtual console it resets the line as usual), login is hushed, and the
# message of the day is shown by .zlogin, only on logins that do not start the
# installer.
autologin_conf="$profile_dir/airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf"
grep -q -- '--autologin root' "$autologin_conf" 2>/dev/null || {
	err "releng's tty1 autologin drop-in is missing or changed; the archiso profile format changed."
	exit 1
}
cat >"$autologin_conf" <<'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --noreset --skip-login --noissue --nonewline --nohints --autologin root - ${TERM}
EOF
: >"$profile_dir/airootfs/root/.hushlogin"
if [[ -f $profile_dir/airootfs/etc/motd ]]; then
	mv -fT -- "$profile_dir/airootfs/etc/motd" "$profile_dir/airootfs/etc/lyona-archiso-motd"
fi

info "Auto-launching lyona-install on tty1 login..."
cat >>"$profile_dir/airootfs/root/.zlogin" <<'EOF'

if [[ $(tty) == "/dev/tty1" && ! -f /root/.lyona-install-done ]]; then
	# agetty already cleared the screen; this covers anything printed since.
	# lyona-install draws its first screen before it checks the network.
	clear
	lyona-install
elif [[ -r /etc/lyona-archiso-motd ]]; then
	# releng's message of the day, which login no longer prints.
	cat /etc/lyona-archiso-motd
fi
EOF

info "Recording the release stamp at /etc/lyona-iso-release..."
build_commit="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || printf 'unknown')"
build_date="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" --utc +%Y-%m-%dT%H:%M:%SZ)"
install -Dm644 /dev/null "$profile_dir/airootfs/etc/lyona-iso-release"
cat >"$profile_dir/airootfs/etc/lyona-iso-release" <<EOF
LYONA_ISO_VERSION=$iso_version
LYONA_ISO_LABEL=$iso_label
LYONA_ISO_COMMIT=$build_commit
LYONA_ISO_BUILD_DATE=$build_date
EOF

if [[ $profile_only == true ]]; then
	info "Done. lyona $iso_version archiso profile is at $profile_dir"
	exit 0
fi

mkdir -p "$output_dir"
mkarchiso_run=$(command -v "$mkarchiso_cmd")
if [[ $arch == aarch64 ]]; then
	# archiso 91's own device-tree step needs `stubble` and a kernel package that
	# keeps its device trees under /usr/lib/modules; Arch Linux ARM has neither.
	# A copy of mkarchiso with systemd-stub doing that step instead (ARM6-02).
	info "Making the mkarchiso that fuses the Snapdragon X device trees into the kernel..."
	"$repo_dir/scripts/lyona-mkarchiso-dtb" "$mkarchiso_run" \
		"$repo_dir/scripts/lyona-mkarchiso-fuse.sh" "$work_dir/mkarchiso"
	mkarchiso_run=$work_dir/mkarchiso
fi
info "Running mkarchiso..."
"$mkarchiso_run" -v -w "$work_dir/build" -o "$output_dir" "$profile_dir"
info "Done. lyona $iso_version ISO is under $output_dir"
